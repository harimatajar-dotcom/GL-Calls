import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { info, success, warning, error, debug }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'level': level.index,
        'tag': tag,
        'message': message,
      };

  factory LogEntry.fromMap(Map<String, dynamic> map) => LogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        level: LogLevel.values[map['level'] as int],
        tag: map['tag'] as String,
        message: map['message'] as String,
      );

  String get levelLabel {
    switch (level) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.success:
        return 'SUCCESS';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.debug:
        return 'DEBUG';
    }
  }

  String get formattedTime {
    return '${timestamp.year}-${_pad(timestamp.month)}-${_pad(timestamp.day)} '
        '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}:${_pad(timestamp.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String toLogLine() {
    return '[$formattedTime] [$levelLabel] [$tag] $message';
  }
}

/// Centralized log service for capturing all app logs
/// Logs are persisted to disk and can be exported as PDF
class LogService {
  static const int _maxLogs = 5000;
  static const String _logFileName = 'glcalls_logs.txt';
  static const String _lastClearedKey = 'logs_last_cleared';

  static final List<LogEntry> _memoryLogs = [];
  static final StreamController<LogEntry> _logStreamController =
      StreamController<LogEntry>.broadcast();
  static bool _initialized = false;
  static File? _logFile;

  /// Stream of new logs (for real-time UI updates)
  static Stream<LogEntry> get logStream => _logStreamController.stream;

  /// Initialize log service - load existing logs from disk
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_logFileName');

      if (await _logFile!.exists()) {
        final lines = await _logFile!.readAsLines();
        for (final line in lines.reversed.take(_maxLogs)) {
          final entry = _parseLogLine(line);
          if (entry != null) {
            _memoryLogs.insert(0, entry);
          }
        }
      }

      log('LogService initialized', level: LogLevel.success, tag: 'LogService');
    } catch (e) {
      debugPrint('[LogService] Init failed: $e');
    }
  }

  /// Add a log entry
  static void log(
    String message, {
    LogLevel level = LogLevel.info,
    String tag = 'App',
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );

    _memoryLogs.add(entry);
    if (_memoryLogs.length > _maxLogs) {
      _memoryLogs.removeAt(0);
    }

    _logStreamController.add(entry);

    // Print to console
    debugPrint(entry.toLogLine());

    // Persist to file (async, fire-and-forget)
    _appendToFile(entry);
  }

  static Future<void> _appendToFile(LogEntry entry) async {
    try {
      if (_logFile == null) {
        final dir = await getApplicationDocumentsDirectory();
        _logFile = File('${dir.path}/$_logFileName');
      }
      await _logFile!.writeAsString(
        '${entry.toLogLine()}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (e) {
      debugPrint('[LogService] File write failed: $e');
    }
  }

  /// Convenience methods
  static void info(String message, {String tag = 'App'}) =>
      log(message, level: LogLevel.info, tag: tag);

  static void success(String message, {String tag = 'App'}) =>
      log(message, level: LogLevel.success, tag: tag);

  static void warning(String message, {String tag = 'App'}) =>
      log(message, level: LogLevel.warning, tag: tag);

  static void error(String message, {String tag = 'App'}) =>
      log(message, level: LogLevel.error, tag: tag);

  static void debug(String message, {String tag = 'App'}) =>
      log(message, level: LogLevel.debug, tag: tag);

  /// Get all logs in memory (newest first)
  static List<LogEntry> getAllLogs() {
    return List.from(_memoryLogs.reversed);
  }

  /// Get logs filtered by level
  static List<LogEntry> getLogsByLevel(LogLevel level) {
    return _memoryLogs.reversed.where((l) => l.level == level).toList();
  }

  /// Get logs filtered by tag
  static List<LogEntry> getLogsByTag(String tag) {
    return _memoryLogs.reversed.where((l) => l.tag == tag).toList();
  }

  /// Clear all logs
  static Future<void> clearLogs() async {
    _memoryLogs.clear();
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastClearedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[LogService] Clear failed: $e');
    }
    log('Logs cleared', level: LogLevel.warning, tag: 'LogService');
  }

  /// Get count of logs by level
  static Map<LogLevel, int> getLogCounts() {
    final counts = <LogLevel, int>{
      for (var level in LogLevel.values) level: 0,
    };
    for (final log in _memoryLogs) {
      counts[log.level] = (counts[log.level] ?? 0) + 1;
    }
    return counts;
  }

  static LogEntry? _parseLogLine(String line) {
    try {
      // Parse format: [2026-03-26 10:30:00] [INFO] [Tag] message
      final regex = RegExp(r'\[(.+?)\] \[(.+?)\] \[(.+?)\] (.*)');
      final match = regex.firstMatch(line);
      if (match == null) return null;

      final timeStr = match.group(1)!;
      final levelStr = match.group(2)!;
      final tag = match.group(3)!;
      final message = match.group(4)!;

      final time = DateTime.tryParse(timeStr.replaceFirst(' ', 'T'));
      if (time == null) return null;

      LogLevel level;
      switch (levelStr) {
        case 'SUCCESS':
          level = LogLevel.success;
          break;
        case 'WARN':
          level = LogLevel.warning;
          break;
        case 'ERROR':
          level = LogLevel.error;
          break;
        case 'DEBUG':
          level = LogLevel.debug;
          break;
        default:
          level = LogLevel.info;
      }

      return LogEntry(timestamp: time, level: level, tag: tag, message: message);
    } catch (e) {
      return null;
    }
  }
}
