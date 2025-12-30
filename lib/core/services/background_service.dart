import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auto_sync_service.dart';

class BackgroundServiceHelper {
  static const String _autoSyncEnabledKey = 'auto_sync_enabled';
  static const String _notificationChannelId = 'gl_dialer_auto_sync';
  static const String _notificationChannelName = 'GL Dialer Auto Sync';

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
          importance: Importance.low,
        ),
      );
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

    if (enabled) {
      await startService();
    } else {
      await stopService();
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

  static void _logGreen(String message) {
    debugPrint('\x1B[32m[BackgroundService] $message\x1B[0m');
  }
}

/// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('\x1B[32m[BackgroundService] Service started\x1B[0m');

  // Initialize auto-sync service
  final autoSyncService = AutoSyncService();
  await autoSyncService.initialize();

  // Listen to phone state changes
  autoSyncService.startListening();

  // Handle stop service
  service.on('stopService').listen((event) {
    autoSyncService.stopListening();
    service.stopSelf();
    debugPrint('\x1B[32m[BackgroundService] Service stopped\x1B[0m');
  });

  // Update notification periodically to show service is running
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // Keep service alive
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'GL Dialer',
          content: 'Auto-sync is active - Monitoring calls',
        );
      }
    }

    // Log to show service is running
    debugPrint('\x1B[34m[BackgroundService] Service heartbeat - ${DateTime.now()}\x1B[0m');
  });
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}
