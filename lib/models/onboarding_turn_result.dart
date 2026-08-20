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
    if (raw.trim().isEmpty) return null;

    String cleaned = raw
        .replaceAll(RegExp(r'```json\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'```'), '')
        .trim();

    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final spokenText = decoded['spoken_text']?.toString();
        if (spokenText != null && spokenText.trim().isNotEmpty) {
          final lang = decoded['collected_language']?.toString();
          final name = decoded['collected_name']?.toString();
          final complete = decoded['onboarding_complete'] == true;

          return OnboardingTurnResult(
            spokenText: spokenText.trim(),
            collectedLanguage: (lang != null && lang != 'null' && lang.trim().isNotEmpty)
                ? lang.trim()
                : null,
            collectedName: (name != null && name != 'null' && name.trim().isNotEmpty)
                ? name.trim()
                : null,
            onboardingComplete: complete,
          );
        }
      }
    } catch (_) {
      // Fall through to regex extraction fallback
    }

    // Fallback: Regex extraction if standard jsonDecode fails
    try {
      final spokenMatch =
          RegExp(r'"spoken_text"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(raw);
      if (spokenMatch != null) {
        final spokenText = spokenMatch
            .group(1)
            ?.replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n');
        if (spokenText != null && spokenText.trim().isNotEmpty) {
          final langMatch =
              RegExp(r'"collected_language"\s*:\s*"([^"]+)"').firstMatch(raw);
          final nameMatch =
              RegExp(r'"collected_name"\s*:\s*"([^"]+)"').firstMatch(raw);
          final completeMatch =
              RegExp(r'"onboarding_complete"\s*:\s*(true|false)').firstMatch(raw);

          return OnboardingTurnResult(
            spokenText: spokenText.trim(),
            collectedLanguage: langMatch?.group(1),
            collectedName: nameMatch?.group(1),
            onboardingComplete: completeMatch?.group(1) == 'true',
          );
        }
      }
    } catch (_) {}

    return null;
  }
}
