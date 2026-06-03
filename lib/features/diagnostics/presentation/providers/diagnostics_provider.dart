import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/background_service.dart';
import '../../data/diagnostic_service.dart';
import '../../domain/diagnostic_check.dart';

/// Drives a sequential run of every diagnostic check defined in §4 of
/// DEVELOPER_NOTE_DIAGNOSTIC_KIT and surfaces a stream of UI updates to
/// the [DiagnosticsScreen].
///
/// The run is intentionally sequential, not parallel — the spec asks
/// for a "live checklist" the user can read as it ticks; running 25
/// checks in parallel would flash everything green/red at once and
/// hide network ordering effects.
class DiagnosticsProvider extends ChangeNotifier {
  DiagnosticsProvider({required this.apiClient});

  final ApiClient apiClient;
  final DiagnosticService _service = DiagnosticService();

  List<DiagnosticResult> _results = const [];
  List<DiagnosticResult> get results => _results;

  bool _running = false;
  bool get running => _running;

  DiagnosticVerdict? _verdict;
  DiagnosticVerdict? get verdict => _verdict;

  String? _s3Host; // captured from NET_PRESIGNED, used by NET_S3_REACHABLE
  Map<String, String> _reportHeader = const {};
  Map<String, String> get reportHeader => _reportHeader;

  /// Start (or restart) a full self-test run.
  Future<void> runAll() async {
    if (_running) return;
    _running = true;
    _verdict = null;
    _s3Host = null;
    _results = _service.buildChecklist();
    _reportHeader = await _service.reportHeader();
    notifyListeners();

    for (final r in _results) {
      r.status = CheckStatus.running;
      notifyListeners();
      try {
        await _runOne(r);
      } catch (e) {
        r.status = CheckStatus.fail;
        r.detail = 'Check threw: $e';
        r.technical = e.toString();
      }
      notifyListeners();
    }

    _verdict = _computeVerdict();
    _running = false;
    notifyListeners();
  }

  Future<void> _runOne(DiagnosticResult r) async {
    switch (r.id) {
      // A. Permissions
      case 'PERM_CALLLOG':
        await _service.runPermCallLog(r);
        break;
      case 'PERM_STORAGE':
        await _service.runPermStorage(r);
        break;
      case 'PERM_PHONE_STATE':
        await _service.runPermPhoneState(r);
        break;
      case 'PERM_NOTIF':
        await _service.runPermNotif(r);
        break;
      case 'PERM_BATTERY':
        await _service.runPermBattery(r);
        break;
      case 'PERM_CONTACTS':
        await _service.runPermContacts(r);
        break;

      // B. Recording capability
      case 'REC_FOLDER_FOUND':
        await _service.runRecFolderFound(r);
        break;
      case 'REC_FOLDER_READABLE':
        await _service.runRecFolderReadable(r);
        break;
      case 'REC_HAS_FILES':
        await _service.runRecHasFiles(r);
        break;
      case 'REC_RECENT':
        await _service.runRecRecent(r);
        break;
      case 'REC_CLOCK_OK':
        await _service.runRecClockOk(r);
        break;

      // C. Auth
      case 'AUTH_LOGGED_IN':
        await _service.runAuthLoggedIn(r);
        break;
      case 'AUTH_TOKEN_LIVE':
        await _service.runAuthTokenLive(r, apiClient);
        break;
      case 'AUTH_BUSINESS_ID':
        await _service.runAuthBusinessId(r);
        break;
      case 'AUTH_CONTEXT':
        await _service.runAuthContext(r);
        break;

      // D. Network
      case 'NET_INTERNET':
        await _service.runNetInternet(r);
        break;
      case 'NET_CRM_API':
        await _service.runNetCrmApi(r, apiClient);
        break;
      case 'NET_PRESIGNED':
        await _service.runNetPresigned(
          r,
          apiClient,
          onS3Host: (host) => _s3Host = host,
        );
        break;
      case 'NET_S3_REACHABLE':
        await _service.runNetS3Reachable(r, _s3Host);
        break;
      case 'NET_APPVERSION':
        await _service.runNetAppVersion(r);
        break;

      // E. Service health
      case 'SVC_RUNNING':
        await _service.runSvcRunning(r);
        break;
      case 'SVC_AUTOSYNC_ON':
        await _service.runSvcAutoSyncOn(r);
        break;
      case 'SVC_HEARTBEAT':
        await _service.runSvcHeartbeat(r);
        break;
      case 'SVC_WORKMANAGER':
        await _service.runSvcWorkManager(r);
        break;
      case 'SVC_RESTART_COUNT':
        await _service.runSvcRestartCount(r);
        break;

      // F. Sync state (info-only)
      case 'SYNC_LAST_OK':
        await _service.runSyncLastOk(r);
        break;
      case 'SYNC_LEDGER_COUNT':
        await _service.runSyncLedgerCount(r);
        break;
      case 'SYNC_PENDING':
        await _service.runSyncPending(r);
        break;
      case 'SYNC_RECENT_FAILURES':
        await _service.runSyncRecentFailures(r);
        break;

      default:
        r.status = CheckStatus.skipped;
        r.detail = 'No implementation for ${r.id}';
    }
  }

  DiagnosticVerdict _computeVerdict() {
    bool anyBlocker = false;
    bool anyWarning = false;
    for (final r in _results) {
      if (r.status == CheckStatus.fail &&
          r.severity == CheckSeverity.blocker) {
        anyBlocker = true;
      }
      if (r.status == CheckStatus.fail &&
          r.severity == CheckSeverity.warning) {
        anyWarning = true;
      }
    }
    if (anyBlocker) return DiagnosticVerdict.notReady;
    if (anyWarning) return DiagnosticVerdict.warningsOnly;
    return DiagnosticVerdict.ready;
  }

  /// Handle the "Fix" button on a single check. Returns a hint string
  /// for the caller (DiagnosticsScreen) to show in a snackbar.
  Future<String> handleFix(DiagnosticResult r) async {
    switch (r.fix) {
      case FixAction.openAppSettings:
        await openAppSettings();
        return 'Opened app settings — re-run when done';
      case FixAction.requestPermission:
        await _requestRelevantPermission(r);
        return 'Re-run diagnostics to confirm';
      case FixAction.openBatterySettings:
        try {
          await Permission.ignoreBatteryOptimizations.request();
        } catch (_) {
          await openAppSettings();
        }
        return 'Allow the exemption, then re-run';
      case FixAction.pickRecordingFolder:
        return 'Open the home screen → Settings → "Recording folder"';
      case FixAction.reLogin:
        return 'Log out from Profile and log in again';
      case FixAction.startService:
        await BackgroundServiceHelper.startService();
        return 'Service restart requested';
      case FixAction.enableAutoSync:
        return 'Turn on Auto-Sync from the home screen';
      case FixAction.openDateTimeSettings:
        return 'Open Android Settings → Date & Time → "Set automatically"';
      case FixAction.openDialerRecordingHelp:
        return 'Turn ON call recording inside your Phone/Dialer app';
      case FixAction.none:
        return 'No automated fix';
    }
  }

  Future<void> _requestRelevantPermission(DiagnosticResult r) async {
    switch (r.id) {
      case 'PERM_CALLLOG':
      case 'PERM_PHONE_STATE':
        await Permission.phone.request();
        break;
      case 'PERM_STORAGE':
        final audio = await Permission.audio.request();
        if (!audio.isGranted) {
          await Permission.manageExternalStorage.request();
        }
        break;
      case 'PERM_NOTIF':
        await Permission.notification.request();
        break;
      case 'PERM_CONTACTS':
        await Permission.contacts.request();
        break;
      case 'REC_FOLDER_READABLE':
        await Permission.manageExternalStorage.request();
        break;
    }
  }
}
