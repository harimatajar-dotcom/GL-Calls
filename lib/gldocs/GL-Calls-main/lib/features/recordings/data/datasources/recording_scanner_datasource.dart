import 'dart:io';
import 'package:call_log/call_log.dart' as call_log;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/recording_entity.dart';
import '../models/recording_model.dart';

abstract class RecordingScannerDataSource {
  Future<List<RecordingModel>> scanForRecordings();
  /// Scan for only the most recent unsynced recording (optimized for auto-sync)
  Future<RecordingModel?> scanForLatestUnsyncedRecording();
  Future<bool> requestPermission();
  Future<bool> hasPermission();
  Future<int> getAudioDuration(String filePath);
}

class RecordingScannerDataSourceImpl implements RecordingScannerDataSource {
  AudioPlayer? _audioPlayer;
  List<call_log.CallLogEntry>? _callLogCache;

  // Common call recording directories on Android
  static const List<String> _recordingPaths = [
    '/storage/emulated/0/Recordings/Call',
    '/storage/emulated/0/Call',
    '/storage/emulated/0/MIUI/sound_recorder/call_rec',
    '/storage/emulated/0/Record/Call',
    '/storage/emulated/0/Sounds/CallRecord',
    '/storage/emulated/0/CallRecordings',
    '/storage/emulated/0/PhoneRecord',
    '/storage/emulated/0/Android/data/com.google.android.dialer/files/Recordings',
    '/storage/emulated/0/Music/Recordings',
    '/storage/emulated/0/Recordings',
    '/storage/emulated/0/DCIM/.callrecord',
    '/storage/emulated/0/VoiceRecorder',
    '/storage/emulated/0/Recording',
    '/storage/emulated/0/Samsung/Voice Recorder',
  ];

  // Audio file extensions
  static const List<String> _audioExtensions = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.amr',
    '.3gp',
    '.ogg',
  ];

  // Key for custom recording folder in SharedPreferences
  static const String _customRecordingFolderKey = 'custom_recording_folder';

  /// Get recording paths including custom folder if set
  Future<List<String>> _getRecordingPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final customFolder = prefs.getString(_customRecordingFolderKey);

    if (customFolder != null && customFolder.isNotEmpty) {
      // If custom folder is set, use it as the primary (and only) path
      _logCyan('📁 Using custom recording folder: $customFolder');
      return [customFolder];
    }

    // Otherwise use default paths
    return _recordingPaths;
  }

  @override
  Future<List<RecordingModel>> scanForRecordings() async {
    final recordings = <RecordingModel>[];

    // Load call logs for matching
    await _loadCallLogs();

    // Get recording paths (custom folder or default paths)
    final paths = await _getRecordingPaths();

    for (final basePath in paths) {
      final directory = Directory(basePath);
      if (await directory.exists()) {
        try {
          await for (final entity in directory.list(recursive: true)) {
            if (entity is File) {
              final extension = entity.path.toLowerCase();
              if (_audioExtensions.any((ext) => extension.endsWith(ext))) {
                try {
                  final stat = await entity.stat();
                  final fileName = entity.path.split('/').last;

                  // Try to extract phone number from filename first
                  String? phoneNumber = _extractPhoneNumber(fileName);
                  CallType callType = CallType.unknown;
                  String? contactName;

                  // If no phone number found, try to match with call log
                  if (phoneNumber == null) {
                    final matchedCall = _findMatchingCallLog(stat.modified);
                    if (matchedCall != null) {
                      phoneNumber = matchedCall.number;
                      contactName = matchedCall.name;
                      callType = _mapCallType(matchedCall.callType);
                      _logCyan('📞 MATCHED: $fileName → ${matchedCall.number} (${matchedCall.name ?? 'Unknown'})');
                    }
                  } else {
                    // Phone number found in filename, still try to get call type
                    final matchedCall = _findMatchingCallLog(stat.modified);
                    if (matchedCall != null) {
                      callType = _mapCallType(matchedCall.callType);
                      contactName = matchedCall.name;
                    }
                  }

                  recordings.add(RecordingModel(
                    fileName: fileName,
                    filePath: entity.path,
                    phoneNumber: phoneNumber,
                    contactName: contactName,
                    duration: 0, // Will be updated when playing
                    fileSize: stat.size,
                    createdAt: stat.modified,
                    isSynced: false,
                    callType: callType,
                  ));
                } catch (e) {
                  // Skip files we can't read
                }
              }
            }
          }
        } catch (e) {
          // Skip directories we can't access
        }
      }
    }

    // Sort by creation date, newest first
    recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return recordings;
  }

  @override
  Future<RecordingModel?> scanForLatestUnsyncedRecording() async {
    _logCyan('🔍 OPTIMIZED SCAN: Looking for latest recording (last 1 hour)...');

    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    RecordingModel? latestRecording;

    // Load call logs only for the last 1 hour
    await _loadCallLogsOptimized();

    // Get recording paths (custom folder or default paths)
    final paths = await _getRecordingPaths();

    for (final basePath in paths) {
      final directory = Directory(basePath);
      if (await directory.exists()) {
        try {
          await for (final entity in directory.list(recursive: true)) {
            if (entity is File) {
              final extension = entity.path.toLowerCase();
              if (_audioExtensions.any((ext) => extension.endsWith(ext))) {
                try {
                  final stat = await entity.stat();

                  // Skip files older than 1 hour
                  if (stat.modified.isBefore(oneHourAgo)) {
                    continue;
                  }

                  final fileName = entity.path.split('/').last;

                  // Try to extract phone number from filename first
                  String? phoneNumber = _extractPhoneNumber(fileName);
                  CallType callType = CallType.unknown;
                  String? contactName;

                  // Match with call log to get phone number and call type
                  final matchedCall = _findMatchingCallLog(stat.modified);
                  if (matchedCall != null) {
                    phoneNumber ??= matchedCall.number;
                    contactName = matchedCall.name;
                    callType = _mapCallType(matchedCall.callType);
                    _logCyan('📞 MATCHED: $fileName → ${matchedCall.number} (${matchedCall.name ?? 'Unknown'})');
                  }

                  final recording = RecordingModel(
                    fileName: fileName,
                    filePath: entity.path,
                    phoneNumber: phoneNumber,
                    contactName: contactName,
                    duration: 0,
                    fileSize: stat.size,
                    createdAt: stat.modified,
                    isSynced: false,
                    callType: callType,
                  );

                  // Keep the most recent recording
                  if (latestRecording == null ||
                      recording.createdAt.isAfter(latestRecording.createdAt)) {
                    latestRecording = recording;
                  }
                } catch (e) {
                  // Skip files we can't read
                }
              }
            }
          }
        } catch (e) {
          // Skip directories we can't access
        }
      }
    }

    if (latestRecording != null) {
      _logCyan('✅ Found latest recording: ${latestRecording.fileName}');
    } else {
      _logCyan('ℹ️ No recent recordings found in last 1 hour');
    }

    return latestRecording;
  }

  /// Load call logs optimized for last 1 hour only
  Future<void> _loadCallLogsOptimized() async {
    try {
      final hasAccess = await Permission.phone.status;
      if (hasAccess.isGranted) {
        final now = DateTime.now();
        final lastHour = now.subtract(const Duration(hours: 1));

        final entries = await call_log.CallLog.query(
          dateFrom: lastHour.millisecondsSinceEpoch,
          dateTo: now.millisecondsSinceEpoch,
        );
        _callLogCache = entries.toList();
        _logCyan('📋 Loaded ${_callLogCache?.length ?? 0} call log entries (last 1h - optimized)');
      }
    } catch (e) {
      debugPrint('Error loading call logs: $e');
      _callLogCache = [];
    }
  }

  /// Load call logs into cache (only last 24 hours for performance)
  Future<void> _loadCallLogs() async {
    try {
      final hasAccess = await Permission.phone.status;
      if (hasAccess.isGranted) {
        // Only load call logs from last 24 hours for performance
        final now = DateTime.now();
        final last24Hours = now.subtract(const Duration(hours: 24));

        final entries = await call_log.CallLog.query(
          dateFrom: last24Hours.millisecondsSinceEpoch,
          dateTo: now.millisecondsSinceEpoch,
        );
        _callLogCache = entries.toList();
        _logCyan('📋 Loaded ${_callLogCache?.length ?? 0} call log entries (last 24h)');
      }
    } catch (e) {
      debugPrint('Error loading call logs: $e');
      _callLogCache = [];
    }
  }

  /// Find matching call log entry by timestamp (within 5 minutes tolerance)
  call_log.CallLogEntry? _findMatchingCallLog(DateTime recordingTime) {
    if (_callLogCache == null || _callLogCache!.isEmpty) return null;

    const toleranceMinutes = 5;
    call_log.CallLogEntry? bestMatch;
    int smallestDiff = toleranceMinutes * 60 * 1000 + 1; // milliseconds

    for (final entry in _callLogCache!) {
      if (entry.timestamp == null) continue;

      final callTime = DateTime.fromMillisecondsSinceEpoch(entry.timestamp!);
      final diff = (recordingTime.millisecondsSinceEpoch - callTime.millisecondsSinceEpoch).abs();

      // Within tolerance and closer than previous match
      if (diff < toleranceMinutes * 60 * 1000 && diff < smallestDiff) {
        smallestDiff = diff;
        bestMatch = entry;
      }
    }

    return bestMatch;
  }

  /// Map call_log package CallType to our CallType
  CallType _mapCallType(call_log.CallType? type) {
    switch (type) {
      case call_log.CallType.incoming:
        return CallType.incoming;
      case call_log.CallType.outgoing:
        return CallType.outgoing;
      case call_log.CallType.missed:
        return CallType.missed;
      default:
        return CallType.unknown;
    }
  }

  String? _extractPhoneNumber(String fileName) {
    // Common patterns for phone numbers in recording filenames
    // Pattern 1: +91XXXXXXXXXX or 91XXXXXXXXXX
    // Pattern 2: XXXXXXXXXX (10 digits)
    // Pattern 3: Separated by - or _ or spaces

    final cleanName = fileName.replaceAll(RegExp(r'[^0-9+]'), ' ');
    final numbers = cleanName.split(' ').where((s) => s.length >= 10).toList();

    for (final num in numbers) {
      if (num.length >= 10 && num.length <= 15) {
        return num;
      }
    }

    return null;
  }

  @override
  Future<bool> requestPermission() async {
    // Request storage permissions
    if (Platform.isAndroid) {
      // Request phone permission for call logs
      await Permission.phone.request();

      // For Android 13+
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;

      // For older Android versions
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // Request manage external storage for full access
      final manageStatus = await Permission.manageExternalStorage.request();
      return manageStatus.isGranted;
    }

    return false;
  }

  @override
  Future<bool> hasPermission() async {
    if (Platform.isAndroid) {
      // Check audio permission first (Android 13+)
      final audioStatus = await Permission.audio.status;
      if (audioStatus.isGranted) return true;

      // Check storage permission
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;

      // Check manage external storage
      final manageStatus = await Permission.manageExternalStorage.status;
      return manageStatus.isGranted;
    }

    return false;
  }

  @override
  Future<int> getAudioDuration(String filePath) async {
    try {
      _audioPlayer ??= AudioPlayer();
      final duration = await _audioPlayer!.setFilePath(filePath);
      await _audioPlayer!.stop();
      return duration?.inSeconds ?? 0;
    } catch (e) {
      debugPrint('Error getting audio duration: $e');
      return 0;
    }
  }

  void _logCyan(String message) {
    print('\x1B[36m$message\x1B[0m');
  }
}
