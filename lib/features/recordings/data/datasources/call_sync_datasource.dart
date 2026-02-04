import 'dart:math';
import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/recording_entity.dart';
import '../models/recording_model.dart';

class CallSyncData {
  final String callId;
  final String phoneNumber;
  final String callStartAt;
  final int duration;
  final String eventType;
  final String direction;
  final String? recordingUrl;

  CallSyncData({
    required this.callId,
    required this.phoneNumber,
    required this.callStartAt,
    required this.duration,
    required this.eventType,
    required this.direction,
    this.recordingUrl,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'call_id': callId,
      'phone_number': phoneNumber,
      'call_start_at': callStartAt,
      'duration': duration,
      'event_type': eventType,
      'direction': direction,
    };

    if (recordingUrl != null) {
      json['recording_url'] = recordingUrl;
    }

    return json;
  }

  factory CallSyncData.fromRecording(RecordingModel recording) {
    // Generate random call_id
    final callId = _generateRandomCallId();

    // Format call_start_at as current sync time (YYYY-MM-DD HH:MM:SS)
    final callStartAt = _formatDateTime(DateTime.now());

    // For non-missed calls, ensure minimum duration of 2s
    final effectiveDuration = (recording.callType != CallType.missed && recording.duration == 0) ? 2 : recording.duration;

    // Determine event type based on call type
    String eventType;
    if (recording.callType == CallType.missed) {
      eventType = 'missed';
    } else {
      eventType = 'answered';
    }

    // Determine direction from actual call type
    String direction;
    switch (recording.callType) {
      case CallType.incoming:
        direction = 'inbound';
        break;
      case CallType.outgoing:
        direction = 'outbound';
        break;
      case CallType.missed:
        direction = 'inbound'; // Missed calls are typically incoming
        break;
      case CallType.unknown:
        // Fallback: use inbound as default
        direction = 'inbound';
        break;
    }

    return CallSyncData(
      callId: callId,
      phoneNumber: recording.phoneNumber ?? 'unknown',
      callStartAt: callStartAt,
      duration: effectiveDuration,
      eventType: eventType,
      direction: direction,
      // Use full CloudFront URL (S3 URL)
      recordingUrl: recording.uploadUrl,
    );
  }

  /// Create CallSyncData from recording without recording URL
  /// Used when file is not found but we still want to sync call metadata
  factory CallSyncData.fromRecordingWithoutUrl(RecordingModel recording) {
    // Generate random call_id
    final callId = _generateRandomCallId();

    // Format call_start_at as current sync time (YYYY-MM-DD HH:MM:SS)
    final callStartAt = _formatDateTime(DateTime.now());

    // For non-missed calls, ensure minimum duration of 2s
    final effectiveDuration = (recording.callType != CallType.missed && recording.duration == 0) ? 2 : recording.duration;

    // Determine event type based on call type
    String eventType;
    if (recording.callType == CallType.missed) {
      eventType = 'missed';
    } else {
      eventType = 'answered';
    }

    // Determine direction from actual call type
    String direction;
    switch (recording.callType) {
      case CallType.incoming:
        direction = 'inbound';
        break;
      case CallType.outgoing:
        direction = 'outbound';
        break;
      case CallType.missed:
        direction = 'inbound'; // Missed calls are typically incoming
        break;
      case CallType.unknown:
        // Fallback: use inbound as default
        direction = 'inbound';
        break;
    }

    return CallSyncData(
      callId: callId,
      phoneNumber: recording.phoneNumber ?? 'unknown',
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
  }) {
    // Generate random call_id
    final callId = _generateRandomCallId();

    // Format call_start_at
    final callStartAt = _formatDateTime(callTime ?? DateTime.now());

    // For non-missed calls, ensure minimum duration of 2s so eventType is 'answered'
    // Some phones don't provide call duration, but the call was still answered
    final effectiveDuration = (callType != CallType.missed && duration == 0) ? 2 : duration;

    // Determine event type based on call type and duration
    String eventType;
    if (callType == CallType.missed) {
      eventType = 'missed';
    } else {
      eventType = 'answered';
    }

    // Determine direction from call type
    String direction;
    switch (callType) {
      case CallType.incoming:
        direction = 'inbound';
        break;
      case CallType.outgoing:
        direction = 'outbound';
        break;
      case CallType.missed:
        direction = 'inbound';
        break;
      case CallType.unknown:
        direction = 'inbound';
        break;
    }

    // Use placeholder URL for direct sync
    const placeholderUrl = 'https://glcalls.s3.amazonaws.com/no-recording.wav';

    return CallSyncData(
      callId: callId,
      phoneNumber: phoneNumber,
      callStartAt: callStartAt,
      duration: effectiveDuration,
      eventType: eventType,
      direction: direction,
      recordingUrl: placeholderUrl,
    );
  }

  /// Generate random call ID
  static String _generateRandomCallId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = random.nextInt(999999).toString().padLeft(6, '0');
    return 'CALL_${timestamp}_$randomPart';
  }

  /// Format datetime as YYYY-MM-DD HH:MM:SS
  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
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

      final response = await apiClient.dio.post(
        '/gl-dialer/calls/sync',
        data: {
          'data': callsData.map((c) => c.toJson()).toList(),
        },
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
