import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/floating_bottom_nav_bar.dart';
import '../../../recordings/presentation/screens/recordings_screen.dart';
import 'call_logs_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final List<String> _titles = const [
    AppStrings.appName,
    'Call Logs',
    'Recordings',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.85),
                    AppColors.primaryDark.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.white.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: AppColors.white),
              onPressed: () {},
            ),
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.search, color: AppColors.white),
              onPressed: () {},
            ),
          if (_currentIndex == 2)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.white),
              onPressed: () {},
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          CallLogsScreen(),
          RecordingsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: FloatingBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
