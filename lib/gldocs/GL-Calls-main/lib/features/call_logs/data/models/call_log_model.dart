import '../../domain/entities/call_log_entity.dart';

class CallLogModel extends CallLogEntity {
  final int? id;
  final bool synced;

  const CallLogModel({
    this.id,
    required super.name,
    required super.number,
    required super.formattedNumber,
    required super.callType,
    required super.timestamp,
    required super.duration,
    super.cachedName,
    this.synced = false,
  });

  factory CallLogModel.fromEntity(CallLogEntity entity) {
    return CallLogModel(
      name: entity.name,
      number: entity.number,
      formattedNumber: entity.formattedNumber,
      callType: entity.callType,
      timestamp: entity.timestamp,
      duration: entity.duration,
      cachedName: entity.cachedName,
    );
  }

  factory CallLogModel.fromMap(Map<String, dynamic> map) {
    return CallLogModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      number: map['number'] as String,
      formattedNumber: map['formatted_number'] as String? ?? '',
      callType: _parseCallType(map['call_type'] as String),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      duration: map['duration'] as int,
      cachedName: map['cached_name'] as String?,
      synced: (map['synced'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'number': number,
      'formatted_number': formattedNumber,
      'call_type': callType.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'duration': duration,
      'cached_name': cachedName,
      'synced': synced ? 1 : 0,
    };
  }

  static CallLogType _parseCallType(String type) {
    switch (type) {
      case 'incoming':
        return CallLogType.incoming;
      case 'outgoing':
        return CallLogType.outgoing;
      case 'missed':
        return CallLogType.missed;
      case 'rejected':
        return CallLogType.rejected;
      case 'blocked':
        return CallLogType.blocked;
      default:
        return CallLogType.unknown;
    }
  }

  CallLogModel copyWith({
    int? id,
    String? name,
    String? number,
    String? formattedNumber,
    CallLogType? callType,
    DateTime? timestamp,
    int? duration,
    String? cachedName,
    bool? synced,
  }) {
    return CallLogModel(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      formattedNumber: formattedNumber ?? this.formattedNumber,
      callType: callType ?? this.callType,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      cachedName: cachedName ?? this.cachedName,
      synced: synced ?? this.synced,
    );
  }
}
