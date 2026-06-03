import '../entities/call_log_entity.dart';

abstract class CallLogRepository {
  Future<List<CallLogEntity>> getCallLogs();
  Future<bool> requestPermission();
  Future<bool> hasPermission();
}
