import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/core.dart';
import 'features/features.dart';

void main() async {
  await AppBindings.init();
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
