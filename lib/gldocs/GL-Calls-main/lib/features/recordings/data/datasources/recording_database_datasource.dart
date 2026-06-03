import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../models/recording_model.dart';

abstract class RecordingDatabaseDataSource {
  Future<List<RecordingModel>> getAllRecordings();
  Future<List<RecordingModel>> getUploadedRecordings();
  Future<RecordingModel?> getLatestRecording();
  Future<RecordingModel?> getLatestNotUploadedRecording();
  Future<void> insertRecording(RecordingModel recording);
  Future<void> insertRecordings(List<RecordingModel> recordings);
  Future<void> updateRecording(RecordingModel recording);
  Future<void> updateUploadStatus(int id, String uploadUrl, String s3Path);
  Future<void> deleteRecording(int id);
  Future<int> getRecordingsCount();
  Future<int> getUploadedRecordingsCount();
  Future<bool> recordingExists(String filePath);
}

class RecordingDatabaseDataSourceImpl implements RecordingDatabaseDataSource {
  @override
  Future<List<RecordingModel>> getAllRecordings() async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => RecordingModel.fromMap(map)).toList();
  }

  @override
  Future<List<RecordingModel>> getUploadedRecordings() async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      where: 'is_uploaded = ?',
      whereArgs: [1],
      orderBy: 'uploaded_at DESC',
    );
    return maps.map((map) => RecordingModel.fromMap(map)).toList();
  }

  @override
  Future<RecordingModel?> getLatestRecording() async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return RecordingModel.fromMap(maps.first);
  }

  @override
  Future<RecordingModel?> getLatestNotUploadedRecording() async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      where: 'is_uploaded = ? OR is_uploaded IS NULL',
      whereArgs: [0],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return RecordingModel.fromMap(maps.first);
  }

  @override
  Future<void> insertRecording(RecordingModel recording) async {
    final db = await databaseHelper.database;
    await db.insert(
      'recordings',
      recording.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> insertRecordings(List<RecordingModel> recordings) async {
    final db = await databaseHelper.database;
    final batch = db.batch();

    for (final recording in recordings) {
      batch.insert(
        'recordings',
        recording.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  @override
  Future<void> updateRecording(RecordingModel recording) async {
    final db = await databaseHelper.database;
    await db.update(
      'recordings',
      recording.toMap(),
      where: 'id = ?',
      whereArgs: [recording.id],
    );
  }

  @override
  Future<void> deleteRecording(int id) async {
    final db = await databaseHelper.database;
    await db.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> getRecordingsCount() async {
    final db = await databaseHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM recordings');
    return result.first['count'] as int;
  }

  @override
  Future<int> getUploadedRecordingsCount() async {
    final db = await databaseHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM recordings WHERE is_uploaded = 1',
    );
    return result.first['count'] as int;
  }

  @override
  Future<void> updateUploadStatus(int id, String uploadUrl, String s3Path) async {
    final db = await databaseHelper.database;
    await db.update(
      'recordings',
      {
        'is_uploaded': 1,
        'upload_url': uploadUrl,
        's3_path': s3Path,
        'uploaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<bool> recordingExists(String filePath) async {
    final db = await databaseHelper.database;
    final result = await db.query(
      'recordings',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    return result.isNotEmpty;
  }
}
