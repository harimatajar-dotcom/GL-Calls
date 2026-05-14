import 'dart:async';
import 'dart:io';

import 'package:call_log/call_log.dart' as call_log;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phone_state/phone_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/recordings/data/datasources/call_sync_datasource.dart';
import '../../features/recordings/data/datasources/recording_database_datasource.dart';
import '../../features/recordings/data/datasources/recording_scanner_datasource.dart';
import '../../features/recordings/data/datasources/recording_upload_datasource.dart';
import '../../features/recordings/data/models/recording_model.dart';
import '../../features/recordings/domain/entities/recording_entity.dart';
import '../network/api_client.dart';
import 'log_service.dart';
import 'synced_call_ledger.dart';

class AutoSyncService {
  StreamSubscription<PhoneState>? _phoneStateSubscription;
  bool _wasInCall = false;
  DateTime? _callStartTime;

  // Services for upload and sync
  late ApiClient _apiClient;
  late RecordingScannerDataSource _scannerDataSource;
  late RecordingDatabaseDataSource _databaseDataSource;
  late RecordingUploadDataSourceImpl _uploadDataSource;
  late CallSyncDataSource _callSyncDataSource;

  /// Initialize the auto-sync service
  Future<void> initialize() async {
    _logGreen('Initializing AutoSyncService...');

    try {
      // Get auth token from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      // Initialize API client (singleton)
      _apiClient = ApiClient();
      if (token.isNotEmpty) {
        _apiClient.setAuthToken(token);
      }

      // Initialize data sources
      _scannerDataSource = RecordingScannerDataSourceImpl();
      _databaseDataSource = RecordingDatabaseDataSourceImpl();
      _uploadDataSource = RecordingUploadDataSourceImpl(apiClient: _apiClient);
      _callSyncDataSource = CallSyncDataSourceImpl(apiClient: _apiClient);

      _logGreen('AutoSyncService initialized successfully');
    } catch (e) {
      _logRed('Failed to initialize AutoSyncService: $e');
    }
  }

  /// Start listening to phone state changes
  void startListening() {
    _logGreen('Starting phone state listener...');

    _phoneStateSubscription = PhoneState.stream.listen((PhoneState state) {
      _handlePhoneStateChange(state);
    });

    _logGreen('Phone state listener started');
  }

  /// Stop listening to phone state changes
  void stopListening() {
    _phoneStateSubscription?.cancel();
    _phoneStateSubscription = null;
    _logGreen('Phone state listener stopped');
  }

  /// Handle phone state changes
  void _handlePhoneStateChange(PhoneState state) {
    _logBlue('Phone state changed: ${state.status}');

    switch (state.status) {
      case PhoneStateStatus.CALL_STARTED:
        _wasInCall = true;
        _callStartTime = DateTime.now();
        _logGreen('Call started at $_callStartTime');
        break;

      case PhoneStateStatus.CALL_ENDED:
        if (_wasInCall) {
          _logGreen('Call ended - Starting auto-sync...');
          // Calculate duration from call start time as fallback
          final callDuration = _callStartTime != null
              ? DateTime.now().difference(_callStartTime!).inSeconds
              : 0;
          _logGreen('Calculated call duration: ${callDuration}s');
          _wasInCall = false;
          // Wait longer for call log to be updated (10 seconds)
          Future.delayed(const Duration(seconds: 10), () {
            _autoSyncLatestRecording(fallbackDuration: callDuration);
          });
        }
        break;

      case PhoneStateStatus.CALL_INCOMING:
        _logBlue('Incoming call from: ${state.number}');
        _wasInCall = true;
        _callStartTime ??= DateTime.now();
        break;

      case PhoneStateStatus.CALL_OUTGOING:
        _logBlue('Outgoing call to: ${state.number}');
        _wasInCall = true;
        _callStartTime ??= DateTime.now();
        break;

      case PhoneStateStatus.NOTHING:
        // Phone is idle
        break;
    }
  }

  /// Read the user's selected dial code (e.g. "+91") from SharedPreferences.
  /// Falls back to "+91" if nothing was stored (legacy sessions pre-update).
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

  /// Sync a CallSyncData payload exactly once across the lifetime of this
  /// install. The `call_id` is deterministic (same physical call → same
  /// id from any sync path), and [SyncedCallLedger.tryAcquire] takes a
  /// cross-isolate lease before the POST so the background isolate
  /// (WorkManager / FlutterBackgroundService) cannot race past us
  /// between the dedupe check and the network call.
  Future<bool> _syncIfNew(CallSyncData data) async {
    final acquired = await SyncedCallLedger.tryAcquire(data.callId);
    if (!acquired) {
      _logBlue('⏭️  Skipping duplicate sync — call_id ${data.callId} already synced or in-flight');
      return true;
    }
    try {
      final ok = await _callSyncDataSource.syncCall(data);
      if (ok) {
        await SyncedCallLedger.commit(data.callId);
      } else {
        await SyncedCallLedger.release(data.callId);
      }
      return ok;
    } catch (e) {
      await SyncedCallLedger.release(data.callId);
      rethrow;
    }
  }

  /// Reload auth token from SharedPreferences (call before each sync)
  /// IMPORTANT: Background isolate has its own cached SharedPreferences view.
  /// Must call reload() to see updates made by the main isolate (login).
  Future<bool> _refreshAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Force reload from native storage so background isolate sees latest token
      await prefs.reload();

      // Try both keys for backwards compatibility
      String token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        token = prefs.getString('AUTH_TOKEN') ?? '';
      }

      _logBlue('All keys in prefs: ${prefs.getKeys().toList()}');

      if (token.isEmpty) {
        _logRed('No auth token found - User needs to login');
        _logRed('Checked keys: auth_token, AUTH_TOKEN');
        return false;
      }

      _apiClient.setAuthToken(token);
      _logGreen('Auth token refreshed (length: ${token.length}, prefix: ${token.substring(0, 10)}...)');
      return true;
    } catch (e) {
      _logRed('Failed to refresh auth token: $e');
      return false;
    }
  }

  /// Auto-sync the latest recording after call ends
  Future<void> _autoSyncLatestRecording({int fallbackDuration = 0}) async {
    try {
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('🔄 AUTO-SYNC STARTED (OPTIMIZED)');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Refresh auth token before sync
      final hasToken = await _refreshAuthToken();
      if (!hasToken) {
        _logRed('Aborting sync - no valid auth token');
        return;
      }

      // Get vendor ID from shared preferences (optional - new API doesn't provide it)
      final prefs = await SharedPreferences.getInstance();
      final vendorId = prefs.getInt('vendor_id') ?? 0;
      _logBlue('Vendor ID: $vendorId (0 = not set, using fallback)');

      // Use optimized scan - only checks last 1 hour
      _logGreen('Scanning for latest recording (optimized - last 1 hour)...');
      final latestRecording = await _scannerDataSource.scanForLatestUnsyncedRecording();

      if (latestRecording == null) {
        _logBlue('No recent recordings found');

        // Check for existing unuploaded recordings
        final latestUnuploaded = await _databaseDataSource.getLatestNotUploadedRecording();
        if (latestUnuploaded == null) {
          _logBlue('No unuploaded recordings in database');

          // Check if auto direct sync is enabled
          final isAutoDirectSyncEnabled = prefs.getBool('auto_direct_sync_enabled') ?? false;

          if (isAutoDirectSyncEnabled) {
            // Use direct sync (no S3 upload, uses placeholder URL)
            _logGreen('Auto Direct Sync enabled - using direct sync...');
            await directSyncFromCallLog(fallbackDuration: fallbackDuration);
          } else {
            // Use dummy file upload to S3
            _logGreen('Attempting to sync from call log with dummy file...');
            await _syncFromCallLogWithDummyFile(vendorId, fallbackDuration: fallbackDuration);
          }
          return;
        }

        // Upload the latest unuploaded recording
        await _uploadAndSync(latestUnuploaded, vendorId);
        return;
      }

      // Check if already in database
      final existingRecordings = await _databaseDataSource.getAllRecordings();
      final existingPaths = existingRecordings.map((r) => r.filePath).toSet();

      if (existingPaths.contains(latestRecording.filePath)) {
        _logBlue('Recording already in database, checking upload status...');

        // Check for existing unuploaded recordings
        final latestUnuploaded = await _databaseDataSource.getLatestNotUploadedRecording();
        if (latestUnuploaded == null) {
          _logBlue('All recordings already uploaded');
          return;
        }

        // Upload the latest unuploaded recording
        await _uploadAndSync(latestUnuploaded, vendorId);
        return;
      }

      // Save new recording to database
      await _databaseDataSource.insertRecordings([latestRecording]);
      _logGreen('Saved new recording to database');

      // Upload and sync
      await _uploadAndSync(latestRecording, vendorId);

    } catch (e, stackTrace) {
      _logRed('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logRed('❌ AUTO-SYNC FAILED');
      _logRed('   Error: $e');
      _logRed('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Sync call data from call log with dummy audio file when no recording exists
  Future<void> _syncFromCallLogWithDummyFile(int vendorId, {int fallbackDuration = 0}) async {
    try {
      // Get the latest call from call log (last 5 minutes)
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

      final entries = await call_log.CallLog.query(
        dateFrom: fiveMinutesAgo.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      if (entries.isEmpty) {
        _logBlue('No recent calls found in call log');
        return;
      }

      // Get the most recent call
      final latestCall = entries.first;
      // Use fallback duration if call_log returns 0
      final duration = (latestCall.duration ?? 0) > 0
          ? latestCall.duration!
          : fallbackDuration;
      _logGreen('Found recent call from call log:');
      _logGreen('   Number: ${latestCall.number}');
      _logGreen('   Duration from call_log: ${latestCall.duration}s');
      _logGreen('   Using duration: ${duration}s${(latestCall.duration ?? 0) == 0 ? " (fallback)" : ""}');
      _logGreen('   Type from call_log: ${latestCall.callType}');
      _logGreen('   Type name: ${latestCall.callType?.name ?? "null"}');

      // Create dummy file
      final dummyFilePath = await _createDummyAudioFile();
      if (dummyFilePath == null) {
        _logRed('Failed to create dummy audio file');
        return;
      }

      // Determine call type - convert from call_log.CallType to local CallType
      CallType callType;
      switch (latestCall.callType) {
        case call_log.CallType.incoming:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (incoming call)');
          break;
        case call_log.CallType.outgoing:
          callType = CallType.outgoing;
          _logGreen('   ➡️ Direction: OUTBOUND (outgoing call)');
          break;
        case call_log.CallType.missed:
          callType = CallType.missed;
          _logGreen('   ➡️ Direction: INBOUND (missed call)');
          break;
        case call_log.CallType.wifiOutgoing:
          callType = CallType.outgoing;
          _logGreen('   ➡️ Direction: OUTBOUND (wifi outgoing)');
          break;
        default:
          callType = CallType.incoming;
          _logGreen('   ⚠️ Direction: INBOUND (default for ${latestCall.callType})');
      }

      // Create a RecordingModel from call log data
      final recording = RecordingModel(
        id: null,
        fileName: 'call_${DateTime.now().millisecondsSinceEpoch}.wav',
        filePath: dummyFilePath,
        localPath: dummyFilePath,
        phoneNumber: latestCall.number ?? 'unknown',
        contactName: latestCall.name,
        duration: duration,
        fileSize: 16044, // Size of silent.wav
        createdAt: DateTime.fromMillisecondsSinceEpoch(latestCall.timestamp ?? now.millisecondsSinceEpoch),
        callType: callType,
      );

      _logGreen('Created recording from call log: ${recording.phoneNumber}');

      // Upload to S3
      _logGreen('Uploading dummy file to S3...');
      final uploadedRecording = await _uploadDataSource.uploadRecording(
        recording: recording,
        vendorId: vendorId,
      );

      if (uploadedRecording == null) {
        _logRed('Upload failed');
        return;
      }

      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('✅ UPLOAD SUCCESSFUL (FROM CALL LOG)');
      _logGreen('   Phone: ${recording.phoneNumber}');
      _logGreen('   Duration: ${recording.duration}s');
      _logGreen('   URL: ${uploadedRecording.uploadUrl}');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Sync call to server with original call data
      _logGreen('Syncing call to server...');
      final syncRecording = uploadedRecording.copyWith(
        phoneNumber: recording.phoneNumber,
        duration: recording.duration,
        callType: recording.callType,
      );
      final countryCode = await _readCountryCode();
      final callSyncData = CallSyncData.fromRecording(syncRecording, countryCode: countryCode);
      await _syncIfNew(callSyncData);

      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('✅ AUTO-SYNC COMPLETED (FROM CALL LOG)');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    } catch (e) {
      _logRed('Error syncing from call log: $e');
    }
  }

  Future<void> _uploadAndSync(dynamic recording, int vendorId) async {
    _logGreen('Found recording: ${recording.fileName}');

    // Check if file exists
    final file = File(recording.filePath);
    var recordingToUpload = recording;
    bool usedDummyFile = false;

    if (!await file.exists()) {
      _logRed('Recording file not found: ${recording.filePath}');
      _logBlue('Using dummy audio file for upload...');

      // Create dummy file from assets
      final dummyFilePath = await _createDummyAudioFile();
      if (dummyFilePath == null) {
        _logRed('Failed to create dummy audio file');
        // Fallback: sync without recording
        final countryCode = await _readCountryCode();
        final callSyncData = CallSyncData.fromRecordingWithoutUrl(recording, countryCode: countryCode);
        await _syncIfNew(callSyncData);
        return;
      }

      // Create a modified recording with the dummy file path
      recordingToUpload = RecordingModel(
        id: recording.id,
        fileName: 'call_${DateTime.now().millisecondsSinceEpoch}.wav',
        filePath: dummyFilePath,
        localPath: dummyFilePath,
        phoneNumber: recording.phoneNumber,
        contactName: recording.contactName,
        duration: recording.duration > 0 ? recording.duration : 1,
        fileSize: 16044, // Size of silent.wav
        createdAt: recording.createdAt,
        callType: recording.callType,
      );
      usedDummyFile = true;
      _logGreen('Using dummy audio file: $dummyFilePath');
    }

    // Get audio duration if not set
    var recordingWithDuration = recordingToUpload;
    if (recordingToUpload.duration == 0 && !usedDummyFile) {
      _logGreen('Getting audio duration...');
      final duration = await _scannerDataSource.getAudioDuration(recordingToUpload.filePath);
      _logGreen('   Duration: ${duration}s');
      recordingWithDuration = recordingToUpload.copyWith(duration: duration);
    }

    // Upload to S3
    _logGreen('Uploading to S3...');
    final uploadedRecording = await _uploadDataSource.uploadRecording(
      recording: recordingWithDuration,
      vendorId: vendorId,
    );

    if (uploadedRecording == null) {
      _logRed('Upload failed');
      return;
    }

    // Update database with upload status (only for real recordings)
    if (recording.id != null && !usedDummyFile) {
      await _databaseDataSource.updateUploadStatus(
        recording.id!,
        uploadedRecording.uploadUrl ?? '',
        uploadedRecording.s3Path ?? '',
      );
    }

    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _logGreen('✅ UPLOAD SUCCESSFUL${usedDummyFile ? " (DUMMY FILE)" : ""}');
    _logGreen('   File: ${uploadedRecording.fileName}');
    _logGreen('   URL: ${uploadedRecording.uploadUrl}');
    _logGreen('   Duration: ${uploadedRecording.duration}s');
    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Sync call to server - use original recording data but with the uploaded URL
    _logGreen('Syncing call to server...');

    // IMPORTANT: ALWAYS get call type from call log to ensure correct direction
    _logGreen('Fetching call type from call log...');
    _logGreen('   Phone number: ${recording.phoneNumber}');
    _logGreen('   Scanner call type was: ${recording.callType}');
    final CallType finalCallType = await _getCallTypeFromCallLog(recording.phoneNumber);
    _logGreen('   Call type from call log: $finalCallType');
    _logGreen('   ➡️ DIRECTION: ${finalCallType == CallType.outgoing ? "OUTBOUND" : "INBOUND"}');

    final syncRecording = uploadedRecording.copyWith(
      phoneNumber: recording.phoneNumber,
      duration: recording.duration > 0 ? recording.duration : 1,
      callType: finalCallType,
    );
    final countryCode = await _readCountryCode();
    final callSyncData = CallSyncData.fromRecording(syncRecording, countryCode: countryCode);
    await _syncIfNew(callSyncData);

    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _logGreen('✅ AUTO-SYNC COMPLETED SUCCESSFULLY');
    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// Create a dummy audio file from assets for upload when recording is not accessible
  Future<String?> _createDummyAudioFile() async {
    try {
      // Load silent.wav from assets
      final byteData = await rootBundle.load('assets/audio/silent.wav');
      final bytes = byteData.buffer.asUint8List();

      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final dummyFilePath = '${tempDir.path}/dummy_call_${DateTime.now().millisecondsSinceEpoch}.wav';

      // Write to temp file
      final dummyFile = File(dummyFilePath);
      await dummyFile.writeAsBytes(bytes);

      _logGreen('Created dummy audio file: $dummyFilePath');
      return dummyFilePath;
    } catch (e) {
      _logRed('Error creating dummy audio file: $e');
      return null;
    }
  }

  /// Direct sync - Sync call data to server
  /// First checks custom folder for recordings, if found uploads that recording
  /// If no recording found, uses placeholder URL
  /// Flow: 1. Check for recording in custom folder  2. Store locally  3. Upload/Sync to server
  Future<bool> directSyncFromCallLog({int fallbackDuration = 0}) async {
    try {
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('📞 DIRECT SYNC STARTED');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Refresh auth token before sync
      final hasToken = await _refreshAuthToken();
      if (!hasToken) {
        _logRed('Aborting direct sync - no valid auth token');
        return false;
      }

      // Get vendor ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final vendorId = prefs.getInt('vendor_id') ?? 0;

      // Step 1: Check for recording in custom folder
      _logGreen('Step 1: Scanning for recording in custom folder...');
      final latestRecording = await _scannerDataSource.scanForLatestUnsyncedRecording();

      if (latestRecording != null) {
        // Found a recording in custom folder - upload it
        _logGreen('   ✓ Found recording: ${latestRecording.fileName}');
        _logGreen('   Phone: ${latestRecording.phoneNumber}');
        _logGreen('   Duration: ${latestRecording.duration}s');

        // Check if file exists
        final file = File(latestRecording.filePath);
        if (await file.exists()) {
          _logGreen('Step 2: Uploading recording to S3...');

          // Get audio duration if not set
          var recordingWithDuration = latestRecording;
          if (latestRecording.duration == 0) {
            final duration = await _scannerDataSource.getAudioDuration(latestRecording.filePath);
            recordingWithDuration = latestRecording.copyWith(duration: duration > 0 ? duration : fallbackDuration);
            _logGreen('   Duration: ${recordingWithDuration.duration}s');
          }

          // Save to local database first
          await _databaseDataSource.insertRecording(recordingWithDuration);
          _logGreen('   ✓ Stored locally');

          if (vendorId > 0) {
            // Upload to S3
            final uploadedRecording = await _uploadDataSource.uploadRecording(
              recording: recordingWithDuration,
              vendorId: vendorId,
            );

            if (uploadedRecording != null) {
              _logGreen('   ✓ Uploaded to S3: ${uploadedRecording.uploadUrl}');

              // Update database with upload status
              final savedRecord = await _databaseDataSource.getLatestRecording();
              if (savedRecord?.id != null) {
                await _databaseDataSource.updateUploadStatus(
                  savedRecord!.id!,
                  uploadedRecording.uploadUrl ?? '',
                  uploadedRecording.s3Path ?? '',
                );
              }

              // Sync to server with actual recording URL
              _logGreen('Step 3: Syncing to server...');
              // ALWAYS get call type from call log
              final callTypeFromLog = await _getCallTypeFromCallLog(recordingWithDuration.phoneNumber);
              _logGreen('   Call type from call log: $callTypeFromLog');
              _logGreen('   ➡️ DIRECTION: ${callTypeFromLog == CallType.outgoing ? "OUTBOUND" : "INBOUND"}');
              final countryCode = await _readCountryCode();
              final callSyncData = CallSyncData.fromRecording(
                uploadedRecording.copyWith(
                  phoneNumber: recordingWithDuration.phoneNumber,
                  duration: recordingWithDuration.duration,
                  callType: callTypeFromLog,
                ),
                countryCode: countryCode,
              );
              final success = await _syncIfNew(callSyncData);

              if (success) {
                _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                _logGreen('✅ DIRECT SYNC COMPLETED (WITH RECORDING)');
                _logGreen('   Recording: ${latestRecording.fileName}');
                _logGreen('   Phone: ${recordingWithDuration.phoneNumber}');
                _logGreen('   Duration: ${recordingWithDuration.duration}s');
                _logGreen('   URL: ${uploadedRecording.uploadUrl}');
                _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                return true;
              }
            }
          }
        }
      }

      // No recording found or upload failed - fall back to call log data with placeholder URL
      _logGreen('No recording found, using call log data with placeholder URL...');

      // Get the latest call from call log (last 10 minutes)
      final now = DateTime.now();
      final tenMinutesAgo = now.subtract(const Duration(minutes: 10));

      final entries = await call_log.CallLog.query(
        dateFrom: tenMinutesAgo.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      if (entries.isEmpty) {
        _logRed('No recent calls found in call log');
        return false;
      }

      // Get the most recent call
      final latestCall = entries.first;
      // Use fallback duration if call_log returns 0
      final duration = (latestCall.duration ?? 0) > 0
          ? latestCall.duration!
          : fallbackDuration;
      _logGreen('Found recent call:');
      _logGreen('   Number: ${latestCall.number}');
      _logGreen('   Duration from call_log: ${latestCall.duration}s');
      _logGreen('   Using duration: ${duration}s${(latestCall.duration ?? 0) == 0 ? " (fallback)" : ""}');
      _logGreen('   Type from call_log: ${latestCall.callType}');
      _logGreen('   Type name: ${latestCall.callType?.name ?? "null"}');

      // Convert call_log.CallType to local CallType
      CallType callType;
      switch (latestCall.callType) {
        case call_log.CallType.incoming:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (incoming call)');
          break;
        case call_log.CallType.outgoing:
          callType = CallType.outgoing;
          _logGreen('   ➡️ Direction: OUTBOUND (outgoing call)');
          break;
        case call_log.CallType.missed:
          callType = CallType.missed;
          _logGreen('   ➡️ Direction: INBOUND (missed call)');
          break;
        case call_log.CallType.rejected:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (rejected call)');
          break;
        case call_log.CallType.blocked:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (blocked call)');
          break;
        case call_log.CallType.answeredExternally:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (answered externally)');
          break;
        case call_log.CallType.voiceMail:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (voicemail)');
          break;
        case call_log.CallType.wifiIncoming:
          callType = CallType.incoming;
          _logGreen('   ➡️ Direction: INBOUND (wifi incoming)');
          break;
        case call_log.CallType.wifiOutgoing:
          callType = CallType.outgoing;
          _logGreen('   ➡️ Direction: OUTBOUND (wifi outgoing)');
          break;
        default:
          callType = CallType.unknown;
          _logGreen('   ⚠️ Direction: UNKNOWN (defaulting to unknown)');
      }

      // Placeholder URL for direct sync
      const placeholderUrl = 'https://glcalls.s3.amazonaws.com/no-recording.wav';

      // Store call data locally
      _logGreen('Storing call data locally...');
      final recording = RecordingModel(
        id: null,
        fileName: 'direct_sync_${DateTime.now().millisecondsSinceEpoch}.wav',
        filePath: 'direct_sync', // No actual file for direct sync
        localPath: 'direct_sync',
        phoneNumber: latestCall.number ?? 'unknown',
        contactName: latestCall.name,
        duration: duration,
        fileSize: 0, // No file for direct sync
        createdAt: DateTime.fromMillisecondsSinceEpoch(latestCall.timestamp ?? now.millisecondsSinceEpoch),
        callType: callType,
        isUploaded: false,
      );

      // Save to local database
      await _databaseDataSource.insertRecording(recording);
      _logGreen('   ✓ Stored locally: ${recording.phoneNumber}');

      // Read from local database
      final savedRecord = await _databaseDataSource.getLatestRecording();

      if (savedRecord == null) {
        _logRed('Failed to read saved record from database');
        return false;
      }

      // Create CallSyncData from locally saved data with placeholder URL
      _logGreen('Syncing to server with placeholder URL...');
      final countryCode = await _readCountryCode();
      final callSyncData = CallSyncData.forDirectSync(
        phoneNumber: savedRecord.phoneNumber ?? 'unknown',
        duration: savedRecord.duration,
        callType: savedRecord.callType,
        callTime: savedRecord.createdAt,
        countryCode: countryCode,
      );

      _logGreen('   Phone: ${callSyncData.phoneNumber}');
      _logGreen('   Duration: ${callSyncData.duration}s');
      _logGreen('   Direction: ${callSyncData.direction}');
      _logGreen('   Recording URL: ${callSyncData.recordingUrl}');

      // Sync to server
      final success = await _syncIfNew(callSyncData);

      if (success) {
        // Update local record as synced
        await _databaseDataSource.updateUploadStatus(
          savedRecord.id!,
          placeholderUrl,
          'direct_sync',
        );

        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        _logGreen('✅ DIRECT SYNC COMPLETED (PLACEHOLDER URL)');
        _logGreen('   Phone: ${savedRecord.phoneNumber}');
        _logGreen('   Duration: ${savedRecord.duration}s');
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return true;
      } else {
        _logRed('Direct sync failed - call stored locally but not synced');
        return false;
      }
    } catch (e) {
      _logRed('Error in direct sync: $e');
      return false;
    }
  }

  /// Get call type from call log by matching phone number (last 10 minutes)
  Future<CallType> _getCallTypeFromCallLog(String? phoneNumber) async {
    try {
      final now = DateTime.now();
      final tenMinutesAgo = now.subtract(const Duration(minutes: 10));

      final entries = await call_log.CallLog.query(
        dateFrom: tenMinutesAgo.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      _logGreen('━━━ CALL LOG LOOKUP ━━━');
      _logGreen('   Looking for phone: $phoneNumber');
      _logGreen('   Found ${entries.length} recent calls');

      if (entries.isEmpty) {
        _logBlue('No recent calls in call log');
        return CallType.unknown;
      }

      // Log all recent calls for debugging
      int i = 0;
      for (final entry in entries) {
        i++;
        _logBlue('   Call #$i: ${entry.number} | Type: ${entry.callType} | Name: ${entry.callType?.name}');
        if (i >= 5) break; // Only log first 5
      }

      // Find matching call by phone number
      for (final entry in entries) {
        if (phoneNumber != null && entry.number != null) {
          // Match last 10 digits
          final entryDigits = entry.number!.replaceAll(RegExp(r'\D'), '');
          final phoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');

          final entryLast10 = entryDigits.length >= 10
              ? entryDigits.substring(entryDigits.length - 10)
              : entryDigits;
          final phoneLast10 = phoneDigits.length >= 10
              ? phoneDigits.substring(phoneDigits.length - 10)
              : phoneDigits;

          _logBlue('   Comparing: $entryLast10 vs $phoneLast10');

          if (entryLast10 == phoneLast10) {
            _logGreen('   ✓ MATCHED! Call type: ${entry.callType} (${entry.callType?.name})');
            return _convertCallLogType(entry.callType);
          }
        }
      }

      // If no match by number, use the most recent call
      final latestCall = entries.first;
      _logGreen('   No match found, using most recent: ${latestCall.callType} (${latestCall.callType?.name})');
      return _convertCallLogType(latestCall.callType);
    } catch (e) {
      _logRed('Error getting call type from log: $e');
      return CallType.unknown;
    }
  }

  /// Convert call_log.CallType to local CallType
  CallType _convertCallLogType(call_log.CallType? type) {
    switch (type) {
      case call_log.CallType.incoming:
        return CallType.incoming;
      case call_log.CallType.outgoing:
        return CallType.outgoing;
      case call_log.CallType.missed:
        return CallType.missed;
      case call_log.CallType.wifiOutgoing:
        return CallType.outgoing;
      default:
        return CallType.incoming;
    }
  }

  void _logGreen(String message) {
    debugPrint('\x1B[32m[AutoSync] $message\x1B[0m');
    LogService.success(message, tag: 'AutoSync');
  }

  void _logBlue(String message) {
    debugPrint('\x1B[34m[AutoSync] $message\x1B[0m');
    LogService.info(message, tag: 'AutoSync');
  }

  void _logRed(String message) {
    debugPrint('\x1B[31m[AutoSync] $message\x1B[0m');
    LogService.error(message, tag: 'AutoSync');
  }
}
