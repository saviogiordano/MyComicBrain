import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/analisi_ocr.dart';

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

  test('avviaAnalisiOcr crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final analisiId = await repo.avviaAnalisiOcr(scansioneId: scansioneId);

    final riga = await (db.select(
      db.analisiOcrTable,
    )..where((a) => a.id.equals(analisiId))).getSingle();
    expect(riga.scansioneId, scansioneId);
    expect(riga.status, StatoAnalisiOcr.inCorso);
    expect(riga.title, isNull);
    expect(riga.completedAt, isNull);
  });

  test('completaAnalisiOcr registra i campi grezzi e lo stato completata', () async {
    final scansioneId = await scansione();
    final analisiId = await repo.avviaAnalisiOcr(scansioneId: scansioneId);

    await repo.completaAnalisiOcr(
      id: analisiId,
      rawResponse: '{"authors":["Stan Lee"]}',
      title: 'Amazing Spider-Man',
      issueNumberLabel: '1',
      publisher: 'Marvel',
      seriesName: 'The Amazing Spider-Man',
      barcode: '123',
      price: r'$1',
    );

    final riga = await (db.select(
      db.analisiOcrTable,
    )..where((a) => a.id.equals(analisiId))).getSingle();
    expect(riga.status, StatoAnalisiOcr.completata);
    expect(riga.title, 'Amazing Spider-Man');
    expect(riga.rawResponse, '{"authors":["Stan Lee"]}');
    expect(riga.completedAt, isNotNull);
  });

  test('fallisciAnalisiOcr registra il motivo e lo stato fallita', () async {
    final scansioneId = await scansione();
    final analisiId = await repo.avviaAnalisiOcr(scansioneId: scansioneId);

    await repo.fallisciAnalisiOcr(id: analisiId, errorMessage: 'timeout');

    final riga = await (db.select(
      db.analisiOcrTable,
    )..where((a) => a.id.equals(analisiId))).getSingle();
    expect(riga.status, StatoAnalisiOcr.fallita);
    expect(riga.errorMessage, 'timeout');
    expect(riga.completedAt, isNotNull);
    expect(riga.title, isNull);
  });
}
