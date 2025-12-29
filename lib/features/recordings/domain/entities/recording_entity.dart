class RecordingEntity {
  final int? id;
  final String fileName;
  final String filePath;
  final String? localPath;
  final String? phoneNumber;
  final String? contactName;
  final int duration; // in seconds
  final int fileSize; // in bytes
  final DateTime createdAt;
  final DateTime? syncedAt;
  final bool isSynced;
  final bool isUploaded;
  final String? uploadUrl; // S3 public URL
  final String? s3Path; // S3 file path for sync API
  final DateTime? uploadedAt;

  const RecordingEntity({
    this.id,
    required this.fileName,
    required this.filePath,
    this.localPath,
    this.phoneNumber,
    this.contactName,
    required this.duration,
    required this.fileSize,
    required this.createdAt,
    this.syncedAt,
    this.isSynced = false,
    this.isUploaded = false,
    this.uploadUrl,
    this.s3Path,
    this.uploadedAt,
  });

  String get displayName {
    if (contactName != null && contactName!.isNotEmpty) {
      return contactName!;
    }
    if (phoneNumber != null && phoneNumber!.isNotEmpty) {
      return phoneNumber!;
    }
    return fileName;
  }

  String get formattedDuration {
    if (duration == 0) return '0:00';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final recordingDate = DateTime(createdAt.year, createdAt.month, createdAt.day);

    if (recordingDate == today) {
      return 'Today ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    } else if (recordingDate == yesterday) {
      return 'Yesterday ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  String get playablePath => localPath ?? filePath;
}
