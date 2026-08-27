import 'package:mycomicbrain/core/domain/ai_provider.dart';

export 'package:mycomicbrain/core/domain/ai_provider.dart';

/// Esito della verifica configurazione.
class EsitoVerifica {
  const EsitoVerifica.successo() : ok = true, messaggio = 'Configurazione valida.';
  const EsitoVerifica.errore(this.messaggio) : ok = false;

  final bool ok;
  final String messaggio;
}

/// Validazione sintattica dell'URL del provider locale (§12, deciso su
/// [Modelli LLM selezionabili per provider e formato/validazione dell'URL per il provider locale](https://github.com/saviogiordano/MyComicBrain/issues/103)):
/// solo forma URL http/https con host — nessuna verifica di raggiungibilità
/// (i client reali sono #109).
bool urlLocaleValido(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

/// Verifica sintattica locale del form Impostazioni prima del salvataggio
/// (§12, #107): nessuna chiamata di rete reale — verificare che i provider
/// AI/ComicVine siano davvero raggiungibili è fuori scope, i client restano
/// #106/#109.
Future<EsitoVerifica> verificaConfigurazione({
  required String apiKey,
  required AiProvider provider,
  required String url,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (apiKey.trim().isEmpty) {
    return const EsitoVerifica.errore('Chiave API mancante.');
  }
  if (provider.richiedeUrl) {
    if (url.trim().isEmpty) {
      return const EsitoVerifica.errore('URL del provider locale mancante.');
    }
    if (!urlLocaleValido(url)) {
      return const EsitoVerifica.errore('URL del provider locale non valido.');
    }
  }
  return const EsitoVerifica.successo();
}
