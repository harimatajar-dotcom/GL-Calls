enum CallLogType { incoming, outgoing, missed, rejected, blocked, unknown }

class CallLogEntity {
  final String name;
  final String number;
  final String formattedNumber;
  final CallLogType callType;
  final DateTime timestamp;
  final int duration; // in seconds
  final String? cachedName;

  const CallLogEntity({
    required this.name,
    required this.number,
    required this.formattedNumber,
    required this.callType,
    required this.timestamp,
    required this.duration,
    this.cachedName,
  });

  String get displayName => cachedName ?? (name.isNotEmpty ? name : number);

  String get formattedDuration {
    if (duration == 0) return '0:00';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (callDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (callDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(timestamp).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
