import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/background_service.dart';
import '../domain/diagnostic_check.dart';

/// Runs the full self-test catalog defined in DEVELOPER_NOTE_DIAGNOSTIC_KIT
/// §4. Each public `run*` method updates a single [DiagnosticResult] in
/// place so the caller (DiagnosticsProvider) can stream live UI updates.
///
/// **Hard rule**: NET_PRESIGNED parses the returned `upload_url` and
/// STOPS. No file is uploaded to S3, no call is POSTed to /calls. The
/// purpose is to confirm the upload pipeline is wired without polluting
/// the backend with test data.
class DiagnosticService {
  DiagnosticService();

  // ─── Known recording paths (mirror RecordingScannerDataSourceImpl) ────
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

  static const List<String> _audioExtensions = [
    '.mp3', '.m4a', '.aac', '.wav', '.amr', '.3gp', '.ogg',
    '.opus', '.flac', '.wma',
  ];

  /// Build the empty checklist in the canonical order. The provider
  /// fills each result in place via the `run*` methods below.
  List<DiagnosticResult> buildChecklist() {
    return [
      // A. Permissions
      DiagnosticResult(
        id: 'PERM_CALLLOG',
        title: 'Call log readable',
        category: 'A. Permissions',
        severity: CheckSeverity.blocker,
        fix: FixAction.requestPermission,
      ),
      DiagnosticResult(
        id: 'PERM_STORAGE',
        title: 'Recording files readable',
        category: 'A. Permissions',
        severity: CheckSeverity.blocker,
        fix: FixAction.requestPermission,
      ),
      DiagnosticResult(
        id: 'PERM_PHONE_STATE',
        title: 'Call start/end detectable',
        category: 'A. Permissions',
        severity: CheckSeverity.blocker,
        fix: FixAction.requestPermission,
      ),
      DiagnosticResult(
        id: 'PERM_NOTIF',
        title: 'Foreground-service notification allowed',
        category: 'A. Permissions',
        severity: CheckSeverity.warning,
        fix: FixAction.requestPermission,
      ),
      DiagnosticResult(
        id: 'PERM_BATTERY',
        title: 'Battery-optimisation exemption',
        category: 'A. Permissions',
        severity: CheckSeverity.blocker,
        fix: FixAction.openBatterySettings,
      ),
      DiagnosticResult(
        id: 'PERM_CONTACTS',
        title: 'Contact-name lookup (optional)',
        category: 'A. Permissions',
        severity: CheckSeverity.info,
        fix: FixAction.requestPermission,
      ),

      // B. Recording capability
      DiagnosticResult(
        id: 'REC_FOLDER_FOUND',
        title: 'Recording folder exists on this device',
        category: 'B. Recording capability',
        severity: CheckSeverity.blocker,
        fix: FixAction.pickRecordingFolder,
      ),
      DiagnosticResult(
        id: 'REC_FOLDER_READABLE',
        title: 'App can list files in the recording folder',
        category: 'B. Recording capability',
        severity: CheckSeverity.blocker,
        fix: FixAction.requestPermission,
      ),
      DiagnosticResult(
        id: 'REC_HAS_FILES',
        title: 'Folder contains audio files',
        category: 'B. Recording capability',
        severity: CheckSeverity.warning,
        fix: FixAction.openDialerRecordingHelp,
      ),
      DiagnosticResult(
        id: 'REC_RECENT',
        title: 'A recording was created recently (last 7 days)',
        category: 'B. Recording capability',
        severity: CheckSeverity.blocker,
        fix: FixAction.openDialerRecordingHelp,
      ),
      DiagnosticResult(
        id: 'REC_CLOCK_OK',
        title: 'Device clock not skewed',
        category: 'B. Recording capability',
        severity: CheckSeverity.warning,
        fix: FixAction.openDateTimeSettings,
      ),

      // C. Auth
      DiagnosticResult(
        id: 'AUTH_LOGGED_IN',
        title: 'Token present locally',
        category: 'C. Auth',
        severity: CheckSeverity.blocker,
        fix: FixAction.reLogin,
      ),
      DiagnosticResult(
        id: 'AUTH_TOKEN_LIVE',
        title: 'Token still valid on server',
        category: 'C. Auth',
        severity: CheckSeverity.blocker,
        fix: FixAction.reLogin,
      ),
      DiagnosticResult(
        id: 'AUTH_BUSINESS_ID',
        title: 'business_id present',
        category: 'C. Auth',
        severity: CheckSeverity.blocker,
        fix: FixAction.reLogin,
      ),
      DiagnosticResult(
        id: 'AUTH_CONTEXT',
        title: 'Full account context (company_id, user_id, ...)',
        category: 'C. Auth',
        severity: CheckSeverity.warning,
        fix: FixAction.reLogin,
      ),

      // D. Network
      DiagnosticResult(
        id: 'NET_INTERNET',
        title: 'Device online',
        category: 'D. Network',
        severity: CheckSeverity.blocker,
      ),
      DiagnosticResult(
        id: 'NET_CRM_API',
        title: 'v3.getleadcrm.com reachable',
        category: 'D. Network',
        severity: CheckSeverity.blocker,
      ),
      DiagnosticResult(
        id: 'NET_PRESIGNED',
        title: 'Presigned-URL endpoint works (DRY-RUN, no upload)',
        category: 'D. Network',
        severity: CheckSeverity.blocker,
        fix: FixAction.reLogin,
      ),
      DiagnosticResult(
        id: 'NET_S3_REACHABLE',
        title: 'S3 host reachable',
        category: 'D. Network',
        severity: CheckSeverity.warning,
      ),
      DiagnosticResult(
        id: 'NET_APPVERSION',
        title: 'appversion.getleadcrm.com reachable',
        category: 'D. Network',
        severity: CheckSeverity.info,
      ),

      // E. Service health
      DiagnosticResult(
        id: 'SVC_RUNNING',
        title: 'Foreground service alive',
        category: 'E. Service health',
        severity: CheckSeverity.blocker,
        fix: FixAction.startService,
      ),
      DiagnosticResult(
        id: 'SVC_AUTOSYNC_ON',
        title: 'Auto-sync enabled',
        category: 'E. Service health',
        severity: CheckSeverity.blocker,
        fix: FixAction.enableAutoSync,
      ),
      DiagnosticResult(
        id: 'SVC_HEARTBEAT',
        title: 'Service heartbeat fresh (< 2 min)',
        category: 'E. Service health',
        severity: CheckSeverity.warning,
        fix: FixAction.startService,
      ),
      DiagnosticResult(
        id: 'SVC_WORKMANAGER',
        title: 'Backup periodic sync scheduled',
        category: 'E. Service health',
        severity: CheckSeverity.warning,
      ),
      DiagnosticResult(
        id: 'SVC_RESTART_COUNT',
        title: 'Service restart count (low = healthy)',
        category: 'E. Service health',
        severity: CheckSeverity.info,
      ),

      // F. Sync state (info-only)
      DiagnosticResult(
        id: 'SYNC_LAST_OK',
        title: 'Last successful sync',
        category: 'F. Sync state',
        severity: CheckSeverity.info,
      ),
      DiagnosticResult(
        id: 'SYNC_LEDGER_COUNT',
        title: 'Total calls synced from this device',
        category: 'F. Sync state',
        severity: CheckSeverity.info,
      ),
      DiagnosticResult(
        id: 'SYNC_PENDING',
        title: 'Local recordings not yet synced',
        category: 'F. Sync state',
        severity: CheckSeverity.info,
      ),
      DiagnosticResult(
        id: 'SYNC_RECENT_FAILURES',
        title: 'Recent sync failures',
        category: 'F. Sync state',
        severity: CheckSeverity.info,
      ),
    ];
  }

  // ─── Permission checks (A) ────────────────────────────────────────────

  Future<void> runPermCallLog(DiagnosticResult r) async {
    final s = await Permission.phone.status;
    r.technical = s.toString();
    if (s.isGranted) {
      r.status = CheckStatus.pass;
      r.detail = 'READ_CALL_LOG granted';
    } else {
      r.status = CheckStatus.fail;
      r.detail = s.isPermanentlyDenied
          ? 'Permission denied; open Settings to grant'
          : 'Permission not granted';
      r.fix = s.isPermanentlyDenied
          ? FixAction.openAppSettings
          : FixAction.requestPermission;
    }
  }

  Future<void> runPermStorage(DiagnosticResult r) async {
    if (!Platform.isAndroid) {
      r.status = CheckStatus.skipped;
      r.detail = 'Not Android';
      return;
    }
    // Without device_info_plus we can't read the precise SDK level.
    // Strategy: probe Permission.audio first (Android 13+). If it's
    // granted, treat that as "modern API" pass. Otherwise fall through
    // to manageExternalStorage (30-32) and finally legacy storage.
    final audio = await Permission.audio.status;
    final manage = await Permission.manageExternalStorage.status;
    final storage = await Permission.storage.status;
    r.technical = 'audio=$audio manage=$manage storage=$storage';
    if (audio.isGranted || manage.isGranted || storage.isGranted) {
      r.status = CheckStatus.pass;
      r.detail = 'Recording files readable';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Storage permission not granted';
      r.fix = audio.isPermanentlyDenied ||
              manage.isPermanentlyDenied ||
              storage.isPermanentlyDenied
          ? FixAction.openAppSettings
          : FixAction.requestPermission;
    }
  }

  Future<void> runPermPhoneState(DiagnosticResult r) async {
    // permission_handler bundles READ_PHONE_STATE under Permission.phone
    // on Android; reuse the same status.
    final s = await Permission.phone.status;
    r.technical = s.toString();
    if (s.isGranted) {
      r.status = CheckStatus.pass;
      r.detail = 'READ_PHONE_STATE granted';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Permission not granted';
    }
  }

  Future<void> runPermNotif(DiagnosticResult r) async {
    if (!Platform.isAndroid) {
      r.status = CheckStatus.skipped;
      return;
    }
    final s = await Permission.notification.status;
    r.technical = s.toString();
    if (s.isGranted) {
      r.status = CheckStatus.pass;
      r.detail = 'Notifications allowed';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Notifications blocked (foreground-service may not display)';
    }
  }

  Future<void> runPermBattery(DiagnosticResult r) async {
    if (!Platform.isAndroid) {
      r.status = CheckStatus.skipped;
      return;
    }
    try {
      final s = await Permission.ignoreBatteryOptimizations.status;
      r.technical = s.toString();
      if (s.isGranted) {
        r.status = CheckStatus.pass;
        r.detail = 'App is exempt from battery optimisation';
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'Battery optimiser may kill the service';
        r.fix = FixAction.openBatterySettings;
      }
    } catch (e) {
      r.status = CheckStatus.warning;
      r.detail = 'Could not query permission ($e)';
    }
  }

  Future<void> runPermContacts(DiagnosticResult r) async {
    final s = await Permission.contacts.status;
    r.technical = s.toString();
    if (s.isGranted) {
      r.status = CheckStatus.pass;
      r.detail = 'Contact-name lookup available';
    } else {
      r.status = CheckStatus.warning;
      r.detail = 'Contact names will not appear in the UI';
    }
  }

  // ─── Recording capability (B) ─────────────────────────────────────────

  /// Returns the first folder from [_recordingPaths] (plus any
  /// `custom_recording_folder` from prefs) that exists, or null.
  Future<String?> _findExistingRecordingFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final custom = prefs.getString('custom_recording_folder');
    final candidates = <String>[
      if (custom != null && custom.isNotEmpty) custom,
      ..._recordingPaths,
    ];
    for (final p in candidates) {
      try {
        if (await Directory(p).exists()) return p;
      } catch (_) {}
    }
    return null;
  }

  Future<void> runRecFolderFound(DiagnosticResult r) async {
    final found = await _findExistingRecordingFolder();
    if (found != null) {
      r.status = CheckStatus.pass;
      r.detail = found;
      r.technical = found;
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'No known call-recording folder on this device';
      r.technical = 'Tried ${_recordingPaths.length} default paths + custom';
    }
  }

  Future<void> runRecFolderReadable(DiagnosticResult r) async {
    final found = await _findExistingRecordingFolder();
    if (found == null) {
      r.status = CheckStatus.skipped;
      r.detail = 'No recording folder to check';
      return;
    }
    try {
      await Directory(found).list().take(1).toList();
      r.status = CheckStatus.pass;
      r.detail = 'Listed without error';
      r.technical = found;
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'Cannot list folder ($e)';
      r.technical = '$found: $e';
    }
  }

  Future<void> runRecHasFiles(DiagnosticResult r) async {
    final found = await _findExistingRecordingFolder();
    if (found == null) {
      r.status = CheckStatus.skipped;
      return;
    }
    int count = 0;
    try {
      await for (final e in Directory(found).list(recursive: true)) {
        if (e is File &&
            _audioExtensions.any((ext) => e.path.toLowerCase().endsWith(ext))) {
          count++;
          if (count >= 50) break; // cap scan
        }
      }
    } catch (_) {}
    r.technical = '$count audio file(s)';
    if (count > 0) {
      r.status = CheckStatus.pass;
      r.detail = '$count audio file(s) present';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'No audio files - is call recording enabled in your dialer?';
    }
  }

  Future<void> runRecRecent(DiagnosticResult r) async {
    final found = await _findExistingRecordingFolder();
    if (found == null) {
      r.status = CheckStatus.skipped;
      return;
    }
    DateTime? newest;
    String? newestPath;
    try {
      await for (final e in Directory(found).list(recursive: true)) {
        if (e is File &&
            _audioExtensions.any((ext) => e.path.toLowerCase().endsWith(ext))) {
          try {
            final stat = await e.stat();
            if (newest == null || stat.modified.isAfter(newest)) {
              newest = stat.modified;
              newestPath = e.path;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (newest == null) {
      r.status = CheckStatus.fail;
      r.detail = 'No recordings found at all';
      return;
    }
    final age = DateTime.now().difference(newest);
    r.technical = 'newest=${newest.toIso8601String()} age=${age.inHours}h '
        'path=$newestPath';
    if (age.inDays <= 7) {
      r.status = CheckStatus.pass;
      r.detail = 'Newest recording: ${_humanAge(age)} ago';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Newest recording is ${_humanAge(age)} old. '
          'Is call recording switched on in your dialer?';
    }
  }

  Future<void> runRecClockOk(DiagnosticResult r) async {
    // Use the `Date` header from any successful API response. We re-use
    // the public NET_APPVERSION endpoint pattern below; this check
    // makes its own lightweight GET so it runs independently.
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final resp = await dio.head('https://${_appVersionHost()}');
      final dateHeader = resp.headers.value('date');
      if (dateHeader == null) {
        r.status = CheckStatus.warning;
        r.detail = 'No Date header in response, cannot verify clock';
        return;
      }
      final serverTime = HttpDate.parse(dateHeader);
      final skewMs = DateTime.now().difference(serverTime).inMilliseconds.abs();
      r.technical = 'skew=${skewMs}ms';
      if (skewMs < 90 * 1000) {
        r.status = CheckStatus.pass;
        r.detail = 'Clock within ${(skewMs / 1000).toStringAsFixed(1)}s of server';
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'Clock off by ${(skewMs / 1000).toStringAsFixed(0)}s '
            '- enable "Set time automatically"';
      }
    } catch (e) {
      r.status = CheckStatus.warning;
      r.detail = 'Could not contact server to compare clock ($e)';
    }
  }

  // ─── Auth (C) ─────────────────────────────────────────────────────────

  Future<void> runAuthLoggedIn(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final t = (prefs.getString('auth_token') ??
            prefs.getString('AUTH_TOKEN') ??
            '')
        .trim();
    r.technical = 'len=${t.length}';
    if (t.isEmpty || t == 'null') {
      r.status = CheckStatus.fail;
      r.detail = 'No auth token found - please log in';
    } else if (t.split('.').length != 3 || t.length < 20) {
      r.status = CheckStatus.fail;
      r.detail = 'Auth token looks malformed - please log in again';
    } else {
      r.status = CheckStatus.pass;
      r.detail = 'Token present';
    }
  }

  Future<void> runAuthTokenLive(DiagnosticResult r, ApiClient apiClient) async {
    if (apiClient.authToken == null || apiClient.authToken!.isEmpty) {
      r.status = CheckStatus.skipped;
      r.detail = 'No token in ApiClient (run AUTH_LOGGED_IN first)';
      return;
    }
    try {
      final resp = await apiClient.dio.get(
        ApiConstants.businesses,
        options: Options(
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      r.technical = 'HTTP ${resp.statusCode}';
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        r.status = CheckStatus.pass;
        r.detail = 'Token accepted by server';
      } else if (resp.statusCode == 401) {
        r.status = CheckStatus.fail;
        r.detail = 'Token rejected (401) - please log in again';
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'Server returned HTTP ${resp.statusCode}';
      }
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'Could not reach server ($e)';
      r.technical = e.toString();
    }
  }

  Future<void> runAuthBusinessId(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getString('business_id') ?? '';
    r.technical = id.isEmpty ? '<empty>' : id;
    if (id.isNotEmpty) {
      r.status = CheckStatus.pass;
      r.detail = 'business_id stored';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'business_id missing - upload will fail';
    }
  }

  Future<void> runAuthContext(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final fields = ['company_id', 'user_id', 'user_phone', 'country_code'];
    final missing = fields.where((k) {
      final v = prefs.getString(k);
      return v == null || v.isEmpty;
    }).toList();
    r.technical = missing.isEmpty ? 'all set' : 'missing: ${missing.join(",")}';
    if (missing.isEmpty) {
      r.status = CheckStatus.pass;
      r.detail = 'Account context complete';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Missing: ${missing.join(", ")}';
    }
  }

  // ─── Network (D) ──────────────────────────────────────────────────────

  Future<void> runNetInternet(DiagnosticResult r) async {
    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        r.status = CheckStatus.pass;
        r.detail = 'DNS resolution succeeded';
        r.technical = result.first.address;
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'No internet';
      }
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'No internet ($e)';
    }
  }

  Future<void> runNetCrmApi(DiagnosticResult r, ApiClient apiClient) async {
    try {
      final resp = await apiClient.dio.get(
        ApiConstants.businesses,
        options: Options(
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      r.technical = 'HTTP ${resp.statusCode}';
      if (resp.statusCode != null && resp.statusCode! < 500) {
        r.status = CheckStatus.pass;
        r.detail = 'Reachable (HTTP ${resp.statusCode})';
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'Server error (HTTP ${resp.statusCode})';
      }
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'Cannot reach v3.getleadcrm.com';
      r.technical = e.toString();
    }
  }

  /// DRY-RUN: requests a presigned URL with diagnostic-only file name,
  /// parses the response, and STOPS. **Does not** PUT to S3 and does
  /// not POST to /calls.
  Future<void> runNetPresigned(
    DiagnosticResult r,
    ApiClient apiClient, {
    void Function(String s3Host)? onS3Host,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final businessId = prefs.getString('business_id') ?? '';
    if (businessId.isEmpty) {
      r.status = CheckStatus.skipped;
      r.detail = 'business_id missing - cannot test presigned URL';
      return;
    }
    try {
      final resp = await apiClient.dio.post(
        ApiConstants.presignedUrlForBusiness(businessId),
        data: {
          'file_name': '__diagnostic_test__.txt',
          'mime_type': 'text/plain',
          'file_size': 4,
          'resource_type': 'voice_recordings',
        },
        options: Options(
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      r.technical = 'HTTP ${resp.statusCode}';
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = resp.data;
        final uploadUrl = (data is Map) ? data['upload_url'] as String? : null;
        if (uploadUrl != null && uploadUrl.isNotEmpty) {
          r.status = CheckStatus.pass;
          r.detail = 'Presigned URL returned (NO upload performed)';
          final uri = Uri.tryParse(uploadUrl);
          if (uri != null && onS3Host != null) onS3Host(uri.host);
        } else {
          r.status = CheckStatus.fail;
          r.detail = 'Response missing upload_url';
        }
      } else if (resp.statusCode == 401) {
        r.status = CheckStatus.fail;
        r.detail = 'Auth rejected (401)';
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'Server returned HTTP ${resp.statusCode}';
      }
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'Request failed ($e)';
      r.technical = e.toString();
    }
  }

  Future<void> runNetS3Reachable(DiagnosticResult r, String? s3Host) async {
    if (s3Host == null || s3Host.isEmpty) {
      r.status = CheckStatus.skipped;
      r.detail = 'No S3 host from NET_PRESIGNED';
      return;
    }
    try {
      final result = await InternetAddress.lookup(s3Host)
          .timeout(const Duration(seconds: 5));
      if (result.isNotEmpty) {
        r.status = CheckStatus.pass;
        r.detail = 'DNS resolves ($s3Host)';
        r.technical = result.first.address;
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'DNS empty';
      }
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'Cannot reach $s3Host ($e)';
    }
  }

  Future<void> runNetAppVersion(DiagnosticResult r) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final resp = await dio.head(
        'https://${_appVersionHost()}',
        options: Options(validateStatus: (_) => true),
      );
      r.technical = 'HTTP ${resp.statusCode}';
      if (resp.statusCode != null && resp.statusCode! < 500) {
        r.status = CheckStatus.pass;
        r.detail = 'Reachable';
      } else {
        r.status = CheckStatus.warning;
        r.detail = 'HTTP ${resp.statusCode}';
      }
    } catch (e) {
      r.status = CheckStatus.warning;
      r.detail = 'Unreachable ($e)';
    }
  }

  // ─── Service health (E) ───────────────────────────────────────────────

  Future<void> runSvcRunning(DiagnosticResult r) async {
    try {
      final running = await BackgroundServiceHelper.isServiceRunning();
      r.technical = 'running=$running';
      if (running) {
        r.status = CheckStatus.pass;
        r.detail = 'Foreground service is alive';
      } else {
        r.status = CheckStatus.fail;
        r.detail = 'Service is not running';
      }
    } catch (e) {
      r.status = CheckStatus.fail;
      r.detail = 'Could not query service ($e)';
    }
  }

  Future<void> runSvcAutoSyncOn(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final on = (prefs.getBool('auto_sync_enabled') ?? false) ||
        (prefs.getBool('auto_direct_sync_enabled') ?? false);
    r.technical = 'auto_sync=${prefs.getBool('auto_sync_enabled')} '
        'auto_direct_sync=${prefs.getBool('auto_direct_sync_enabled')}';
    if (on) {
      r.status = CheckStatus.pass;
      r.detail = 'Auto-sync is enabled';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Auto-sync is OFF';
    }
  }

  Future<void> runSvcHeartbeat(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ts = prefs.getInt('last_heartbeat_ms');
    if (ts == null) {
      r.status = CheckStatus.fail;
      r.detail = 'No heartbeat recorded yet';
      return;
    }
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    r.technical = 'age_ms=$age';
    if (age < 2 * 60 * 1000) {
      r.status = CheckStatus.pass;
      r.detail = 'Heartbeat ${(age / 1000).toStringAsFixed(0)}s old';
    } else {
      r.status = CheckStatus.fail;
      r.detail = 'Heartbeat is ${_humanAge(Duration(milliseconds: age))} old '
          '(service may be a zombie)';
    }
  }

  Future<void> runSvcWorkManager(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final registered = prefs.getBool('workmanager_registered') ?? false;
    r.technical = 'registered=$registered';
    if (registered) {
      r.status = CheckStatus.pass;
      r.detail = 'Periodic backup sync is scheduled';
    } else {
      r.status = CheckStatus.warning;
      r.detail = 'WorkManager backup not confirmed registered';
    }
  }

  Future<void> runSvcRestartCount(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final n = prefs.getInt('service_restart_count') ?? 0;
    r.technical = 'count=$n';
    r.status = CheckStatus.pass; // info-only
    if (n == 0) {
      r.detail = 'No restarts recorded';
    } else if (n < 5) {
      r.detail = '$n restart(s)';
    } else {
      r.detail = '$n restart(s) - OS may be killing the service';
    }
  }

  // ─── Sync state (F) - info-only ───────────────────────────────────────

  Future<void> runSyncLastOk(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ts = prefs.getInt('last_successful_sync_ms');
    r.status = CheckStatus.pass;
    if (ts == null) {
      r.detail = 'No successful sync recorded yet';
      r.technical = '<unset>';
    } else {
      final age = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - ts);
      r.detail = '${_humanAge(age)} ago';
      r.technical = DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();
    }
  }

  Future<void> runSyncLedgerCount(DiagnosticResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ids = prefs.getStringList('synced_call_ids_v1') ?? const [];
    r.status = CheckStatus.pass;
    r.detail = '${ids.length} call(s) synced from this device';
    r.technical = 'count=${ids.length}';
  }

  Future<void> runSyncPending(DiagnosticResult r) async {
    final found = await _findExistingRecordingFolder();
    if (found == null) {
      r.status = CheckStatus.skipped;
      r.detail = 'No recording folder';
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final syncedNames = (prefs.getStringList('synced_file_names_v1') ?? const [])
        .toSet();
    int total = 0;
    int pending = 0;
    try {
      await for (final e in Directory(found).list(recursive: true)) {
        if (e is File &&
            _audioExtensions.any((ext) => e.path.toLowerCase().endsWith(ext))) {
          total++;
          final name = e.path.split('/').last;
          if (!syncedNames.contains(name)) pending++;
          if (total >= 500) break; // cap
        }
      }
    } catch (_) {}
    r.status = CheckStatus.pass;
    r.detail = '$pending unsynced / $total scanned';
    r.technical = 'pending=$pending total=$total cap=500';
    // Also expose informational warning if many pending
    if (pending > 10) {
      r.status = CheckStatus.warning;
    }
  }

  Future<void> runSyncRecentFailures(DiagnosticResult r) async {
    // We don't currently persist a failure log; this becomes meaningful
    // once SyncFailureNotifier persists. For now report ledger-derived
    // hint: leases still in-flight.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final inFlightKeys = prefs.getKeys()
        .where((k) => k.startsWith('sync_in_flight_'))
        .toList();
    r.status = CheckStatus.pass;
    r.detail = inFlightKeys.isEmpty
        ? 'No sync currently mid-flight'
        : '${inFlightKeys.length} call(s) mid-flight (may have failed and not yet retried)';
    r.technical = 'in_flight=${inFlightKeys.length}';
  }

  // ─── Header for the exported report ───────────────────────────────────

  Future<Map<String, String>> reportHeader() async {
    final info = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    // Without device_info_plus available, fall back to Platform's
    // shipped strings. They're less detailed (no manufacturer/model on
    // Android, no SDK level) but enough for a support report header.
    return {
      'app': '${info.appName} v${info.version} (${info.buildNumber})',
      'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'timestamp': DateTime.now().toIso8601String(),
      'business_id': prefs.getString('business_id') ?? '',
      'user_id': prefs.getString('user_id') ?? '',
    };
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  String _appVersionHost() {
    final uri = Uri.tryParse(ApiConstants.baseUrl);
    return uri?.host ?? 'v3.getleadcrm.com';
  }

  String _humanAge(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 30) return '${d.inDays}d';
    return '${(d.inDays / 30).toStringAsFixed(0)}mo';
  }
}
