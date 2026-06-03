import '../entities/recording_entity.dart';

abstract class RecordingRepository {
  Future<List<RecordingEntity>> getAllRecordings();
  Future<List<RecordingEntity>> getUploadedRecordings();
  Future<RecordingEntity?> getLatestRecording();
  Future<RecordingEntity?> getLatestNotUploadedRecording();
  Future<void> syncRecordings();
  Future<bool> requestPermission();
  Future<bool> hasPermission();
  Future<int> getRecordingsCount();
  Future<int> getUploadedRecordingsCount();
  Future<RecordingEntity?> uploadLatestRecording(int vendorId);
  Future<bool> syncCallToServer(RecordingEntity recording);
  Future<RecordingEntity?> uploadAndSyncLatestRecording(int vendorId);
}
