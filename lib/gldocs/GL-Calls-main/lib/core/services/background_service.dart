import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version_service.dart';
import 'auto_sync_service.dart';
import 'health_check_service.dart';
import 'log_service.dart';
import 'workmanager_service.dart';

class BackgroundServiceHelper {
  static const String _autoSyncEnabledKey = 'auto_sync_enabled';
  static const String _autoDirectSyncEnabledKey = 'auto_direct_sync_enabled';
  static const String _customRecordingFolderKey = 'custom_recording_folder';
  static const String _notificationChannelId = 'gl_dialer_auto_sync';
  static const String _notificationChannelName = 'GL Dialer Auto Sync';
  static const String _serviceRestartCountKey = 'service_restart_count';
  static const String _lastServiceStartKey = 'last_service_start';

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Initialize background service
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Initialize notifications
    await _initializeNotifications();

    // Configure the service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'GL Dialer',
        initialNotificationContent: 'Auto-sync is running',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// Initialize local notifications
  static Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    // Create notification channel for Android
    if (Platform.isAndroid) {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _notificationChannelId,
          _notificationChannelName,
          description: 'Notification channel for GL Dialer auto-sync',
          importance: Importance.defaultImportance,
          showBadge: false,
          enableVibration: false,
          playSound: false,
        ),
      );

      // Request notification permission on Android 13+
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  /// Check if auto-sync is enabled
  static Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSyncEnabledKey) ?? false;
  }

  /// Set auto-sync enabled/disabled
  static Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncEnabledKey, enabled);

    // Notify tracking API of status change (non-blocking)
    AppVersionService.postAutoSyncStatus(enabled);

    if (enabled) {
      await startService();
      // Enable WorkManager backup mechanisms (with error handling)
      try {
        await WorkManagerService.initialize();
        await WorkManagerService.enableBackupSync();
      } catch (e) {
        _logGreen('WorkManager setup skipped: $e');
      }
      // Start AlarmManager-based health check (Samsung-resistant)
      try {
        await HealthCheckService.startHealthCheck();
      } catch (e) {
        _logGreen('HealthCheck setup skipped: $e');
      }
      // Record service start time
      await prefs.setInt(_lastServiceStartKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_serviceRestartCountKey, 0);
    } else {
      // Only stop service if auto direct sync is also disabled
      final isDirectSyncEnabled = await isAutoDirectSyncEnabled();
      if (!isDirectSyncEnabled) {
        await stopService();
        // Disable WorkManager backup mechanisms
        try {
          await WorkManagerService.disableBackupSync();
        } catch (e) {
          _logGreen('WorkManager disable skipped: $e');
        }
        // Stop health check
        try {
          await HealthCheckService.stopHealthCheck();
        } catch (e) {
          _logGreen('HealthCheck stop skipped: $e');
        }
      }
    }
  }

  /// Check if auto direct sync is enabled
  static Future<bool> isAutoDirectSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoDirectSyncEnabledKey) ?? false;
  }

  /// Set auto direct sync enabled/disabled
  static Future<void> setAutoDirectSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoDirectSyncEnabledKey, enabled);

    if (enabled) {
      await startService();
      // Enable WorkManager backup mechanisms (with error handling)
      try {
        await WorkManagerService.initialize();
        await WorkManagerService.enableBackupSync();
      } catch (e) {
        _logGreen('WorkManager setup skipped: $e');
      }
      // Start AlarmManager-based health check (Samsung-resistant)
      try {
        await HealthCheckService.startHealthCheck();
      } catch (e) {
        _logGreen('HealthCheck setup skipped: $e');
      }
      // Record service start time
      await prefs.setInt(_lastServiceStartKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_serviceRestartCountKey, 0);
    } else {
      // Only stop service if auto sync is also disabled
      final isAutoSyncEnabled = await BackgroundServiceHelper.isAutoSyncEnabled();
      if (!isAutoSyncEnabled) {
        await stopService();
        // Disable WorkManager backup mechanisms
        try {
          await WorkManagerService.disableBackupSync();
        } catch (e) {
          _logGreen('WorkManager disable skipped: $e');
        }
        // Stop health check
        try {
          await HealthCheckService.stopHealthCheck();
        } catch (e) {
          _logGreen('HealthCheck stop skipped: $e');
        }
      }
    }
  }

  /// Get custom recording folder path
  static Future<String?> getCustomRecordingFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customRecordingFolderKey);
  }

  /// Set custom recording folder path
  static Future<void> setCustomRecordingFolder(String? folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    if (folderPath != null) {
      await prefs.setString(_customRecordingFolderKey, folderPath);
    } else {
      await prefs.remove(_customRecordingFolderKey);
    }
  }

  /// Start background service
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (!isRunning) {
      await service.startService();
      _logGreen('Background service started');
    }
  }

  /// Stop background service
  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (isRunning) {
      service.invoke('stopService');
      _logGreen('Background service stopped');
    }
  }

  /// Check if service is running
  static Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  /// Recover service if killed (called from WorkManager)
  static Future<void> recoverServiceIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final isAutoSyncEnabled = prefs.getBool(_autoSyncEnabledKey) ?? false;
    final isAutoDirectSyncEnabled = prefs.getBool(_autoDirectSyncEnabledKey) ?? false;

    if (!isAutoSyncEnabled && !isAutoDirectSyncEnabled) {
      return; // No need to recover
    }

    final isRunning = await isServiceRunning();
    if (!isRunning) {
      _logGreen('Service was killed, recovering...');

      // Increment restart count
      int restartCount = prefs.getInt(_serviceRestartCountKey) ?? 0;
      restartCount++;
      await prefs.setInt(_serviceRestartCountKey, restartCount);

      _logGreen('Restart attempt #$restartCount');
      await startService();
    }
  }

  /// Get service restart count
  static Future<int> getRestartCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_serviceRestartCountKey) ?? 0;
  }

  /// Get last service start time
  static Future<DateTime?> getLastServiceStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastServiceStartKey);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  static void _logGreen(String message) {
    debugPrint('\x1B[32m[BackgroundService] $message\x1B[0m');
    LogService.info(message, tag: 'BackgroundService');
  }
}

/// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('\x1B[32m[BackgroundService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
  debugPrint('\x1B[32m[BackgroundService] SERVICE STARTED\x1B[0m');
  debugPrint('\x1B[32m[BackgroundService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

  // Record service start time
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('last_service_start', DateTime.now().millisecondsSinceEpoch);

  // Initialize auto-sync service
  final autoSyncService = AutoSyncService();
  bool isInitialized = false;

  try {
    await autoSyncService.initialize();
    isInitialized = true;
    debugPrint('\x1B[32m[BackgroundService] AutoSyncService initialized\x1B[0m');
  } catch (e) {
    debugPrint('\x1B[31m[BackgroundService] Failed to initialize AutoSyncService: $e\x1B[0m');
  }

  // Listen to phone state changes
  if (isInitialized) {
    autoSyncService.startListening();
    debugPrint('\x1B[32m[BackgroundService] Phone state listener started\x1B[0m');
  }

  // Handle stop service
  service.on('stopService').listen((event) {
    autoSyncService.stopListening();
    service.stopSelf();
    debugPrint('\x1B[32m[BackgroundService] Service stopped by user\x1B[0m');
  });

  // Update notification periodically to show service is running
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Set as foreground service immediately with sticky notification
    await service.setAsForegroundService();
  }

  // Keep service alive with heartbeat and self-recovery check
  int heartbeatCount = 0;
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    heartbeatCount++;

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Update notification with uptime info
        final uptimeMinutes = (heartbeatCount * 30) ~/ 60;
        service.setForegroundNotificationInfo(
          title: 'GL Calls - Auto Sync Active',
          content: 'Monitoring calls (Uptime: ${uptimeMinutes}m)',
        );
      }
    }

    // Re-initialize listener if needed (self-recovery)
    if (isInitialized && heartbeatCount % 4 == 0) {
      // Every 2 minutes, check if listener is still active
      try {
        autoSyncService.stopListening();
        autoSyncService.startListening();
        debugPrint('\x1B[34m[BackgroundService] Listener refreshed\x1B[0m');
      } catch (e) {
        debugPrint('\x1B[31m[BackgroundService] Failed to refresh listener: $e\x1B[0m');
      }
    }

    // Log heartbeat
    debugPrint('\x1B[34m[BackgroundService] Heartbeat #$heartbeatCount - ${DateTime.now()}\x1B[0m');
  });
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}
