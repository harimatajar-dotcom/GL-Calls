import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../call_logs/presentation/providers/call_log_provider.dart';
import '../../../recordings/presentation/providers/recording_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCallLogs();
    });
  }

  Future<void> _loadCallLogs() async {
    final callLogProvider = context.read<CallLogProvider>();
    final recordingProvider = context.read<RecordingProvider>();

    if (callLogProvider.status == CallLogStatus.initial) {
      final hasPermission = await callLogProvider.repository.hasPermission();
      if (hasPermission && mounted) {
        await callLogProvider.loadCallLogs();
      }
    }

    // Also load recordings
    if (recordingProvider.status == RecordingStatus.initial && mounted) {
      await recordingProvider.loadRecordings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CallLogProvider, RecordingProvider>(
      builder: (context, callLogProvider, recordingProvider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeCard(context),
              const SizedBox(height: 24),
              _buildStatsGrid(callLogProvider),
              const SizedBox(height: 24),
              _buildRecordingsCard(recordingProvider),
              const SizedBox(height: 24),
              _buildUploadSection(recordingProvider),
              const SizedBox(height: 24),
              if (recordingProvider.uploadedRecordings.isNotEmpty)
                _buildUploadedRecordings(recordingProvider),
              if (recordingProvider.uploadedRecordings.isNotEmpty)
                const SizedBox(height: 24),
              _buildQuickActions(callLogProvider),
              const SizedBox(height: 24),
              _buildRecentCalls(callLogProvider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final callLogProvider = context.watch<CallLogProvider>();
    final userName = authProvider.user?.name ?? 'User';
    final totalCalls = callLogProvider.callLogs.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back,',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            userName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage, color: AppColors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$totalCalls Calls Saved',
                      style: const TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Synced',
                      style: TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(CallLogProvider provider) {
    final incomingCount = provider.incomingCalls.length;
    final outgoingCount = provider.outgoingCalls.length;
    final missedCount = provider.missedCalls.length;
    final totalCount = provider.callLogs.length;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          icon: Icons.call_received,
          label: 'Incoming',
          value: incomingCount.toString(),
          color: AppColors.success,
        ),
        _buildStatCard(
          icon: Icons.call_made,
          label: 'Outgoing',
          value: outgoingCount.toString(),
          color: AppColors.primary,
        ),
        _buildStatCard(
          icon: Icons.call_missed,
          label: 'Missed',
          value: missedCount.toString(),
          color: AppColors.warning,
        ),
        _buildStatCard(
          icon: Icons.phone,
          label: 'Total',
          value: totalCount.toString(),
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsCard(RecordingProvider provider) {
    final recordingsCount = provider.recordingsCount;

    return GestureDetector(
      onTap: () {
        // Navigate to recordings tab (index 2)
        final dashboardState = context.findAncestorStateOfType<State>();
        if (dashboardState != null && dashboardState.mounted) {
          // This will be handled by the dashboard
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.shade400,
              Colors.purple.shade700,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.mic,
                color: AppColors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call Recordings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    recordingsCount > 0
                        ? '$recordingsCount recordings saved'
                        : 'Tap to view recordings',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                recordingsCount.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(CallLogProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.sync,
                label: 'Sync Now',
                color: AppColors.primary,
                isLoading: provider.status == CallLogStatus.loading,
                onTap: () => provider.refresh(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.refresh,
                label: 'Refresh',
                color: AppColors.success,
                isLoading: false,
                onTap: () => provider.refresh(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2,
                ),
              )
            else
              Icon(icon, color: AppColors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCalls(CallLogProvider provider) {
    final recentCalls = provider.callLogs.take(5).toList();

    if (recentCalls.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
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
        child: Column(
          children: [
            Icon(
              Icons.phone_outlined,
              size: 48,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            const Text(
              'No call logs yet',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your recent calls will appear here',
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Calls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '${provider.callLogs.length} total',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentCalls.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AppColors.divider,
            ),
            itemBuilder: (context, index) {
              final call = recentCalls[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getCallColor(call.callType).withValues(alpha: 0.1),
                  child: Icon(
                    _getCallIcon(call.callType),
                    color: _getCallColor(call.callType),
                    size: 20,
                  ),
                ),
                title: Text(
                  call.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  call.formattedNumber,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      call.formattedTime,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      call.formattedDuration,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getCallIcon(callType) {
    switch (callType.toString()) {
      case 'CallLogType.incoming':
        return Icons.call_received;
      case 'CallLogType.outgoing':
        return Icons.call_made;
      case 'CallLogType.missed':
        return Icons.call_missed;
      default:
        return Icons.call;
    }
  }

  Color _getCallColor(callType) {
    switch (callType.toString()) {
      case 'CallLogType.incoming':
        return AppColors.success;
      case 'CallLogType.outgoing':
        return AppColors.primary;
      case 'CallLogType.missed':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildUploadSection(RecordingProvider provider) {
    final authProvider = context.watch<AuthProvider>();
    final vendorId = authProvider.user?.vendorId ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.teal.shade400,
            Colors.teal.shade700,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cloud_upload,
                  color: AppColors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload & Sync Call',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upload recording to cloud & sync call details',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.uploadStatus == UploadStatus.error && provider.errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.errorMessage!,
                      style: const TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (provider.uploadStatus == UploadStatus.success && provider.lastUploadedRecording != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_done, color: AppColors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Uploaded: ${provider.lastUploadedRecording!.fileName}',
                          style: const TextStyle(color: AppColors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.sync, color: AppColors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Call synced to server',
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: provider.isUploading || provider.recordings.isEmpty
                  ? null
                  : () async {
                      await provider.uploadLatestRecording(vendorId);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: Colors.teal.shade700,
                disabledBackgroundColor: AppColors.white.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: provider.isUploading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.teal.shade700,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Uploading & Syncing...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        Text(
                          provider.recordings.isEmpty
                              ? 'No Recordings Available'
                              : 'Upload & Sync Latest Call',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadedRecordings(RecordingProvider provider) {
    final uploadedRecordings = provider.uploadedRecordings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Uploaded Recordings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${uploadedRecordings.length} uploaded',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: uploadedRecordings.length > 5 ? 5 : uploadedRecordings.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AppColors.divider,
            ),
            itemBuilder: (context, index) {
              final recording = uploadedRecordings[index];
              return ListTile(
                onTap: () => _showUploadedRecordingDetails(recording),
                leading: CircleAvatar(
                  backgroundColor: AppColors.success.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.cloud_done,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
                title: Text(
                  recording.phoneNumber ?? recording.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  recording.contactName ?? 'Unknown Contact',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatUploadDate(recording.uploadedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showUploadedRecordingDetails(dynamic recording) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cloud_done,
                    color: AppColors.success,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Uploaded Recording',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recording.fileName,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Phone Number', recording.phoneNumber ?? 'Unknown'),
            const SizedBox(height: 12),
            _buildDetailRow('Contact', recording.contactName ?? 'Unknown'),
            const SizedBox(height: 12),
            _buildDetailRow('Uploaded At', _formatUploadDateTime(recording.uploadedAt)),
            const SizedBox(height: 12),
            const Text(
              'Cloud URL',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      recording.uploadUrl ?? 'No URL',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      if (recording.uploadUrl != null) {
                        await Clipboard.setData(ClipboardData(text: recording.uploadUrl!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('URL copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.copy, size: 20),
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatUploadDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatUploadDateTime(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
