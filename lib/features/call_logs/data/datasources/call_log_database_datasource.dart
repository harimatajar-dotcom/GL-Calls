import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/call_log_entity.dart';
import '../models/call_log_model.dart';

abstract class CallLogDatabaseDataSource {
  Future<List<CallLogModel>> getAllCallLogs();
  Future<List<CallLogModel>> getCallLogsByType(CallLogType type);
  Future<void> insertCallLog(CallLogModel callLog);
  Future<void> insertCallLogs(List<CallLogModel> callLogs);
  Future<void> deleteAllCallLogs();
  Future<int> getCallLogsCount();
  Future<DateTime?> getLastSyncTime();
}

class CallLogDatabaseDataSourceImpl implements CallLogDatabaseDataSource {
  @override
  Future<List<CallLogModel>> getAllCallLogs() async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'call_logs',
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => CallLogModel.fromMap(map)).toList();
  }

  @override
  Future<List<CallLogModel>> getCallLogsByType(CallLogType type) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'call_logs',
      where: 'call_type = ?',
      whereArgs: [type.name],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => CallLogModel.fromMap(map)).toList();
  }

  @override
  Future<void> insertCallLog(CallLogModel callLog) async {
    final db = await databaseHelper.database;
    await db.insert(
      'call_logs',
      callLog.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> insertCallLogs(List<CallLogModel> callLogs) async {
    final db = await databaseHelper.database;
    final batch = db.batch();

    for (final callLog in callLogs) {
      batch.insert(
        'call_logs',
        callLog.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  @override
  Future<void> deleteAllCallLogs() async {
    final db = await databaseHelper.database;
    await db.delete('call_logs');
  }

  @override
  Future<int> getCallLogsCount() async {
    final db = await databaseHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM call_logs');
    return result.first['count'] as int;
  }

  @override
  Future<DateTime?> getLastSyncTime() async {
    final db = await databaseHelper.database;
    final result = await db.rawQuery(
      'SELECT MAX(timestamp) as last_sync FROM call_logs',
    );
    final timestamp = result.first['last_sync'] as int?;
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
}
