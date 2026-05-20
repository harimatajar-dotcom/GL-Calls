import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/core.dart';
import 'core/services/background_service.dart';
import 'core/services/health_check_service.dart';
import 'core/services/log_service.dart';
import 'core/services/sync_failure_notifier.dart';
import 'core/services/workmanager_service.dart';
import 'features/features.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize log service first to capture all subsequent logs
  await LogService.initialize();
  LogService.info('App starting...', tag: 'App');

  // Initialize app bindings
  await AppBindings.init();
  LogService.success('App bindings initialized', tag: 'App');

  // Initialize background service for auto-sync
  await BackgroundServiceHelper.initialize();
  LogService.success('Background service initialized', tag: 'BackgroundService');

  // Initialize health check service (Samsung-resistant alarm)
  await HealthCheckService.initialize();
  LogService.success('Health check service initialized', tag: 'HealthCheck');

  // Initialize push notifier for sync failures (high-importance channel
  // with sound so the user is alerted even when the app is closed)
  await SyncFailureNotifier.initialize();
  LogService.success('Sync failure notifier initialized', tag: 'SyncFailureNotifier');

  // Initialize WorkManager for backup sync (non-blocking)
  _initializeWorkManager();

  runApp(const GLDialerApp());
}

/// Initialize WorkManager and background services in background
/// This is non-blocking to prevent app startup delays
Future<void> _initializeWorkManager() async {
  try {
    await WorkManagerService.initialize();

    // Check if auto-sync was enabled and start service
    final isAutoSyncEnabled = await BackgroundServiceHelper.isAutoSyncEnabled();
    final isAutoDirectSyncEnabled = await BackgroundServiceHelper.isAutoDirectSyncEnabled();

    if (isAutoSyncEnabled || isAutoDirectSyncEnabled) {
      await BackgroundServiceHelper.startService();
      // Enable WorkManager backup mechanisms
      await WorkManagerService.enableBackupSync();
      // Start AlarmManager-based health check
      await HealthCheckService.startHealthCheck();
    }
  } catch (e) {
    debugPrint('WorkManager initialization failed: $e');
  }
}

class GLDialerApp extends StatelessWidget {
  const GLDialerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppBindings.providers,
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
