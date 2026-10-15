import 'dart:convert';
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_compressor.dart';
import 'package:mycomicbrain/core/data/identificazione_pipeline.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';

/// Pipeline di analisi copertina di fine batch (§6.1 OCR + §6.2 computer
/// vision, deciso su #27/#32, esteso su #49): per ogni Scansione appena
/// confermata, ridimensiona/comprime la cover per l'invio
/// (`comprimiCoverPerAI`, mitiga `coverAnalysisTimeout` su una foto ad alta
/// risoluzione), chiama il provider AI configurato dalle Impostazioni (§12,
/// Claude di default, vedi `coverAnalysisClientProvider` in
/// `providers.dart`), fa il parsing della risposta secondo lo schema deciso
/// (#31, #47) e persiste il risultato — completata o fallita,
/// nessun retry automatico. Le Scansioni del batch sono processate in
/// sequenza: un batch di fine sessione non ha requisiti di concorrenza, e
/// restare sequenziali evita di sommare più chiamate in parallelo contro il
/// rate limit (vedi ricerca #28). Quando l'Analisi Copertina si completa con
/// successo, aggancia subito l'Identificazione (§6.3, deciso su #58): stesso
/// trigger/batch, non un'azione manuale dell'utente. Un fallimento
/// dell'Identificazione (es. ComicVine irraggiungibile, già gestito da
/// `IdentificazionePipeline` con stato `fallita` e nessun retry) non tocca
/// lo stato `completata` già persistito dell'Analisi Copertina.
///
/// Con un Profilo la Scansione può essere mandata al riconoscimento senza
/// rete (ADR-0008, #210): [accoda] crea la riga `pending` ("in attesa di
/// rete") e [avviaInAttesa], al ritorno della rete, la prende in carico.
/// Solo il device che ha il file la avvia: gli altri, che ricevono la
/// Scansione con la Sincronizzazione ma non l'immagine, la lasciano
/// `pending`, così la stessa chiamata AI non si paga due volte.
class AnalisiCopertinaPipeline {
  AnalisiCopertinaPipeline({
    required ComicsRepository repository,
    CoverAnalysisClient? client,
    IdentificazionePipeline? identificazionePipeline,
    Future<String> Function(String image)? risolviImmagine,
  }) : _repository = repository,
       _client = client ?? ClaudeCoverAnalysisClient(),
       _identificazionePipeline =
           identificazionePipeline ??
           IdentificazionePipeline(repository: repository),
       _risolviImmagine = risolviImmagine ?? _stessoPercorso;

  final ComicsRepository _repository;
  final CoverAnalysisClient _client;
  final IdentificazionePipeline _identificazionePipeline;

  /// Il percorso del file sul device per il valore di `Scansioni.image`
  /// (`ScansioneStorage.risolvi`): una Scansione arrivata da un altro
  /// device ha un percorso relativo alla cartella del Profilo.
  final Future<String> Function(String image) _risolviImmagine;

  static Future<String> _stessoPercorso(String image) async => image;

  Future<void>? _inAttesaInCorso;
  var _inAttesaDiNuovo = false;

  /// Avvia l'analisi per ogni Scansione del batch, identificata dal
  /// percorso immagine già persistito (#21): [accoda], poi [avviaInAttesa].
  /// Ogni Scansione è indipendente: il fallimento di una non blocca le
  /// altre.
  Future<void> avviaBatch(Iterable<String> percorsiImmagine) async {
    await accoda(percorsiImmagine);
    await avviaInAttesa();
  }

  /// Manda le Scansioni del batch al riconoscimento senza avviarlo: senza
  /// rete restano `pending` fino ad [avviaInAttesa]. Salta le Scansioni che
  /// hanno già un'Analisi Copertina (hanno il loro retry, [riprova]) e
  /// quelle il cui file non è su questo device.
  Future<void> accoda(Iterable<String> percorsiImmagine) async {
    for (final percorso in percorsiImmagine) {
      final String scansioneId;
      try {
        scansioneId = await _repository.idScansionePerImmagine(percorso);
      } on Object {
        // La Scansione può essere stata cancellata con lo swipe-to-delete
        // dopo che il batch è partito — possibile su un batch ripreso dalla
        // Dashboard, dove la cancellazione resta sempre disponibile
        // (segnalato da utente, vedi `RiepilogoPage.ripresa`). Nulla da
        // analizzare: si passa alla successiva.
        continue;
      }
      if (!await File(await _risolviImmagine(percorso)).exists()) continue;
      await _repository.accodaAnalisiCopertina(scansioneId: scansioneId);
    }
  }

  /// Prende in carico, una alla volta, le Scansioni `pending` il cui file è
  /// su questo device, comprese quelle accodate mentre gira. Una chiamata
  /// durante un giro in corso non ne fa partire un secondo in parallelo:
  /// il giro in corso ricomincia alla fine.
  Future<void> avviaInAttesa() {
    if (_inAttesaInCorso case final inCorso?) {
      _inAttesaDiNuovo = true;
      return inCorso;
    }
    return _inAttesaInCorso = _giroInAttesa().whenComplete(
      () => _inAttesaInCorso = null,
    );
  }

  Future<void> _giroInAttesa() async {
    // Una Scansione senza file resta `pending`: non va ripresa a ogni giro.
    final saltate = <String>{};
    do {
      _inAttesaDiNuovo = false;
      while (true) {
        final inAttesa = await _repository
            .watchScansioniInAttesaDiAnalisi()
            .first;
        ScansioneInAttesa? prossima;
        String? file;
        for (final s in inAttesa) {
          if (saltate.contains(s.analisiId)) continue;
          final percorso = await _risolviImmagine(s.image);
          if (await File(percorso).exists()) {
            prossima = s;
            file = percorso;
            break;
          }
          saltate.add(s.analisiId);
        }
        if (prossima == null || file == null) break;
        await _repository.riavviaAnalisiCopertina(id: prossima.analisiId);
        await _eseguiAnalisi(
          analisiId: prossima.analisiId,
          scansioneId: prossima.scansioneId,
          percorsoImmagine: file,
        );
      }
    } while (_inAttesaDiNuovo);
  }

  /// Ripete l'Analisi Copertina di una Scansione — retry manuale dal
  /// riepilogo (nessun retry automatico — #27): riusa la riga
  /// `AnalisiCopertina` esistente invece di crearne una seconda. Chiamato
  /// sia da una riga `fallita` (retry sulla chip di errore) sia, su
  /// richiesta esplicita dell'utente, da una riga già `completata` (chip
  /// "Completata" del riepilogo): in quel caso scarta il risultato
  /// precedente e riaggancia anche l'Identificazione a valle (#58), che
  /// riprende a sua volta la propria riga invece di duplicarla — vedi
  /// `IdentificazionePipeline.identifica`.
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
      percorsoImmagine: await _risolviImmagine(percorsoImmagine),
    );
  }

  Future<void> _eseguiAnalisi({
    required String analisiId,
    required String scansioneId,
    required String percorsoImmagine,
  }) async {
    try {
      final bytes = await File(percorsoImmagine).readAsBytes();
      final risultato = await _client.estraiCopertina(
        comprimiCoverPerAI(bytes),
      );
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
        year: risultato.year,
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
    try {
      await _identificazionePipeline.identifica(scansioneId: scansioneId);
    } on Object {
      // Un fallimento imprevisto qui (non un `ComicVineException`, già
      // gestito dentro `identifica`) non deve interrompere `avviaBatch`:
      // l'Analisi Copertina di questa Scansione è già persistita
      // `completata` sopra, e ogni Scansione del batch è indipendente —
      // un'eccezione non catturata qui si propagherebbe fuori dal `for` di
      // `avviaBatch`, saltando tutte le Scansioni successive del batch
      // (segnalato da utente: capitava rielaborando una Scansione già
      // `completata`, dove una seconda riga `AnalisiCopertina` per lo
      // stesso id fa fallire `getSingle()` dentro `identifica`).
    }
  }
}
