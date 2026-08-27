/// Provider AI selezionabili per l'Analisi Copertina (§12, deciso su
/// [Modelli LLM selezionabili per provider e formato/validazione dell'URL per il provider locale](https://github.com/saviogiordano/MyComicBrain/issues/103)).
/// Vive in `core/domain` (non nello schermo Impostazioni) perché
/// `SettingsRepository` (#105) e i client AI/ComicVine migrati su #106 ne
/// hanno bisogno tanto quanto la UI.
enum AiProvider { openai, claude, openRouter, locale }

extension AiProviderLabel on AiProvider {
  String get label => switch (this) {
    AiProvider.openai => 'OpenAI',
    AiProvider.claude => 'Claude',
    AiProvider.openRouter => 'OpenRouter',
    AiProvider.locale => 'Locale',
  };

  /// Elenco chiuso di modelli curati, o `null` quando il campo modello è
  /// testo libero (OpenRouter, Locale — deciso su #103). Lista esatta
  /// affinata su #106: `gpt-5.6-terra` è l'unico modello OpenAI già testato
  /// in produzione per vision + structured outputs strict mode (era
  /// hardcoded in `OpenAiCoverAnalysisClient` prima della migrazione alle
  /// Impostazioni), quindi resta il default.
  List<String>? get modelliCurati => switch (this) {
    AiProvider.openai => const ['gpt-5.6-terra', 'gpt-4.1', 'gpt-4o'],
    AiProvider.claude => const [
      'claude-opus-5',
      'claude-sonnet-5',
      'claude-haiku-4-5',
    ],
    AiProvider.openRouter => null,
    AiProvider.locale => null,
  };

  String get modelloDefault => switch (this) {
    AiProvider.openai => 'gpt-5.6-terra',
    AiProvider.claude => 'claude-sonnet-5',
    AiProvider.openRouter => 'anthropic/claude-sonnet-4.5',
    AiProvider.locale => '',
  };

  bool get richiedeUrl => this == AiProvider.locale;
}
