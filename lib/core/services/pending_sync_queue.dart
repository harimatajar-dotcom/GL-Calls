import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable "sync owed" queue — fixes issue 1A + 1B in
/// ISSUE_AUTOSYNC_MISS_AND_DUPLICATE.md.
///
/// Problem it solves: the CALL_ENDED → sync trigger used to live only in
/// memory (`Future.delayed(10s)`). If the OS killed the isolate in that
/// window — very common right after a call on Samsung/Xiaomi — the sync
/// never fired and was never retried. And the backstop scan only looked
/// 1 hour back, so anything missed for >1 h was lost forever.
///
/// Model: the moment a call ends we persist a [PendingSync] entry
/// SYNCHRONOUSLY (before any delay). Every sync trigger — service start,
/// CALL_ENDED, WorkManager periodic — calls [drainableEntries] and
/// re-attempts each owed sync. An entry is only removed when the ledger
/// confirms the call actually committed ([removeEntry]) or when it
/// expires ([_maxAge], default 7 days) so a permanently-broken entry
/// can't wedge the queue.
class PendingSyncQueue {
  PendingSyncQueue._();

  static const String _key = 'pending_sync_queue_v1';
  static const int _maxEntries = 200;
  static const Duration _maxAge = Duration(days: 7);

  /// Persist a "this call owes a sync" record. Call this BEFORE any
  /// in-memory delay so a process kill can't lose the intent.
  static Future<void> enqueue(PendingSync entry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = List<String>.from(prefs.getStringList(_key) ?? const []);
    // Dedupe on the entry's stable id so re-enqueues of the same call
    // (listener + queue drain overlapping) don't grow the queue.
    if (list.any((raw) => _idOf(raw) == entry.id)) return;
    list.add(jsonEncode(entry.toJson()));
    if (list.length > _maxEntries) {
      list.removeRange(0, list.length - _maxEntries);
    }
    await prefs.setStringList(_key, list);
  }

  /// All entries still owed, oldest first. Expired entries are pruned
  /// as a side effect.
  static Future<List<PendingSync>> drainableEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = List<String>.from(prefs.getStringList(_key) ?? const []);
    final now = DateTime.now();
    final kept = <String>[];
    final out = <PendingSync>[];
    for (final raw in list) {
      try {
        final e = PendingSync.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (now.difference(e.enqueuedAt) > _maxAge) continue; // expired
        kept.add(raw);
        out.add(e);
      } catch (_) {
        // corrupt entry — drop
      }
    }
    if (kept.length != list.length) {
      await prefs.setStringList(_key, kept);
    }
    return out;
  }

  /// Remove a confirmed-synced (or hopeless) entry.
  static Future<void> removeEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = List<String>.from(prefs.getStringList(_key) ?? const []);
    list.removeWhere((raw) => _idOf(raw) == id);
    await prefs.setStringList(_key, list);
  }

  static Future<int> length() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return (prefs.getStringList(_key) ?? const []).length;
  }

  static String? _idOf(String raw) {
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)['id'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// One owed sync. [phone] may be null when the listener didn't deliver a
/// number — the drain then relies on the recording scan alone.
class PendingSync {
  final String id; // stable: phone|minute or ts-based fallback
  final String? phone;
  final DateTime callEndedAt;
  final int fallbackDuration;
  final DateTime enqueuedAt;

  PendingSync({
    required this.id,
    required this.phone,
    required this.callEndedAt,
    required this.fallbackDuration,
    required this.enqueuedAt,
  });

  factory PendingSync.forCallEnd({
    String? phone,
    required DateTime callEndedAt,
    required int fallbackDuration,
  }) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    final last10 =
        digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    final minute = DateTime.utc(
      callEndedAt.toUtc().year,
      callEndedAt.toUtc().month,
      callEndedAt.toUtc().day,
      callEndedAt.toUtc().hour,
      callEndedAt.toUtc().minute,
    ).toIso8601String();
    return PendingSync(
      id: last10.isEmpty ? 'ts_$minute' : '$last10|$minute',
      phone: phone,
      callEndedAt: callEndedAt,
      fallbackDuration: fallbackDuration,
      enqueuedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'callEndedAt': callEndedAt.toIso8601String(),
        'fallbackDuration': fallbackDuration,
        'enqueuedAt': enqueuedAt.toIso8601String(),
      };

  factory PendingSync.fromJson(Map<String, dynamic> json) => PendingSync(
        id: json['id'] as String,
        phone: json['phone'] as String?,
        callEndedAt: DateTime.parse(json['callEndedAt'] as String),
        fallbackDuration: (json['fallbackDuration'] as num?)?.toInt() ?? 0,
        enqueuedAt: DateTime.parse(json['enqueuedAt'] as String),
      );
}
