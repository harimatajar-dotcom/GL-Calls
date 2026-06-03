import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/diagnostic_check.dart';
import '../providers/diagnostics_provider.dart';
import '../widgets/diagnostic_tile.dart';

/// "Run Diagnostics" screen — reached from Profile.
///
/// Always available, always re-runnable. Streams check progress live;
/// shows an overall verdict banner once finished; exposes Copy / Share
/// report buttons that emit the same content as text + PDF.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-run once on entry so the user sees results without an extra tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiagnosticsProvider>().runAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy),
            onPressed: _copyReport,
          ),
          IconButton(
            tooltip: 'Share report (PDF)',
            icon: const Icon(Icons.ios_share),
            onPressed: _shareReport,
          ),
        ],
      ),
      body: Consumer<DiagnosticsProvider>(
        builder: (context, p, _) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _VerdictBanner(provider: p)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: p.running ? null : () => p.runAll(),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(p.running
                              ? 'Running…'
                              : 'Run full self-test'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (p.results.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('Tap "Run full self-test" to begin')),
                ),
              ..._buildGroupedSlivers(p),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(DiagnosticsProvider p) {
    final groups = <String, List<DiagnosticResult>>{};
    for (final r in p.results) {
      groups.putIfAbsent(r.category, () => []).add(r);
    }
    final slivers = <Widget>[];
    for (final entry in groups.entries) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            entry.key,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
          ),
        ),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => DiagnosticTile(
            result: entry.value[i],
            onFix: (r) async {
              final msg = await context.read<DiagnosticsProvider>().handleFix(r);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(msg)),
              );
            },
          ),
          childCount: entry.value.length,
        ),
      ));
    }
    return slivers;
  }

  String _buildTextReport(DiagnosticsProvider p) {
    final buf = StringBuffer();
    buf.writeln('GL Calls — Diagnostic report');
    buf.writeln('───────────────────────────────');
    p.reportHeader.forEach((k, v) => buf.writeln('$k: $v'));
    buf.writeln();
    final verdict = p.verdict;
    buf.writeln('Overall verdict: ${verdict == null ? "(incomplete)" : _verdictLabel(verdict)}');
    buf.writeln();
    String? lastCategory;
    for (final r in p.results) {
      if (r.category != lastCategory) {
        buf.writeln();
        buf.writeln('## ${r.category}');
        lastCategory = r.category;
      }
      buf.writeln('  [${_statusGlyph(r.status)}] ${r.id} — ${r.title}');
      buf.writeln('       severity: ${r.severity.name}');
      buf.writeln('       detail:   ${r.detail}');
      if (r.technical != null && r.technical!.isNotEmpty) {
        buf.writeln('       tech:     ${r.technical}');
      }
    }
    return buf.toString();
  }

  Future<void> _copyReport() async {
    final p = context.read<DiagnosticsProvider>();
    final text = _buildTextReport(p);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  Future<void> _shareReport() async {
    final p = context.read<DiagnosticsProvider>();
    final pdfBytes = await _buildPdf(p);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/gl_calls_diagnostics.pdf');
    await file.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'GL Calls diagnostic report',
    );
  }

  Future<List<int>> _buildPdf(DiagnosticsProvider p) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return [
            pw.Text('GL Calls — Diagnostic report',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            for (final entry in p.reportHeader.entries)
              pw.Text('${entry.key}: ${entry.value}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'Overall verdict: ${p.verdict == null ? "(incomplete)" : _verdictLabel(p.verdict!)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            ..._pdfChecks(p),
          ];
        },
      ),
    );
    return doc.save();
  }

  List<pw.Widget> _pdfChecks(DiagnosticsProvider p) {
    final widgets = <pw.Widget>[];
    String? lastCategory;
    for (final r in p.results) {
      if (r.category != lastCategory) {
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(pw.Text(r.category,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
        lastCategory = r.category;
      }
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('[${_statusGlyph(r.status)}] ${r.id} — ${r.title}'),
            pw.Text('    severity: ${r.severity.name}  ·  detail: ${r.detail}',
                style: const pw.TextStyle(fontSize: 9)),
            if (r.technical != null && r.technical!.isNotEmpty)
              pw.Text('    tech: ${r.technical}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      ));
    }
    return widgets;
  }

  String _statusGlyph(CheckStatus s) {
    switch (s) {
      case CheckStatus.pass: return 'OK';
      case CheckStatus.warning: return 'WARN';
      case CheckStatus.fail: return 'FAIL';
      case CheckStatus.skipped: return 'SKIP';
      case CheckStatus.running: return '…';
      case CheckStatus.pending: return ' ';
    }
  }

  String _verdictLabel(DiagnosticVerdict v) {
    switch (v) {
      case DiagnosticVerdict.ready: return 'READY to sync';
      case DiagnosticVerdict.warningsOnly: return 'Working with warnings';
      case DiagnosticVerdict.notReady: return 'NOT READY — fix the blockers';
    }
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.provider});
  final DiagnosticsProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider.results.isEmpty) return const SizedBox.shrink();
    final v = provider.verdict;
    Color color;
    String text;
    IconData icon;
    if (provider.running || v == null) {
      color = Colors.blue;
      text = 'Running diagnostics…';
      icon = Icons.hourglass_top;
    } else {
      switch (v) {
        case DiagnosticVerdict.ready:
          color = Colors.green;
          text = '✅ Ready to sync';
          icon = Icons.check_circle;
          break;
        case DiagnosticVerdict.warningsOnly:
          color = Colors.orange;
          text = '⚠️ Working, with warnings';
          icon = Icons.warning_amber_rounded;
          break;
        case DiagnosticVerdict.notReady:
          final blockers = provider.results.where((r) => r.isBlocking).length;
          color = Colors.red;
          text = '❌ Not ready — $blockers blocker(s) must be fixed';
          icon = Icons.cancel;
          break;
      }
    }
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
