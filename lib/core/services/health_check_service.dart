import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_service.dart';

const int _healthCheckAlarmId = 1001;
const int _healthAlertNotificationId = 999;
const String _healthChannelId = 'gl_dialer_health';
const String _healthChannelName = 'GL Dialer Service Health';

/// Health check service that uses AlarmManager (Samsung-resistant)
/// to monitor background service and alert user via notification when it stops
class HealthCheckService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize health check (call from main.dart)
  static Future<void> initialize() async {
    try {
      await AndroidAlarmManager.initialize();
      await _initNotificationChannel();
      debugPrint('[HealthCheck] Initialized');
    } catch (e) {
      debugPrint('[HealthCheck] Init failed: $e');
    }
  }

  /// Create high-priority notification channel for health alerts
  static Future<void> _initNotificationChannel() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _healthChannelId,
        _healthChannelName,
        description: 'Alerts when auto-sync service stops working',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Start periodic health check (every 15 minutes)
  static Future<void> startHealthCheck() async {
    try {
      // Cancel any existing alarm
      await AndroidAlarmManager.cancel(_healthCheckAlarmId);

      // Schedule new periodic alarm
      final success = await AndroidAlarmManager.periodic(
        const Duration(minutes: 15),
        _healthCheckAlarmId,
        _performHealthCheck,
        wakeup: true,
        rescheduleOnReboot: true,
        exact: true,
        allowWhileIdle: true,
      );

      debugPrint('[HealthCheck] Started: $success');
    } catch (e) {
      debugPrint('[HealthCheck] Failed to start: $e');
    }
  }

  /// Stop health check
  static Future<void> stopHealthCheck() async {
    try {
      await AndroidAlarmManager.cancel(_healthCheckAlarmId);
      await _notifications.cancel(_healthAlertNotificationId);
      debugPrint('[HealthCheck] Stopped');
    } catch (e) {
      debugPrint('[HealthCheck] Failed to stop: $e');
    }
  }

  /// Show alert notification when service is dead
  static Future<void> _showServiceDeadAlert() async {
    const androidDetails = AndroidNotificationDetails(
      _healthChannelId,
      _healthChannelName,
      channelDescription: 'Alerts when auto-sync service stops working',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFE53935),
      styleInformation: BigTextStyleInformation(
        'Auto-sync has stopped working. Tap here to restart it and ensure your calls are synced.',
        contentTitle: '⚠️ Auto-Sync Stopped',
      ),
      actions: [
        AndroidNotificationAction(
          'restart_service',
          'Restart Now',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _healthAlertNotificationId,
      '⚠️ Auto-Sync Stopped',
      'Tap to restart the call sync service',
      details,
      payload: 'restart_service',
    );

    debugPrint('[HealthCheck] Alert notification shown');
  }

  /// Handle notification tap - restart service
  static void _onNotificationTapped(NotificationResponse response) async {
    debugPrint('[HealthCheck] Notification tapped: ${response.payload}');
    if (response.payload == 'restart_service' ||
        response.actionId == 'restart_service') {
      await BackgroundServiceHelper.startService();
      await _notifications.cancel(_healthAlertNotificationId);
    }
  }
}

/// Top-level function called by AlarmManager
@pragma('vm:entry-point')
Future<void> _performHealthCheck() async {
  debugPrint('[HealthCheck] ━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('[HealthCheck] Running health check at ${DateTime.now()}');

  try {
    final prefs = await SharedPreferences.getInstance();
    final isAutoSyncEnabled = prefs.getBool('auto_sync_enabled') ?? false;
    final isAutoDirectSyncEnabled = prefs.getBool('auto_direct_sync_enabled') ?? false;

    if (!isAutoSyncEnabled && !isAutoDirectSyncEnabled) {
      debugPrint('[HealthCheck] Auto-sync disabled, no check needed');
      return;
    }

    // Check if service is running
    final isRunning = await BackgroundServiceHelper.isServiceRunning();
    debugPrint('[HealthCheck] Service running: $isRunning');

    if (!isRunning) {
      // Try to restart service silently first
      debugPrint('[HealthCheck] Service dead, attempting restart...');
      await BackgroundServiceHelper.startService();

      // Wait a bit and check again
      await Future.delayed(const Duration(seconds: 3));
      final restarted = await BackgroundServiceHelper.isServiceRunning();

      if (!restarted) {
        // Auto-restart failed, alert the user
        debugPrint('[HealthCheck] Auto-restart FAILED, showing alert');
        await HealthCheckService._showServiceDeadAlert();
      } else {
        debugPrint('[HealthCheck] Service restarted successfully');
        // Update last check timestamp
        await prefs.setInt(
          'last_health_check',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } else {
      // Service is running, all good
      await prefs.setInt(
        'last_health_check',
        DateTime.now().millisecondsSinceEpoch,
      );
      // Cancel any stale alert notifications
      await HealthCheckService._notifications.cancel(_healthAlertNotificationId);
    }
  } catch (e) {
    debugPrint('[HealthCheck] Error: $e');
  }
  debugPrint('[HealthCheck] ━━━━━━━━━━━━━━━━━━━━━━');
}
