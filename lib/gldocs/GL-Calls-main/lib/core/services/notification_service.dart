import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final String type; // welcome, sync_success, sync_error, auto_sync
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.type,
    this.isRead = false,
  });

  IconData get icon {
    switch (type) {
      case 'welcome':
        return Icons.celebration;
      case 'sync_success':
        return Icons.cloud_done;
      case 'sync_error':
        return Icons.cloud_off;
      case 'auto_sync_enabled':
        return Icons.sync;
      case 'auto_sync_disabled':
        return Icons.sync_disabled;
      case 'upload_success':
        return Icons.upload_file;
      case 'upload_error':
        return Icons.error_outline;
      default:
        return Icons.notifications;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'welcome':
        return Colors.purple;
      case 'sync_success':
        return Colors.green;
      case 'sync_error':
        return Colors.red;
      case 'auto_sync_enabled':
        return Colors.blue;
      case 'auto_sync_disabled':
        return Colors.grey;
      case 'upload_success':
        return Colors.teal;
      case 'upload_error':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      createdAt: createdAt,
      type: type,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
      'type': type,
      'isRead': isRead,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      type: json['type'] as String,
      isRead: json['isRead'] as bool? ?? false,
    );
  }
}

class NotificationService {
  static const String _storageKey = 'app_notifications';
  static NotificationService? _instance;
  static SharedPreferences? _prefs;

  NotificationService._();

  static Future<NotificationService> getInstance() async {
    if (_instance == null) {
      _instance = NotificationService._();
      _prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  Future<List<AppNotification>> getNotifications() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      final notifications = jsonList
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      // Sort by date, newest first
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notifications;
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveNotifications(List<AppNotification> notifications) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final jsonList = notifications.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, json.encode(jsonList));
  }

  Future<void> addNotification(AppNotification notification) async {
    final notifications = await getNotifications();
    notifications.insert(0, notification);
    // Keep only last 50 notifications
    if (notifications.length > 50) {
      notifications.removeRange(50, notifications.length);
    }
    await _saveNotifications(notifications);
  }

  Future<void> markAsRead(String id) async {
    final notifications = await getNotifications();
    final index = notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      notifications[index] = notifications[index].copyWith(isRead: true);
      await _saveNotifications(notifications);
    }
  }

  Future<void> markAllAsRead() async {
    final notifications = await getNotifications();
    final updatedNotifications = notifications
        .map((n) => n.copyWith(isRead: true))
        .toList();
    await _saveNotifications(updatedNotifications);
  }

  Future<void> deleteNotification(String id) async {
    final notifications = await getNotifications();
    notifications.removeWhere((n) => n.id == id);
    await _saveNotifications(notifications);
  }

  Future<void> clearAll() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<int> getUnreadCount() async {
    final notifications = await getNotifications();
    return notifications.where((n) => !n.isRead).length;
  }

  // Helper methods to add specific notifications
  static Future<void> addWelcomeNotification(String userName) async {
    final service = await getInstance();
    final now = DateTime.now();
    final formattedDate = '${now.day}/${now.month}/${now.year} at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    await service.addNotification(AppNotification(
      id: 'welcome_${now.millisecondsSinceEpoch}',
      title: 'Welcome to GL Dialer!',
      message: 'Hello $userName! You logged in on $formattedDate. Start syncing your calls today!',
      createdAt: now,
      type: 'welcome',
    ));
  }

  static Future<void> addAutoSyncNotification(bool enabled) async {
    final service = await getInstance();
    final now = DateTime.now();

    await service.addNotification(AppNotification(
      id: 'auto_sync_${now.millisecondsSinceEpoch}',
      title: enabled ? 'Auto-Sync Enabled' : 'Auto-Sync Disabled',
      message: enabled
          ? 'Your calls will now be automatically uploaded and synced after each call ends.'
          : 'Auto-sync has been turned off. You can manually sync your calls.',
      createdAt: now,
      type: enabled ? 'auto_sync_enabled' : 'auto_sync_disabled',
    ));
  }

  static Future<void> addSyncSuccessNotification(String phoneNumber, int duration) async {
    final service = await getInstance();
    final now = DateTime.now();

    await service.addNotification(AppNotification(
      id: 'sync_success_${now.millisecondsSinceEpoch}',
      title: 'Call Synced Successfully',
      message: 'Call with $phoneNumber (${duration}s) has been uploaded and synced to the server.',
      createdAt: now,
      type: 'sync_success',
    ));
  }

  static Future<void> addSyncErrorNotification(String phoneNumber, String errorMessage) async {
    final service = await getInstance();
    final now = DateTime.now();

    await service.addNotification(AppNotification(
      id: 'sync_error_${now.millisecondsSinceEpoch}',
      title: 'Sync Failed',
      message: 'Failed to sync call with $phoneNumber. Error: $errorMessage',
      createdAt: now,
      type: 'sync_error',
    ));
  }

  static Future<void> addUploadSuccessNotification(String fileName) async {
    final service = await getInstance();
    final now = DateTime.now();

    await service.addNotification(AppNotification(
      id: 'upload_success_${now.millisecondsSinceEpoch}',
      title: 'Recording Uploaded',
      message: 'Recording "$fileName" has been uploaded to the cloud.',
      createdAt: now,
      type: 'upload_success',
    ));
  }

  static Future<void> addUploadErrorNotification(String fileName, String errorMessage) async {
    final service = await getInstance();
    final now = DateTime.now();

    await service.addNotification(AppNotification(
      id: 'upload_error_${now.millisecondsSinceEpoch}',
      title: 'Upload Failed',
      message: 'Failed to upload "$fileName". Error: $errorMessage',
      createdAt: now,
      type: 'upload_error',
    ));
  }
}
