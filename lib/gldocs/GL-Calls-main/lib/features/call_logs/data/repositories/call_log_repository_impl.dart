import '../../domain/entities/call_log_entity.dart';
import '../../domain/repositories/call_log_repository.dart';
import '../datasources/call_log_local_datasource.dart';
import '../datasources/call_log_database_datasource.dart';
import '../models/call_log_model.dart';

class CallLogRepositoryImpl implements CallLogRepository {
  final CallLogLocalDataSource localDataSource;
  final CallLogDatabaseDataSource databaseDataSource;

  CallLogRepositoryImpl({
    required this.localDataSource,
    required this.databaseDataSource,
  });

  @override
  Future<List<CallLogEntity>> getCallLogs() async {
    // First sync from phone to local database
    await syncCallLogs();
    // Then return from local database
    return await databaseDataSource.getAllCallLogs();
  }

  @override
  Future<bool> requestPermission() async {
    return await localDataSource.requestPermission();
  }

  @override
  Future<bool> hasPermission() async {
    return await localDataSource.hasPermission();
  }

  /// Syncs call logs from phone to local database
  Future<void> syncCallLogs() async {
    final hasAccess = await hasPermission();
    if (!hasAccess) return;

    // Get call logs from phone
    final phoneCallLogs = await localDataSource.getCallLogs();

    // Convert to models and insert into database
    final models = phoneCallLogs
        .map((entity) => CallLogModel.fromEntity(entity))
        .toList();

    await databaseDataSource.insertCallLogs(models);
  }

  /// Gets call logs count from local database
  Future<int> getLocalCallLogsCount() async {
    return await databaseDataSource.getCallLogsCount();
  }

  /// Clears all local call logs
  Future<void> clearLocalCallLogs() async {
    await databaseDataSource.deleteAllCallLogs();
  }
}
