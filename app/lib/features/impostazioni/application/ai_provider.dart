/// Provider AI selezionabili (§12, deciso su #103).
enum AiProvider { openai, claude, openRouter, locale }

extension AiProviderLabel on AiProvider {
  String get label => switch (this) {
    AiProvider.openai => 'OpenAI',
    AiProvider.claude => 'Claude',
    AiProvider.openRouter => 'OpenRouter',
    AiProvider.locale => 'Locale',
  };

  /// Elenco chiuso di modelli curati, o `null` quando il campo modello è
  /// testo libero (OpenRouter, Locale — deciso su #103).
  List<String>? get modelliCurati => switch (this) {
    AiProvider.openai => const ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o'],
    AiProvider.claude => const [
      'claude-opus-5',
      'claude-sonnet-5',
      'claude-haiku-4-5',
    ],
    AiProvider.openRouter => null,
    AiProvider.locale => null,
  };

  String get modelloDefault => switch (this) {
    AiProvider.openai => 'gpt-4.1',
    AiProvider.claude => 'claude-sonnet-5',
    AiProvider.openRouter => 'anthropic/claude-sonnet-4.5',
    AiProvider.locale => '',
  };

  bool get richiedeUrl => this == AiProvider.locale;
}

/// Esito della verifica configurazione.
class EsitoVerifica {
  const EsitoVerifica.successo() : ok = true, messaggio = 'Configurazione valida.';
  const EsitoVerifica.errore(this.messaggio) : ok = false;

  final bool ok;
  final String messaggio;
}

/// Verifica sintattica locale, in attesa del `SettingsRepository` (deciso
/// su #101, non ancora implementato): nessuna chiamata di rete reale finché
/// la persistenza delle Impostazioni non esiste.
Future<EsitoVerifica> verificaConfigurazione({
  required String apiKey,
  required AiProvider provider,
  required String url,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (apiKey.trim().isEmpty) {
    return const EsitoVerifica.errore('Chiave API mancante.');
  }
  if (provider.richiedeUrl && url.trim().isEmpty) {
    return const EsitoVerifica.errore('URL del provider locale mancante.');
  }
  return const EsitoVerifica.successo();
}
