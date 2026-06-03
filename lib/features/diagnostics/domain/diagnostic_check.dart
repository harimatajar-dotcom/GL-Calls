/// Status of a single diagnostic check as it runs.
enum CheckStatus { pending, running, pass, warning, fail, skipped }

/// Drives the overall verdict shown to the user.
enum CheckSeverity {
  /// Sync cannot work at all without this. One failed -> overall NOT READY.
  blocker,

  /// Sync may work but is unreliable / degraded.
  warning,

  /// Status / context only, never "fails", never affects verdict.
  info,
}

/// Deep-link target that the "Fix" button invokes for this result.
/// Maps 1:1 to a handler in `DiagnosticsProvider.handleFix`.
enum FixAction {
  none,
  openAppSettings,
  requestPermission,
  openBatterySettings,
  pickRecordingFolder,
  reLogin,
  startService,
  enableAutoSync,
  openDateTimeSettings,
  openDialerRecordingHelp,
}

/// One row in the diagnostic checklist. IDs are stable and used in the
/// exported report - keep them in sync with the spec
/// (DEVELOPER_NOTE_DIAGNOSTIC_KIT.md §4).
class DiagnosticResult {
  final String id;
  final String title;
  final String category;
  final CheckSeverity severity;
  CheckStatus status;
  String detail;
  String? technical;
  FixAction fix;

  DiagnosticResult({
    required this.id,
    required this.title,
    required this.category,
    required this.severity,
    this.status = CheckStatus.pending,
    this.detail = '',
    this.technical,
    this.fix = FixAction.none,
  });

  bool get isBlocking => severity == CheckSeverity.blocker && status == CheckStatus.fail;
  bool get isWarning => severity == CheckSeverity.warning && status == CheckStatus.fail;
}

/// Overall verdict computed once every check has finished.
enum DiagnosticVerdict { ready, warningsOnly, notReady }
