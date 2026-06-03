import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/call_log_entity.dart';

abstract class CallLogLocalDataSource {
  Future<List<CallLogEntity>> getCallLogs();
  Future<bool> requestPermission();
  Future<bool> hasPermission();
}

class CallLogLocalDataSourceImpl implements CallLogLocalDataSource {
  @override
  Future<List<CallLogEntity>> getCallLogs() async {
    final hasAccess = await hasPermission();
    if (!hasAccess) {
      return [];
    }

    final Iterable<CallLogEntry> entries = await CallLog.get();

    return entries.map((entry) {
      return CallLogEntity(
        name: entry.name ?? '',
        number: entry.number ?? '',
        formattedNumber: entry.formattedNumber ?? entry.number ?? '',
        callType: _mapCallType(entry.callType),
        timestamp: DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0),
        duration: entry.duration ?? 0,
        cachedName: entry.cachedMatchedNumber,
      );
    }).toList();
  }

  @override
  Future<bool> requestPermission() async {
    final phoneStatus = await Permission.phone.request();
    final callLogStatus = await Permission.contacts.request();

    return phoneStatus.isGranted || callLogStatus.isGranted;
  }

  @override
  Future<bool> hasPermission() async {
    final status = await Permission.phone.status;
    return status.isGranted;
  }

  CallLogType _mapCallType(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return CallLogType.incoming;
      case CallType.outgoing:
        return CallLogType.outgoing;
      case CallType.missed:
        return CallLogType.missed;
      case CallType.rejected:
        return CallLogType.rejected;
      case CallType.blocked:
        return CallLogType.blocked;
      default:
        return CallLogType.unknown;
    }
  }
}
