import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../di/injection_container.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/call_logs/presentation/providers/call_log_provider.dart';
import '../../features/recordings/presentation/providers/recording_provider.dart';

class AppBindings {
  AppBindings._();

  static List<SingleChildWidget> get providers => [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => sl.createAuthProvider(),
        ),
        ChangeNotifierProvider<CallLogProvider>(
          create: (_) => sl.createCallLogProvider(),
        ),
        ChangeNotifierProvider<RecordingProvider>(
          create: (_) => sl.createRecordingProvider(),
        ),
      ];

  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    await sl.init();
  }
}
