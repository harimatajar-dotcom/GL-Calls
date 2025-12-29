import '../../domain/entities/recording_entity.dart';

class RecordingModel extends RecordingEntity {
  const RecordingModel({
    super.id,
    required super.fileName,
    required super.filePath,
    super.localPath,
    super.phoneNumber,
    super.contactName,
    required super.duration,
    required super.fileSize,
    required super.createdAt,
    super.syncedAt,
    super.isSynced,
    super.isUploaded,
    super.uploadUrl,
    super.s3Path,
    super.uploadedAt,
  });

  factory RecordingModel.fromEntity(RecordingEntity entity) {
    return RecordingModel(
      id: entity.id,
      fileName: entity.fileName,
      filePath: entity.filePath,
      localPath: entity.localPath,
      phoneNumber: entity.phoneNumber,
      contactName: entity.contactName,
      duration: entity.duration,
      fileSize: entity.fileSize,
      createdAt: entity.createdAt,
      syncedAt: entity.syncedAt,
      isSynced: entity.isSynced,
      isUploaded: entity.isUploaded,
      uploadUrl: entity.uploadUrl,
      s3Path: entity.s3Path,
      uploadedAt: entity.uploadedAt,
    );
  }

  factory RecordingModel.fromMap(Map<String, dynamic> map) {
    return RecordingModel(
      id: map['id'] as int?,
      fileName: map['file_name'] as String,
      filePath: map['file_path'] as String,
      localPath: map['local_path'] as String?,
      phoneNumber: map['phone_number'] as String?,
      contactName: map['contact_name'] as String?,
      duration: map['duration'] as int? ?? 0,
      fileSize: map['file_size'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      syncedAt: map['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['synced_at'] as int)
          : null,
      isSynced: (map['is_synced'] as int?) == 1,
      isUploaded: (map['is_uploaded'] as int?) == 1,
      uploadUrl: map['upload_url'] as String?,
      s3Path: map['s3_path'] as String?,
      uploadedAt: map['uploaded_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['uploaded_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_name': fileName,
      'file_path': filePath,
      'local_path': localPath,
      'phone_number': phoneNumber,
      'contact_name': contactName,
      'duration': duration,
      'file_size': fileSize,
      'created_at': createdAt.millisecondsSinceEpoch,
      'synced_at': syncedAt?.millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'is_uploaded': isUploaded ? 1 : 0,
      'upload_url': uploadUrl,
      's3_path': s3Path,
      'uploaded_at': uploadedAt?.millisecondsSinceEpoch,
    };
  }

  RecordingModel copyWith({
    int? id,
    String? fileName,
    String? filePath,
    String? localPath,
    String? phoneNumber,
    String? contactName,
    int? duration,
    int? fileSize,
    DateTime? createdAt,
    DateTime? syncedAt,
    bool? isSynced,
    bool? isUploaded,
    String? uploadUrl,
    String? s3Path,
    DateTime? uploadedAt,
  }) {
    return RecordingModel(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      localPath: localPath ?? this.localPath,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      isSynced: isSynced ?? this.isSynced,
      isUploaded: isUploaded ?? this.isUploaded,
      uploadUrl: uploadUrl ?? this.uploadUrl,
      s3Path: s3Path ?? this.s3Path,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}
