/// Provider AI selezionabili per l'Analisi Copertina (§12, deciso su
/// [Modelli LLM selezionabili per provider e formato/validazione dell'URL per il provider locale](https://github.com/saviogiordano/MyComicBrain/issues/103)).
/// Vive in `core/domain` (non nello schermo Impostazioni) perché
/// `SettingsRepository` (#105) e i client AI/ComicVine migrati su #106 ne
/// hanno bisogno tanto quanto la UI.
enum AiProvider { openai, claude, openRouter, locale }

/// I due ruoli indipendenti in cui si sdoppia la selezione di [AiProvider]
/// (ADR-0001, deciso su
/// [Schema Impostazioni per lo split Provider AI Visivo/Testuale](https://github.com/saviogiordano/MyComicBrain/issues/127)):
/// Visivo per l'Analisi Copertina (§6, invariato nel comportamento) e
/// Testuale per l'Assistente conversazionale (§10). Ogni ruolo ha la propria
/// selezione di brand, API key, modello e (per Locale) URL in
/// `SettingsRepository` — non condivisi fra ruoli anche a parità di brand.
enum RuoloProviderAi { visivo, testuale }

extension RuoloProviderAiLabel on RuoloProviderAi {
  String get label => switch (this) {
    RuoloProviderAi.visivo => 'Visivo',
    RuoloProviderAi.testuale => 'Testuale',
  };
}

extension AiProviderLabel on AiProvider {
  String get label => switch (this) {
    AiProvider.openai => 'OpenAI',
    AiProvider.claude => 'Claude',
    AiProvider.openRouter => 'OpenRouter',
    AiProvider.locale => 'Locale',
  };

  /// Elenco chiuso di modelli curati, o `null` quando il campo modello è
  /// testo libero (OpenRouter, Locale — deciso su #103). Condiviso fra i due
  /// ruoli (#127): nulla vieta di usare un modello "Testuale" per la vision
  /// o viceversa, cambia solo il default consigliato — vedi [modelloDefault].
  /// Lista esatta affinata su #106: `gpt-5.6-terra` è l'unico modello OpenAI
  /// già testato in produzione per vision + structured outputs strict mode
  /// (era hardcoded in `OpenAiCoverAnalysisClient` prima della migrazione
  /// alle Impostazioni), quindi resta il default Visivo. `gpt-5.6-luna`
  /// aggiunto su #127 perché è il default Testuale deciso su #121 e va
  /// selezionabile dal picker (campo a lista chiusa per OpenAI, non testo
  /// libero).
  List<String>? get modelliCurati => switch (this) {
    AiProvider.openai => const [
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-4.1',
      'gpt-4o',
    ],
    AiProvider.claude => const [
      'claude-opus-5',
      'claude-sonnet-5',
      'claude-haiku-4-5',
    ],
    AiProvider.openRouter => null,
    AiProvider.locale => null,
  };

  /// Modello di default per [ruolo] — indipendente per Visivo/Testuale
  /// (ADR-0001, #127): il ruolo Testuale privilegia costo/velocità
  /// sull'orchestrazione delle tool call (§10) rispetto alla vision +
  /// structured output del ruolo Visivo. Valori Testuale decisi su
  /// [Modelli di default per il Provider AI Testuale](https://github.com/saviogiordano/MyComicBrain/issues/121).
  /// Locale non ha default fisso in nessuno dei due ruoli: resta testo
  /// libero (#103).
  String modelloDefault(RuoloProviderAi ruolo) => switch ((this, ruolo)) {
    (AiProvider.openai, RuoloProviderAi.visivo) => 'gpt-5.6-terra',
    (AiProvider.openai, RuoloProviderAi.testuale) => 'gpt-5.6-luna',
    (AiProvider.claude, RuoloProviderAi.visivo) => 'claude-sonnet-5',
    (AiProvider.claude, RuoloProviderAi.testuale) => 'claude-haiku-4-5',
    (
      AiProvider.openRouter,
      RuoloProviderAi.visivo,
    ) =>
      'anthropic/claude-sonnet-4.5',
    (
      AiProvider.openRouter,
      RuoloProviderAi.testuale,
    ) =>
      'anthropic/claude-haiku-4.5',
    (AiProvider.locale, _) => '',
  };

  bool get richiedeUrl => this == AiProvider.locale;
}
