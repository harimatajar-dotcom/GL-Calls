import 'package:flutter/material.dart';

import '../../domain/diagnostic_check.dart';

/// One row in the diagnostic checklist.
///
/// Leading icon = current [CheckStatus] (spinner / tick / warn / cross).
/// Title = the human-readable check name.
/// Subtitle = the plain-language detail from the result.
/// Trailing = a "Fix" button when the check failed AND has a fix.
class DiagnosticTile extends StatelessWidget {
  const DiagnosticTile({
    super.key,
    required this.result,
    required this.onFix,
  });

  final DiagnosticResult result;
  final Future<void> Function(DiagnosticResult) onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: _StatusIcon(status: result.status, severity: result.severity),
      title: Text(result.title),
      subtitle: Text(
        result.detail.isEmpty ? _placeholderForStatus(result.status) : result.detail,
        style: theme.textTheme.bodySmall,
      ),
      trailing: _showFixButton()
          ? OutlinedButton(
              onPressed: () => onFix(result),
              child: const Text('Fix'),
            )
          : null,
      dense: true,
      isThreeLine: result.detail.length > 60,
    );
  }

  bool _showFixButton() =>
      result.status == CheckStatus.fail && result.fix != FixAction.none;

  String _placeholderForStatus(CheckStatus s) {
    switch (s) {
      case CheckStatus.pending:
        return '…';
      case CheckStatus.running:
        return 'Checking…';
      case CheckStatus.skipped:
        return 'Skipped';
      case CheckStatus.pass:
        return 'OK';
      case CheckStatus.warning:
        return 'Warning';
      case CheckStatus.fail:
        return 'Failed';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.severity});
  final CheckStatus status;
  final CheckSeverity severity;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case CheckStatus.pending:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
      case CheckStatus.running:
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case CheckStatus.pass:
        return const Icon(Icons.check_circle, color: Colors.green);
      case CheckStatus.warning:
        return const Icon(Icons.warning_amber_rounded, color: Colors.orange);
      case CheckStatus.fail:
        return Icon(
          severity == CheckSeverity.blocker
              ? Icons.cancel
              : Icons.error_outline,
          color: severity == CheckSeverity.blocker
              ? Colors.red
              : Colors.orange,
        );
      case CheckStatus.skipped:
        return const Icon(Icons.do_not_disturb_on_outlined, color: Colors.grey);
    }
  }
}
