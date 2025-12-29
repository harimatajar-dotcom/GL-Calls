import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../call_logs/domain/entities/call_log_entity.dart';
import '../../../call_logs/presentation/providers/call_log_provider.dart';

class CallLogsScreen extends StatefulWidget {
  const CallLogsScreen({super.key});

  @override
  State<CallLogsScreen> createState() => _CallLogsScreenState();
}

class _CallLogsScreenState extends State<CallLogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedTabIndex = _tabController.index;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCallLogs();
    });
  }

  Future<void> _loadCallLogs() async {
    final provider = context.read<CallLogProvider>();
    final hasPermission = await provider.repository.hasPermission();
    if (hasPermission) {
      await provider.loadCallLogs();
    } else {
      await provider.requestPermission();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<CallLogEntity> _filterCalls(List<CallLogEntity> calls) {
    if (_searchQuery.isEmpty) return calls;
    return calls.where((call) {
      final query = _searchQuery.toLowerCase();
      return call.displayName.toLowerCase().contains(query) ||
          call.number.contains(query) ||
          call.formattedNumber.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.scaffoldBackground,
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: Consumer<CallLogProvider>(
              builder: (context, provider, _) {
                if (provider.status == CallLogStatus.loading) {
                  return _buildLoadingState();
                }

                if (provider.status == CallLogStatus.permissionDenied) {
                  return _buildPermissionDenied(provider);
                }

                if (provider.status == CallLogStatus.error) {
                  return _buildError(provider);
                }

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCallList(_filterCalls(provider.callLogs)),
                    _buildCallList(_filterCalls(provider.incomingCalls)),
                    _buildCallList(_filterCalls(provider.outgoingCalls)),
                    _buildCallList(_filterCalls(provider.missedCalls)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.scaffoldBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search calls...',
                hintStyle: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.textHint,
                  size: 22,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppColors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          _buildTab('All', Icons.phone_rounded, 0),
          _buildTab('Incoming', Icons.call_received_rounded, 1),
          _buildTab('Outgoing', Icons.call_made_rounded, 2),
          _buildTab('Missed', Icons.call_missed_rounded, 3),
        ],
      ),
    );
  }

  Widget _buildTab(String label, IconData icon, int index) {
    final isSelected = _selectedTabIndex == index;
    return Tab(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? AppColors.white : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Loading Call Logs...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied(CallLogProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.warning.withValues(alpha: 0.15),
                    AppColors.warning.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.warning.withValues(alpha: 0.2),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.phone_locked_rounded,
                  size: 48,
                  color: AppColors.warning,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Permission Required',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'To view your call history, please grant access to your call logs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => provider.requestPermission(),
                icon: const Icon(Icons.lock_open_rounded, size: 20),
                label: const Text('Grant Permission'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: AppColors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(CallLogProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Something Went Wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unable to load your call logs.\nPlease try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => provider.refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallList(List<CallLogEntity> calls) {
    if (calls.isEmpty) {
      return _buildEmptyState();
    }

    // Group calls by date
    final groupedCalls = _groupCallsByDate(calls);

    return RefreshIndicator(
      onRefresh: () => context.read<CallLogProvider>().refresh(),
      color: AppColors.primary,
      backgroundColor: AppColors.white,
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 100),
        itemCount: groupedCalls.length,
        itemBuilder: (context, index) {
          final group = groupedCalls[index];
          return _buildDateGroup(group);
        },
      ),
    );
  }

  List<_CallGroup> _groupCallsByDate(List<CallLogEntity> calls) {
    final Map<String, List<CallLogEntity>> groups = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final call in calls) {
      final callDate = DateTime(call.timestamp.year, call.timestamp.month, call.timestamp.day);
      String key;

      if (callDate == today) {
        key = 'Today';
      } else if (callDate == yesterday) {
        key = 'Yesterday';
      } else if (now.difference(call.timestamp).inDays < 7) {
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        key = days[call.timestamp.weekday - 1];
      } else {
        key = '${call.timestamp.day}/${call.timestamp.month}/${call.timestamp.year}';
      }

      groups.putIfAbsent(key, () => []).add(call);
    }

    return groups.entries.map((e) => _CallGroup(e.key, e.value)).toList();
  }

  Widget _buildDateGroup(_CallGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.calls.length} calls',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
        ...group.calls.map((call) => _buildCallCard(call)),
      ],
    );
  }

  Widget _buildCallCard(CallLogEntity call) {
    final color = _getCallColor(call.callType);
    final icon = _getCallIcon(call.callType);
    final typeLabel = _getCallTypeLabel(call.callType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showCallDetails(call),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar with initials
                _buildAvatar(call),
                const SizedBox(width: 14),

                // Call info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              call.displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 12, color: color),
                                const SizedBox(width: 4),
                                Text(
                                  typeLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 14,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              call.formattedNumber,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildInfoChip(
                            Icons.access_time_rounded,
                            call.formattedTime,
                          ),
                          const SizedBox(width: 12),
                          _buildInfoChip(
                            Icons.timer_outlined,
                            call.formattedDuration,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(CallLogEntity call) {
    final initials = _getInitials(call.displayName);
    final color = _getAvatarColor(call.displayName);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    // Check if it's a phone number
    if (RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(name)) {
      return '#';
    }

    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFFEF4444), // Red
      const Color(0xFFF97316), // Orange
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF10B981), // Emerald
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF3B82F6), // Blue
    ];

    final index = name.hashCode.abs() % colors.length;
    return colors[index];
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: AppColors.textHint,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final emptyMessages = [
      {'icon': Icons.phone_outlined, 'text': 'No calls found'},
      {'icon': Icons.call_received_rounded, 'text': 'No incoming calls'},
      {'icon': Icons.call_made_rounded, 'text': 'No outgoing calls'},
      {'icon': Icons.call_missed_rounded, 'text': 'No missed calls'},
    ];

    final message = emptyMessages[_selectedTabIndex];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              message['icon'] as IconData,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message['text'] as String,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : 'Your call history will appear here',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => context.read<CallLogProvider>().refresh(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  void _showCallDetails(CallLogEntity call) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CallDetailsSheet(call: call),
    );
  }

  IconData _getCallIcon(CallLogType type) {
    switch (type) {
      case CallLogType.incoming:
        return Icons.call_received_rounded;
      case CallLogType.outgoing:
        return Icons.call_made_rounded;
      case CallLogType.missed:
        return Icons.call_missed_rounded;
      case CallLogType.rejected:
        return Icons.call_end_rounded;
      case CallLogType.blocked:
        return Icons.block_rounded;
      case CallLogType.unknown:
        return Icons.phone_rounded;
    }
  }

  String _getCallTypeLabel(CallLogType type) {
    switch (type) {
      case CallLogType.incoming:
        return 'Incoming';
      case CallLogType.outgoing:
        return 'Outgoing';
      case CallLogType.missed:
        return 'Missed';
      case CallLogType.rejected:
        return 'Rejected';
      case CallLogType.blocked:
        return 'Blocked';
      case CallLogType.unknown:
        return 'Unknown';
    }
  }

  Color _getCallColor(CallLogType type) {
    switch (type) {
      case CallLogType.incoming:
        return AppColors.success;
      case CallLogType.outgoing:
        return const Color(0xFF3B82F6); // Blue
      case CallLogType.missed:
        return AppColors.error;
      case CallLogType.rejected:
        return AppColors.warning;
      case CallLogType.blocked:
        return AppColors.textSecondary;
      case CallLogType.unknown:
        return AppColors.textHint;
    }
  }
}

class _CallGroup {
  final String title;
  final List<CallLogEntity> calls;

  _CallGroup(this.title, this.calls);
}

class _CallDetailsSheet extends StatelessWidget {
  final CallLogEntity call;

  const _CallDetailsSheet({required this.call});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Avatar
          _buildAvatar(),
          const SizedBox(height: 16),

          // Name
          Text(
            call.displayName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            call.formattedNumber,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          // Call details
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.scaffoldBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  'Call Type',
                  _getCallTypeLabel(call.callType),
                  _getCallIcon(call.callType),
                  _getCallColor(call.callType),
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  'Time',
                  '${call.timestamp.hour.toString().padLeft(2, '0')}:${call.timestamp.minute.toString().padLeft(2, '0')}',
                  Icons.access_time_rounded,
                  AppColors.textSecondary,
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  'Date',
                  '${call.timestamp.day}/${call.timestamp.month}/${call.timestamp.year}',
                  Icons.calendar_today_rounded,
                  AppColors.textSecondary,
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  'Duration',
                  call.formattedDuration,
                  Icons.timer_outlined,
                  AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: _buildSheetButton(
                    context,
                    icon: Icons.call_rounded,
                    label: 'Call',
                    color: AppColors.success,
                    onTap: () async {
                      Navigator.pop(context);
                      final uri = Uri.parse('tel:${call.number}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSheetButton(
                    context,
                    icon: Icons.message_rounded,
                    label: 'Message',
                    color: AppColors.primary,
                    onTap: () async {
                      Navigator.pop(context);
                      final uri = Uri.parse('sms:${call.number}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final initials = _getInitials(call.displayName);
    final color = _getAvatarColor(call.displayName);

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    if (RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(name)) {
      return '#';
    }
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF14B8A6),
      const Color(0xFF06B6D4),
      const Color(0xFF3B82F6),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSheetButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCallIcon(CallLogType type) {
    switch (type) {
      case CallLogType.incoming:
        return Icons.call_received_rounded;
      case CallLogType.outgoing:
        return Icons.call_made_rounded;
      case CallLogType.missed:
        return Icons.call_missed_rounded;
      case CallLogType.rejected:
        return Icons.call_end_rounded;
      case CallLogType.blocked:
        return Icons.block_rounded;
      case CallLogType.unknown:
        return Icons.phone_rounded;
    }
  }

  String _getCallTypeLabel(CallLogType type) {
    switch (type) {
      case CallLogType.incoming:
        return 'Incoming';
      case CallLogType.outgoing:
        return 'Outgoing';
      case CallLogType.missed:
        return 'Missed';
      case CallLogType.rejected:
        return 'Rejected';
      case CallLogType.blocked:
        return 'Blocked';
      case CallLogType.unknown:
        return 'Unknown';
    }
  }

  Color _getCallColor(CallLogType type) {
    switch (type) {
      case CallLogType.incoming:
        return AppColors.success;
      case CallLogType.outgoing:
        return const Color(0xFF3B82F6);
      case CallLogType.missed:
        return AppColors.error;
      case CallLogType.rejected:
        return AppColors.warning;
      case CallLogType.blocked:
        return AppColors.textSecondary;
      case CallLogType.unknown:
        return AppColors.textHint;
    }
  }
}
