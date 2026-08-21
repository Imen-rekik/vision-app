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
      'af': 'Afrikaans',
      'am': 'Amharic',
      'ar': 'Arabic',
      'az': 'Azerbaijani',
      'be': 'Belarusian',
      'bg': 'Bulgarian',
      'bn': 'Bengali',
      'bs': 'Bosnian',
      'ca': 'Catalan',
      'cs': 'Czech',
      'cy': 'Welsh',
      'da': 'Danish',
      'de': 'German',
      'el': 'Greek',
      'en': 'English',
      'es': 'Spanish',
      'et': 'Estonian',
      'eu': 'Basque',
      'fa': 'Persian',
      'fi': 'Finnish',
      'fil': 'Filipino',
      'fr': 'French',
      'ga': 'Irish',
      'gl': 'Galician',
      'gu': 'Gujarati',
      'he': 'Hebrew',
      'hi': 'Hindi',
      'hr': 'Croatian',
      'hu': 'Hungarian',
      'hy': 'Armenian',
      'id': 'Indonesian',
      'is': 'Icelandic',
      'it': 'Italian',
      'ja': 'Japanese',
      'jv': 'Javanese',
      'ka': 'Georgian',
      'kk': 'Kazakh',
      'km': 'Khmer',
      'kn': 'Kannada',
      'ko': 'Korean',
      'ku': 'Kurdish',
      'ky': 'Kyrgyz',
      'lo': 'Lao',
      'lt': 'Lithuanian',
      'lv': 'Latvian',
      'mk': 'Macedonian',
      'ml': 'Malayalam',
      'mn': 'Mongolian',
      'mr': 'Marathi',
      'ms': 'Malay',
      'my': 'Burmese',
      'ne': 'Nepali',
      'nl': 'Dutch',
      'no': 'Norwegian',
      'pa': 'Punjabi',
      'pl': 'Polish',
      'ps': 'Pashto',
      'pt': 'Portuguese',
      'ro': 'Romanian',
      'ru': 'Russian',
      'si': 'Sinhala',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'so': 'Somali',
      'sq': 'Albanian',
      'sr': 'Serbian',
      'su': 'Sundanese',
      'sv': 'Swedish',
      'sw': 'Swahili',
      'ta': 'Tamil',
      'te': 'Telugu',
      'th': 'Thai',
      'tl': 'Tagalog',
      'tr': 'Turkish',
      'uk': 'Ukrainian',
      'ur': 'Urdu',
      'uz': 'Uzbek',
      'vi': 'Vietnamese',
      'yo': 'Yoruba',
      'zh': 'Chinese',
      'zu': 'Zulu',
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
