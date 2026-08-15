import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _completedKey = 'onboarding_completed';
  static const String _languageKey = 'selected_language';
  static const String _preferredLanguageKey = 'preferred_language';
  static const String _userNameKey = 'user_name';
  static const String _voiceOnboardingCompletedKey =
      'voice_onboarding_completed';
  static const String _interactiveOnboardingCompletedKey =
      'interactive_onboarding_completed';

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    debugPrint('OnboardingService: saved onboarding_completed=true');
  }

  Future<String?> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey);
  }

  Future<void> setSelectedLanguage(String localeCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, localeCode);
    debugPrint('OnboardingService: saved selected_language=$localeCode');
  }

  Future<void> setPreferredLanguage(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredLanguageKey, langCode);
    debugPrint('OnboardingService: saved preferred_language=$langCode');
  }

  Future<String?> getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_preferredLanguageKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved;
    }

    final systemLocale = ui.PlatformDispatcher.instance.locale.languageCode;
    return systemLocale.isEmpty ? 'en' : systemLocale;
  }

  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
    debugPrint('OnboardingService: saved user_name=$name');
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_userNameKey);
    if (saved == null || saved.trim().isEmpty) {
      return null;
    }
    return saved;
  }

  Future<void> setVoiceOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceOnboardingCompletedKey, completed);
    debugPrint('OnboardingService: saved voice_onboarding_completed=$completed');
  }

  Future<bool> isVoiceOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceOnboardingCompletedKey) ?? false;
  }

  Future<void> setInteractiveOnboardingCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_interactiveOnboardingCompletedKey, value);
    debugPrint(
      'OnboardingService: saved interactive_onboarding_completed=$value',
    );
    await setVoiceOnboardingCompleted(value);
  }

  Future<bool> isInteractiveOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final interactiveCompleted =
        prefs.getBool(_interactiveOnboardingCompletedKey);
    if (interactiveCompleted != null) {
      return interactiveCompleted;
    }

    return isVoiceOnboardingCompleted();
  }
}
