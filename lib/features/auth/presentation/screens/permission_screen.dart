import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isLoading = false;
  bool _phoneGranted = false;
  bool _storageGranted = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPermissions();
  }

  Future<void> _checkExistingPermissions() async {
    final phoneStatus = await Permission.phone.status;
    final storageStatus = await _checkStoragePermission();

    setState(() {
      _phoneGranted = phoneStatus.isGranted;
      _storageGranted = storageStatus;
    });

    if (_phoneGranted && _storageGranted) {
      _navigateToDashboard();
    }
  }

  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 13+ use audio permission
      final audioStatus = await Permission.audio.status;
      if (audioStatus.isGranted) return true;

      // For older Android versions use storage permission
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;

      // Check manage external storage for full access
      final manageStatus = await Permission.manageExternalStorage.status;
      return manageStatus.isGranted;
    }
    return true;
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    // Request phone permission (includes call log on Android)
    final phoneStatus = await Permission.phone.request();
    setState(() => _phoneGranted = phoneStatus.isGranted);

    // Request storage permissions for recordings
    bool storageGranted = false;
    if (Platform.isAndroid) {
      // For Android 13+ request audio permission
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        storageGranted = true;
      } else {
        // For older versions, try storage permission
        final storageStatus = await Permission.storage.request();
        if (storageStatus.isGranted) {
          storageGranted = true;
        } else {
          // Try manage external storage for full access
          final manageStatus = await Permission.manageExternalStorage.request();
          storageGranted = manageStatus.isGranted;
        }
      }
    } else {
      storageGranted = true;
    }

    setState(() => _storageGranted = storageGranted);

    if (_phoneGranted && _storageGranted) {
      _navigateToDashboard();
    } else if (phoneStatus.isPermanentlyDenied ||
               await Permission.audio.isPermanentlyDenied ||
               await Permission.storage.isPermanentlyDenied) {
      _showSettingsDialog();
    } else {
      setState(() => _isLoading = false);
      _showPermissionDeniedSnackbar();
    }
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  void _showSettingsDialog() {
    setState(() => _isLoading = false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Call log and storage permissions are required to use this app. '
          'Please enable them in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Permission denied. Please grant access to continue.'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security,
                  size: 60,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'App Permissions',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'GL Dialer needs access to your call logs and storage to sync your calls and recordings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _buildPermissionItem(
                icon: Icons.phone_in_talk,
                title: 'Call Logs',
                description: 'Access and sync your call history',
                isGranted: _phoneGranted,
              ),
              const SizedBox(height: 12),
              _buildPermissionItem(
                icon: Icons.audio_file,
                title: 'Audio Files',
                description: 'Access call recordings from your device',
                isGranted: _storageGranted,
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                icon: Icons.storage,
                title: 'Local Storage',
                description: 'Your data is stored securely on your device',
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                icon: Icons.lock,
                title: 'Private & Secure',
                description: 'Your data never leaves your device',
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Grant Permissions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _navigateToDashboard,
                child: Text(
                  'Skip for now',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted ? AppColors.success : AppColors.divider,
          width: isGranted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isGranted ? AppColors.success : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isGranted)
            const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 24,
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
