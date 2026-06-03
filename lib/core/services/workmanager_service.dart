import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'auto_sync_service.dart';
import 'background_service.dart';

/// WorkManager task names
const String periodicSyncTask = 'com.glcalls.periodicSync';
const String serviceRecoveryTask = 'com.glcalls.serviceRecovery';
const String missedCallSyncTask = 'com.glcalls.missedCallSync';

/// WorkManager callback dispatcher - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('\x1B[33m[WorkManager] Executing task: $taskName\x1B[0m');

    try {
      switch (taskName) {
        case periodicSyncTask:
          return await _executePeriodicSync();

        case serviceRecoveryTask:
          return await _executeServiceRecovery();

        case missedCallSyncTask:
          return await _executeMissedCallSync();

        default:
          debugPrint('\x1B[31m[WorkManager] Unknown task: $taskName\x1B[0m');
          return true;
      }
    } catch (e) {
      debugPrint('\x1B[31m[WorkManager] Task failed: $e\x1B[0m');
      return false; // Retry the task
    }
  });
}

/// Execute periodic sync - checks for unsynced recordings
///
/// A-15: This used to only do anything when isAutoDirectSyncEnabled was
/// true. In plain auto-sync mode (the default for most users) the task
/// woke up, checked the flag, and returned without actually syncing
/// anything — making it inert. Now it runs the latest-recording scan
/// in either mode so missed recordings get caught.
Future<bool> _executePeriodicSync() async {
  debugPrint('\x1B[33m[WorkManager] Starting periodic sync...\x1B[0m');

  final prefs = await SharedPreferences.getInstance();
  final isAutoSyncEnabled = prefs.getBool('auto_sync_enabled') ?? false;
  final isAutoDirectSyncEnabled = prefs.getBool('auto_direct_sync_enabled') ?? false;

  if (!isAutoSyncEnabled && !isAutoDirectSyncEnabled) {
    debugPrint('\x1B[33m[WorkManager] Auto sync is disabled, skipping\x1B[0m');
    return true;
  }

  // Initialize and run sync
  final autoSyncService = AutoSyncService();
  await autoSyncService.initialize();

  // Direct-sync mode: query the call log and sync the most recent call
  // even without a recording file.
  if (isAutoDirectSyncEnabled) {
    await autoSyncService.directSyncFromCallLog();
  }
  // Plain auto-sync mode: scan for unsynced recording files and sync
  // them. Previously this branch did nothing.
  if (isAutoSyncEnabled) {
    try {
      await autoSyncService.runPeriodicScanAndSync();
    } catch (e) {
      debugPrint('\x1B[31m[WorkManager] Scan sync failed: $e\x1B[0m');
    }
  }

  debugPrint('\x1B[32m[WorkManager] Periodic sync completed\x1B[0m');
  return true;
}

/// Execute service recovery - restarts foreground service if killed
Future<bool> _executeServiceRecovery() async {
  debugPrint('\x1B[33m[WorkManager] Checking service status...\x1B[0m');

  final prefs = await SharedPreferences.getInstance();
  final isAutoSyncEnabled = prefs.getBool('auto_sync_enabled') ?? false;
  final isAutoDirectSyncEnabled = prefs.getBool('auto_direct_sync_enabled') ?? false;

  if (!isAutoSyncEnabled && !isAutoDirectSyncEnabled) {
    debugPrint('\x1B[33m[WorkManager] Auto sync is disabled, no recovery needed\x1B[0m');
    return true;
  }

  // Check if foreground service is running
  final isRunning = await BackgroundServiceHelper.isServiceRunning();

  if (!isRunning) {
    debugPrint('\x1B[33m[WorkManager] Service not running, restarting...\x1B[0m');
    await BackgroundServiceHelper.startService();
    debugPrint('\x1B[32m[WorkManager] Service restarted successfully\x1B[0m');
  } else {
    debugPrint('\x1B[32m[WorkManager] Service is running normally\x1B[0m');
  }

  return true;
}

/// Execute missed call sync - syncs calls that may have been missed
Future<bool> _executeMissedCallSync() async {
  debugPrint('\x1B[33m[WorkManager] Checking for missed calls to sync...\x1B[0m');

  final prefs = await SharedPreferences.getInstance();
  final isAutoDirectSyncEnabled = prefs.getBool('auto_direct_sync_enabled') ?? false;

  if (!isAutoDirectSyncEnabled) {
    return true;
  }

  final autoSyncService = AutoSyncService();
  await autoSyncService.initialize();
  await autoSyncService.directSyncFromCallLog();

  debugPrint('\x1B[32m[WorkManager] Missed call sync completed\x1B[0m');
  return true;
}

/// WorkManager service helper
class WorkManagerService {
  /// Initialize WorkManager
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    debugPrint('\x1B[32m[WorkManager] Initialized\x1B[0m');
  }

  /// Register periodic sync task (runs every 15 minutes as backup)
  static Future<void> registerPeriodicSync() async {
    await Workmanager().registerPeriodicTask(
      'periodic_sync_task',
      periodicSyncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    debugPrint('\x1B[32m[WorkManager] Periodic sync registered (every 15 min)\x1B[0m');
  }

  /// Register service recovery task (runs every 15 minutes to check service)
  static Future<void> registerServiceRecovery() async {
    await Workmanager().registerPeriodicTask(
      'service_recovery_task',
      serviceRecoveryTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    debugPrint('\x1B[32m[WorkManager] Service recovery registered (every 15 min)\x1B[0m');
  }

  /// Register one-time missed call sync task
  static Future<void> registerMissedCallSync() async {
    await Workmanager().registerOneOffTask(
      'missed_call_sync_${DateTime.now().millisecondsSinceEpoch}',
      missedCallSyncTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      initialDelay: const Duration(seconds: 30),
    );
    debugPrint('\x1B[32m[WorkManager] Missed call sync task registered\x1B[0m');
  }

  /// Cancel all periodic tasks
  static Future<void> cancelAllTasks() async {
    await Workmanager().cancelAll();
    debugPrint('\x1B[32m[WorkManager] All tasks cancelled\x1B[0m');
  }

  /// Cancel specific task
  static Future<void> cancelTask(String taskName) async {
    await Workmanager().cancelByUniqueName(taskName);
    debugPrint('\x1B[32m[WorkManager] Task cancelled: $taskName\x1B[0m');
  }

  /// Enable all backup mechanisms (called when auto-sync is enabled)
  ///
  /// A-14: We deliberately do NOT register `serviceRecoveryTask` here.
  /// `HealthCheckService` (AlarmManager-based, Samsung-resistant) is the
  /// single watchdog responsible for restarting the foreground service
  /// when it dies. Running both in parallel was duplicate work + extra
  /// battery drain for the same outcome. WorkManager keeps the
  /// `periodicSyncTask` job (which has a different purpose — catching
  /// missed recordings — see A-15).
  static Future<void> enableBackupSync() async {
    await registerPeriodicSync();
    debugPrint('\x1B[32m[WorkManager] Backup sync mechanisms enabled '
        '(serviceRecoveryTask SKIPPED — HealthCheckService owns watchdog)\x1B[0m');
  }

  /// Disable all backup mechanisms (called when auto-sync is disabled)
  static Future<void> disableBackupSync() async {
    await cancelAllTasks();
    debugPrint('\x1B[32m[WorkManager] Backup sync mechanisms disabled\x1B[0m');
  }
}
