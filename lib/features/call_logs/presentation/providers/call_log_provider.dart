import 'package:flutter/material.dart';
import '../../domain/entities/call_log_entity.dart';
import '../../domain/repositories/call_log_repository.dart';

enum CallLogStatus { initial, loading, loaded, error, permissionDenied }

class CallLogProvider extends ChangeNotifier {
  final CallLogRepository repository;

  CallLogProvider({required this.repository});

  CallLogStatus _status = CallLogStatus.initial;
  List<CallLogEntity> _callLogs = [];
  String _errorMessage = '';
  bool _hasPermission = false;

  CallLogStatus get status => _status;
  List<CallLogEntity> get callLogs => _callLogs;
  String get errorMessage => _errorMessage;
  bool get hasPermission => _hasPermission;

  // A-18: Memoize the per-type filters. Previously each getter
  // re-filtered the full _callLogs list on every UI rebuild, an O(N)
  // walk per access; with 5000+ entries and three getters that's
  // 15000 comparisons every frame. Cache and invalidate on load.
  List<CallLogEntity>? _incomingCache;
  List<CallLogEntity>? _outgoingCache;
  List<CallLogEntity>? _missedCache;

  List<CallLogEntity> get incomingCalls => _incomingCache ??=
      _callLogs.where((c) => c.callType == CallLogType.incoming).toList();

  List<CallLogEntity> get outgoingCalls => _outgoingCache ??=
      _callLogs.where((c) => c.callType == CallLogType.outgoing).toList();

  List<CallLogEntity> get missedCalls => _missedCache ??=
      _callLogs.where((c) => c.callType == CallLogType.missed).toList();

  void _invalidateFilterCaches() {
    _incomingCache = null;
    _outgoingCache = null;
    _missedCache = null;
  }

  Future<void> checkPermission() async {
    _hasPermission = await repository.hasPermission();
    notifyListeners();
  }

  Future<void> requestPermission() async {
    _status = CallLogStatus.loading;
    notifyListeners();

    final granted = await repository.requestPermission();
    _hasPermission = granted;

    if (granted) {
      await loadCallLogs();
    } else {
      _status = CallLogStatus.permissionDenied;
      notifyListeners();
    }
  }

  Future<void> loadCallLogs() async {
    _status = CallLogStatus.loading;
    notifyListeners();

    try {
      final hasAccess = await repository.hasPermission();
      if (!hasAccess) {
        _status = CallLogStatus.permissionDenied;
        notifyListeners();
        return;
      }

      _callLogs = await repository.getCallLogs();
      _invalidateFilterCaches();
      _status = CallLogStatus.loaded;
    } catch (e) {
      _status = CallLogStatus.error;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  Future<void> refresh() async {
    await loadCallLogs();
  }
}
