import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';

export 'package:mycomicbrain/core/domain/ai_provider.dart';

/// Esito della verifica configurazione.
class EsitoVerifica {
  const EsitoVerifica.successo()
    : ok = true,
      messaggio = 'Configurazione valida.';
  const EsitoVerifica.errore(this.messaggio) : ok = false;

  final bool ok;
  final String messaggio;
}

/// Validazione sintattica dell'URL del provider locale (§12, deciso su
/// [Modelli LLM selezionabili per provider e formato/validazione dell'URL per il provider locale](https://github.com/saviogiordano/MyComicBrain/issues/103)):
/// solo forma URL http/https con host — nessuna verifica di raggiungibilità
/// (i client reali sono #109). Resta usata dalla validazione del campo URL
/// prima del salvataggio (`impostazioni_page.dart`), distinta dalla verifica
/// di raggiungibilità reale sotto.
bool urlLocaleValido(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Verifica reale della configurazione del provider AI (§12, deciso su
/// [Gestire l'assenza di configurazione: messaggi chiari quando manca provider/chiave](https://github.com/saviogiordano/MyComicBrain/issues/108),
/// separata per sezione su richiesta esplicita dell'utente): interroga per
/// davvero il provider AI configurato con una chiamata minima
/// ([CoverAnalysisClient.verificaConnessione]), invece del solo controllo
/// sintattico di prima (raggiungibilità reale rimandata da #107 al client,
/// implementato su #106/#109 per tutti e quattro i provider AI). Il client è
/// già risolto dalle Impostazioni correnti da chi chiama
/// (`coverAnalysisClientProvider` in `core/data/providers.dart`).
Future<EsitoVerifica> verificaProviderAi({
  required CoverAnalysisClient Function() aiClient,
}) async {
  final errore = await _verificaUna(() => aiClient().verificaConnessione());
  return errore == null
      ? const EsitoVerifica.successo()
      : EsitoVerifica.errore(errore);
}

/// Verifica reale della configurazione ComicVine — vedi [verificaProviderAi],
/// stessa logica applicata al provider fumetti.
Future<EsitoVerifica> verificaProviderComicVine({
  required ComicVineClient Function() comicVineClient,
}) async {
  final errore = await _verificaUna(
    () => comicVineClient().verificaConnessione(),
  );
  return errore == null
      ? const EsitoVerifica.successo()
      : EsitoVerifica.errore(errore);
}

/// Verifica reale della configurazione del Provider AI Testuale (§10, #129)
/// — stessa logica di [verificaProviderAi] applicata al ruolo
/// [RuoloProviderAi.testuale] tramite [AssistenteClient.verificaConnessione].
/// A differenza degli altri due, il fallimento tipico è [AssistenteException]
/// (che non porta un messaggio utente-facing proprio, §24/#124): il suo
/// `sottotipo` è mappato al copy condiviso [copyErroreAssistente], la stessa
/// fonte usata da `AssistenteOrchestrator` per i Messaggi di sistema.
Future<EsitoVerifica> verificaProviderAssistente({
  required AssistenteClient Function() assistenteClient,
}) async {
  try {
    await assistenteClient().verificaConnessione();
    return const EsitoVerifica.successo();
  } on AssistenteException catch (e) {
    return EsitoVerifica.errore(copyErroreAssistente(e.sottotipo));
  } on Object catch (e) {
    return EsitoVerifica.errore(e.toString());
  }
}

Future<String?> _verificaUna(Future<void> Function() chiamata) async {
  try {
    await chiamata();
    return null;
  } on CoverAnalysisException catch (e) {
    return e.message;
  } on ComicVineException catch (e) {
    return e.message;
  } on Object catch (e) {
    return e.toString();
  }
}
