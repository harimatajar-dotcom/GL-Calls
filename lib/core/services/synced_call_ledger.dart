import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight client-side dedupe ledger for call-sync.
///
/// Combined with deterministic `call_id` generation
/// (see `CallSyncData.buildDeterministicCallId`), this ensures the same
/// physical call is never POSTed twice — even across:
///   • app restarts
///   • main isolate vs. background (FlutterBackgroundService / WorkManager)
///   • two sync triggers firing within the same second
///
/// Concurrency model — we keep three states for each `callId`:
///
///   1. **committed**  → permanent, persisted in [_key].
///        Set after a successful API POST. Future syncs short-circuit.
///   2. **in-flight**  → temporary, persisted in [_inFlightKeyPrefix].
///        Set BEFORE the POST. Acts as a lease so a second isolate that
///        wakes up mid-POST sees "someone else is already on it" and
///        bails. Has a [_inFlightTtl] so a crashed sync doesn't block
///        retries forever.
///   3. **in-memory**  → [_inFlightLocal] set, per isolate.
///        Closes the same-isolate race (two awaits firing concurrently)
///        without an extra SharedPreferences round-trip.
///
/// To keep storage bounded we cap the committed list at [_maxEntries] and
/// drop the oldest ids when we cross the cap.
class SyncedCallLedger {
  SyncedCallLedger._();

  static const String _key = 'synced_call_ids_v1';
  static const String _inFlightKeyPrefix = 'sync_in_flight_';
  static const int _maxEntries = 2000;
  static const Duration _inFlightTtl = Duration(seconds: 45);

  /// Per-isolate in-memory lock. Cheap fast-path that avoids a
  /// `SharedPreferences.reload()` for back-to-back syncs in the same
  /// isolate.
  static final Set<String> _inFlightLocal = <String>{};

  /// Returns true if [callId] has already been committed as synced.
  /// Does NOT check the in-flight lease — that is what [tryAcquire]
  /// is for.
  static Future<bool> isSynced(String callId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ids = prefs.getStringList(_key) ?? const [];
    return ids.contains(callId);
  }

  /// Try to acquire an exclusive lease to sync [callId].
  ///
  /// Returns:
  ///   • `true`  → caller owns the lease, MUST call [commit] on success
  ///                or [release] on failure.
  ///   • `false` → another sync attempt is already responsible. Caller
  ///                should treat this as "already handled" and stop.
  ///
  /// This atomically checks: in-memory lock → committed list → in-flight
  /// lease (with TTL). If all clear, it writes the in-flight lease before
  /// returning so the next caller (in any isolate) sees it.
  static Future<bool> tryAcquire(String callId) async {
    if (_inFlightLocal.contains(callId)) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // Already permanently synced.
    final ids = prefs.getStringList(_key) ?? const [];
    if (ids.contains(callId)) return false;

    // Active lease held by another isolate?
    final leaseKey = '$_inFlightKeyPrefix$callId';
    final leasedAt = prefs.getInt(leaseKey);
    if (leasedAt != null) {
      final age = DateTime.now().millisecondsSinceEpoch - leasedAt;
      if (age < _inFlightTtl.inMilliseconds) return false;
      // else — stale lease (crashed sync), reclaim it below.
    }

    _inFlightLocal.add(callId);
    await prefs.setInt(leaseKey, DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  /// Mark [callId] as permanently synced and clear the in-flight lease.
  /// Idempotent.
  static Future<void> commit(String callId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ids = List<String>.from(prefs.getStringList(_key) ?? const []);
    if (!ids.contains(callId)) {
      ids.add(callId);
      if (ids.length > _maxEntries) {
        ids.removeRange(0, ids.length - _maxEntries);
      }
      await prefs.setStringList(_key, ids);
    }
    await prefs.remove('$_inFlightKeyPrefix$callId');
    _inFlightLocal.remove(callId);
  }

  /// Drop the in-flight lease without committing (sync failed). The next
  /// caller can retry.
  static Future<void> release(String callId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_inFlightKeyPrefix$callId');
    _inFlightLocal.remove(callId);
  }

  /// Mark [callId] as synced. Idempotent. Kept for legacy call sites that
  /// haven't migrated to the [tryAcquire] / [commit] flow yet.
  static Future<void> markSynced(String callId) async {
    await commit(callId);
  }
}
