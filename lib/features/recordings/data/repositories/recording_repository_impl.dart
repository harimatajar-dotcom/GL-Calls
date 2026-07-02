import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/sync_failure_notifier.dart';
import '../../../../core/services/synced_call_ledger.dart';
import '../../domain/entities/recording_entity.dart';
import '../../domain/repositories/recording_repository.dart';
import '../datasources/call_sync_datasource.dart';
import '../datasources/recording_database_datasource.dart';
import '../datasources/recording_scanner_datasource.dart';
import '../datasources/recording_upload_datasource.dart';
import '../models/recording_model.dart';

class RecordingRepositoryImpl implements RecordingRepository {
  final RecordingDatabaseDataSource databaseDataSource;
  final RecordingScannerDataSource scannerDataSource;
  final RecordingUploadDataSourceImpl uploadDataSource;
  final CallSyncDataSourceImpl callSyncDataSource;

  RecordingRepositoryImpl({
    required this.databaseDataSource,
    required this.scannerDataSource,
    required this.uploadDataSource,
    required this.callSyncDataSource,
  });

  @override
  Future<List<RecordingEntity>> getAllRecordings() async {
    return await databaseDataSource.getAllRecordings();
  }

  @override
  Future<List<RecordingEntity>> getUploadedRecordings() async {
    return await databaseDataSource.getUploadedRecordings();
  }

  @override
  Future<RecordingEntity?> getLatestRecording() async {
    return await databaseDataSource.getLatestRecording();
  }

  @override
  Future<RecordingEntity?> getLatestNotUploadedRecording() async {
    return await databaseDataSource.getLatestNotUploadedRecording();
  }

  @override
  Future<void> syncRecordings() async {
    final hasAccess = await hasPermission();
    if (!hasAccess) return;

    // Scan for new recordings
    final scannedRecordings = await scannerDataSource.scanForRecordings();

    // Filter out recordings that already exist in the database
    final newRecordings = <RecordingModel>[];
    for (final recording in scannedRecordings) {
      final exists = await databaseDataSource.recordingExists(recording.filePath);
      if (!exists) {
        newRecordings.add(recording);
      }
    }

    // Insert new recordings
    if (newRecordings.isNotEmpty) {
      await databaseDataSource.insertRecordings(newRecordings);
    }
  }

  @override
  Future<bool> requestPermission() async {
    return await scannerDataSource.requestPermission();
  }

  @override
  Future<bool> hasPermission() async {
    return await scannerDataSource.hasPermission();
  }

  @override
  Future<int> getRecordingsCount() async {
    return await databaseDataSource.getRecordingsCount();
  }

  @override
  Future<int> getUploadedRecordingsCount() async {
    return await databaseDataSource.getUploadedRecordingsCount();
  }

  @override
  Future<RecordingEntity?> uploadLatestRecording(int vendorId) async {
    // Get the latest recording that hasn't been uploaded
    final latestRecording = await databaseDataSource.getLatestNotUploadedRecording();

    if (latestRecording == null) {
      _logYellow('⚠️ No recordings to upload');
      return null;
    }

    // Upload the recording
    final uploadedRecording = await uploadDataSource.uploadRecording(
      recording: latestRecording,
      vendorId: vendorId,
    );

    if (uploadedRecording != null) {
      // Update the database with upload status
      await databaseDataSource.updateUploadStatus(
        latestRecording.id!,
        uploadedRecording.uploadUrl!,
        uploadedRecording.s3Path!,
      );
      return uploadedRecording;
    }

    return null;
  }

  @override
  Future<bool> syncCallToServer(RecordingEntity recording) async {
    if (recording is! RecordingModel) {
      _logYellow('⚠️ Invalid recording type for sync');
      return false;
    }

    final countryCode = await _readCountryCode();
    final resolved = await _resolveDirectionAuthoritative(recording);
    final callData = CallSyncData.fromRecording(resolved, countryCode: countryCode);
    return await _syncIfNew(callData);
  }

  @override
  Future<RecordingEntity?> uploadAndSyncLatestRecording(int vendorId) async {
    // Step 1: Upload the recording to S3
    final uploadedRecording = await uploadLatestRecording(vendorId);

    if (uploadedRecording == null) {
      return null;
    }

    // Step 2: Sync the call to the server with full CloudFront URL
    final countryCode = await _readCountryCode();
    if (uploadedRecording is RecordingModel) {
      final resolved = await _resolveDirectionAuthoritative(uploadedRecording);
      await _syncIfNew(CallSyncData.fromRecording(resolved, countryCode: countryCode));
    } else {
      // Determine direction authoritatively from the device call log.
      // The recording's own callType may be the scanner's "unknown"
      // default; trusting it would put the call in the wrong column on
      // the dashboard.
      final phoneForLookup = _formatPhoneNumber(uploadedRecording.phoneNumber);
      final scannerFallback = uploadedRecording.callType == CallType.outgoing
          ? 'outbound'
          : 'inbound';
      final direction = await CallSyncData.resolveDirectionFromCallLog(
        phoneForLookup,
        fallback: scannerFallback,
      );

      // Determine event type
      String eventType;
      if (uploadedRecording.callType == CallType.missed) {
        eventType = 'missed';
      } else {
        eventType = uploadedRecording.duration > 0 ? 'answered' : 'missed';
      }

      // Create CallSyncData manually from entity
      final phoneNumber = _formatPhoneNumber(uploadedRecording.phoneNumber);
      final callData = CallSyncData(
        callId: CallSyncData.buildDeterministicCallId(
          phoneNumber: phoneNumber,
          callTime: uploadedRecording.createdAt,
          direction: direction,
        ),
        phoneNumber: phoneNumber,
        countryCode: countryCode,
        callStartAt: _formatDateTime(uploadedRecording.createdAt),
        duration: uploadedRecording.duration,
        eventType: eventType,
        direction: direction,
        // Use full CloudFront URL instead of s3Path
        recordingUrl: uploadedRecording.uploadUrl,
      );
      await _syncIfNew(callData);
    }

    return uploadedRecording;
  }

  /// Read the user's selected dial code (e.g. "+91") from SharedPreferences.
  Future<String?> _readCountryCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final code = prefs.getString('country_code');
      if (code != null && code.isNotEmpty) return code;
      return '+91';
    } catch (_) {
      return '+91';
    }
  }

  /// Dedupe wrapper around [CallSyncDataSourceImpl.syncCall].
  ///
  /// Uses [SyncedCallLedger.tryAcquire] / [commit] / [release] so a
  /// concurrent sync from the background isolate cannot race past us
  /// between the "is it synced" check and the POST.
  ///
  /// Also checks the filename history as a second-line defense: even if a
  /// recording's timestamp drifts across a UTC-minute boundary (producing
  /// a different call_id), the filename itself stays constant, so the
  /// same physical recording is never POSTed twice.
  Future<bool> _syncIfNew(CallSyncData data) async {
    // Filename gate — runs BEFORE the call_id lease so we short-circuit
    // even when call_id differs due to time drift between sync paths.
    final fileName = data.fileName ?? '';
    if (fileName.isNotEmpty && await SyncedCallLedger.isFileNameSynced(fileName)) {
      _logYellow('⏭️  Skipping — file_name "$fileName" already synced (history match)');
      return true;
    }

    // Issue-fix 2A/2B: direction-free duplicate gate (mirrors
    // AutoSyncService._syncIfNew). Blocks a second path whose call_id
    // differs only because of direction-token or minute-bucket drift.
    final callStart = _tryParseCallStart(data.callStartAt);
    if (callStart != null &&
        await SyncedCallLedger.isPhoneMinuteSynced(
          data.phoneNumber,
          callStart,
          toleranceBuckets: 1,
        )) {
      _logYellow('⏭️  Skipping — ${data.phoneNumber} already synced within ±1 min '
          '(cross-path duplicate gate)');
      return true;
    }

    final acquired = await SyncedCallLedger.tryAcquire(data.callId);
    if (!acquired) {
      _logYellow('⏭️  Skipping duplicate sync — call_id ${data.callId} already synced or in-flight');
      return true;
    }
    try {
      final ok = await callSyncDataSource.syncCall(data);
      if (ok) {
        await SyncedCallLedger.commit(data.callId);
        if (fileName.isNotEmpty) {
          await SyncedCallLedger.markFileNameSynced(fileName);
        }
        if (callStart != null) {
          await SyncedCallLedger.markPhoneMinuteSynced(
              data.phoneNumber, callStart);
        }
      } else {
        await SyncedCallLedger.release(data.callId);
        await SyncFailureNotifier.notifyFailure(
          phoneNumber: data.phoneNumber,
          reason: 'Server did not accept the sync (HTTP error)',
        );
      }
      return ok;
    } catch (e) {
      await SyncedCallLedger.release(data.callId);
      await SyncFailureNotifier.notifyFailure(
        phoneNumber: data.phoneNumber,
        reason: 'Network error: ${e.toString().split('\n').first}',
      );
      rethrow;
    }
  }

  /// Parse the wire-format call_start_at for the phone|minute duplicate
  /// gate. Handles ISO-8601 and the legacy 'yyyy-MM-dd HH:mm:ss' form
  /// (Dart's DateTime.parse accepts the space separator). Null on
  /// garbage — the gate is then skipped (call_id dedup still applies).
  DateTime? _tryParseCallStart(String callStartAt) {
    try {
      return DateTime.parse(callStartAt);
    } catch (_) {
      return null;
    }
  }

  /// Replace the recording's `callType` with the authoritative value from
  /// the device call log. The scanner defaults to `unknown`/`incoming`
  /// when it cannot detect direction; sending that to the server causes
  /// the call to land in the wrong column on the dashboard.
  Future<RecordingModel> _resolveDirectionAuthoritative(RecordingModel recording) async {
    final phone = recording.phoneNumber;
    if (phone == null || phone.isEmpty) return recording;
    final fallback = recording.callType == CallType.outgoing ? 'outbound' : 'inbound';
    final dir = await CallSyncData.resolveDirectionFromCallLog(phone, fallback: fallback);
    final resolved = dir == 'outbound' ? CallType.outgoing : CallType.incoming;
    if (resolved == recording.callType) return recording;
    return recording.copyWith(callType: resolved);
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      return 'unknown';
    }
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length == 10) {
      cleaned = '91$cleaned';
    }
    return cleaned;
  }

  void _logYellow(String message) {
    print('\x1B[33m$message\x1B[0m');
  }
}
