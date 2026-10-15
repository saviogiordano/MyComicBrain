import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';

import 'generated/schema.dart';

/// Migrazione 18 → 19 (ADR-0008, #209): la coda dei file. Una Replica già
/// sincronizzata mette in coda i file creati prima della coda.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const righe = '''
    insert into opere (id, title, created_at) values
      ('o1', 'Dylan Dog', '2026-10-01T10:00:00.000');
    insert into serie (id, name, cover_image) values
      ('s1', 'Dylan Dog', 'copertine/s.jpg');
    insert into edizioni (id, opera_id, cover_image, created_at) values
      ('e1', 'o1', 'copertine/a.jpg', '2026-10-01T10:00:00.000'),
      ('e2', 'o1', 'https://comicvine.example/b.jpg', '2026-10-01T10:00:00.000'),
      ('e3', 'o1', 'scansioni/c.jpg', '2026-10-01T10:00:00.000'),
      ('e4', 'o1', 'copertine/a.jpg', '2026-10-01T10:00:00.000');
    insert into scansioni (id, image, created_at) values
      ('x1', 'scansioni/c.jpg', '2026-10-01T10:00:00.000');
  ''';

  Future<List<(String, String)>> coda(AppDatabase db) async => [
    for (final f in await (db.select(
      db.codaFileTable,
    )..orderBy([(f) => OrderingTerm.asc(f.percorso)])).get())
      (f.bucket, f.percorso),
  ];

  test('una Replica già sincronizzata mette in coda i suoi file', () async {
    final schema = await verifier.schemaAt(18);
    schema.rawDatabase.execute('''
      $righe
      insert into stato_sincronizzazione (id, cursore, ultima)
        values (1, '7', '2026-10-01T10:00:00.000');
    ''');
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 19);

    expect(await coda(db), [
      ('covers', 'copertine/a.jpg'),
      ('covers', 'copertine/s.jpg'),
      ('covers', 'scansioni/c.jpg'),
      ('scansioni', 'scansioni/c.jpg'),
    ]);
  });

  test('la Modalità locale resta con la coda vuota', () async {
    final schema = await verifier.schemaAt(18);
    schema.rawDatabase.execute(righe);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 19);

    expect(await coda(db), isEmpty);
  });
}
