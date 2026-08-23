import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/matching_engine.dart';

/// Orchestratore dell'Identificazione (§6.3, deciso su #53): a partire
/// dall'Analisi Copertina già `completata` di una Scansione, genera i
/// Candidati col motore di matching (#52/#57) — prima sul catalogo interno,
/// poi, solo se nessun candidato interno supera la soglia, su ComicVine — e
/// li persiste uno per uno. Stesso pattern a stati/nessun-retry di
/// `AnalisiCopertinaPipeline`. L'aggancio automatico a fine pipeline di
/// Analisi Copertina (il trigger) è fuori scope di questo ticket — vedi
/// [Agganciare l'Identificazione automatica a fine pipeline di Analisi
/// Copertina](https://github.com/saviogiordano/MyComicBrain/issues/58).
class IdentificazionePipeline {
  IdentificazionePipeline({
    required ComicsRepository repository,
    ComicVineClient? comicVineClient,
    MatchingEngine? motore,
  }) : _repository = repository,
       _comicVineClient = comicVineClient ?? ComicVineHttpClient(),
       _motore = motore ?? const MatchingEngine();

  final ComicsRepository _repository;
  final ComicVineClient _comicVineClient;
  final MatchingEngine _motore;

  /// Avvia l'Identificazione per la Scansione con questo id, la cui Analisi
  /// Copertina deve già essere `completata`. Un fallimento tecnico (es.
  /// ComicVine irraggiungibile) porta l'Identificazione a `fallita` — nessun
  /// retry automatico, come `AnalisiCopertinaPipeline`.
  Future<void> identifica({required int scansioneId}) async {
    final analisi = await _repository.analisiCopertinaPerScansione(scansioneId);
    final identificazioneId = await _repository.avviaIdentificazione(scansioneId: scansioneId);

    try {
      final catalogo = await _repository.catalogoPerMatching();
      final numeriPosseduti = await _repository.numeriPossedutiPerSerie();

      var candidati = _motore.candidatiInterni(
        analisi: analisi,
        catalogo: catalogo,
        numeriPossedutiPerSerie: numeriPosseduti,
      );

      if (candidati.isEmpty) {
        final risultati = await _comicVineClient.cercaIssue(
          title: analisi.title,
          seriesName: analisi.seriesName,
          issueNumberLabel: analisi.issueNumberLabel,
          publisher: analisi.publisher,
        );
        candidati = _motore.candidatiEsterni(
          analisi: analisi,
          risultati: risultati,
          catalogo: catalogo,
          numeriPossedutiPerSerie: numeriPosseduti,
        );
      }

      for (final candidato in candidati) {
        await _repository.aggiungiCandidato(
          identificazioneId: identificazioneId,
          source: candidato.source,
          punteggio: candidato.punteggio,
          edizioneId: candidato.edizioneId,
          title: candidato.title,
          seriesName: candidato.seriesName,
          issueNumberLabel: candidato.issueNumberLabel,
          publisher: candidato.publisher,
          coverImageUrl: candidato.coverImageUrl,
        );
      }

      await _repository.completaIdentificazione(id: identificazioneId);
    } on ComicVineException catch (e) {
      await _repository.fallisciIdentificazione(id: identificazioneId, errorMessage: e.toString());
    }
  }
}
