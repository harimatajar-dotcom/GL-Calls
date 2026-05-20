import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows an external (system tray) push notification with sound when a
/// call sync fails. Distinct from [NotificationService] — that one is the
/// in-app notification list; this one surfaces failures on the device so
/// the user notices even when the app is closed.
///
/// Uses its own channel (`gl_dialer_sync_failure`) and notification ID
/// range starting at 2000 to stay clear of [HealthCheckService] (id 999).
class SyncFailureNotifier {
  static const String _channelId = 'gl_dialer_sync_failure';
  static const String _channelName = 'GL Dialer Sync Failures';
  static const int _baseNotificationId = 2000;
  static const int _maxNotificationIds = 100;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _nextOffset = 0;

  /// One-time setup. Safe to call multiple times — re-entries are no-ops.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _notifications.initialize(initSettings);

      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Alerts when a call sync fails to upload to the server',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      _initialized = true;
      debugPrint('[SyncFailureNotifier] Initialized');
    } catch (e) {
      debugPrint('[SyncFailureNotifier] Init failed: $e');
    }
  }

  /// Show a push notification for a failed sync. Plays the channel's
  /// default sound and vibrates per Android's high-importance behavior.
  ///
  /// [phoneNumber] — the number associated with the call (best-effort; may
  /// be null/unknown).
  /// [reason] — short reason string ("Network error", "S3 upload failed",
  /// "Server rejected", etc.). Shown in the notification body.
  static Future<void> notifyFailure({
    String? phoneNumber,
    required String reason,
  }) async {
    // Init lazily so call sites don't have to remember to call init().
    if (!_initialized) await initialize();
    if (!_initialized) return; // init failed; nothing to do

    try {
      final displayPhone = (phoneNumber == null || phoneNumber.isEmpty)
          ? 'Unknown number'
          : phoneNumber;

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Alerts when a call sync fails to upload to the server',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFE53935),
        playSound: true,
        enableVibration: true,
      );

      final details = NotificationDetails(
        android: androidDetails.copyWithBigText(
          'Call with $displayPhone could not be synced.\n$reason\n'
          'It will retry automatically on the next sync attempt.',
        ),
      );

      // Each failure gets its own id (within a small ring) so the OS
      // doesn't collapse them into a single notification when several
      // fail in a row.
      final id = _baseNotificationId + _nextOffset;
      _nextOffset = (_nextOffset + 1) % _maxNotificationIds;

      await _notifications.show(
        id,
        '⚠️ Call Sync Failed',
        'Sync failed for $displayPhone — tap for details',
        details,
      );
      debugPrint('[SyncFailureNotifier] Shown id=$id phone=$displayPhone reason=$reason');
    } catch (e) {
      debugPrint('[SyncFailureNotifier] Show failed: $e');
    }
  }
}

extension on AndroidNotificationDetails {
  /// Returns a copy of these details with a [BigTextStyleInformation] body
  /// applied. Works around `AndroidNotificationDetails` not having a
  /// `copyWith` constructor.
  AndroidNotificationDetails copyWithBigText(String text) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      ongoing: ongoing,
      autoCancel: autoCancel,
      icon: icon,
      color: color,
      playSound: playSound,
      enableVibration: enableVibration,
      styleInformation: BigTextStyleInformation(text),
    );
  }
}
