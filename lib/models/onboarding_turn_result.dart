import 'dart:convert';

class OnboardingTurnResult {
  final String spokenText;
  final String? collectedLanguage;
  final String? collectedName;
  final bool onboardingComplete;

  const OnboardingTurnResult({
    required this.spokenText,
    required this.collectedLanguage,
    required this.collectedName,
    required this.onboardingComplete,
  });

  static OnboardingTurnResult? tryParse(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'^```(json)?'), '')
        .replaceAll(RegExp(r'```$'), '')
        .trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) return null;

      final spokenText = decoded['spoken_text'];
      final onboardingComplete = decoded['onboarding_complete'];
      if (spokenText is! String || onboardingComplete is! bool) return null;

      return OnboardingTurnResult(
        spokenText: spokenText,
        collectedLanguage: decoded['collected_language'] as String?,
        collectedName: decoded['collected_name'] as String?,
        onboardingComplete: onboardingComplete,
      );
    } catch (_) {
      return null;
    }
  }
}
