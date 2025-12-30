import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:phone_state/phone_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/recordings/data/datasources/call_sync_datasource.dart';
import '../../features/recordings/data/datasources/recording_database_datasource.dart';
import '../../features/recordings/data/datasources/recording_scanner_datasource.dart';
import '../../features/recordings/data/datasources/recording_upload_datasource.dart';
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
      _logGreen('🔄 AUTO-SYNC STARTED');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Get vendor ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final vendorId = prefs.getInt('vendor_id') ?? 0;

      if (vendorId == 0) {
        _logRed('No vendor ID found - User may not be logged in');
        return;
      }

      // Scan for new recordings
      _logGreen('Scanning for new recordings...');
      final scannedRecordings = await _scannerDataSource.scanForRecordings();

      if (scannedRecordings.isEmpty) {
        _logRed('No recordings found on device');
        return;
      }

      // Get existing recordings from database
      final existingRecordings = await _databaseDataSource.getAllRecordings();
      final existingPaths = existingRecordings.map((r) => r.filePath).toSet();

      // Find new recordings
      final newRecordings = scannedRecordings
          .where((r) => !existingPaths.contains(r.filePath))
          .toList();

      if (newRecordings.isEmpty) {
        _logBlue('No new recordings to sync');

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

      // Save new recordings to database
      await _databaseDataSource.insertRecordings(newRecordings);
      _logGreen('Saved ${newRecordings.length} new recording(s) to database');

      // Get the latest recording (just saved)
      final latestRecording = newRecordings.first;

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

  Future<void> _uploadAndSync(dynamic recording, int vendorId) async {
    _logGreen('Found recording: ${recording.fileName}');

    // Check if file exists
    final file = File(recording.filePath);
    if (!await file.exists()) {
      _logRed('Recording file not found: ${recording.filePath}');
      return;
    }

    // Get audio duration if not set
    var recordingWithDuration = recording;
    if (recording.duration == 0) {
      _logGreen('Getting audio duration...');
      final duration = await _scannerDataSource.getAudioDuration(recording.filePath);
      _logGreen('   Duration: ${duration}s');
      recordingWithDuration = recording.copyWith(duration: duration);
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

    // Update database with upload status
    if (recording.id != null) {
      await _databaseDataSource.updateUploadStatus(
        recording.id!,
        uploadedRecording.uploadUrl ?? '',
        uploadedRecording.s3Path ?? '',
      );
    }

    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _logGreen('✅ UPLOAD SUCCESSFUL');
    _logGreen('   File: ${uploadedRecording.fileName}');
    _logGreen('   URL: ${uploadedRecording.uploadUrl}');
    _logGreen('   Duration: ${uploadedRecording.duration}s');
    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Sync call to server
    _logGreen('Syncing call to server...');
    final callSyncData = CallSyncData.fromRecording(uploadedRecording);
    await _callSyncDataSource.syncCall(callSyncData);

    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _logGreen('✅ AUTO-SYNC COMPLETED SUCCESSFULLY');
    _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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
