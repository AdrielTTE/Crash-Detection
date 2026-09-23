import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/sensor_dashboard.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Light status-bar icons: the whole app is a dark instrument panel, and the
  // platform default paints dark-on-dark on Android.
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const CrashDetectionApp());
}

class CrashDetectionApp extends StatelessWidget {
  const CrashDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crash Detection',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SensorDashboard(),
    );
  }
}
