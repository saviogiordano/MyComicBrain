import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/scansione.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  test(
    'una Scansione inserita senza recognitionStatus esplicito parte "in sospeso"',
    () async {
      final id = await db
          .into(db.scansioni)
          .insert(
            ScansioniCompanion.insert(
              image: '/scansioni/123.jpg',
              createdAt: DateTime.now(),
            ),
          );

      final scansione = await (db.select(
        db.scansioni,
      )..where((s) => s.id.equals(id))).getSingle();

      expect(scansione.recognitionStatus, StatoRiconoscimento.inSospeso);
      expect(scansione.userId, isNull);
      expect(scansione.ocrText, isNull);
      expect(scansione.confidence, isNull);
    },
  );
}
