# Issue Report — Auto-Sync Misses & Duplicate Syncs

**Project:** GL-Calls (Flutter call-recording sync app for GetLeadCRM)
**Reported by:** Hari (device owner / field observation)
**Status:** FIXED (client-side) — see §7. One server-side gap (2C) remains open.
**Date reported:** 2026-07-02 · **Date fixed:** 2026-07-02
**Fix commits:** `93be763` (Problem 1), `eab5a3c` (Problem 2)

---

## 1. Symptoms as observed in the field

Two intermittent problems, both while **Auto-Sync is ON**:

1. **Sync sometimes does not happen.** After some calls the audio recording is
   never uploaded / the call never appears on the server. Other calls sync
   fine. There is no error shown to the user — it just silently doesn't sync.

2. **Sometimes the same call syncs twice.** When it *does* sync, occasionally
   the same number / call is pushed to the server **two times** (duplicate row
   on the dashboard).

Both are **intermittent** ("sometimes") — the same device works correctly for
long stretches and then misses or duplicates under different timing/conditions.

---

## 2. Root design tension (why both happen)

The app has **five triggers** that can each sync the same call:

1. Live `CALL_ENDED` listener → `_autoSyncLatestRecording`
   (`auto_sync_service.dart:94`)
2. WorkManager periodic (15 min) → scan-sync (`workmanager_service.dart`)
3. WorkManager periodic → direct-sync-from-call-log
4. Dummy-file upload path
5. Health-check restart → re-scan

This redundancy is intentional (survive being killed), but it creates a
trade-off:

- When **all** triggers fail / fire outside their windows → **Problem 1 (no sync)**
- When **two** triggers fire for the same call with slightly different data →
  **Problem 2 (duplicate)**

The dedup system is *content-addressed*:
`call_id = hash(normalized_phone | UTC-minute | direction)`.
It only works if **every** path computes a byte-identical `call_id`.

---

## 3. Problem 1 — Sync sometimes doesn't happen

| # | Cause | Chance | Why |
|---|---|---|---|
| 1A | 1-hour scan window | HIGH | `scanForLatestUnsyncedRecording` skips files older than 1 h (`recording_scanner_datasource.dart:153,174`). If the service was dead >1 h (phone off overnight, battery kill), the recording is "too old" and is never synced. |
| 1B | Non-durable 10 s delay | HIGH | On CALL_ENDED the sync is a `Future.delayed(10s)` held in memory (`auto_sync_service.dart:111`). If the OS kills the isolate in those 10 s (common right after a call on Samsung/Xiaomi), the sync never fires and is never retried — there is no persisted "sync owed" record. |
| 1C | Recording file not written within 10 s | MEDIUM | Some dialers transcode/finalise the `.m4a` slowly. At the 10 s scan the file doesn't exist yet → nothing to sync (and 1B means no retry). |
| 1D | Battery exemption not granted | HIGH | A-6 added the request, but if the user skips it the OEM kills the service → live listener dead → only WorkManager remains (throttled + bound by 1A's 1-hour window). |
| 1E | `_wasInCall` state lost | MEDIUM | Sync fires only if `_wasInCall==true` at CALL_ENDED (`:95`). If the service (re)started mid-call, the flag is false → CALL_ENDED ignored. |
| 1F | Token cleared by 401 | LOW / total | A-16 wipes the token on any 401. `_autoSyncLatestRecording` aborts if `_refreshAuthToken()` fails (`:254`). After one 401 everything silently stops until re-login. |
| 1G | Recording folder unknown / permission revoked | MEDIUM | If the dialer saves outside the 14 known paths, or storage permission is revoked, the scan finds nothing. (Detected by Part B `REC_FOLDER`/`PERM_STORAGE`.) |

**Dominant:** 1A + 1B — a non-durable trigger with no persistent retry queue,
plus a 1-hour ceiling on the backstop scan. Any recording not caught in its
first hour is lost forever.

---

## 4. Problem 2 — Duplicate syncing (same call twice)

A duplicate happens whenever two paths compute a **different `call_id`** for the
same physical call.

| # | Cause | Chance | Why |
|---|---|---|---|
| 2A | minute-bucket mismatch (scanner fallback) | MEDIUM | When the scanner can't match a call-log entry it falls back to `stat.modified` (file-write time) instead of call-log time (`recording_scanner_datasource.dart:201-203`). Direct-sync always uses call-log time (`auto_sync_service.dart:829`). If file-write is 30-90 s after call start and crosses a minute boundary → two different ids → duplicate. |
| 2B | direction-token mismatch (introduced by A-2) | MEDIUM | `call_id` now includes a direction token. If one path resolves inbound/outbound and the other gets `?`/unknown (call log not yet populated, or fallback), the tokens differ → different id → duplicate. A-2 fixed same-minute collisions but added this new duplicate surface. |
| 2C | server "at-least-once" delivery | MEDIUM | If the POST reaches the server, the row is written, but the 200 response times out on the way back — the client sees failure, releases the lease, retries the same `call_id`. Unless the server upserts on `call_id`, this is a duplicate the client cannot prevent. Entirely server-side. |
| 2D | filename gate useless for synthetic names | MEDIUM | Filename-history dedup (A-11) only helps with a stable filename. Direct-sync/dummy-file paths generate `direct_sync_<now>.wav` / `call_<now>.wav` — a new unique name every run (`auto_sync_service.dart:822`). So for those paths dedup rests entirely on `call_id` agreement (2A/2B). |
| 2E | cross-isolate race (narrowed, not closed) | LOW | A-12's write→reload→confirm narrows the window but SharedPreferences isn't truly atomic across main + WorkManager isolates. A-15 increased exposure because WorkManager now also runs the scan-sync. |
| 2F | ledger eviction at 2000 | LOW | `synced_call_ids_v1` is FIFO-capped at 2000. On a high-volume device an old `call_id` can be evicted; if that old file is still on disk and re-scanned it re-syncs. |

**Dominant:** 2A + 2B — the dedup is only as strong as the weakest agreement
between paths on phone + minute + direction. 2C (server idempotency) cannot be
fixed from the app alone.

---

## 5. Why it feels random

Both problems are timing-and-environment dependent:

- whether the recording file is written before the 10 s scan (dialer speed)
- whether the call log is updated before each path reads it (OS speed)
- whether the OEM kills the service in the post-call window (device + battery setting)
- whether two isolates wake within the same second
- whether a POST's *response* (not request) is what times out

None are deterministic, so the same phone syncs perfectly for days then
misses/duplicates under slightly different timing.

---

## 6. Recommended structural fix (not yet implemented)

The symptom-level patches (A-1…A-18) reduced but did not eliminate these. The
root fix is two changes:

1. **Durable pending-sync queue.** Persist "call X owes a sync" the moment a
   call ends; drain the queue on every trigger until the server confirms;
   never bound draining by a 1-hour window. This kills Problem 1 (1A + 1B).

2. **Single `call_id` source + server upsert.** All paths anchor `call_id` on
   the call-log entry's row-id or start-time (never file-mtime), resolve
   direction from one authoritative place, and the **server upserts on
   `call_id`**. This kills Problem 2 (2A + 2B + 2C).

Note the two problems trade off: making triggers more aggressive (fixes
no-sync) increases duplicate risk, and vice-versa. Only the durable-queue +
guaranteed-id-agreement approach resolves both at once.

---

## 7. Fix status (implemented 2026-07-02)

### Commit `93be763` — Problem 1 (missed syncs)

| Cause | Status | How |
|---|---|---|
| 1A (1-hour scan window) | ✅ Fixed | `scanForLatestUnsyncedRecording` + `_loadCallLogsOptimized` widened to 24 h |
| 1B (non-durable 10 s delay) | ✅ Fixed | New `PendingSyncQueue` (`lib/core/services/pending_sync_queue.dart`): "sync owed" entry persisted at CALL_ENDED **before** any delay; drained on post-call pass + every WorkManager 15-min tick; entry removed only after `SyncedCallLedger.isPhoneMinuteSynced` confirms commit; 7-day expiry, 200-entry cap |
| 1C (file written late) | ✅ Covered by retry | Queue re-attempts on every trigger until confirmed |
| 1D (battery kill) | ◑ Mitigated | A-6 requests exemption; queue + WorkManager now recover what the kill missed |
| 1E (`_wasInCall` lost) | ◑ Mitigated | Queue drain on service start re-attempts; the flag itself unchanged |
| 1F (401 wipes token) | ⏳ Open | Still stops all sync until re-login — by design; Part B diagnostics surface it |
| 1G (unknown folder) | ⏳ Open | Detected by Part B `REC_FOLDER_*` checks, needs user action |

### Commit `eab5a3c` — Problem 2 (duplicates)

| Cause | Status | How |
|---|---|---|
| 2A (minute-bucket mismatch) | ✅ Fixed | Direction-free `phone\|minute ±1 bucket` gate in both `_syncIfNew` impls (`SyncedCallLedger.isPhoneMinuteSynced` / `markPhoneMinuteSynced`) blocks the second path even when its call_id differs |
| 2B (direction-token mismatch) | ✅ Fixed | Same gate — direction is not part of the gate key |
| 2C (server at-least-once) | ❌ Open — **backend** | Server must upsert on `call_id`. Cannot be fixed client-side. Flag to backend team. |
| 2D (synthetic filenames unique per retry) | ✅ Fixed | `_syntheticFileName(prefix, phone, callTime)` — deterministic `<prefix>_<last10>_<utcMinute>.wav` for direct-sync + dummy paths |
| 2E (cross-isolate race) | ◑ Narrowed (A-12) | Confirmation-pattern lease; phone\|minute gate adds a second net |
| 2F (ledger eviction) | ✅ Fixed | Cap raised 2000 → 5000 |

**Accepted trade-off:** the ±1-bucket gate treats two genuine calls to the
same number within ~1 minute as one call (they collapse). This matches the
pre-A-2 behaviour and is far rarer than the duplicates it prevents.

**Tests:** `test/call_id_dedup_test.dart` updated to the post-A-2 contract
(direction in hash, token normalization, unknown-direction stability) —
12/12 passing.

**Action for backend team (2C):** make `POST /api/mobile/gl-dialer/calls`
idempotent — upsert on `call_id`. Until then a lost 200 response can still
produce one duplicate per network flake.
