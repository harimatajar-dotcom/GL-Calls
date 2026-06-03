import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/log_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<LogEntry> _logs = [];
  LogLevel? _filter;
  StreamSubscription<LogEntry>? _logSubscription;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _logSubscription = LogService.logStream.listen((_) {
      if (mounted) _loadLogs();
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _logs = _filter == null
          ? LogService.getAllLogs()
          : LogService.getLogsByLevel(_filter!);
    });
  }

  /// Build a PDF Document from current logs
  pw.Document _buildPdf() {
    final pdf = pw.Document();
    final logs = LogService.getAllLogs();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.red, width: 2),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GL Calls - Application Logs',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900,
                      ),
                    ),
                    pw.Text(
                      'Generated: $dateStr ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          build: (context) => [
            pw.SizedBox(height: 12),
            // Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _pdfSummaryItem(
                    'Total',
                    logs.length.toString(),
                    PdfColors.blue700,
                  ),
                  _pdfSummaryItem(
                    'Errors',
                    LogService.getLogCounts()[LogLevel.error]
                            ?.toString() ??
                        '0',
                    PdfColors.red700,
                  ),
                  _pdfSummaryItem(
                    'Warnings',
                    LogService.getLogCounts()[LogLevel.warning]
                            ?.toString() ??
                        '0',
                    PdfColors.orange700,
                  ),
                  _pdfSummaryItem(
                    'Success',
                    LogService.getLogCounts()[LogLevel.success]
                            ?.toString() ??
                        '0',
                    PdfColors.green700,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Log Entries',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            // Logs table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(95),
                1: pw.FixedColumnWidth(55),
                2: pw.FixedColumnWidth(75),
                3: pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfTableHeader('Time'),
                    _pdfTableHeader('Level'),
                    _pdfTableHeader('Tag'),
                    _pdfTableHeader('Message'),
                  ],
                ),
                ...logs.map((log) => pw.TableRow(
                      children: [
                        _pdfTableCell(log.formattedTime, fontSize: 8),
                        _pdfTableCell(
                          log.levelLabel,
                          fontSize: 8,
                          color: _pdfLevelColor(log.level),
                          bold: true,
                        ),
                        _pdfTableCell(log.tag, fontSize: 8),
                        _pdfTableCell(log.message, fontSize: 8),
                      ],
                    )),
              ],
            ),
          ],
        ),
      );

    return pdf;
  }

  /// Open in-app PDF preview (with print/share buttons built-in)
  Future<void> _previewPdf() async {
    setState(() => _isExporting = true);
    try {
      final pdf = _buildPdf();
      final bytes = await pdf.save();

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Logs Preview')),
            body: PdfPreview(
              build: (format) => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: true,
              allowSharing: true,
              pdfFileName:
                  'glcalls_logs_${DateTime.now().millisecondsSinceEpoch}.pdf',
            ),
          ),
        ),
      );
      LogService.success('Logs PDF previewed', tag: 'LogsScreen');
    } catch (e) {
      LogService.error('Failed to preview PDF: $e', tag: 'LogsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to preview: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Save PDF to disk and share via system share sheet
  Future<void> _exportAsPdf() async {
    setState(() => _isExporting = true);
    try {
      final pdf = _buildPdf();
      final dir = await getTemporaryDirectory();
      final dateStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final fileName = 'glcalls_logs_$dateStr.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'GL Calls Application Logs',
        text: 'Logs exported from GL Calls on $dateStr',
      );
      LogService.success('Logs exported as PDF', tag: 'LogsScreen');
    } catch (e) {
      LogService.error('Failed to export PDF: $e', tag: 'LogsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  pw.Widget _pdfSummaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _pdfTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _pdfTableCell(String text,
      {double fontSize = 9, PdfColor? color, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  PdfColor _pdfLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.success:
        return PdfColors.green700;
      case LogLevel.warning:
        return PdfColors.orange700;
      case LogLevel.error:
        return PdfColors.red700;
      case LogLevel.debug:
        return PdfColors.grey600;
      case LogLevel.info:
        return PdfColors.blue700;
    }
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.success:
        return AppColors.success;
      case LogLevel.warning:
        return AppColors.warning;
      case LogLevel.error:
        return AppColors.error;
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
    }
  }

  IconData _levelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.success:
        return Icons.check_circle;
      case LogLevel.warning:
        return Icons.warning_amber_rounded;
      case LogLevel.error:
        return Icons.error;
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.info:
        return Icons.info_outline;
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs'),
        content: const Text(
          'Are you sure you want to clear all logs? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LogService.clearLogs();
      _loadLogs();
    }
  }

  void _copyLog(LogEntry log) {
    Clipboard.setData(ClipboardData(text: log.toLogLine()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = LogService.getLogCounts();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: _logs.isEmpty ? null : _confirmClear,
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'View PDF',
            onPressed: _logs.isEmpty || _isExporting ? null : _previewPdf,
          ),
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'Export as PDF',
            onPressed: _logs.isEmpty || _isExporting ? null : _exportAsPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                _buildStatChip(
                  'All',
                  _logs.length,
                  Colors.blueGrey,
                  null,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  'Errors',
                  counts[LogLevel.error] ?? 0,
                  AppColors.error,
                  LogLevel.error,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  'Warnings',
                  counts[LogLevel.warning] ?? 0,
                  AppColors.warning,
                  LogLevel.warning,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  'Success',
                  counts[LogLevel.success] ?? 0,
                  AppColors.success,
                  LogLevel.success,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Log list
          Expanded(
            child: _logs.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return _buildLogTile(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
      String label, int count, Color color, LogLevel? level) {
    final isSelected = _filter == level;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filter = isSelected ? null : level;
          });
          _loadLogs();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogTile(LogEntry log) {
    final color = _levelColor(log.level);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onLongPress: () => _copyLog(log),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_levelIcon(log.level), size: 14, color: color),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.levelLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.tag,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  log.formattedTime.split(' ').last,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              log.message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No logs yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _filter == null
                ? 'Application logs will appear here'
                : 'No ${_filter!.name} logs found',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
