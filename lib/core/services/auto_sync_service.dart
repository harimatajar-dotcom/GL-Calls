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
          _wasInCall = false;
          // Wait a bit for the recording to be saved
          Future.delayed(const Duration(seconds: 5), () {
            _autoSyncLatestRecording();
          });
        }
        break;

      case PhoneStateStatus.CALL_INCOMING:
        _logBlue('Incoming call from: ${state.number}');
        _wasInCall = true;
        break;

      case PhoneStateStatus.CALL_OUTGOING:
        _logBlue('Outgoing call to: ${state.number}');
        _wasInCall = true;
        break;

      case PhoneStateStatus.NOTHING:
        // Phone is idle
        break;
    }
  }

  /// Auto-sync the latest recording after call ends
  Future<void> _autoSyncLatestRecording() async {
    try {
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('🔄 AUTO-SYNC STARTED (OPTIMIZED)');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Get vendor ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final vendorId = prefs.getInt('vendor_id') ?? 0;

      if (vendorId == 0) {
        _logRed('No vendor ID found - User may not be logged in');
        return;
      }

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
            await directSyncFromCallLog();
          } else {
            // Use dummy file upload to S3
            _logGreen('Attempting to sync from call log with dummy file...');
            await _syncFromCallLogWithDummyFile(vendorId);
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
  Future<void> _syncFromCallLogWithDummyFile(int vendorId) async {
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
      _logGreen('Found recent call from call log:');
      _logGreen('   Number: ${latestCall.number}');
      _logGreen('   Duration: ${latestCall.duration}s');
      _logGreen('   Type: ${latestCall.callType}');

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
          break;
        case call_log.CallType.outgoing:
          callType = CallType.outgoing;
          break;
        case call_log.CallType.missed:
          callType = CallType.missed;
          break;
        default:
          callType = CallType.incoming;
      }

      // Create a RecordingModel from call log data
      final recording = RecordingModel(
        id: null,
        fileName: 'call_${DateTime.now().millisecondsSinceEpoch}.wav',
        filePath: dummyFilePath,
        localPath: dummyFilePath,
        phoneNumber: latestCall.number ?? 'unknown',
        contactName: latestCall.name,
        duration: latestCall.duration ?? 0,
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
      final callSyncData = CallSyncData.fromRecording(syncRecording);
      await _callSyncDataSource.syncCall(callSyncData);

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
        final callSyncData = CallSyncData.fromRecordingWithoutUrl(recording);
        await _callSyncDataSource.syncCall(callSyncData);
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
    final syncRecording = usedDummyFile
        ? uploadedRecording.copyWith(
            phoneNumber: recording.phoneNumber,
            duration: recording.duration > 0 ? recording.duration : 1,
            callType: recording.callType,
          )
        : uploadedRecording;
    final callSyncData = CallSyncData.fromRecording(syncRecording);
    await _callSyncDataSource.syncCall(callSyncData);

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

  /// Direct sync - Sync call data directly to server without S3 upload
  /// Uses placeholder URL and gets call data from call_log
  Future<bool> directSyncFromCallLog() async {
    try {
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('📞 DIRECT SYNC STARTED');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

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
      _logGreen('Found recent call:');
      _logGreen('   Number: ${latestCall.number}');
      _logGreen('   Duration: ${latestCall.duration}s');
      _logGreen('   Type: ${latestCall.callType}');

      // Convert call_log.CallType to local CallType
      CallType callType;
      switch (latestCall.callType) {
        case call_log.CallType.incoming:
          callType = CallType.incoming;
          break;
        case call_log.CallType.outgoing:
          callType = CallType.outgoing;
          break;
        case call_log.CallType.missed:
          callType = CallType.missed;
          break;
        default:
          callType = CallType.incoming;
      }

      // Create CallSyncData for direct sync (with placeholder URL)
      final callSyncData = CallSyncData.forDirectSync(
        phoneNumber: latestCall.number ?? 'unknown',
        duration: latestCall.duration ?? 0,
        callType: callType,
        callTime: latestCall.timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(latestCall.timestamp!)
            : now,
      );

      _logGreen('Syncing to server...');
      _logGreen('   Phone: ${callSyncData.phoneNumber}');
      _logGreen('   Duration: ${callSyncData.duration}s');
      _logGreen('   Direction: ${callSyncData.direction}');
      _logGreen('   Recording URL: ${callSyncData.recordingUrl}');

      // Sync directly to server
      final success = await _callSyncDataSource.syncCall(callSyncData);

      if (success) {
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        _logGreen('✅ DIRECT SYNC COMPLETED');
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return true;
      } else {
        _logRed('Direct sync failed');
        return false;
      }
    } catch (e) {
      _logRed('Error in direct sync: $e');
      return false;
    }
  }

  void _logGreen(String message) {
    debugPrint('\x1B[32m[AutoSync] $message\x1B[0m');
  }

  void _logBlue(String message) {
    debugPrint('\x1B[34m[AutoSync] $message\x1B[0m');
  }

  void _logRed(String message) {
    debugPrint('\x1B[31m[AutoSync] $message\x1B[0m');
  }
}
