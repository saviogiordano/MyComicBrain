import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:path/path.dart' as p;

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

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> scansione() => repo.aggiungiScansione(image: '/scansioni/1.jpg');

  /// Una Scansione con un'Analisi Copertina già `completata` — invariante
  /// richiesto da `confermaCandidato` per un Candidato `esterno` (deciso su
  /// #70: i campi bibliografici vengono presi da qui, non più solo dal
  /// Candidato ComicVine). Nessun campo valorizzato di default: i test che
  /// non passano parametri esercitano il ripiego sui campi grezzi del
  /// Candidato quando l'AI non ha letto nulla.
  Future<int> scansioneConAnalisi({
    String? title,
    String? issueNumberLabel,
    String? publisher,
    String? seriesName,
    String? isbn,
    String? barcode,
    String? price,
    String? releaseDate,
    int? pageCount,
    String? language,
    String? color,
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
      pageCount: pageCount,
      language: language,
      color: color,
    );
    return scansioneId;
  }

  test('avviaIdentificazione crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );

    final riga = await (db.select(
      db.identificazioneTable,
    )..where((i) => i.id.equals(identificazioneId))).getSingle();
    expect(riga.scansioneId, scansioneId);
    expect(riga.status, StatoIdentificazione.inCorso);
    expect(riga.errorMessage, isNull);
    expect(riga.completedAt, isNull);
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

      final riga = await (db.select(
        db.candidatiTable,
      )..where((c) => c.id.equals(candidatoId))).getSingle();
      expect(riga.identificazioneId, identificazioneId);
      expect(riga.source, FonteCandidato.interno);
      expect(riga.edizioneId, edizioneId);
      expect(riga.punteggio, 92.5);
      expect(riga.scelto, isFalse);
      expect(riga.title, isNull);
    },
  );

  test(
    'watchIdentificazione risolve il coverImageUrl locale di un Candidato '
    'interno sulla cartella base corrente (bug osservato: la cover del '
    'candidato "già in collezione" non si vedeva mai in "Possibile '
    'corrispondenza")',
    () async {
      final tempBase = await Directory.systemTemp.createTemp(
        'watchIdentificazione_cover_interno_test_',
      );
      addTearDown(() => tempBase.delete(recursive: true));
      final repoConBase = ComicsRepository(
        db,
        copertinaDownloader: CopertinaDownloader(
          baseDirectory: () async => tempBase,
        ),
      );

      final scansioneId = await repoConBase.aggiungiScansione(
        image: '/scansioni/1.jpg',
      );
      final identificazioneId = await repoConBase.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final operaId = await repoConBase.aggiungiOpera(title: 'Batman');
      final edizioneId = await repoConBase.aggiungiEdizione(operaId: operaId);
      await repoConBase.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 96,
        edizioneId: edizioneId,
        coverImageUrl: p.join('copertine', '1.jpg'),
      );

      final esito = await repoConBase.watchIdentificazione(scansioneId).first;
      expect(
        esito.candidati.single.coverImageUrl,
        p.join(tempBase.path, 'copertine', '1.jpg'),
      );
    },
  );

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

      final riga = await (db.select(
        db.candidatiTable,
      )..where((c) => c.id.equals(candidatoId))).getSingle();
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

      final riga = await (db.select(
        db.identificazioneTable,
      )..where((i) => i.id.equals(identificazioneId))).getSingle();
      expect(riga.status, StatoIdentificazione.completata);
      expect(riga.completedAt, isNotNull);
      final candidati = await (db.select(
        db.candidatiTable,
      )..where((c) => c.identificazioneId.equals(identificazioneId))).get();
      expect(candidati, isEmpty);
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

      final riga = await (db.select(
        db.identificazioneTable,
      )..where((i) => i.id.equals(identificazioneId))).getSingle();
      expect(riga.status, StatoIdentificazione.fallita);
      expect(riga.errorMessage, 'ComicVine offline');
      expect(riga.completedAt, isNotNull);
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

      final rigaScelta = await (db.select(
        db.candidatiTable,
      )..where((c) => c.id.equals(scelto))).getSingle();
      final rigaAltro = await (db.select(
        db.candidatiTable,
      )..where((c) => c.id.equals(altro))).getSingle();
      expect(rigaScelta.scelto, isTrue);
      expect(rigaAltro.scelto, isFalse);
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
      final candidato =
          (await repo.watchIdentificazione(scansioneId).first).candidati.single;
      expect(candidato.id, candidatoId);

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final copia = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      expect(copia.edizioneId, edizioneId);
      expect(copia.status, StatoCopia.posseduta);
      expect(copia.scansioneId, scansioneId);
      final edizioni = await db.select(db.edizioni).get();
      expect(
        edizioni,
        hasLength(1),
        reason: 'nessuna nuova Edizione creata per un candidato interno',
      );
      final rigaCandidato = await (db.select(
        db.candidatiTable,
      )..where((c) => c.id.equals(candidatoId))).getSingle();
      expect(rigaCandidato.scelto, isTrue);
    },
  );

  test(
    'confermaCandidato esterno crea Opera/Serie/Edizione/Copia da zero e scarica la cover in locale',
    () async {
      final tempBase = await Directory.systemTemp.createTemp(
        'confermaCandidato_esterno_test_',
      );
      addTearDown(() => tempBase.delete(recursive: true));
      final repoConDownload = ComicsRepository(
        db,
        copertinaDownloader: CopertinaDownloader(
          httpClient: _FakeCoverHttpClient(bytes: [1, 2, 3]),
          baseDirectory: () async => tempBase,
        ),
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
      final candidato =
          (await repo.watchIdentificazione(scansioneId).first).candidati.single;

      final copiaId = await repoConDownload.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final copia = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      expect(copia.status, StatoCopia.posseduta);
      expect(copia.scansioneId, scansioneId);
      final edizione = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(copia.edizioneId))).getSingle();
      expect(edizione.publisher, 'Marvel');
      expect(edizione.issueNumberLabel, '1');
      expect(edizione.issueNumber, 1);
      // La cover è stata scaricata in locale (§6.3): non più l'URL remoto
      // ma un file dentro la directory `copertine/`. Salvato *relativo*
      // alla cartella base, non assoluto: il container dell'app cambia
      // UUID a ogni reinstallazione/aggiornamento su iOS, un percorso
      // assoluto persistito in DB non sarebbe più valido al riavvio
      // successivo (bug osservato: cover sparita dopo un nuovo `flutter
      // run`) — vedi `percorso_locale.dart`.
      final coverImage = edizione.coverImage;
      expect(coverImage, isNotNull);
      expect(coverImage, isNot('https://comicvine.example/1.jpg'));
      expect(p.isRelative(coverImage!), isTrue);
      expect(p.dirname(coverImage), 'copertine');
      final fileCopertina = File(p.join(tempBase.path, coverImage));
      expect(fileCopertina.existsSync(), isTrue);
      expect(fileCopertina.readAsBytesSync(), [1, 2, 3]);
      final opera = await (db.select(
        db.opere,
      )..where((o) => o.id.equals(edizione.operaId))).getSingle();
      expect(opera.title, 'Amazing Spider-Man');
      final serie = await (db.select(
        db.serieTable,
      )..where((s) => s.id.equals(edizione.serieId!))).getSingle();
      expect(serie.name, 'The Amazing Spider-Man');
      final rigaCandidato = await (db.select(
        db.candidatiTable,
      )..where((c) => c.id.equals(candidatoId))).getSingle();
      expect(rigaCandidato.scelto, isTrue);
    },
  );

  test(
    "confermaCandidato esterno: download cover fallito ricade sull'URL remoto",
    () async {
      final repoDownloadFallito = ComicsRepository(
        db,
        copertinaDownloader: CopertinaDownloader(
          httpClient: _FakeCoverHttpClient(),
        ),
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
      final candidato =
          (await repo.watchIdentificazione(scansioneId).first).candidati.single;

      final copiaId = await repoDownloadFallito.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final copia = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      final edizione = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(copia.edizioneId))).getSingle();
      expect(edizione.coverImage, 'https://comicvine.example/1.jpg');
    },
  );

  test(
    "confermaCandidato esterno: i campi bibliografici vengono dall'Analisi "
    'Copertina (AI), non da ComicVine — deciso su #70: la risorsa `issue` '
    'di ComicVine non espone editore/data/prezzo/pagine/lingua/colore/EAN, '
    "solo l'AI che ha letto la copertina scansionata li fornisce",
    () async {
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
      final candidato =
          (await repo.watchIdentificazione(scansioneId).first).candidati.single;

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final copia = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      final edizione = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(copia.edizioneId))).getSingle();
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
      final candidato =
          (await repo.watchIdentificazione(scansioneId).first).candidati.single;

      final copiaId = await repo.confermaCandidato(
        candidato: candidato,
        scansioneId: scansioneId,
      );

      final copia = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      final edizione = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(copia.edizioneId))).getSingle();
      final opera = await (db.select(
        db.opere,
      )..where((o) => o.id.equals(edizione.operaId))).getSingle();
      final serie = await (db.select(
        db.serieTable,
      )..where((s) => s.id.equals(edizione.serieId!))).getSingle();
      expect(opera.title, 'Amazing Fantasy 15');
      expect(serie.name, 'Amazing Fantasy');
      expect(edizione.issueNumberLabel, '15');
    },
  );

  test(
    'aggiungiCopia con scansioneId collega la Copia alla Scansione di origine',
    () async {
      final scansioneId = await scansione();
      final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);

      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        scansioneId: scansioneId,
      );

      final riga = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      expect(riga.scansioneId, scansioneId);
    },
  );
}
