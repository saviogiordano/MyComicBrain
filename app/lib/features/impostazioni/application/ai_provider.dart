import 'package:mycomicbrain/core/domain/ai_provider.dart';

export 'package:mycomicbrain/core/domain/ai_provider.dart';

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
