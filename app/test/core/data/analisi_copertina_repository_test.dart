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
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> scansione() => repo.aggiungiScansione(image: '/scansioni/1.jpg');

  test(
    "idScansionePerImmagine trova l'id dalla Scansione persistita",
    () async {
      final id = await scansione();

      expect(await repo.idScansionePerImmagine('/scansioni/1.jpg'), id);
    },
  );

  test(
    'eliminaScansione rimuove solo la riga indicata (swipe-to-delete nel riepilogo, #59)',
    () async {
      final id = await scansione();
      final altroId = await repo.aggiungiScansione(image: '/scansioni/2.jpg');

      await repo.eliminaScansione(id: id);

      final righe = await db.select(db.scansioni).get();
      expect(righe.map((r) => r.id), [altroId]);
    },
  );

  test('avviaAnalisiCopertina crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final analisiId = await repo.avviaAnalisiCopertina(
      scansioneId: scansioneId,
    );

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

  test(
    'completaAnalisiCopertina registra i campi grezzi e lo stato completata',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

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
        printingType: 'Direct Edition',
        classificazione: 'Rated T+',
        description: 'Peter Parker affronta Venom in un confronto decisivo.',
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
      expect(riga.printingType, 'Direct Edition');
      expect(riga.classificazione, 'Rated T+');
      expect(riga.description, 'Peter Parker affronta Venom in un confronto decisivo.');
      expect(riga.completedAt, isNotNull);
    },
  );

  test(
    'completaAnalisiCopertina senza campi di computer vision lascia le liste vuote',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');

      final riga = await (db.select(
        db.analisiCopertinaTable,
      )..where((a) => a.id.equals(analisiId))).getSingle();
      expect(riga.characters, isEmpty);
      expect(riga.coverStyleTags, isEmpty);
      expect(riga.visualElementTags, isEmpty);
      expect(riga.printingType, isNull);
      expect(riga.classificazione, isNull);
      expect(riga.description, isNull);
    },
  );

  test(
    'fallisciAnalisiCopertina registra il motivo e lo stato fallita',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

      await repo.fallisciAnalisiCopertina(
        id: analisiId,
        errorMessage: 'timeout',
      );

      final riga = await (db.select(
        db.analisiCopertinaTable,
      )..where((a) => a.id.equals(analisiId))).getSingle();
      expect(riga.status, StatoAnalisiCopertina.fallita);
      expect(riga.errorMessage, 'timeout');
      expect(riga.completedAt, isNotNull);
      expect(riga.title, isNull);
    },
  );

  group('watchStatoAnalisiCopertina', () {
    test('pending finché la pipeline non ha ancora creato la riga', () async {
      await scansione();

      final stato = await repo
          .watchStatoAnalisiCopertina('/scansioni/1.jpg')
          .first;

      expect(stato.stato, StatoAnalisiCopertina.pending);
      expect(stato.errorMessage, isNull);
    });

    test('inCorso mentre la pipeline chiama il provider AI', () async {
      final scansioneId = await scansione();
      await repo.avviaAnalisiCopertina(scansioneId: scansioneId);

      final stato = await repo
          .watchStatoAnalisiCopertina('/scansioni/1.jpg')
          .first;

      expect(stato.stato, StatoAnalisiCopertina.inCorso);
    });

    test('completata dopo completaAnalisiCopertina', () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');

      final stato = await repo
          .watchStatoAnalisiCopertina('/scansioni/1.jpg')
          .first;

      expect(stato.stato, StatoAnalisiCopertina.completata);
    });

    test('fallita con errorMessage dopo fallisciAnalisiCopertina', () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repo.fallisciAnalisiCopertina(
        id: analisiId,
        errorMessage: 'timeout',
      );

      final stato = await repo
          .watchStatoAnalisiCopertina('/scansioni/1.jpg')
          .first;

      expect(stato.stato, StatoAnalisiCopertina.fallita);
      expect(stato.errorMessage, 'timeout');
    });

    test('emette un nuovo valore quando lo stato cambia', () async {
      final scansioneId = await scansione();
      final valori = <StatoAnalisiCopertina>[];
      final sub = repo
          .watchStatoAnalisiCopertina('/scansioni/1.jpg')
          .listen((s) => valori.add(s.stato));

      await pumpEventQueue();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await pumpEventQueue();
      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');
      await pumpEventQueue();
      await sub.cancel();

      expect(valori, [
        StatoAnalisiCopertina.pending,
        StatoAnalisiCopertina.inCorso,
        StatoAnalisiCopertina.completata,
      ]);
    });
  });
}
