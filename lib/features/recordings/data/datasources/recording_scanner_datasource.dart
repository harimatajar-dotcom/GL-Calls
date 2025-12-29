import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../models/recording_model.dart';

abstract class RecordingScannerDataSource {
  Future<List<RecordingModel>> scanForRecordings();
  Future<bool> requestPermission();
  Future<bool> hasPermission();
}

class RecordingScannerDataSourceImpl implements RecordingScannerDataSource {
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

  @override
  Future<List<RecordingModel>> scanForRecordings() async {
    final recordings = <RecordingModel>[];

    for (final basePath in _recordingPaths) {
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

                  // Try to extract phone number from filename
                  final phoneNumber = _extractPhoneNumber(fileName);

                  recordings.add(RecordingModel(
                    fileName: fileName,
                    filePath: entity.path,
                    phoneNumber: phoneNumber,
                    duration: 0, // Will be updated when playing
                    fileSize: stat.size,
                    createdAt: stat.modified,
                    isSynced: false,
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
}
