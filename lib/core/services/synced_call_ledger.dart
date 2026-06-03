import 'dart:math';

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
  static const String _fileNameKey = 'synced_file_names_v1';
  static const int _maxEntries = 2000;
  // A-8: Raised from 45s to 5 min. Voice recordings on a slow network
  // can easily take longer than 45s to upload (presigned URL fetch +
  // S3 PUT of a multi-MB m4a); the old TTL expired mid-upload, letting
  // another isolate re-acquire the lease and POST a duplicate. Long-
  // running calls (heartbeat-renewable) use [renewLease] below to
  // refresh the lease while still on the wire.
  static const Duration _inFlightTtl = Duration(minutes: 5);

  /// Per-isolate in-memory lock. Cheap fast-path that avoids a
  /// `SharedPreferences.reload()` for back-to-back syncs in the same
  /// isolate.
  static final Set<String> _inFlightLocal = <String>{};

  /// Random source used to generate per-attempt acquire tokens for the
  /// confirmation pattern in [tryAcquire] (A-12).
  static final Random _random = Random.secure();

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
    // A-12 note: the lease is now stored as a String "<token>|<ms>"
    // instead of an int. We migrate transparently: a legacy int lease
    // is read via getInt and treated as token "(legacy)".
    final leaseKey = '$_inFlightKeyPrefix$callId';
    int? existingLeasedAt;
    final rawString = prefs.getString(leaseKey);
    if (rawString != null) {
      final pipe = rawString.indexOf('|');
      existingLeasedAt = pipe < 0 ? null : int.tryParse(rawString.substring(pipe + 1));
    } else {
      // Legacy int storage from older builds.
      existingLeasedAt = prefs.getInt(leaseKey);
    }
    if (existingLeasedAt != null) {
      final age = DateTime.now().millisecondsSinceEpoch - existingLeasedAt;
      if (age < _inFlightTtl.inMilliseconds) return false;
      // else — stale lease (crashed sync), reclaim it below.
    }

    // A-12: SharedPreferences offers no atomic compare-and-swap, so
    // two isolates can both pass the read-check above and both write
    // their own lease. To detect that race, we write a per-attempt
    // token, immediately reload, and only own the lease if our token
    // is the one still stored. If a competitor's token is there
    // instead, we release in-memory state and refuse the lease.
    final token = _newAcquireToken();
    final valueToStore = '$token|${DateTime.now().millisecondsSinceEpoch}';
    _inFlightLocal.add(callId);
    await prefs.setString(leaseKey, valueToStore);

    // Confirmation step.
    await prefs.reload();
    final readBack = prefs.getString(leaseKey);
    final wonRace = readBack != null && readBack.startsWith('$token|');
    if (!wonRace) {
      _inFlightLocal.remove(callId);
      return false;
    }
    return true;
  }

  /// Generate a per-attempt token used by the [tryAcquire] confirmation
  /// pattern. Combines a 64-bit random with a microsecond timestamp so
  /// two attempts in the same isolate (even within the same nanosecond)
  /// produce different tokens.
  static String _newAcquireToken() {
    final r = (_random.nextInt(1 << 32) << 32) | _random.nextInt(1 << 32);
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '${r.toRadixString(16)}_${ts.toRadixString(16)}';
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

  /// Refresh the in-flight lease timestamp so it doesn't expire during a
  /// long upload. Callers that hold the lease for longer than ~2 min
  /// (e.g. large S3 PUTs on slow networks) should call this every
  /// minute or so. No-op if the lease isn't held locally.
  ///
  /// Preserves the existing acquire token (A-12) so the confirmation
  /// pattern keeps working — we don't want a renew to look like a
  /// fresh competitor's lease.
  static Future<void> renewLease(String callId) async {
    if (!_inFlightLocal.contains(callId)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final leaseKey = '$_inFlightKeyPrefix$callId';
    final current = prefs.getString(leaseKey);
    final tokenPart = current != null && current.contains('|')
        ? current.substring(0, current.indexOf('|'))
        : _newAcquireToken();
    await prefs.setString(
      leaseKey,
      '$tokenPart|${DateTime.now().millisecondsSinceEpoch}',
    );
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

  /// Returns true if a recording with [fileName] has already been synced.
  ///
  /// This is a second-line defense alongside the deterministic call_id:
  /// even if a file's timestamp drifts across a UTC-minute boundary
  /// (producing a different call_id), the filename itself stays constant,
  /// so the same physical recording can never be POSTed twice.
  static Future<bool> isFileNameSynced(String fileName) async {
    if (fileName.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final names = prefs.getStringList(_fileNameKey) ?? const [];
    return names.contains(fileName);
  }

  /// Persist [fileName] in the synced-filename history. Idempotent.
  /// Capped at [_maxEntries] with FIFO eviction.
  static Future<void> markFileNameSynced(String fileName) async {
    if (fileName.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final names = List<String>.from(prefs.getStringList(_fileNameKey) ?? const []);
    if (!names.contains(fileName)) {
      names.add(fileName);
      if (names.length > _maxEntries) {
        names.removeRange(0, names.length - _maxEntries);
      }
      await prefs.setStringList(_fileNameKey, names);
    }
  }
}
