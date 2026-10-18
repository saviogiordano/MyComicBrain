import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

import 'contratto/adapter_sotto_contratto.dart';

/// `http.Client` finto per [CopertinaDownloader]: risponde con [bytes] fissi,
/// oppure lancia se `null` (simula un host irraggiungibile) — stesso
/// pattern di `comic_vine_client_test.dart`/`copertina_downloader_test.dart`.
class _FakeCoverHttpClient extends http.BaseClient {
  _FakeCoverHttpClient({this.bytes});

  final List<int>? bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final corpo = bytes;
    if (corpo == null) throw const SocketException('host irraggiungibile');
    return http.StreamedResponse(Stream.value(corpo), 200);
  }
}

void main() => contrattoIdentificazione(creaAdapterDriftInMemoria);

/// Area Identificazione della suite di contratto di `ComicsRepository`
/// (ADR-0007): Identificazione e Candidati, la conferma di un Candidato, la
/// cover presa da una Scansione e i dati del motore di matching. Le verifiche
/// passano solo dall'interfaccia, così la stessa area gira su ogni adapter.
void contrattoIdentificazione(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;
  late Directory tempBase;

  /// Il percorso immagine di ogni Scansione creata da [scansione], per
  /// `watchScansioneConfermata`.
  final immagini = <String, String>{};

  setUp(() async {
    adapter = await crea();
    repo = adapter.repo;
    tempBase = await Directory.systemTemp.createTemp(
      'contratto_identificazione_',
    );
    immagini.clear();
  });

  tearDown(() async {
    await adapter.chiudi();
    await tempBase.delete(recursive: true);
  });

  /// Un repository sugli stessi dati con le cover in [tempBase], per i test
  /// che salvano o risolvono cover (`path_provider` non è disponibile nei
  /// test).
  ComicsRepository repoConCover({http.Client? httpClient}) => adapter.repoCon(
    copertinaDownloader: CopertinaDownloader(
      httpClient: httpClient,
      baseDirectory: () async => tempBase,
    ),
  );

  Future<String> scansione() async {
    final immagine = await adapter.immagineScansione(
      '${immagini.length + 1}.jpg',
    );
    final id = await repo.aggiungiScansione(image: immagine);
    immagini[id] = immagine;
    return id;
  }

  Future<bool> confermata(String scansioneId) =>
      repo.watchScansioneConfermata(immagini[scansioneId]!).first;

  Future<List<Candidato>> candidati(String scansioneId) async =>
      (await repo.watchIdentificazione(scansioneId).first).candidati;

  /// L'Edizione a cui appartiene la Copia [copiaId], con le sue Copie. Letta
  /// con [repoConCover]: `watchEdizione` risolve anche la cover.
  Future<(EdizioneDettaglio, CopiaDettaglio)> edizioneDiCopia(
    String copiaId,
  ) async {
    final lettore = repoConCover();
    for (final e in await lettore.catalogoPerMatching()) {
      final dettaglio = (await lettore.watchEdizione(e.edizioneId).first)!;
      for (final copia in dettaglio.copie) {
        if (copia.id == copiaId) return (dettaglio, copia);
      }
    }
    throw StateError('Copia $copiaId non trovata');
  }

  /// Una Scansione con un'Analisi Copertina già `completata` — invariante
  /// richiesto da `confermaCandidato` per un Candidato `esterno` (deciso su
  /// #70: i campi bibliografici vengono presi da qui, non più solo dal
  /// Candidato ComicVine). Nessun campo valorizzato di default: i test che
  /// non passano parametri esercitano il ripiego sui campi grezzi del
  /// Candidato quando l'AI non ha letto nulla.
  Future<String> scansioneConAnalisi({
    String? title,
    String? issueNumberLabel,
    String? publisher,
    String? seriesName,
    String? isbn,
    String? barcode,
    String? price,
    String? releaseDate,
    int? year,
    int? pageCount,
    String? language,
    String? color,
    String? printingType,
    String? classificazione,
    String? description,
  }) async {
    final scansioneId = await scansione();
    final analisiId = await repo.avviaAnalisiCopertina(
      scansioneId: scansioneId,
    );
    await repo.completaAnalisiCopertina(
      id: analisiId,
      rawResponse: '{}',
      title: title,
      issueNumberLabel: issueNumberLabel,
      publisher: publisher,
      seriesName: seriesName,
      isbn: isbn,
      barcode: barcode,
      price: price,
      releaseDate: releaseDate,
      year: year,
      pageCount: pageCount,
      language: language,
      color: color,
      printingType: printingType,
      classificazione: classificazione,
      description: description,
    );
    return scansioneId;
  }

  test('avviaIdentificazione crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );

    expect(
      await repo.idIdentificazionePerScansione(scansioneId),
      identificazioneId,
    );
    final esito = await repo.watchIdentificazione(scansioneId).first;
    expect(esito.stato, StatoIdentificazione.inCorso);
    expect(esito.errorMessage, isNull);
    expect(esito.candidati, isEmpty);
  });

  test(
    "idIdentificazionePerScansione è null finché l'Identificazione non esiste",
    () async {
      final scansioneId = await scansione();

      expect(await repo.idIdentificazionePerScansione(scansioneId), isNull);
    },
  );

  test('riavviaIdentificazione torna inCorso e scarta i Candidati del giro '
      'precedente', () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 80,
    );
    await repo.fallisciIdentificazione(
      id: identificazioneId,
      errorMessage: 'ComicVine offline',
    );

    await repo.riavviaIdentificazione(id: identificazioneId);

    final esito = await repo.watchIdentificazione(scansioneId).first;
    expect(esito.stato, StatoIdentificazione.inCorso);
    expect(esito.errorMessage, isNull);
    expect(esito.candidati, isEmpty);
  });

  test(
    "aggiungiCandidato persiste un candidato interno collegato a un'Edizione",
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        issueNumberLabel: '1',
      );

      final candidatoId = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 92.5,
        edizioneId: edizioneId,
      );

      final riga = (await candidati(scansioneId)).single;
      expect(riga.id, candidatoId);
      expect(riga.source, FonteCandidato.interno);
      expect(riga.edizioneId, edizioneId);
      expect(riga.punteggio, 92.5);
      expect(riga.scelto, isFalse);
      expect(riga.title, isNull);
    },
  );

  test('watchIdentificazione risolve il coverImageUrl di un Candidato interno '
      "come la cover dell'Edizione catalogata (bug osservato: la cover del "
      'candidato "già in collezione" non si vedeva mai in "Possibile '
      'corrispondenza")', () async {
    final repoConBase = repoConCover();
    final sorgente = File('${tempBase.path}/sorgente.jpg')
      ..writeAsBytesSync([7, 8, 9]);
    final cover = await repoConBase.salvaCoverLocale(sorgente);

    final scansioneId = await scansione();
    final identificazioneId = await repoConBase.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    final operaId = await repoConBase.aggiungiOpera(title: 'Batman');
    final edizioneId = await repoConBase.aggiungiEdizione(
      operaId: operaId,
      coverImage: cover,
    );
    await repoConBase.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.interno,
      punteggio: 96,
      edizioneId: edizioneId,
      coverImageUrl: cover,
    );

    final esito = await repoConBase.watchIdentificazione(scansioneId).first;
    final risolta = esito.candidati.single.coverImageUrl;
    expect(risolta, await repoConBase.risolviCoverImage(cover));
    expect(File(risolta!).readAsBytesSync(), [7, 8, 9]);
  });

  test(
    'aggiungiCandidato persiste un candidato esterno con i campi grezzi ComicVine',
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );

      final candidatoId = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 71,
        title: 'Amazing Spider-Man',
        seriesName: 'The Amazing Spider-Man',
        issueNumberLabel: '1',
        publisher: 'Marvel',
        year: 1963,
        coverImageUrl: 'https://comicvine.example/1.jpg',
      );

      final riga = (await candidati(scansioneId)).single;
      expect(riga.id, candidatoId);
      expect(riga.source, FonteCandidato.esterno);
      expect(riga.edizioneId, isNull);
      expect(riga.title, 'Amazing Spider-Man');
      expect(riga.seriesName, 'The Amazing Spider-Man');
      expect(riga.issueNumberLabel, '1');
      expect(riga.publisher, 'Marvel');
      expect(riga.year, 1963);
      expect(riga.coverImageUrl, 'https://comicvine.example/1.jpg');
    },
  );

  test(
    'completaIdentificazione registra lo stato completata anche con zero candidati',
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );

      await repo.completaIdentificazione(id: identificazioneId);

      final esito = await repo.watchIdentificazione(scansioneId).first;
      expect(esito.stato, StatoIdentificazione.completata);
      expect(esito.errorMessage, isNull);
      expect(esito.candidati, isEmpty);
    },
  );

  test(
    'fallisciIdentificazione registra il motivo e lo stato fallita',
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );

      await repo.fallisciIdentificazione(
        id: identificazioneId,
        errorMessage: 'ComicVine offline',
      );

      final esito = await repo.watchIdentificazione(scansioneId).first;
      expect(esito.stato, StatoIdentificazione.fallita);
      expect(esito.errorMessage, 'ComicVine offline');
    },
  );

  test(
    'marcaCandidatoScelto marca la riga confermata senza toccare le altre',
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final scelto = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 80,
      );
      final altro = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 50,
      );

      await repo.marcaCandidatoScelto(id: scelto);

      final righe = {for (final c in await candidati(scansioneId)) c.id: c};
      expect(righe[scelto]!.scelto, isTrue);
      expect(righe[altro]!.scelto, isFalse);
    },
  );

  test(
    'analisiCopertinaPerScansione legge la riga completata della Scansione',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repo.completaAnalisiCopertina(
        id: analisiId,
        rawResponse: '{}',
        title: 'Batman',
        seriesName: 'Batman',
      );

      final analisi = await repo.analisiCopertinaPerScansione(scansioneId);

      expect(analisi.id, analisiId);
      expect(analisi.title, 'Batman');
      expect(analisi.seriesName, 'Batman');
    },
  );

  test(
    'catalogoPerMatching risolve Opera/Serie via join, Serie nullable quando assente',
    () async {
      final operaId = await repo.aggiungiOpera(title: 'Batman');
      final serieId = await repo.aggiungiSerie(name: 'Batman (1940)');
      final edizioneConSerie = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
        publisher: 'DC Comics',
        issueNumber: 42,
        issueNumberLabel: '42',
        coverImage: 'https://example/42.jpg',
      );
      final operaSenzaSerie = await repo.aggiungiOpera(title: 'One shot');
      final edizioneSenzaSerie = await repo.aggiungiEdizione(
        operaId: operaSenzaSerie,
      );

      final catalogo = await repo.catalogoPerMatching();

      expect(catalogo, hasLength(2));
      final conSerie = catalogo.firstWhere(
        (e) => e.edizioneId == edizioneConSerie,
      );
      expect(conSerie.title, 'Batman');
      expect(conSerie.serieId, serieId);
      expect(conSerie.seriesName, 'Batman (1940)');
      expect(conSerie.publisher, 'DC Comics');
      expect(conSerie.issueNumber, 42);
      expect(conSerie.issueNumberLabel, '42');
      expect(conSerie.coverImage, 'https://example/42.jpg');
      final senzaSerie = catalogo.firstWhere(
        (e) => e.edizioneId == edizioneSenzaSerie,
      );
      expect(senzaSerie.serieId, isNull);
      expect(senzaSerie.seriesName, isNull);
    },
  );

  test(
    'numeriPossedutiPerSerie raggruppa solo le Copie possedute/prestate con numero',
    () async {
      final serieId = await repo.aggiungiSerie(name: 'Spider-Man');
      final operaId = await repo.aggiungiOpera(title: 'Spider-Man');
      final edizione1 = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
        issueNumber: 1,
      );
      final edizione2 = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
        issueNumber: 2,
      );
      final edizioneVenduta = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
        issueNumber: 3,
      );
      final edizioneSenzaNumero = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
      );
      await repo.aggiungiCopia(
        edizioneId: edizione1,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizione2,
        status: StatoCopia.prestata,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneVenduta,
        status: StatoCopia.venduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneSenzaNumero,
        status: StatoCopia.posseduta,
      );

      final numeri = await repo.numeriPossedutiPerSerie();

      expect(numeri[serieId], {1, 2});
    },
  );

  test(
    'watchIdentificazione emette pending finché la riga non esiste ancora',
    () async {
      final scansioneId = await scansione();

      final esito = await repo.watchIdentificazione(scansioneId).first;

      expect(esito.stato, StatoIdentificazione.pending);
      expect(esito.errorMessage, isNull);
      expect(esito.candidati, isEmpty);
    },
  );

  test(
    'watchIdentificazione riflette lo stato e i Candidati ordinati per punteggio',
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );

      final basso = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 50,
        title: 'Basso',
      );
      final alto = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 90,
        title: 'Alto',
      );
      await repo.completaIdentificazione(id: identificazioneId);

      final esito = await repo.watchIdentificazione(scansioneId).first;

      expect(esito.stato, StatoIdentificazione.completata);
      expect(esito.candidati.map((c) => c.id), [alto, basso]);
      expect(esito.candidati.first.title, 'Alto');
      expect(esito.candidati.first.scelto, isFalse);
    },
  );

  test('watchIdentificazione riflette completata con zero Candidati', () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.completaIdentificazione(id: identificazioneId);

    final esito = await repo.watchIdentificazione(scansioneId).first;

    expect(esito.stato, StatoIdentificazione.completata);
    expect(esito.candidati, isEmpty);
  });

  test(
    "confermaCandidato interno marca la riga scelta e aggiunge una Copia all'Edizione",
    () async {
      final scansioneId = await scansione();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final operaId = await repo.aggiungiOpera(title: 'Batman');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        issueNumberLabel: '42',
      );
      final candidatoId = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 96,
        edizioneId: edizioneId,
      );
      final candidato = (await candidati(scansioneId)).single;
      expect(candidato.id, candidatoId);

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final (edizione, copia) = await edizioneDiCopia(copiaId);
      expect(edizione.edizioneId, edizioneId);
      expect(copia.status, StatoCopia.posseduta);
      expect(copia.condition, CondizioneCopia.fine);
      expect(copia.purchasePrice, isNull);
      expect(await confermata(scansioneId), isTrue);
      expect(
        await repo.catalogoPerMatching(),
        hasLength(1),
        reason: 'nessuna nuova Edizione creata per un candidato interno',
      );
      expect((await candidati(scansioneId)).single.scelto, isTrue);
    },
  );

  test(
    "confermaCandidato interno applica la Descrizione letta dall'Analisi "
    "Copertina di questa Scansione quando l'Edizione già catalogata non ne "
    'ha ancora una — una seconda copia dello stesso numero non deve far '
    'perdere una trama nel frattempo disponibile (richiesta utente)',
    () async {
      final scansioneId = await scansioneConAnalisi(
        description: 'Peter Parker affronta il Green Goblin.',
      );
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final operaId = await repo.aggiungiOpera(title: 'Batman');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        issueNumberLabel: '42',
      );
      await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 96,
        edizioneId: edizioneId,
      );
      final candidato = (await candidati(scansioneId)).single;

      await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final edizione = (await repo.watchEdizione(edizioneId).first)!;
      expect(edizione.description, 'Peter Parker affronta il Green Goblin.');
    },
  );

  test(
    'confermaCandidato interno non sovrascrive la Descrizione già presente '
    "sull'Edizione con quella (diversa) letta da questa Analisi Copertina — "
    'stesso principio "primo valore buono vince" del percorso esterno',
    () async {
      final scansioneId = await scansioneConAnalisi(
        description: 'Trama letta in questa nuova scansione.',
      );
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final operaId = await repo.aggiungiOpera(title: 'Batman');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        issueNumberLabel: '42',
        description: 'Trama già presente in catalogo.',
      );
      await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 96,
        edizioneId: edizioneId,
      );
      final candidato = (await candidati(scansioneId)).single;

      await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final edizione = (await repo.watchEdizione(edizioneId).first)!;
      expect(edizione.description, 'Trama già presente in catalogo.');
    },
  );

  test('confermaCandidato aggiunge la Copia con condizione di default "Fine" e '
      'prezzo di acquisto pre-compilato dal prezzo di copertina letto '
      "dall'AI (bug osservato: la Copia veniva creata senza condizione né "
      'prezzo)', () async {
    final scansioneId = await scansioneConAnalisi(price: '€ 5,30');
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    final operaId = await repo.aggiungiOpera(title: 'Batman');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      issueNumberLabel: '42',
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.interno,
      punteggio: 96,
      edizioneId: edizioneId,
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (_, copia) = await edizioneDiCopia(copiaId);
    expect(copia.condition, CondizioneCopia.fine);
    expect(copia.purchasePrice, 5.30);
  });

  test('confermaCandidato riconosce un prezzo di copertina in dollari (fumetto '
      'americano) dal simbolo "\$" letto dall\'AI, e lo marca come tale sulla '
      'Copia', () async {
    final scansioneId = await scansioneConAnalisi(price: r'$3.99');
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    final operaId = await repo.aggiungiOpera(title: 'Batman');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      issueNumberLabel: '42',
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.interno,
      punteggio: 96,
      edizioneId: edizioneId,
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (_, copia) = await edizioneDiCopia(copiaId);
    expect(copia.purchasePrice, 3.99);
    expect(copia.purchasePriceCurrency, ValutaPrezzo.usd);
  });

  test('confermaCandidato assume EUR quando il prezzo di copertina letto '
      "dall'AI non riporta il simbolo del dollaro", () async {
    final scansioneId = await scansioneConAnalisi(price: '€ 5,30');
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    final operaId = await repo.aggiungiOpera(title: 'Batman');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      issueNumberLabel: '42',
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.interno,
      punteggio: 96,
      edizioneId: edizioneId,
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (_, copia) = await edizioneDiCopia(copiaId);
    expect(copia.purchasePriceCurrency, ValutaPrezzo.eur);
  });

  test(
    'confermaCandidato esterno crea Opera/Serie/Edizione/Copia da zero e '
    'conserva una copia propria della cover invece del solo URL remoto',
    () async {
      final repoConDownload = repoConCover(
        httpClient: _FakeCoverHttpClient(bytes: [1, 2, 3]),
      );

      final scansioneId = await scansioneConAnalisi();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final candidatoId = await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 78,
        title: 'Amazing Spider-Man',
        seriesName: 'The Amazing Spider-Man',
        issueNumberLabel: '1',
        publisher: 'Marvel',
        coverImageUrl: 'https://comicvine.example/1.jpg',
      );
      final candidato = (await candidati(scansioneId)).single;

      final copiaId = await repoConDownload.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final (edizione, copia) = await edizioneDiCopia(copiaId);
      expect(copia.status, StatoCopia.posseduta);
      expect(await confermata(scansioneId), isTrue);
      expect(edizione.publisher, 'Marvel');
      expect(edizione.issueNumberLabel, '1');
      expect(edizione.issueNumber, 1);
      expect(edizione.titolo, 'Amazing Spider-Man');
      expect(edizione.serieName, 'The Amazing Spider-Man');
      // La cover è stata scaricata (§6.3): in DB non c'è più l'URL remoto
      // ma un valore dell'adapter che si risolve nel file scaricato.
      final coverImage = await repoConDownload.coverImageGrezzoDi(
        edizione.edizioneId,
      );
      expect(coverImage, isNotNull);
      expect(coverImage, isNot('https://comicvine.example/1.jpg'));
      final fileCopertina = File(
        (await repoConDownload.risolviCoverImage(coverImage))!,
      );
      expect(fileCopertina.readAsBytesSync(), [1, 2, 3]);
      final righe = await candidati(scansioneId);
      expect(righe.single.id, candidatoId);
      expect(righe.single.scelto, isTrue);
    },
  );

  test('confermaCandidato esterno con numero decimale ("679.1") salva '
      "l'Edizione con issueNumber sulla parte intera — bug osservato: "
      '`int.tryParse` falliva sul decimale lasciando `issueNumber` `null`, '
      'e la Copia spariva dalla griglia numerica di Serie (#99) pur essendo '
      'stata salvata correttamente', () async {
    final scansioneId = await scansioneConAnalisi();
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 78,
      title: 'Amazing Spider-Man',
      seriesName: 'The Amazing Spider-Man',
      issueNumberLabel: '679.1',
      publisher: 'Marvel',
      coverImageUrl: 'https://comicvine.example/679.1.jpg',
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (edizione, _) = await edizioneDiCopia(copiaId);
    expect(edizione.issueNumberLabel, '679.1');
    expect(edizione.issueNumber, 679);
  });

  test(
    "confermaCandidato esterno: download cover fallito ricade sull'URL remoto",
    () async {
      final repoDownloadFallito = repoConCover(
        httpClient: _FakeCoverHttpClient(),
      );

      final scansioneId = await scansioneConAnalisi();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 78,
        title: 'Amazing Spider-Man',
        coverImageUrl: 'https://comicvine.example/1.jpg',
      );
      final candidato = (await candidati(scansioneId)).single;

      final copiaId = await repoDownloadFallito.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final (edizione, _) = await edizioneDiCopia(copiaId);
      expect(
        await repo.coverImageGrezzoDi(edizione.edizioneId),
        'https://comicvine.example/1.jpg',
      );
    },
  );

  test("confermaCandidato esterno: i campi bibliografici vengono dall'Analisi "
      'Copertina (AI), non da ComicVine — deciso su #70: la risorsa `issue` '
      'di ComicVine non espone editore/data/prezzo/pagine/lingua/colore/EAN, '
      "solo l'AI che ha letto la copertina scansionata li fornisce", () async {
    final scansioneId = await scansioneConAnalisi(
      publisher: 'Marvel Worldwide Inc.',
      releaseDate: 'febbraio 2013',
      price: r'$7,99',
      pageCount: 104,
      language: 'inglese',
      color: 'a colori',
      barcode: '75960604716170011',
    );
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 78,
      title: 'The Amazing Spider-Man',
      issueNumberLabel: '700',
      coverImageUrl: 'https://comicvine.example/700.jpg',
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (edizione, _) = await edizioneDiCopia(copiaId);
    expect(edizione.publisher, 'Marvel Worldwide Inc.');
    expect(edizione.releaseDate, 'febbraio 2013');
    expect(edizione.coverPrice, r'$7,99');
    expect(edizione.pageCount, 104);
    expect(edizione.language, 'inglese');
    expect(edizione.color, 'a colori');
    expect(edizione.ean, '75960604716170011');
    // Titolo/numero: nessun conflitto in questo caso, ma verificati per
    // completezza — arrivano comunque dal Candidato quando l'AI non li
    // sovrascrive con un valore proprio.
    expect(edizione.issueNumberLabel, '700');
  });

  test('confermaCandidato esterno: Tipo di stampa/Classificazione/Descrizione '
      "vengono dall'Analisi Copertina (AI), nessun ripiego sul Candidato — "
      'deciso su #71/#74: la risorsa `issue` di ComicVine non espone questi '
      "campi, l'AI è l'unica fonte", () async {
    final scansioneId = await scansioneConAnalisi(
      printingType: 'Direct Edition',
      classificazione: 'Rated T+',
      description: 'Peter Parker affronta il Green Goblin.',
    );
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 78,
      title: 'The Amazing Spider-Man',
      issueNumberLabel: '700',
      coverImageUrl: 'https://comicvine.example/700.jpg',
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (edizione, _) = await edizioneDiCopia(copiaId);
    expect(edizione.printingType, 'Direct Edition');
    expect(edizione.classificazione, 'Rated T+');
    expect(edizione.description, 'Peter Parker affronta il Green Goblin.');
  });

  test(
    'confermaCandidato esterno: Tipo di stampa/Classificazione/Descrizione '
    "restano vuoti quando l'Analisi Copertina non li ha letti — nessun "
    'ripiego possibile, il Candidato ComicVine non porta questi campi',
    () async {
      final scansioneId = await scansioneConAnalisi();
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 78,
        title: 'The Amazing Spider-Man',
        issueNumberLabel: '700',
        coverImageUrl: 'https://comicvine.example/700.jpg',
      );
      final candidato = (await candidati(scansioneId)).single;

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final (edizione, _) = await edizioneDiCopia(copiaId);
      expect(edizione.printingType, isNull);
      expect(edizione.classificazione, isNull);
      expect(edizione.description, isNull);
    },
  );

  test(
    "confermaCandidato esterno: un campo letto dall'AI vince sullo stesso "
    'campo del Candidato ComicVine quando entrambi sono valorizzati',
    () async {
      final scansioneId = await scansioneConAnalisi(
        title: 'Amazing Fantasy 15',
        seriesName: 'Amazing Fantasy',
        issueNumberLabel: '15',
      );
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 78,
        title: 'Amazing Fantasy #15',
        seriesName: 'Amazing Fantasy (Marvel)',
        issueNumberLabel: '015',
        coverImageUrl: 'https://comicvine.example/15.jpg',
      );
      final candidato = (await candidati(scansioneId)).single;

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final (edizione, _) = await edizioneDiCopia(copiaId);
      expect(edizione.titolo, 'Amazing Fantasy 15');
      expect(edizione.serieName, 'Amazing Fantasy');
      expect(edizione.issueNumberLabel, '15');
    },
  );

  test(
    'confermaCandidato esterno: il prefisso "#" letto dall\'AI nel numero '
    'viene ripulito prima del salvataggio, altrimenti issueNumber resta '
    'null (int.tryParse("#12") fallisce) e issueNumberLabel resta sporco',
    () async {
      final scansioneId = await scansioneConAnalisi(issueNumberLabel: '#12');
      final identificazioneId = await repo.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repo.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 78,
        title: 'Some Comic',
        coverImageUrl: 'https://comicvine.example/12.jpg',
      );
      final candidato = (await candidati(scansioneId)).single;

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final (edizione, _) = await edizioneDiCopia(copiaId);
      expect(edizione.issueNumberLabel, '12');
      expect(edizione.issueNumber, 12);
    },
  );

  test("confermaCandidato esterno: l'anno letto dall'AI (campo strutturato a "
      'sé, deciso su #81) viene salvato sull\'Edizione', () async {
    final scansioneId = await scansioneConAnalisi(year: 1988);
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 78,
      title: 'Some Comic',
      coverImageUrl: 'https://comicvine.example/12.jpg',
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (edizione, _) = await edizioneDiCopia(copiaId);
    expect(edizione.year, 1988);
  });

  test("confermaCandidato esterno: l'anno del Candidato è il ripiego quando "
      "l'AI non l'ha letto", () async {
    final scansioneId = await scansioneConAnalisi();
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 78,
      title: 'Some Comic',
      year: 1988,
      coverImageUrl: 'https://comicvine.example/12.jpg',
    );
    final candidato = (await candidati(scansioneId)).single;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final (edizione, _) = await edizioneDiCopia(copiaId);
    expect(edizione.year, 1988);
  });

  test(
    'aggiungiCopia con scansioneId collega la Copia alla Scansione di origine',
    () async {
      final scansioneId = await scansione();
      final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);

      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        scansioneId: scansioneId,
      );

      expect(await confermata(scansioneId), isTrue);
    },
  );

  test(
    'coverImagePerScansione restituisce una cover per aggiungiEdizione che '
    "si risolve nell'immagine della Scansione (inserimento manuale, #63)",
    () async {
      final repoConBase = repoConCover();
      final scansioneId = await scansione();

      final cover = await repoConBase.coverImagePerScansione(scansioneId);
      final operaId = await repoConBase.aggiungiOpera(title: 'Batman');
      final edizioneId = await repoConBase.aggiungiEdizione(
        operaId: operaId,
        coverImage: cover,
      );

      expect(await repoConBase.coverImageGrezzoDi(edizioneId), cover);
      final risolta = await repoConBase.risolviCoverImage(cover);
      expect(File(risolta!).readAsBytesSync(), bytesImmagineScansione);
    },
  );

  test(
    'coverImagePerScansione trova la Scansione anche se il container iOS è '
    'cambiato (segnalato da utente: cover assente in Inserisci manualmente '
    'dopo una reinstallazione)',
    () async {
      final repoConBase = repoConCover();
      File('${tempBase.path}/scansioni/vecchia.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([4, 5, 6]);
      // Percorso assoluto scritto da un'installazione precedente.
      final scansioneId = await repo.aggiungiScansione(
        image:
            '/var/mobile/Containers/Data/Application/VECCHIO/Library/'
            'Application Support/scansioni/vecchia.jpg',
      );

      final cover = await repoConBase.coverImagePerScansione(scansioneId);

      expect(cover, 'scansioni/vecchia.jpg');
      final risolta = await repoConBase.risolviCoverImage(cover);
      expect(File(risolta!).readAsBytesSync(), [4, 5, 6]);
    },
  );

  test('ripristinaCoverMancantiDaScansione ridà la cover della Scansione alle '
      'sole Edizioni senza cover con una Copia scansionata', () async {
    final repoConBase = repoConCover();
    final operaId = await repo.aggiungiOpera(title: 'Batman');
    final senzaCover = await repo.aggiungiEdizione(operaId: operaId);
    final conCover = await repo.aggiungiEdizione(
      operaId: operaId,
      coverImage: 'https://example/42.jpg',
    );
    final senzaScansione = await repo.aggiungiEdizione(operaId: operaId);
    for (final edizioneId in [senzaCover, conCover]) {
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        scansioneId: await scansione(),
      );
    }
    await repo.aggiungiCopia(
      edizioneId: senzaScansione,
      status: StatoCopia.posseduta,
    );

    final ripristinate = await repoConBase.ripristinaCoverMancantiDaScansione();

    expect(ripristinate, 1);
    final cover = await repoConBase.coverImageGrezzoDi(senzaCover);
    final risolta = await repoConBase.risolviCoverImage(cover);
    expect(File(risolta!).readAsBytesSync(), bytesImmagineScansione);
    expect(await repo.coverImageGrezzoDi(conCover), 'https://example/42.jpg');
    expect(await repo.coverImageGrezzoDi(senzaScansione), isNull);
  });

  test(
    'ripristinaCoverMancantiDaScansione trova la Scansione anche se il '
    'container iOS è cambiato',
    () async {
      final repoConBase = repoConCover();
      File('${tempBase.path}/scansioni/vecchia.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([4, 5, 6]);
      final operaId = await repo.aggiungiOpera(title: 'Batman');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        scansioneId: await repo.aggiungiScansione(
          image:
              '/var/mobile/Containers/Data/Application/VECCHIO/Library/'
              'Application Support/scansioni/vecchia.jpg',
        ),
      );

      await repoConBase.ripristinaCoverMancantiDaScansione();

      expect(
        await repoConBase.coverImageGrezzoDi(edizioneId),
        'scansioni/vecchia.jpg',
      );
    },
  );
}
