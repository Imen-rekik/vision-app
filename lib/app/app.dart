import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/live_test/live_test_screen.dart';
import '../screens/onboarding/permissions_screen.dart';
import '../screens/onboarding/voice_onboarding_screen.dart';
import '../screens/splash/splash_screen.dart';
import 'theme/app_theme.dart';

class VisionApp extends StatelessWidget {
  const VisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/live-test',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/permissions': (_) => const PermissionsScreen(),
        '/voice-onboarding': (_) => const VoiceOnboardingScreen(),
        '/home': (_) => const HomeScreen(),
        '/live-test': (_) => const LiveTestScreen(),
      },
    );
  }
}
