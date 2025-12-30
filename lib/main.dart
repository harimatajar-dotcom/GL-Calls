import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/core.dart';
import 'core/services/background_service.dart';
import 'features/features.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize app bindings
  await AppBindings.init();

  // Initialize background service for auto-sync
  await BackgroundServiceHelper.initialize();

  // Check if auto-sync was enabled and start service
  final isAutoSyncEnabled = await BackgroundServiceHelper.isAutoSyncEnabled();
  if (isAutoSyncEnabled) {
    await BackgroundServiceHelper.startService();
  }

  runApp(const GLDialerApp());
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
