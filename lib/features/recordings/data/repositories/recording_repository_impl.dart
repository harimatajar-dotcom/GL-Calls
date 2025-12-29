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

    final callData = CallSyncData.fromRecording(recording);
    return await callSyncDataSource.syncCall(callData);
  }

  @override
  Future<RecordingEntity?> uploadAndSyncLatestRecording(int vendorId) async {
    // Step 1: Upload the recording to S3
    final uploadedRecording = await uploadLatestRecording(vendorId);

    if (uploadedRecording == null) {
      return null;
    }

    // Step 2: Sync the call to the server with full CloudFront URL
    if (uploadedRecording is RecordingModel) {
      await callSyncDataSource.syncCall(CallSyncData.fromRecording(uploadedRecording));
    } else {
      // Create CallSyncData manually from entity
      final callData = CallSyncData(
        callId: '${uploadedRecording.createdAt.millisecondsSinceEpoch}_${uploadedRecording.phoneNumber ?? 'unknown'}',
        phoneNumber: _formatPhoneNumber(uploadedRecording.phoneNumber),
        callStartAt: _formatDateTime(uploadedRecording.createdAt),
        duration: uploadedRecording.duration,
        eventType: uploadedRecording.duration > 0 ? 'answered' : 'missed',
        direction: 'inbound',
        // Use full CloudFront URL instead of s3Path
        recordingUrl: uploadedRecording.uploadUrl,
      );
      await callSyncDataSource.syncCall(callData);
    }

    return uploadedRecording;
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
