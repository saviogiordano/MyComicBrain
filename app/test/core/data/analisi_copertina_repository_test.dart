import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';

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

  test("idScansionePerImmagine trova l'id dalla Scansione persistita", () async {
    final id = await scansione();

    expect(await repo.idScansionePerImmagine('/scansioni/1.jpg'), id);
  });

  test('avviaAnalisiCopertina crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final analisiId = await repo.avviaAnalisiCopertina(scansioneId: scansioneId);

    final riga = await (db.select(
      db.analisiCopertinaTable,
    )..where((a) => a.id.equals(analisiId))).getSingle();
    expect(riga.scansioneId, scansioneId);
    expect(riga.status, StatoAnalisiCopertina.inCorso);
    expect(riga.title, isNull);
    expect(riga.characters, isEmpty);
    expect(riga.coverStyleTags, isEmpty);
    expect(riga.visualElementTags, isEmpty);
    expect(riga.recognizedPublisherLogo, isNull);
    expect(riga.recognizedSeriesLogo, isNull);
    expect(riga.completedAt, isNull);
  });

  test('completaAnalisiCopertina registra i campi grezzi e lo stato completata', () async {
    final scansioneId = await scansione();
    final analisiId = await repo.avviaAnalisiCopertina(scansioneId: scansioneId);

    await repo.completaAnalisiCopertina(
      id: analisiId,
      rawResponse: '{"authors":["Stan Lee"]}',
      title: 'Amazing Spider-Man',
      issueNumberLabel: '1',
      publisher: 'Marvel',
      seriesName: 'The Amazing Spider-Man',
      barcode: '123',
      price: r'$1',
      characters: const ['Spider-Man'],
      coverStyleTags: const ['stile realistico'],
      visualElementTags: const ['sfondo con esplosione'],
      recognizedPublisherLogo: 'Marvel',
    );

    final riga = await (db.select(
      db.analisiCopertinaTable,
    )..where((a) => a.id.equals(analisiId))).getSingle();
    expect(riga.status, StatoAnalisiCopertina.completata);
    expect(riga.title, 'Amazing Spider-Man');
    expect(riga.rawResponse, '{"authors":["Stan Lee"]}');
    expect(riga.characters, ['Spider-Man']);
    expect(riga.coverStyleTags, ['stile realistico']);
    expect(riga.visualElementTags, ['sfondo con esplosione']);
    expect(riga.recognizedPublisherLogo, 'Marvel');
    expect(riga.recognizedSeriesLogo, isNull);
    expect(riga.completedAt, isNotNull);
  });

  test(
    'completaAnalisiCopertina senza campi di computer vision lascia le liste vuote',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(scansioneId: scansioneId);

      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');

      final riga = await (db.select(
        db.analisiCopertinaTable,
      )..where((a) => a.id.equals(analisiId))).getSingle();
      expect(riga.characters, isEmpty);
      expect(riga.coverStyleTags, isEmpty);
      expect(riga.visualElementTags, isEmpty);
    },
  );

  test('fallisciAnalisiCopertina registra il motivo e lo stato fallita', () async {
    final scansioneId = await scansione();
    final analisiId = await repo.avviaAnalisiCopertina(scansioneId: scansioneId);

    await repo.fallisciAnalisiCopertina(id: analisiId, errorMessage: 'timeout');

    final riga = await (db.select(
      db.analisiCopertinaTable,
    )..where((a) => a.id.equals(analisiId))).getSingle();
    expect(riga.status, StatoAnalisiCopertina.fallita);
    expect(riga.errorMessage, 'timeout');
    expect(riga.completedAt, isNotNull);
    expect(riga.title, isNull);
  });
}
