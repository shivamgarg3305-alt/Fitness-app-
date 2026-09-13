import 'package:flutter/material.dart';
import 'theme/app_colors.dart';
import 'navigation/app_shell.dart';
import 'services/foreground_service_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Registers the notification channel / task options. Must happen
  // before any ForegroundServiceController.startService() call — safe
  // to call once here even though the service itself only actually
  // starts when a sleep session begins (see SoundDetectionService.start).
  ForegroundServiceController.initialize();
  runApp(const KittySleepApp());
}

class KittySleepApp extends StatelessWidget {
  const KittySleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kitty Sleep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: AppColors.navyDeep,
      ),
      home: const AppShell(),
    );
  }
}
