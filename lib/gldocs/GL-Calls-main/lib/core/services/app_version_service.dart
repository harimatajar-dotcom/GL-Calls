import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

/// Service that posts user info to the app-users tracking API after login.
///
/// Endpoint: POST https://appversion.getleadcrm.com/api/app-users
/// Called once per login to track active users / app versions.
class AppVersionService {
  static const String _baseUrl = 'https://appversion.getleadcrm.com';
  static const String _endpoint = '/api/app-users';
  static const String _appName = 'GL_DIALER';

  /// Post user details to the app-users tracking API.
  /// Called after successful login.
  static Future<void> postUserDetails({
    required String name,
    required String email,
    String? mobile,
    int? vendorId,
  }) async {
    try {
      // Get app version
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      // Get auto-sync status
      final prefs = await SharedPreferences.getInstance();
      final isAutoSyncEnabled = prefs.getBool('auto_sync_enabled') ?? false;
      final autoSyncStatus = isAutoSyncEnabled ? 'On' : 'Off';

      // vendor_id = company_id (first branch from /businesses/{id}/meta)
      // Both app-users and auto-sync-status APIs must use the SAME vendor_id
      String vendorIdValue = prefs.getString('company_id') ?? '';
      if (vendorIdValue.isEmpty) {
        vendorIdValue = prefs.getString('business_id') ?? '';
      }
      if (vendorIdValue.isEmpty) {
        vendorIdValue = prefs.getString('user_id') ?? '';
      }

      // Format current time as YYYY-MM-DD HH:MM
      final now = DateTime.now();
      final lastLogin = '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
          '${_pad(now.hour)}:${_pad(now.minute)}';

      final body = {
        'vendor_id': vendorIdValue,
        'name': name,
        'email': email,
        'mobile': mobile ?? '',
        'app_name': _appName,
        'app_version': appVersion,
        'status': 'active',
        'auto_sync': autoSyncStatus,
        'last_login': lastLogin,
      };

      // Log the API call in green - line by line for readability
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 APP-USERS TRACKING REQUEST\x1B[0m');
      debugPrint('\x1B[32m[API] URL: $_baseUrl$_endpoint\x1B[0m');
      debugPrint('\x1B[32m[API] Method: POST\x1B[0m');
      debugPrint('\x1B[32m[API] ── Body Fields ──\x1B[0m');
      body.forEach((key, value) {
        debugPrint('\x1B[32m[API]   $key: $value\x1B[0m');
      });
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      LogService.info(
        'POST $_endpoint | vendor_id=${body['vendor_id']} | name=${body['name']} | auto_sync=${body['auto_sync']}',
        tag: 'AppVersion',
      );

      // Use a fresh Dio instance (different base URL, no auth needed)
      final dio = Dio(BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ));

      final response = await dio.post(_endpoint, data: body);

      debugPrint('\x1B[32m[API] ✅ APP-USERS RESPONSE: ${response.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Data: ${response.data}\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 201) {
        LogService.success('App-users tracking posted', tag: 'AppVersion');
      } else {
        LogService.warning(
          'App-users tracking returned ${response.statusCode}',
          tag: 'AppVersion',
        );
      }
    } catch (e) {
      // Non-fatal - tracking failure shouldn't block login
      debugPrint('\x1B[33m[AppVersion] Tracking failed (non-fatal): $e\x1B[0m');
      LogService.warning('App-users tracking failed: $e', tag: 'AppVersion');
    }
  }

  /// Post auto-sync status change to the tracking API.
  /// Called whenever user toggles auto-sync on/off.
  ///
  /// Endpoint: POST https://appversion.getleadcrm.com/api/auto-sync-status
  static Future<void> postAutoSyncStatus(bool isEnabled) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      final prefs = await SharedPreferences.getInstance();
      // vendor_id = company_id (first branch.id from /businesses/{id}/meta)
      // Falls back to business_id, then user_id if meta call failed
      String vendorIdValue = prefs.getString('company_id') ?? '';
      if (vendorIdValue.isEmpty) {
        vendorIdValue = prefs.getString('business_id') ?? '';
      }
      if (vendorIdValue.isEmpty) {
        vendorIdValue = prefs.getString('user_id') ?? '';
      }

      final body = {
        'vendor_id': vendorIdValue,
        'app_version': appVersion,
        'auto_sync': isEnabled ? 'On' : 'Off',
      };

      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 AUTO-SYNC STATUS UPDATE\x1B[0m');
      debugPrint('\x1B[32m[API] URL: $_baseUrl/api/auto-sync-status\x1B[0m');
      debugPrint('\x1B[32m[API] Method: POST\x1B[0m');
      debugPrint('\x1B[32m[API] ── Body Fields ──\x1B[0m');
      body.forEach((key, value) {
        debugPrint('\x1B[32m[API]   $key: $value\x1B[0m');
      });
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      LogService.info(
        'POST /api/auto-sync-status | vendor_id=${body['vendor_id']} | auto_sync=${body['auto_sync']}',
        tag: 'AppVersion',
      );

      final dio = Dio(BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ));

      final response = await dio.post('/api/auto-sync-status', data: body);

      debugPrint('\x1B[32m[API] ✅ AUTO-SYNC STATUS RESPONSE: ${response.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Data: ${response.data}\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 201) {
        LogService.success(
          'Auto-sync status posted: ${isEnabled ? "On" : "Off"}',
          tag: 'AppVersion',
        );
      } else {
        LogService.warning(
          'Auto-sync status returned ${response.statusCode}',
          tag: 'AppVersion',
        );
      }
    } catch (e) {
      debugPrint('\x1B[33m[AppVersion] Auto-sync status post failed: $e\x1B[0m');
      LogService.warning('Auto-sync status post failed: $e', tag: 'AppVersion');
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
