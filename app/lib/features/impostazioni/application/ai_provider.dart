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

/// Verifica reale della configurazione corrente (§12, deciso su
/// [Gestire l'assenza di configurazione: messaggi chiari quando manca provider/chiave](https://github.com/saviogiordano/MyComicBrain/issues/108)):
/// interroga per davvero il provider AI e ComicVine con una chiamata minima
/// ([CoverAnalysisClient.verificaConnessione]/[ComicVineClient.verificaConnessione]),
/// invece del solo controllo sintattico di prima (raggiungibilità reale
/// rimandata da #107 ai client, implementati su #106/#109 per tutti e
/// quattro i provider AI). I client sono già risolti dalle Impostazioni
/// correnti da chi chiama (`coverAnalysisClientProvider`/
/// `comicVineClientProvider` in `core/data/providers.dart`).
Future<EsitoVerifica> verificaConfigurazione({
  required CoverAnalysisClient Function() aiClient,
  required ComicVineClient Function() comicVineClient,
}) async {
  final erroreAi = await _verificaUna(() => aiClient().verificaConnessione());
  final erroreComicVine = await _verificaUna(
    () => comicVineClient().verificaConnessione(),
  );

  if (erroreAi == null && erroreComicVine == null) {
    return const EsitoVerifica.successo();
  }
  return EsitoVerifica.errore(
    [
      if (erroreAi != null) 'AI: $erroreAi',
      if (erroreComicVine != null) 'ComicVine: $erroreComicVine',
    ].join(' · '),
  );
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
