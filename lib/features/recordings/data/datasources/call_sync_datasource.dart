import 'package:call_log/call_log.dart' as call_log;
import 'package:dio/dio.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/recording_entity.dart';
import '../models/recording_model.dart';

class CallSyncData {
  final String callId;
  final String phoneNumber;
  final String? countryCode;
  final String callStartAt;
  final int duration;
  final String eventType;
  final String direction;
  final String? recordingUrl;
  final String? filePath;  // S3 key - backend uses this to generate signed download URLs
  final String? fileName;
  final String? fileMimeType;

  CallSyncData({
    required this.callId,
    required this.phoneNumber,
    this.countryCode,
    required this.callStartAt,
    required this.duration,
    required this.eventType,
    required this.direction,
    this.recordingUrl,
    this.filePath,
    this.fileName,
    this.fileMimeType,
  });

  Map<String, dynamic> toJson() {
    // Server requires recording_url to be a relative S3 key
    // (no protocol, no leading slash). file_path from presigned URL is the right value.
    final pathOrUrl = (filePath != null && filePath!.isNotEmpty)
        ? filePath!.replaceFirst(RegExp(r'^/+'), '') // strip leading slashes
        : recordingUrl;

    return {
      'call_id': callId,
      'phone_number': phoneNumber,
      if (countryCode != null && countryCode!.isNotEmpty) 'country_code': countryCode,
      'call_start_at': callStartAt,
      'duration': duration,
      'event_type': eventType,
      'direction': direction,
      'recording_url': pathOrUrl,
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (fileMimeType != null) 'file_mime_type': fileMimeType,
    };
  }

  factory CallSyncData.fromRecording(
    RecordingModel recording, {
    String? countryCode,
  }) {
    final phoneNumber = _normalizePhoneForWire(
      recording.phoneNumber ?? 'unknown',
      countryCode,
    );
    final direction = _directionFor(recording.callType);

    // Deterministic call_id derived from (phone + actual call time + direction).
    // Same recording → same call_id, so retries don't create duplicate rows.
    final callId = buildDeterministicCallId(
      phoneNumber: phoneNumber,
      callTime: recording.createdAt,
      direction: direction,
    );

    // Use the ACTUAL call/recording time, not the sync time.
    final callStartAt = _formatDateTime(recording.createdAt);

    // For non-missed calls, ensure minimum duration of 2s
    final effectiveDuration = (recording.callType != CallType.missed && recording.duration == 0) ? 2 : recording.duration;

    // Determine event type based on call type
    final eventType = recording.callType == CallType.missed ? 'missed' : 'answered';

    return CallSyncData(
      callId: callId,
      phoneNumber: phoneNumber,
      countryCode: countryCode,
      callStartAt: callStartAt,
      duration: effectiveDuration,
      eventType: eventType,
      direction: direction,
      // Use full S3/CloudFront URL
      recordingUrl: recording.uploadUrl,
      // S3 key - backend uses this for generating signed GET URLs on private bucket
      filePath: recording.s3Path,
      fileName: recording.fileName,
      fileMimeType: _mimeFromFileName(recording.fileName),
    );
  }

  /// Prepend the user's country code (digits only) to bare 10-digit
  /// numbers so the server gets the full international form.
  ///
  /// Strict rule: ONLY rewrites when the input is EXACTLY 10 digits with
  /// no other characters. Anything else — already-prefixed numbers,
  /// numbers with `+`, spaces, dashes, or any length other than 10 — is
  /// returned unchanged.
  ///
  /// This is wire-format normalization only. It does NOT affect the
  /// deterministic call_id (which always uses last-10-digit hashing), so
  /// previously-synced calls stay matched in the dedup ledger after the
  /// fix lands.
  static String _normalizePhoneForWire(String phoneNumber, String? countryCode) {
    if (phoneNumber.isEmpty || phoneNumber == 'unknown') return phoneNumber;
    // Strict match: exactly 10 digits, no leading +, no spaces, no dashes.
    final isBareTen = RegExp(r'^\d{10}$').hasMatch(phoneNumber);
    if (!isBareTen) return phoneNumber;
    // Default to "+91" when no preference is stored (matches the rest of
    // the codebase's India-default behavior).
    final cc = (countryCode == null || countryCode.isEmpty ? '+91' : countryCode)
        .replaceAll(RegExp(r'\D'), '');
    if (cc.isEmpty) return phoneNumber;
    return '$cc$phoneNumber';
  }

  /// Resolve mime type from filename extension
  static String _mimeFromFileName(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'amr':
        return 'audio/amr';
      case '3gp':
        return 'audio/3gpp';
      default:
        return 'audio/mp4';
    }
  }

  /// Create CallSyncData from recording without recording URL
  /// Used when file is not found but we still want to sync call metadata
  factory CallSyncData.fromRecordingWithoutUrl(
    RecordingModel recording, {
    String? countryCode,
  }) {
    final phoneNumber = _normalizePhoneForWire(
      recording.phoneNumber ?? 'unknown',
      countryCode,
    );
    final direction = _directionFor(recording.callType);

    final callId = buildDeterministicCallId(
      phoneNumber: phoneNumber,
      callTime: recording.createdAt,
      direction: direction,
    );

    final callStartAt = _formatDateTime(recording.createdAt);

    // For non-missed calls, ensure minimum duration of 2s
    final effectiveDuration = (recording.callType != CallType.missed && recording.duration == 0) ? 2 : recording.duration;

    final eventType = recording.callType == CallType.missed ? 'missed' : 'answered';

    return CallSyncData(
      callId: callId,
      phoneNumber: phoneNumber,
      countryCode: countryCode,
      callStartAt: callStartAt,
      duration: effectiveDuration,
      eventType: eventType,
      direction: direction,
      recordingUrl: null, // No recording URL since file not found
    );
  }

  /// Direct sync - Create CallSyncData with placeholder URL for direct API sync
  /// Used for syncing call data directly without S3 upload
  factory CallSyncData.forDirectSync({
    required String phoneNumber,
    required int duration,
    required CallType callType,
    DateTime? callTime,
    String? countryCode,
  }) {
    final direction = _directionFor(callType);
    final effectiveCallTime = callTime ?? DateTime.now();
    final normalizedPhone = _normalizePhoneForWire(phoneNumber, countryCode);

    final callId = buildDeterministicCallId(
      phoneNumber: normalizedPhone,
      callTime: effectiveCallTime,
      direction: direction,
    );

    final callStartAt = _formatDateTime(effectiveCallTime);

    // For non-missed calls, ensure minimum duration of 2s so eventType is 'answered'
    // Some phones don't provide call duration, but the call was still answered
    final effectiveDuration = (callType != CallType.missed && duration == 0) ? 2 : duration;

    final eventType = callType == CallType.missed ? 'missed' : 'answered';

    // Use placeholder URL for direct sync
    const placeholderUrl = 'https://glcalls.s3.amazonaws.com/no-recording.wav';

    return CallSyncData(
      callId: callId,
      phoneNumber: normalizedPhone,
      countryCode: countryCode,
      callStartAt: callStartAt,
      duration: effectiveDuration,
      eventType: eventType,
      direction: direction,
      recordingUrl: placeholderUrl,
    );
  }

  /// Map a [CallType] to the wire-format direction string.
  static String _directionFor(CallType callType) {
    switch (callType) {
      case CallType.outgoing:
        return 'outbound';
      case CallType.incoming:
      case CallType.missed:
      case CallType.unknown:
        return 'inbound';
    }
  }

  /// Normalize a phone number to its last 10 digits for hashing.
  ///
  /// Same physical number can arrive in many forms:
  ///   "9876543210", "+91 98765 43210", "919876543210", "09876543210"
  /// All of these collapse to "9876543210" so the [call_id] stays stable
  /// across sync paths.
  static String normalizePhoneForId(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 10) return digits;
    return digits.substring(digits.length - 10);
  }

  /// Round a [DateTime] down to the start of its UTC minute. Used for
  /// hashing — millisecond/second skew between sync paths (file mtime vs.
  /// call_log timestamp) must not produce different ids for the same call.
  static DateTime bucketCallTimeToMinute(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute);
  }

  /// Build a stable call_id from the call's intrinsic properties.
  ///
  /// Hash input: `(normalized phone | UTC-minute | direction)`.
  ///
  /// Why direction is now part of the hash (A-2 fix). Previously direction
  /// was excluded to avoid phantom duplicates when the scanner and direct-
  /// sync paths disagreed on direction. With the authoritative call-log
  /// direction lookup (`resolveDirectionFromCallLog`) and the matching
  /// improvements in A-1, both paths now agree on direction reliably. The
  /// old scheme silently dropped the second of two genuine calls in
  /// opposite directions within the same minute (e.g. a quick callback) —
  /// they hashed to the same id and the second was treated as a dup.
  ///
  /// Direction is folded into a 3-state token (`in`/`out`/`?`) so that a
  /// `null`/unknown direction still produces a stable id rather than two
  /// different ids depending on which call site supplied it. Direction
  /// MUST come from the call-log resolver, not the scanner's default —
  /// see [resolveDirectionFromCallLog].
  ///
  /// Trade-off acknowledged: two genuine calls in the **same** direction
  /// to the same number within the same UTC minute still collide. That
  /// collision is rare in practice (back-to-back outbound redials are the
  /// main case) and tightening to seconds is not safe because the scanner
  /// and direct-sync paths can disagree on the second-level timestamp.
  static String buildDeterministicCallId({
    required String phoneNumber,
    required DateTime callTime,
    String? direction,
  }) {
    final phone = normalizePhoneForId(phoneNumber);
    final minute = bucketCallTimeToMinute(callTime).toIso8601String();
    final dirToken = _directionToken(direction);
    final input = '$phone|$minute|$dirToken';
    final hex = _fnv1a64Hex(input);
    return 'CALL_$hex';
  }

  /// Normalize a direction string into a stable 3-state token so the hash
  /// stays deterministic regardless of casing/null.
  static String _directionToken(String? direction) {
    if (direction == null) return '?';
    final lower = direction.toLowerCase().trim();
    if (lower == 'outbound' || lower == 'outgoing' || lower == 'out') return 'out';
    if (lower == 'inbound' || lower == 'incoming' || lower == 'in') return 'in';
    return '?';
  }

  /// Resolve the authoritative direction for a call by looking it up in
  /// the device call log. This is the SINGLE source of truth — the file
  /// scanner's default ("incoming" when unknown) must never reach the
  /// server, otherwise the dashboard mis-categorizes the call.
  ///
  /// Returns 'inbound' / 'outbound'. Falls back to [fallback] if no
  /// matching call log entry can be found within the last 30 minutes.
  static Future<String> resolveDirectionFromCallLog(
    String phoneNumber, {
    String fallback = 'inbound',
  }) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(minutes: 30));
      final entries = await call_log.CallLog.query(
        dateFrom: from.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      final wanted = normalizePhoneForId(phoneNumber);
      for (final entry in entries) {
        if (entry.number == null) continue;
        final entryDigits = normalizePhoneForId(entry.number!);
        if (entryDigits == wanted) {
          return _directionFromCallLogType(entry.callType) ?? fallback;
        }
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  static String? _directionFromCallLogType(call_log.CallType? type) {
    switch (type) {
      case call_log.CallType.outgoing:
      case call_log.CallType.wifiOutgoing:
        return 'outbound';
      case call_log.CallType.incoming:
      case call_log.CallType.missed:
      case call_log.CallType.rejected:
      case call_log.CallType.blocked:
      case call_log.CallType.voiceMail:
      case call_log.CallType.wifiIncoming:
      case call_log.CallType.answeredExternally:
        return 'inbound';
      default:
        return null;
    }
  }

  /// 64-bit FNV-1a hash → 16-char hex. Deterministic, no external deps.
  static String _fnv1a64Hex(String input) {
    // Operate in two 32-bit halves to stay within JS-safe int range.
    const int prime = 0x100000001b3;
    int hash = 0xcbf29ce484222325;
    for (final byte in input.codeUnits) {
      hash = hash ^ byte;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Format datetime as ISO 8601 timestamp (e.g. 2026-04-27T10:27:44.123Z)
  static String _formatDateTime(DateTime dt) {
    return dt.toUtc().toIso8601String();
  }
}

abstract class CallSyncDataSource {
  Future<bool> syncCall(CallSyncData callData);
  Future<bool> syncCalls(List<CallSyncData> callsData);
}

class CallSyncDataSourceImpl implements CallSyncDataSource {
  final ApiClient apiClient;

  CallSyncDataSourceImpl({required this.apiClient});

  @override
  Future<bool> syncCall(CallSyncData callData) async {
    return syncCalls([callData]);
  }

  @override
  Future<bool> syncCalls(List<CallSyncData> callsData) async {
    try {
      _logBlue('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logBlue('📞 SYNCING ${callsData.length} CALL(S)...');

      // New API: send each call as direct body (not wrapped in 'data' array)
      // Endpoint: {{baseUrl}}/api/mobile/gl-dialer/calls
      final firstCall = callsData.first;
      final body = firstCall.toJson();

      // Log full API call details in green
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('[API] 🚀 SYNC CALL REQUEST');
      _logGreen('[API] URL: ${ApiConstants.baseUrl}${ApiConstants.syncCalls}');
      _logGreen('[API] Method: POST');
      _logGreen('[API] Auth: Bearer ${apiClient.authToken?.substring(0, 20) ?? "NONE"}...');
      _logGreen('[API] Body: $body');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final response = await apiClient.dio.post(
        ApiConstants.syncCalls,
        data: body,
      );

      // Log raw API response in yellow
      _logYellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logYellow('📡 RAW API RESPONSE');
      _logYellow('   Status Code: ${response.statusCode}');
      _logYellow('   Response Data: ${response.data}');
      _logYellow('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (response.statusCode == 200 || response.statusCode == 202) {
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        _logGreen('✅ CALL SYNC API RESPONSE');
        _logGreen('   Status: ${response.statusCode}');
        _logGreen('   Response: ${response.data}');
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        for (final call in callsData) {
          _logGreen('✅ SYNCED: ${call.phoneNumber}');
          _logGreen('   Call ID: ${call.callId}');
          _logGreen('   Call Start At: ${call.callStartAt}');
          _logGreen('   Duration: ${call.duration}s');
          _logGreen('   Event Type: ${call.eventType}');
          _logGreen('   Direction: ${call.direction}');
          if (call.recordingUrl != null) {
            _logGreen('   Recording URL: ${call.recordingUrl}');
          }
        }
        _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return true;
      } else {
        _logRed('❌ SYNC FAILED: Status ${response.statusCode}');
        _logRed('   Response: ${response.data}');
        return false;
      }
    } on DioException catch (e) {
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logGreen('[API] ❌ SYNC CALL ERROR');
      _logGreen('[API] URL: ${e.requestOptions.uri}');
      _logGreen('[API] Status: ${e.response?.statusCode}');
      _logGreen('[API] Response: ${e.response?.data}');
      _logGreen('[API] Message: ${e.message}');
      _logGreen('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logRed('❌ SYNC ERROR: ${e.message}');
      return false;
    } catch (e) {
      _logRed('❌ SYNC ERROR: $e');
      return false;
    }
  }

  void _logGreen(String message) {
    print('\x1B[32m$message\x1B[0m');
  }

  void _logBlue(String message) {
    print('\x1B[34m$message\x1B[0m');
  }

  void _logYellow(String message) {
    print('\x1B[33m$message\x1B[0m');
  }

  void _logRed(String message) {
    print('\x1B[31m$message\x1B[0m');
  }
}
