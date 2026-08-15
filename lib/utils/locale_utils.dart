import '../models/language_option.dart';

class LocaleUtils {
  /// Converts a raw locale tag (e.g. 'en-US', 'es_ES', 'fr-FR') into a clean, human-readable display name.
  static String getDisplayName(String rawLocale) {
    if (rawLocale.isEmpty) return 'Unknown';

    final normalized = rawLocale.replaceAll('_', '-');
    final parts = normalized.split('-');
    final langCode = parts[0].toLowerCase();
    final countryCode = parts.length > 1 ? parts[1].toUpperCase() : '';

    const languageNames = {
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'ru': 'Russian',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'tr': 'Turkish',
      'pl': 'Polish',
      'da': 'Danish',
      'fi': 'Finnish',
      'no': 'Norwegian',
      'el': 'Greek',
      'he': 'Hebrew',
      'th': 'Thai',
      'id': 'Indonesian',
      'vi': 'Vietnamese',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'ro': 'Romanian',
      'uk': 'Ukrainian',
    };

    const countryNames = {
      'US': 'United States',
      'GB': 'United Kingdom',
      'CA': 'Canada',
      'AU': 'Australia',
      'ES': 'Spain',
      'MX': 'Mexico',
      'FR': 'France',
      'DE': 'Germany',
      'IT': 'Italy',
      'BR': 'Brazil',
      'PT': 'Portugal',
      'CN': 'China',
      'TW': 'Taiwan',
      'JP': 'Japan',
      'KR': 'South Korea',
      'SA': 'Saudi Arabia',
      'IN': 'India',
      'RU': 'Russia',
    };

    final langName = languageNames[langCode] ?? langCode.toUpperCase();
    if (countryCode.isNotEmpty && countryNames.containsKey(countryCode)) {
      return '$langName (${countryNames[countryCode]})';
    } else if (countryCode.isNotEmpty) {
      return '$langName ($countryCode)';
    }

    return langName;
  }

  /// Parses raw TTS language list into a deduplicated list of LanguageOption models.
  static List<LanguageOption> parseTtsLanguages(List<dynamic> rawList) {
    final Map<String, LanguageOption> optionsMap = {};

    for (final item in rawList) {
      if (item is String && item.isNotEmpty) {
        final ttsLocale = item;
        final normalizedLocale = item.replaceAll('_', '-');
        final displayName = getDisplayName(normalizedLocale);

        /// handling duplicates
        if (!optionsMap.containsKey(normalizedLocale)) {
          optionsMap[normalizedLocale] = LanguageOption(
            locale: normalizedLocale,
            displayName: displayName,
            ttsLocale: ttsLocale,
          );
        }
      }
    }

    final options = optionsMap.values.toList();
    options.sort((a, b) => a.displayName.compareTo(b.displayName));
    return options;
  }
}
