import 'dart:convert';
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/identificazione_pipeline.dart';

/// Pipeline di analisi copertina di fine batch (§6.1 OCR + §6.2 computer
/// vision, deciso su #27/#32, esteso su #49): per ogni Scansione appena
/// confermata, chiama il provider AI configurato (Claude di default, vedi
/// `CoverAnalysisProviderConfig`), fa il parsing della risposta secondo lo
/// schema deciso (#31, #47) e persiste il risultato — completata o fallita,
/// nessun retry automatico. Le Scansioni del batch sono processate in
/// sequenza: un batch di fine sessione non ha requisiti di concorrenza, e
/// restare sequenziali evita di sommare più chiamate in parallelo contro il
/// rate limit (vedi ricerca #28). Quando l'Analisi Copertina si completa con
/// successo, aggancia subito l'Identificazione (§6.3, deciso su #58): stesso
/// trigger/batch, non un'azione manuale dell'utente. Un fallimento
/// dell'Identificazione (es. ComicVine irraggiungibile, già gestito da
/// `IdentificazionePipeline` con stato `fallita` e nessun retry) non tocca
/// lo stato `completata` già persistito dell'Analisi Copertina.
class AnalisiCopertinaPipeline {
  AnalisiCopertinaPipeline({
    required ComicsRepository repository,
    CoverAnalysisClient? client,
    IdentificazionePipeline? identificazionePipeline,
  }) : _repository = repository,
       _client = client ?? ClaudeCoverAnalysisClient(),
       _identificazionePipeline =
           identificazionePipeline ??
           IdentificazionePipeline(repository: repository);

  final ComicsRepository _repository;
  final CoverAnalysisClient _client;
  final IdentificazionePipeline _identificazionePipeline;

  /// Avvia l'analisi per ogni Scansione del batch, identificata dal
  /// percorso immagine già persistito (#21). Ogni Scansione è indipendente:
  /// il fallimento di una non blocca le altre.
  Future<void> avviaBatch(Iterable<String> percorsiImmagine) async {
    for (final percorso in percorsiImmagine) {
      await _avviaUna(percorso);
    }
  }

  Future<void> _avviaUna(String percorsoImmagine) async {
    final scansioneId = await _repository.idScansionePerImmagine(
      percorsoImmagine,
    );
    final analisiId = await _repository.avviaAnalisiCopertina(
      scansioneId: scansioneId,
    );
    await _eseguiAnalisi(
      analisiId: analisiId,
      scansioneId: scansioneId,
      percorsoImmagine: percorsoImmagine,
    );
  }

  /// Ripete l'Analisi Copertina di una Scansione già `fallita` (retry
  /// manuale dal riepilogo, nessun retry automatico — #27): riusa la riga
  /// `AnalisiCopertina` esistente invece di crearne una seconda.
  Future<void> riprova(String percorsoImmagine) async {
    final scansioneId = await _repository.idScansionePerImmagine(
      percorsoImmagine,
    );
    final analisiId = await _repository.idAnalisiCopertinaPerScansione(
      scansioneId,
    );
    await _repository.riavviaAnalisiCopertina(id: analisiId);
    await _eseguiAnalisi(
      analisiId: analisiId,
      scansioneId: scansioneId,
      percorsoImmagine: percorsoImmagine,
    );
  }

  Future<void> _eseguiAnalisi({
    required int analisiId,
    required int scansioneId,
    required String percorsoImmagine,
  }) async {
    try {
      final bytes = await File(percorsoImmagine).readAsBytes();
      final risultato = await _client.estraiCopertina(bytes);
      await _repository.completaAnalisiCopertina(
        id: analisiId,
        title: risultato.title,
        issueNumberLabel: risultato.issueNumberLabel,
        publisher: risultato.publisher,
        seriesName: risultato.seriesName,
        isbn: risultato.isbn,
        barcode: risultato.barcode,
        price: risultato.price,
        releaseDate: risultato.releaseDate,
        pageCount: risultato.pageCount,
        language: risultato.language,
        color: risultato.color,
        issn: risultato.issn,
        characters: risultato.characters,
        coverStyleTags: risultato.coverStyleTags,
        visualElementTags: risultato.visualElementTags,
        recognizedPublisherLogo: risultato.recognizedPublisherLogo,
        recognizedSeriesLogo: risultato.recognizedSeriesLogo,
        printingType: risultato.printingType,
        classificazione: risultato.classificazione,
        description: risultato.description,
        rawResponse: jsonEncode(risultato.raw),
      );
    } on Object catch (e) {
      await _repository.fallisciAnalisiCopertina(
        id: analisiId,
        errorMessage: e.toString(),
      );
      return;
    }
    await _identificazionePipeline.identifica(scansioneId: scansioneId);
  }
}
