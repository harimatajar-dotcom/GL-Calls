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

    // A-18: scope the query to the last 90 days. CallLog.get() reads the
    // entire device call history every time - on phones with years of
    // history that can be many thousands of entries and a multi-second
    // load every screen open. 90 days is more than enough for any
    // dashboard view; older calls are still synced (via the recordings
    // pathway) but not re-listed locally.
    final now = DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    final Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: ninetyDaysAgo.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
    );

    return entries.map((entry) {
      return CallLogEntity(
        name: entry.name ?? '',
        number: entry.number ?? '',
        formattedNumber: entry.formattedNumber ?? entry.number ?? '',
        callType: _mapCallType(entry.callType),
        timestamp: DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0),
        duration: entry.duration ?? 0,
        // A-7 fix: cachedName must contain the cached contact NAME, not
        // a phone number. The prior code assigned cachedMatchedNumber
        // here, which is a normalized phone number; combined with
        // displayName preferring cachedName, the UI showed raw numbers
        // instead of contact names even when one was cached.
        cachedName: entry.name,
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
