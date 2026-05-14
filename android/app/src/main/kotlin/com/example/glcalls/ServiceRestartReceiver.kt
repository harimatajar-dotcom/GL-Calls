package com.example.glcalls

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BroadcastReceiver to restart the background service when it gets killed
 * or when the device boots up / app gets updated
 */
class ServiceRestartReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ServiceRestartReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received broadcast: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                Log.d(TAG, "Device boot completed - checking if service should restart")
                restartServiceIfNeeded(context)
            }
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "App updated - checking if service should restart")
                restartServiceIfNeeded(context)
            }
            "com.glcalls.RESTART_SERVICE" -> {
                Log.d(TAG, "Manual restart requested")
                restartServiceIfNeeded(context)
            }
        }
    }

    private fun restartServiceIfNeeded(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isAutoSyncEnabled = prefs.getBoolean("flutter.auto_sync_enabled", false)
            val isAutoDirectSyncEnabled = prefs.getBoolean("flutter.auto_direct_sync_enabled", false)

            if (isAutoSyncEnabled || isAutoDirectSyncEnabled) {
                Log.d(TAG, "Auto-sync is enabled, starting background service...")

                // Start the Flutter background service
                val serviceIntent = Intent(context, id.flutter.flutter_background_service.BackgroundService::class.java)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }

                Log.d(TAG, "Background service start requested")
            } else {
                Log.d(TAG, "Auto-sync is disabled, not starting service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart service: ${e.message}", e)
        }
    }
}
