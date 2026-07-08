# Developer Note — Critical Fixes & In‑App Diagnostic Kit

**Project:** GL‑Calls (Flutter call‑recording sync app for GetLeadCRM)
**Audience of this doc:** the developer implementing the work
**Status:** Specification — to be implemented, then returned for re‑verification
**Date:** 2026‑06‑03

This note has **two parts**:
- **Part A — Codebase audit & critical fixes.** Bugs found in a full review of the app, prioritised, with file:line and recommended fixes. Several of these silently break sync and must be fixed.
- **Part B — In‑app diagnostic / self‑test kit.** A new "Run Diagnostics" feature so customers can self‑verify their device before relying on sync.

Some Part A fixes are **prerequisites** for Part B (token rehydration, battery‑optimisation permission, heartbeat/last‑sync timestamps) — they appear in both places; do them once.

When done, return the completion document described in §9. We will re‑verify against this note and `CLAUDE.md`.

---

# PART A — Codebase Audit & Critical Fixes

Findings from a full multi‑module review (recordings engine, background services, auth, call logs, core infra, native Android, UI). Fix in priority order. **Ignore `lib/gldocs/`** — it is a stale duplicate of the whole tree and should be deleted (see A‑37).

## A‑0. Priority summary

| # | Severity | Issue | Where |
|---|---|---|---|
| A‑1 | 🔴 Critical | Recording↔call matched by **time only (±5 min)**, not phone number | `recording_scanner_datasource.dart:278‑299` |
| A‑2 | 🔴 Critical | `call_id` **collision**: same number + same UTC minute → 2nd call dropped | `call_sync_datasource.dart:271‑281` |
| A‑3 | 🔴 Critical | `syncCalls` **only sends the first** element despite looking like a batch | `call_sync_datasource.dart:377‑390` |
| A‑4 | 🔴 Critical | **Auth token not rehydrated** into `ApiClient` on startup → unauthenticated calls | `api_client.dart` / splash / `injection_container.dart` |
| A‑5 | 🔴 Critical | "Most recent call" **fallback** when number doesn't match → wrong direction/number | `auto_sync_service.dart:905, 684` |
| A‑6 | 🔴 Critical | **No battery‑optimisation exemption** → service killed silently | manifest + runtime |
| A‑7 | 🔴 Critical | `cachedName` actually stores a **phone number** (`cachedMatchedNumber`) → UI shows numbers not names | `call_log_local_datasource.dart:29` |
| A‑8 | 🟠 High | 45s dedup lease can **expire mid‑upload** on slow networks → duplicate uploads | `synced_call_ledger.dart:34` |
| A‑9 | 🟠 High | Listener refresh every 2 min can **drop a `CALL_ENDED`** event | `background_service.dart:348‑357` |
| A‑10 | 🟠 High | `_callStartTime` **never reset** on CALL_ENDED → inflated duration next call | `auto_sync_service.dart` |
| A‑11 | 🟠 High | Filename dedup defense **only in manual sync**, not auto‑sync | `synced_call_ledger.dart:117‑145` |
| A‑12 | 🟠 High | `tryAcquire` **not atomic** across isolates → possible double‑acquire | `synced_call_ledger.dart:62‑84` |
| A‑13 | 🟠 High | **No upload retry** despite `maxRetryAttempts=3` constant | `recording_upload_datasource.dart` |
| A‑14 | 🟠 High | **Redundant watchdogs** (WorkManager + AlarmManager same job) → battery drain | services |
| A‑15 | 🟠 High | Periodic WorkManager sync **inert** unless direct‑sync mode on | `workmanager_service.dart:61‑63` |
| A‑16 | 🟠 High | **No token refresh / no 401 handling**; `isLoggedIn` trusts any non‑empty string | `api_client.dart:32‑35`, `auth_local_datasource.dart:62‑65` |
| A‑17 | 🟠 High | Reboot fragility: alarm `RebootBroadcastReceiver` **disabled** by default | `AndroidManifest.xml:104` |
| A‑18 | 🟠 High | Call logs read **entire** device log every load; no pagination; N+1 getter filtering | `call_log_local_datasource.dart:19`, `call_log_provider.dart:22‑29` |
| A‑19 | 🟡 Medium | Token stored **plaintext** in 3 prefs copies, no secure storage | `auth_local_datasource.dart:27‑30` |
| A‑20 | 🟡 Medium | Logs **plaintext password** + full login response (token) | `auth_remote_datasource.dart:51, 63` |
| A‑21 | 🟡 Medium | Permissions trivially **skippable** despite "required" copy | `permission_screen.dart:250` |
| A‑22 | 🟡 Medium | Logout uses **legacy/mismatched** endpoint | `api_constants.dart:14` |
| A‑23 | 🟡 Medium | Hardcoded **+91 India** default in many places | multiple |
| A‑24 | 🟡 Medium | `.opus/.flac/.wma` recordings **never discovered** (in MIME map, not scan list) | `recording_scanner_datasource.dart:42‑50` |
| A‑25 | 🟡 Medium | Custom folder override **replaces all** default scan paths | `recording_scanner_datasource.dart:56‑68` |
| A‑26 | 🟡 Medium | Permission inconsistency: request checks phone OR contacts, `hasPermission` only phone | `call_log_local_datasource.dart:36‑44` |
| A‑27 | 🟡 Medium | `CallType.values[index]` **no bounds check** → crash on bad value | `recording_model.dart:65` |
| A‑28 | 🟡 Medium | Hardcoded dummy file size `16044`, placeholder S3 URLs, inconsistent min‑duration (1s vs 2s) | `auto_sync_service.dart`, `call_sync_datasource.dart` |
| A‑29 | 🟡 Medium | `synced` flag on call_logs is **dead** (never set to 1); `getLastSyncTime` unused → full re‑sync every load | `call_log_*` |
| A‑30 | 🔵 Play blocker | `READ_CALL_LOG` + `MANAGE_EXTERNAL_STORAGE` — Play‑restricted, high rejection risk | manifest |
| A‑31 | 🔵 Play blocker | App ID `com.example.glcalls` — Play rejects placeholder | `build.gradle.kts:25` |
| A‑32 | 🔵 Play blocker | Release **signed with debug key** | `build.gradle.kts:39` |
| A‑33 | 🔵 Release | `FOREGROUND_SERVICE_PHONE_CALL` declared but **unused** | `AndroidManifest.xml:17` |
| A‑34 | 🔵 Release | iOS background is a **no‑op** (effectively Android‑only) | `background_service.dart:366` |
| A‑35 | 🟢 Cleanup | `home_screen.dart` 2300‑line monolith; entire **Direct‑Sync UI unreachable** (dead code) | `home_screen.dart` |
| A‑36 | 🟢 Cleanup | Profile screen mostly **inert placeholders** + fake "2.5GB/5GB", "Verified" | `profile_screen.dart` |
| A‑37 | 🟢 Cleanup | **Delete `lib/gldocs/`** duplicate tree; wrong asset paths point into it | `app_assets.dart:5‑6` |

## A‑1 … A‑7 — 🔴 Critical (fix first; these silently lose or corrupt data)

**A‑1 — Match recordings to calls by phone number, not time alone.** `_findMatchingCallLog` picks the nearest call within ±5 min and **ignores the number entirely** (`recording_scanner_datasource.dart:278‑299`). Two calls in 5 minutes → recording attributed to the wrong contact, which then flows into `call_id` and the CRM.
*Fix:* match on normalised number (last‑10‑digits) **first**, then pick the nearest in time among that number's calls. Only fall back to time‑only if the filename has no number, and flag such matches as low‑confidence.

**A‑2 — `call_id` collision drops legitimate calls.** `call_id = hash(last‑10‑digits | UTC‑minute)`, direction excluded (`call_sync_datasource.dart:271‑281`). Two real calls to/from the same number within the same minute (e.g. a quick callback) collapse to one id; the second is silently skipped as a duplicate.
*Fix:* incorporate more entropy — call‑log row id / exact start timestamp (seconds) / direction — into the id, while keeping it deterministic across the scanner and direct‑sync paths so the two paths still agree. Coordinate the new scheme with the backend.

**A‑3 — `syncCalls` only POSTs the first call.** `final firstCall = callsData.first; final body = firstCall.toJson();` then the success loop logs *every* item as "SYNCED" and marks them committed (`call_sync_datasource.dart:377‑390`). Today it's always called with a single‑element list so it's latent, but any future batch caller silently drops all‑but‑one **and** marks them done.
*Fix:* either loop and POST each call, or rename/restrict the method to a single call and remove the misleading batch loop.

**A‑4 — Rehydrate the auth token on startup.** `ApiClient._authToken` is in‑memory only; nothing restores it from prefs on foreground launch (`api_client.dart`, splash, `injection_container.dart`). A returning user reaching the dashboard makes authenticated calls **with no `Authorization` header** until background sync happens to repopulate it.
*Fix:* in DI/startup, read `AUTH_TOKEN`/`auth_token` and call `apiClient.setAuthToken(...)` before any authenticated call. *(Prerequisite for Part B `AUTH_TOKEN_LIVE`, `NET_PRESIGNED`.)*

**A‑5 — Remove the "most recent call" fallback.** When the number doesn't match, `_getCallTypeFromCallLog` / direction lookups fall back to `entries.first` and default direction to incoming (`auto_sync_service.dart:905, 684`). Under back‑to‑back calls this attaches the wrong call's direction/number.
*Fix:* if no number match within the window, mark direction/type **unknown** and either skip or sync as low‑confidence — never silently borrow another call's data.

**A‑6 — Request battery‑optimisation exemption.** The whole architecture is built to survive being killed, yet `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is **not** in the manifest and never requested, so OEM battery managers (Samsung/Xiaomi) kill the service anyway.
*Fix:* add the manifest permission + a runtime `Permission.ignoreBatteryOptimizations.request()` in onboarding. *(Prerequisite for Part B `PERM_BATTERY`.)*

**A‑7 — `cachedName` is a number, not a name.** `cachedName: entry.cachedMatchedNumber` (`call_log_local_datasource.dart:29`) stores a normalised **number**; the real cached contact name is `entry.name`. Because `displayName` prefers `cachedName`, the UI shows raw numbers even when a contact name exists.
*Fix:* use `entry.name` for the name; keep `cachedMatchedNumber` (if needed) as a separate number field.

## A‑8 … A‑18 — 🟠 High (reliability & correctness)

- **A‑8 / A‑11 / A‑12 — dedup robustness.** Raise the in‑flight lease TTL or renew it during long uploads (A‑8, `synced_call_ledger.dart:34`); use the filename dedup gate in the **auto‑sync** paths too, not just manual (A‑11, `:117‑145`); make `tryAcquire` as atomic as SharedPreferences allows or add a single‑isolate sync coordinator (A‑12, `:62‑84`). Net goal: **no duplicate uploads, no dropped calls.**
- **A‑9 — listener refresh gap.** The 2‑min stop/start of the phone‑state listener (`background_service.dart:348‑357`) can miss a `CALL_ENDED`. Avoid tearing the stream down on a timer; if a refresh is truly needed, re‑scan recent calls after re‑subscribing to catch anything missed.
- **A‑10 — reset `_callStartTime`** on CALL_ENDED (`auto_sync_service.dart`) so the next call's duration isn't inflated by stale state.
- **A‑13 — add upload retry** (the `maxRetryAttempts=3` constant is unused). Exponential backoff on `uploadToS3`, and persist a "pending upload" so a failure retries on the next cycle rather than being lost.
- **A‑14 / A‑15 — consolidate background schedulers.** WorkManager `serviceRecoveryTask` and AlarmManager health‑check do the same job (A‑14) — keep one watchdog. Make the periodic WorkManager sync actually sync in plain auto‑sync mode (A‑15, `workmanager_service.dart:61‑63`), or document why it no‑ops.
- **A‑16 — handle 401 / token expiry.** The error interceptor is a no‑op pass‑through and `isLoggedIn` trusts any non‑empty string. Add a 401 handler (refresh or force re‑login) and validate the token, not just its presence.
- **A‑17 — reboot persistence.** The alarm plugin's `RebootBroadcastReceiver` is `enabled=false` (`AndroidManifest.xml:104`); confirm the health alarm actually re‑arms after reboot (your custom `ServiceRestartReceiver` covers the service, but verify the alarm path).
- **A‑18 — call‑log performance.** Use `CallLog.query` with a date range instead of `CallLog.get()` reading the entire history every load (`call_log_local_datasource.dart:19`); memoise the incoming/outgoing/missed getters instead of re‑filtering the whole list on every rebuild (`call_log_provider.dart:22‑29`); use `getLastSyncTime` for incremental sync.

## A‑19 … A‑29 — 🟡 Medium (security & quality)

- **A‑19 / A‑20 — secrets.** Move the token to `flutter_secure_storage` and stop keeping 3 plaintext copies (A‑19). Remove logging of the password and full login/token responses (A‑20, `auth_remote_datasource.dart:51, 63`); never log tokens/passwords/full bodies.
- **A‑21 — permissions UX.** Either enforce required permissions or change the copy; today "Skip for now" lets users bypass everything while the UI says it's required.
- **A‑22 — logout endpoint** path mismatch (`api_constants.dart:14`) means server‑side session invalidation may silently fail.
- **A‑23 — country code.** Stop hardcoding `+91`; derive from the user's stored `country_code`/`country_iso`.
- **A‑24 / A‑25 — recording discovery.** Add `.opus/.flac/.wma` (and any others in the MIME map) to the scan extensions (A‑24); make the custom folder **additive** to the defaults, or clearly communicate it replaces them (A‑25).
- **A‑26 — permission check consistency** between `requestPermission` and `hasPermission` (`call_log_local_datasource.dart:36‑44`).
- **A‑27 — bounds‑check** `CallType.values[index]` before indexing (`recording_model.dart:65`).
- **A‑28 — magic values.** Replace hardcoded `16044`, placeholder S3 URLs, and the inconsistent 1s/2s min‑duration floors with named constants and one consistent rule.
- **A‑29 — call‑log sync.** Either set the `synced` flag and do incremental sync, or remove the dead column; avoid full re‑map+re‑insert on every read.

## A‑30 … A‑37 — 🔵 Play Store / release & 🟢 cleanup

> **Read before any Play Store submission.** A‑30/31/32 are hard blockers.

- **A‑30 — restricted permissions.** `READ_CALL_LOG` and `MANAGE_EXTERNAL_STORAGE` are both Play‑restricted; a call‑recording utility is unlikely to qualify and the call‑log+contacts+all‑files+silent‑upload combination is exactly the "stalkerware" pattern Google scrutinises. Decide the distribution channel (Play with a Permissions Declaration + scoped‑storage migration to `READ_MEDIA_AUDIO`/MediaStore, vs. enterprise/sideload). This is a **product/legal decision**, not just code — flag it to us.
- **A‑31 — set a real application ID** (not `com.example.glcalls`).
- **A‑32 — real signing config** for release (currently the debug key).
- **A‑33 — drop the unused `FOREGROUND_SERVICE_PHONE_CALL`** permission (no phoneCall‑typed service uses it).
- **A‑34 — iOS**: either implement background sync or make "Android‑only" explicit.
- **A‑35 / A‑36 — dead/placeholder UI.** Remove or wire up the unreachable Direct‑Sync UI and `home_screen.dart` dead builders; replace fake Profile values ("2.5GB/5GB", "Verified Account", decorative auto‑sync switch) with real data or remove them.
- **A‑37 — delete `lib/gldocs/`** and fix the asset paths in `app_assets.dart:5‑6` that point into it.

> **Note on scope:** Part B (the diagnostic kit) does not require *all* of Part A to be fixed first — but it **does** require A‑4, A‑6, and the heartbeat/last‑sync timestamps (Part B §6). At minimum fix the 🔴 Critical items; schedule the rest.

---

# PART B — Diagnostic / Self‑Test Kit

## 1. Why we are building this

We ship this app to many customers who install it on their own phones **in their own premises**. The entire value of the app is that call recordings sync to the CRM automatically in the background. The problem: **almost every failure in this app is silent.** If call recording is turned off in the dialer, if a permission is denied, if the battery optimiser kills the service, if the login token is missing — the app keeps running and looks fine, but **nothing reaches the server**, and nobody notices for days.

We need a built‑in **"Run Diagnostics" self‑test** the customer can run themselves to confirm, with a clear green/red verdict, that **everything required for calls to sync is working — before they rely on it.**

### Product decisions (already made — do not change without asking)
1. **Placement:** a **"Run Diagnostics" screen reached from the Profile menu.** Always available, re‑runnable any time. It is **not** a forced onboarding wizard.
2. **End‑to‑end test = DRY‑RUN only.** The test may authenticate and **request** an S3 presigned URL, but it must **never actually upload a file to S3 and never POST a real call to `/api/mobile/gl-dialer/calls`.** We do not want test/junk data created on the backend.
3. **Report + guided fix.** Every failed check shows a button that deep‑links the user to the exact place to fix it (grant permission, disable battery optimisation, pick recording folder, re‑login, etc.).

---

## 2. UX flow

```
Profile screen
  └─ "Run Diagnostics"  (replace one of the inert onTap:(){} rows,
                          profile_screen.dart:136/155/162/200/207)
        └─ DiagnosticsScreen
              ├─ [Run Full Self‑Test] button (primary)
              ├─ Live checklist: each check shows
              │     ⏳ running → ✅ pass / ⚠️ warning / ❌ fail
              │     subtitle = plain‑language detail
              │     trailing = [Fix] button when a guided fix exists
              ├─ Overall verdict banner at top once finished:
              │     ✅ "Ready to sync"  (no blockers failed)
              │     ⚠️ "Working, with warnings"
              │     ❌ "Not ready — N blocker(s) must be fixed"
              └─ [Copy report] / [Share report] (reuse pdf/printing/share_plus
                    already in pubspec — same as LogsScreen export)
```

- Checks run **sequentially** with a visible progress state; the screen stays responsive.
- Re‑running re‑evaluates everything fresh (call `prefs.reload()` first).
- After returning from a "Fix" deep‑link (e.g. app settings), re‑run automatically or prompt "Re‑check now".

---

## 3. Severity model

Every check has a **severity** that drives the overall verdict:

| Severity | Meaning | Effect on verdict |
|---|---|---|
| **BLOCKER** | Sync cannot work at all without this | One failed → overall ❌ "Not ready" |
| **WARNING** | Sync may work but is unreliable / degraded | Overall ⚠️ if no blockers fail |
| **INFO** | Status / context, never "fails" | Never affects verdict |

---

## 4. The full check catalog (source of truth)

Implement **every** check below. Each is: `id` · what it proves · how to check · pass criteria · severity · guided‑fix action. IDs are stable — keep them in code and in the report.

### A. Permissions & OS setup

| ID | Checks | How (Flutter) | Pass | Severity | Fix action |
|---|---|---|---|---|---|
| `PERM_CALLLOG` | Call‑log readable | `Permission.phone.status` (READ_CALL_LOG) | granted | BLOCKER | request → if permanentlyDenied `openAppSettings()` |
| `PERM_STORAGE` | Recording files readable | API‑aware: 33+ `Permission.audio`; 30–32 `Permission.manageExternalStorage`; ≤29 `Permission.storage` | granted | BLOCKER | request → settings |
| `PERM_PHONE_STATE` | Call start/end detectable | `Permission.phone` (covers READ_PHONE_STATE) | granted | BLOCKER | request |
| `PERM_NOTIF` | Foreground‑service notification allowed | `Permission.notification.status` (33+) | granted | WARNING | request |
| `PERM_BATTERY` | **Battery‑optimisation exemption** | `Permission.ignoreBatteryOptimizations.status` (must add — currently NOT implemented) | granted | BLOCKER | `Permission.ignoreBatteryOptimizations.request()` / open settings |
| `PERM_CONTACTS` | Contact‑name lookup (optional) | `Permission.contacts.status` | granted | INFO | request |

> **Note:** `PERM_BATTERY` requires adding the `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission to `AndroidManifest.xml` — it is currently missing. See §6 prerequisites.

### B. Device recording capability — **the most important category**

| ID | Checks | How | Pass | Severity | Fix action |
|---|---|---|---|---|---|
| `REC_FOLDER_FOUND` | A recording folder exists on this device | Reuse the 14 known paths in `recording_scanner_datasource.dart:24‑39` (+ `custom_recording_folder`); check `Directory.existsSync()` | at least one exists | BLOCKER | "Pick recording folder" → folder picker, save to `custom_recording_folder` |
| `REC_FOLDER_READABLE` | App can actually list files there | `directory.list()` returns without error | succeeds | BLOCKER | re‑check storage permission / pick folder |
| `REC_HAS_FILES` | Folder contains any audio files | scan for the supported extensions | ≥1 audio file | WARNING | guidance: enable call recording in dialer |
| `REC_RECENT` | **A recording was created recently** (proves dialer recording is actually ON) | newest audio file mtime within last N days (default 7) | found | BLOCKER | guidance card: "Turn on Call Recording in your Phone/Dialer app" + OEM‑specific tip |
| `REC_CLOCK_OK` | Device clock not skewed (call_id uses UTC minute) | compare device time to server time (`Date` header from any API response, or appversion endpoint) | within ±90s | WARNING | "Set date & time to automatic" → open date settings |

> `REC_RECENT` is the single check that catches the #1 real‑world failure: the customer's dialer call‑recording is simply switched off, or saves nowhere we scan. Make its guidance prominent and OEM‑aware (Samsung / Xiaomi/MIUI / Google Dialer instructions).

### C. Authentication & account

| ID | Checks | How | Pass | Severity | Fix action |
|---|---|---|---|---|---|
| `AUTH_LOGGED_IN` | Token present | `AUTH_TOKEN`/`auth_token` non‑empty in prefs | non‑empty | BLOCKER | "Log in again" → LoginScreen |
| `AUTH_TOKEN_LIVE` | Token still valid on server | authenticated `GET /api/mobile/businesses`; **must not 401** | HTTP 200 | BLOCKER | re‑login |
| `AUTH_BUSINESS_ID` | `business_id` present (needed for presigned URL) | prefs `business_id` non‑empty | non‑empty | BLOCKER | re‑login / re‑fetch businesses |
| `AUTH_CONTEXT` | `company_id`, `user_id`, `user_phone`, `country_code` set | prefs non‑empty | all set | WARNING | re‑login |

> **Depends on a prerequisite fix:** the token is currently NOT rehydrated into `ApiClient` on app start (known bug). `AUTH_TOKEN_LIVE` will falsely fail until that is fixed — fix it as part of this work (see §6).

### D. Network & backend connectivity

| ID | Checks | How | Pass | Severity | Fix action |
|---|---|---|---|---|---|
| `NET_INTERNET` | Device online | reachability / a lightweight GET | reachable | BLOCKER | "Check your internet connection" |
| `NET_CRM_API` | `v3.getleadcrm.com` reachable | `GET /api/mobile/businesses` returns a response | 2xx/auth response | BLOCKER | retry |
| `NET_PRESIGNED` | **Presigned‑URL endpoint works (DRY‑RUN)** | `POST /api/mobile/businesses/{business_id}/upload/presigned-url` with `resource_type=voice_recordings`, `file_name=__diagnostic_test__.txt`, tiny `file_size`, `mime_type=text/plain`. **Parse the returned `upload_url` and STOP. Do NOT upload to S3.** | valid `upload_url` returned | BLOCKER | re‑login / contact support |
| `NET_S3_REACHABLE` | S3 host reachable (no upload) | DNS/HEAD/`OPTIONS` to the host from the returned `upload_url` | reachable | WARNING | check network/firewall |
| `NET_APPVERSION` | `appversion.getleadcrm.com` reachable | lightweight GET/POST | reachable | INFO | — |

> **/calls cannot be safely dry‑run** (a POST creates a real call record). Do **not** call it. `AUTH_TOKEN_LIVE` + `NET_PRESIGNED` together prove auth and the upload path; note this limitation in the report text.

### E. Background service health

| ID | Checks | How | Pass | Severity | Fix action |
|---|---|---|---|---|---|
| `SVC_RUNNING` | Foreground service alive | `BackgroundServiceHelper.isServiceRunning()` (background_service.dart:228) | true | BLOCKER | "Start background service" → start it |
| `SVC_AUTOSYNC_ON` | Auto‑sync enabled | prefs `auto_sync_enabled` == true | true | BLOCKER | toggle on |
| `SVC_HEARTBEAT` | Service actually processing (not zombie) | service writes `last_heartbeat_ms` to prefs every 30s tick (add this); check it is < 2 min old | recent | WARNING | restart service |
| `SVC_WORKMANAGER` | Backup periodic sync scheduled | track a `workmanager_registered` flag set at registration | true | WARNING | re‑register |
| `SVC_RESTART_COUNT` | OS is not repeatedly killing it | read `_serviceRestartCountKey` (background_service.dart) | low / not climbing | INFO | points user to battery check |

> `SVC_HEARTBEAT` requires the service to persist a `last_heartbeat_ms` timestamp on its existing 30‑second timer (background_service.dart:333). Small addition; it is the only reliable way to prove the service isn't a zombie.

### F. Sync state & history (INFO — context for support)

| ID | Shows | How |
|---|---|---|
| `SYNC_LAST_OK` | When the last call synced successfully | persist `last_successful_sync_ms` on commit in `SyncedCallLedger` / auto_sync_service |
| `SYNC_LEDGER_COUNT` | Total calls synced from this device | size of `synced_call_ids_v1` |
| `SYNC_PENDING` | Local recordings found but not yet synced | scan vs ledger |
| `SYNC_RECENT_FAILURES` | Last few failures + reasons | read from `SyncFailureNotifier` / LogService |

---

## 5. Implementation guidance

Keep it consistent with the existing clean‑architecture layout. Reuse existing services — do **not** duplicate scanning/permission/network logic.

### 5.1 Suggested structure
```
lib/features/diagnostics/
  domain/
    diagnostic_check.dart        // enums + result model
  data/
    diagnostic_service.dart      // runs all checks, returns List<DiagnosticResult>
  presentation/
    providers/diagnostics_provider.dart   // ChangeNotifier, runs sequentially
    screens/diagnostics_screen.dart
    widgets/diagnostic_tile.dart
```

### 5.2 Result model (shape)
```dart
enum CheckStatus { pending, running, pass, warning, fail, skipped }
enum CheckSeverity { blocker, warning, info }
enum FixAction { none, openAppSettings, requestPermission, openBatterySettings,
                 pickRecordingFolder, reLogin, startService, enableAutoSync,
                 openDateTimeSettings, openDialerRecordingHelp }

class DiagnosticResult {
  final String id;            // e.g. 'REC_RECENT'
  final String title;         // user-facing
  final String category;      // A..F
  final CheckSeverity severity;
  CheckStatus status;
  String detail;              // plain-language result line
  String? technical;          // raw value for the support report
  FixAction fix;
}
```

### 5.3 Reuse, don't reinvent
- **Permissions:** `permission_handler` (same calls as `permission_screen.dart`).
- **Folders/scan:** call into `RecordingScannerDataSource` (expose a lightweight "list candidate folders + newest file" helper rather than running a full sync).
- **Network/auth:** use the shared `ApiClient` (singleton) so the diagnostic uses the **same** token path the real app does — this is what makes `AUTH_TOKEN_LIVE` meaningful.
- **Service status:** `BackgroundServiceHelper`.
- **Dedup/sync state:** `SyncedCallLedger`, `SyncFailureNotifier`, `LogService`.
- **Report export:** reuse the PDF/share pipeline from `LogsScreen` (`pdf` + `printing` + `share_plus`).

### 5.4 Report output
The "Copy/Share report" must produce a compact text + PDF block including, per check: `id`, status, severity, detail, technical value — plus a header with app version (`package_info_plus`), device model, Android SDK int, timestamp, `business_id`, `user_id`. This is what a customer sends to support when something is red.

---

## 6. Prerequisite bug‑fixes bundled into this work

These must be fixed for the diagnostics to be truthful; do them as part of this task:

1. **Rehydrate the auth token on app startup.** `ApiClient._authToken` is in‑memory only and never restored from prefs on foreground launch, so authenticated calls go out with no `Authorization` header. Set it from `AUTH_TOKEN` during DI/startup. (Without this, `AUTH_TOKEN_LIVE` and `NET_PRESIGNED` will wrongly fail.)
2. **Add `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** to `AndroidManifest.xml` and implement the runtime request, so `PERM_BATTERY` can pass and the service stops getting killed.
3. **Persist `last_heartbeat_ms`** on the service's existing 30‑second timer (background_service.dart:333) for `SVC_HEARTBEAT`.
4. **Persist `last_successful_sync_ms`** when a call commits to the ledger, for `SYNC_LAST_OK`.

---

## 7. Definition of done (acceptance criteria)

- [ ] "Run Diagnostics" reachable from Profile; replaces an inert `onTap`.
- [ ] All checks in §4 (A–F) implemented with the exact `id`s listed.
- [ ] Sequential run with live ⏳/✅/⚠️/❌ states and an overall verdict banner.
- [ ] Each BLOCKER/WARNING failure shows a working **Fix** deep‑link.
- [ ] `NET_PRESIGNED` requests a presigned URL **and stops** — verified by network capture that **no S3 PUT/POST and no `/calls` POST occurs** during a self‑test.
- [ ] Copy/Share report produces text + PDF with all fields in §5.4.
- [ ] Prerequisite fixes 1–4 in §6 implemented.
- [ ] Manual test matrix passed (see §8).
- [ ] No raw secrets/tokens printed to logs by the new code.

## 8. Manual test matrix the developer must run before returning

Run the self‑test on a real device under each condition and confirm the stated check goes red and its Fix button works:

| Scenario | Expected red check |
|---|---|
| Revoke call‑log permission | `PERM_CALLLOG` |
| Revoke storage/audio permission | `PERM_STORAGE` |
| Battery optimisation left ON for the app | `PERM_BATTERY` |
| Turn OFF call recording in the dialer, wait | `REC_RECENT` |
| Set a wrong recording folder | `REC_FOLDER_READABLE`/`REC_HAS_FILES` |
| Set device clock 5 min off | `REC_CLOCK_OK` |
| Log out | `AUTH_LOGGED_IN`, `AUTH_TOKEN_LIVE` |
| Airplane mode | `NET_INTERNET`, `NET_CRM_API`, `NET_PRESIGNED` |
| Stop the background service | `SVC_RUNNING` |
| Disable auto‑sync toggle | `SVC_AUTOSYNC_ON` |
| All correct | overall ✅ "Ready to sync", and **no upload occurred** |

---

## 9. What to send back to us (completion document)

When done, send a **completion document** that lets us re‑verify without guessing. It must contain:

1. **File map:** every new/changed file with a one‑line purpose.
2. **Check coverage table:** each `id` from §4 → file:line where it's implemented → status (done/partial/skipped) → notes.
3. **Prerequisite fixes:** for each of §6.1–6.4, the file:line of the change.
4. **Dry‑run proof:** a short note + screenshot/log showing a full self‑test run with **no S3/`/calls` network calls** (e.g. a charles/mitmproxy or logcat capture).
5. **Manual test matrix results** (§8) — pass/fail per row, on which device + Android version.
6. **Known gaps / deviations** from this spec and why.
7. A sample **exported diagnostic report** (the PDF/text).

We will re‑analyse the codebase against this document and this spec before sign‑off (see `CLAUDE.md`).
