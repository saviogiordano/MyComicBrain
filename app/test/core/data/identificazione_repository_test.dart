import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> scansione() => repo.aggiungiScansione(image: '/scansioni/1.jpg');

  test('avviaIdentificazione crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final identificazioneId = await repo.avviaIdentificazione(scansioneId: scansioneId);

    final riga = await (db.select(
      db.identificazioneTable,
    )..where((i) => i.id.equals(identificazioneId))).getSingle();
    expect(riga.scansioneId, scansioneId);
    expect(riga.status, StatoIdentificazione.inCorso);
    expect(riga.errorMessage, isNull);
    expect(riga.completedAt, isNull);
  });

  test("aggiungiCandidato persiste un candidato interno collegato a un'Edizione", () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(scansioneId: scansioneId);
    final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');
    final edizioneId = await repo.aggiungiEdizione(operaId: operaId, issueNumberLabel: '1');

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
  });

  test('aggiungiCandidato persiste un candidato esterno con i campi grezzi ComicVine', () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(scansioneId: scansioneId);

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
  });

  test('completaIdentificazione registra lo stato completata anche con zero candidati', () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(scansioneId: scansioneId);

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
  });

  test('fallisciIdentificazione registra il motivo e lo stato fallita', () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(scansioneId: scansioneId);

    await repo.fallisciIdentificazione(id: identificazioneId, errorMessage: 'ComicVine offline');

    final riga = await (db.select(
      db.identificazioneTable,
    )..where((i) => i.id.equals(identificazioneId))).getSingle();
    expect(riga.status, StatoIdentificazione.fallita);
    expect(riga.errorMessage, 'ComicVine offline');
    expect(riga.completedAt, isNotNull);
  });

  test('marcaCandidatoScelto marca la riga confermata senza toccare le altre', () async {
    final scansioneId = await scansione();
    final identificazioneId = await repo.avviaIdentificazione(scansioneId: scansioneId);
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
  });

  test('analisiCopertinaPerScansione legge la riga completata della Scansione', () async {
    final scansioneId = await scansione();
    final analisiId = await repo.avviaAnalisiCopertina(scansioneId: scansioneId);
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
  });

  test('catalogoPerMatching risolve Opera/Serie via join, Serie nullable quando assente', () async {
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
    final edizioneSenzaSerie = await repo.aggiungiEdizione(operaId: operaSenzaSerie);

    final catalogo = await repo.catalogoPerMatching();

    expect(catalogo, hasLength(2));
    final conSerie = catalogo.firstWhere((e) => e.edizioneId == edizioneConSerie);
    expect(conSerie.title, 'Batman');
    expect(conSerie.serieId, serieId);
    expect(conSerie.seriesName, 'Batman (1940)');
    expect(conSerie.publisher, 'DC Comics');
    expect(conSerie.issueNumber, 42);
    expect(conSerie.issueNumberLabel, '42');
    expect(conSerie.coverImage, 'https://example/42.jpg');
    final senzaSerie = catalogo.firstWhere((e) => e.edizioneId == edizioneSenzaSerie);
    expect(senzaSerie.serieId, isNull);
    expect(senzaSerie.seriesName, isNull);
  });

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
      final edizioneSenzaNumero = await repo.aggiungiEdizione(operaId: operaId, serieId: serieId);
      await repo.aggiungiCopia(edizioneId: edizione1, status: StatoCopia.posseduta);
      await repo.aggiungiCopia(edizioneId: edizione2, status: StatoCopia.prestata);
      await repo.aggiungiCopia(edizioneId: edizioneVenduta, status: StatoCopia.venduta);
      await repo.aggiungiCopia(edizioneId: edizioneSenzaNumero, status: StatoCopia.posseduta);

      final numeri = await repo.numeriPossedutiPerSerie();

      expect(numeri[serieId], {1, 2});
    },
  );

  test('aggiungiCopia con scansioneId collega la Copia alla Scansione di origine', () async {
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
  });
}
