class LanguageOption {
  final String locale;
  final String displayName;
  final String ttsLocale;

  const LanguageOption({
    required this.locale,
    required this.displayName,
    required this.ttsLocale,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanguageOption &&
          runtimeType == other.runtimeType &&
          locale == other.locale;

  @override
  int get hashCode => locale.hashCode;
}
