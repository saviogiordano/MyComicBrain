import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/supabase/importazione_modalita_locale.dart';
import 'package:mycomicbrain/core/data/supabase/uuid_v4.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Importazione della Modalità locale (ADR-0005, #173) contro lo stack
/// locale: `scripts/test-contratto-supabase.sh` imposta le variabili.
void main() {
  final url = Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final chiave = Platform.environment['SUPABASE_TEST_PUBLISHABLE_KEY'] ?? '';
  final configurato = url.isNotEmpty && chiave.isNotEmpty;

  late Directory base;
  final chiudere = <Future<void> Function()>[];

  Future<(SupabaseClient, String)> utente() async {
    final c = SupabaseClient(
      url,
      chiave,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    chiudere.add(c.dispose);
    final casuale = Random.secure().nextInt(1 << 32).toRadixString(36);
    final risposta = await c.auth.signUp(
      email: 'importa-$casuale@example.com',
      password: 'Importa-$casuale-pw1',
    );
    return (c, risposta.user!.id);
  }

  AppDatabase drift() {
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    chiudere.add(db.close);
    return db;
  }

  ImportazioneModalitaLocale importatore(
    AppDatabase db,
    SupabaseClient c,
    String userId,
  ) => ImportazioneModalitaLocale(
    db: db,
    client: c,
    userId: userId,
    baseDirectory: () async => base,
  );

  /// Un device in Modalità locale: due Copie (una nata da una Scansione già
  /// risolta), una cover locale (percorso relativo) e una Scansione da
  /// completare con la sua Analisi.
  Future<void> popola(AppDatabase db) async {
    final adesso = DateTime.utc(2026, 1, 2, 10);
    Directory(p.join(base.path, 'copertine')).createSync(recursive: true);
    File(p.join(base.path, 'copertine', 'dd1.jpg')).writeAsBytesSync([1, 2]);
    Directory(p.join(base.path, 'scansioni')).createSync(recursive: true);
    final immagineScansione = p.join(base.path, 'scansioni', 'aperta.jpg');
    File(immagineScansione).writeAsBytesSync([3, 4]);

    final opera = await db
        .into(db.opere)
        .insertReturning(
          OpereCompanion.insert(title: 'Dylan Dog', createdAt: adesso),
        )
        .then((r) => r.id);
    final edizione = await db
        .into(db.edizioni)
        .insertReturning(
          EdizioniCompanion.insert(
            operaId: opera,
            issueNumberLabel: const Value('1'),
            coverImage: const Value('copertine/dd1.jpg'),
            createdAt: adesso,
          ),
        )
        .then((r) => r.id);
    final risolta = await db
        .into(db.scansioni)
        .insertReturning(
          ScansioniCompanion.insert(
            image: p.join(base.path, 'scansioni', 'risolta.jpg'),
            createdAt: adesso,
          ),
        )
        .then((r) => r.id);
    for (final scansione in [risolta, null]) {
      await db
          .into(db.copie)
          .insert(
            CopieCompanion.insert(
              edizioneId: edizione,
              status: StatoCopia.posseduta,
              createdAt: adesso,
              updatedAt: adesso,
              scansioneId: Value(scansione),
            ),
          );
    }
    final aperta = await db
        .into(db.scansioni)
        .insertReturning(
          ScansioniCompanion.insert(
            image: immagineScansione,
            createdAt: adesso,
          ),
        )
        .then((r) => r.id);
    await db
        .into(db.analisiCopertinaTable)
        .insert(
          AnalisiCopertinaTableCompanion.insert(
            scansioneId: aperta,
            title: const Value('Martin Mystère'),
            characters: const Value(['Martin', 'Java']),
            status: const Value(StatoAnalisiCopertina.completata),
            createdAt: adesso,
          ),
        );
  }

  // Ogni test apre più database drift in memoria: è voluto.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('importazione_');
  });

  tearDown(() async {
    for (final chiudi in chiudere.reversed) {
      await chiudi();
    }
    chiudere.clear();
    if (base.existsSync()) await base.delete(recursive: true);
  });

  group('su Supabase locale', () {
    test('il riepilogo conta Copie, Scansioni da completare e i fumetti '
        "già nell'account", () async {
      final (c, userId) = await utente();
      final db = drift();
      await popola(db);

      final riepilogo = await importatore(db, c, userId).riepilogo();

      expect(riepilogo.fumetti, 2);
      expect(riepilogo.scansioniDaCompletare, 1);
      expect(riepilogo.fumettiNellAccount, 0);
    });

    test("importa catalogo, Scansione aperta e immagini nell'account, poi "
        'svuota drift e i file locali', () async {
      final (c, userId) = await utente();
      final db = drift();
      await popola(db);
      final avanzamenti = <AvanzamentoImportazione>[];

      final esito =
          await importatore(
            db,
            c,
            userId,
          ).importa(
            uuidV4(),
            avanzamento: avanzamenti.add,
          );

      expect(esito.fumettiNellAccount, 2);
      final edizione = await c
          .from('edizioni')
          .select('cover_image, collection_id, copie(scansione_id)')
          .single();
      final coverImage = edizione['cover_image'] as String;
      expect(coverImage, startsWith('${edizione['collection_id']}/'));
      expect(await c.storage.from('covers').download(coverImage), [1, 2]);
      expect(
        (edizione['copie'] as List).map((c) => (c as Map)['scansione_id']),
        [null, null],
      );

      final scansione = await c
          .from('scansioni')
          .select('image, analisi_copertina(title, characters)')
          .single();
      final immagine = scansione['image'] as String;
      expect(immagine, startsWith('$userId/'));
      expect(await c.storage.from('scansioni').download(immagine), [3, 4]);
      expect(scansione['analisi_copertina'], [
        {
          'title': 'Martin Mystère',
          'characters': ['Martin', 'Java'],
        },
      ]);

      expect(await db.opere.count().getSingle(), 0);
      expect(await db.scansioni.count().getSingle(), 0);
      expect(Directory(p.join(base.path, 'copertine')).existsSync(), isFalse);
      expect(avanzamenti.last.frazione, 1);
      expect(
        avanzamenti.map((a) => a.fase).toSet(),
        FaseImportazione.values.toSet(),
      );
    });

    test('un nuovo tentativo con lo stesso id dopo una risposta persa non '
        'duplica nulla', () async {
      final (c, userId) = await utente();
      final importId = uuidV4();
      final primo = drift();
      await popola(primo);
      await importatore(primo, c, userId).importa(importId);

      // Il device non ha visto la risposta: drift ha ancora gli stessi dati.
      final secondo = drift();
      await popola(secondo);
      final esito = await importatore(secondo, c, userId).importa(importId);

      expect(esito.fumettiNellAccount, 2);
      expect(await c.from('copie').count(), 2);
      expect(await secondo.copie.count().getSingle(), 0);
    });

    test('un account già popolato riceve i fumetti del device in più, senza '
        'deduplica', () async {
      final (c, userId) = await utente();
      final primo = drift();
      await popola(primo);
      await importatore(
        primo,
        c,
        userId,
      ).importa(uuidV4());

      final altroDevice = drift();
      await popola(altroDevice);
      final importa = importatore(altroDevice, c, userId);
      expect((await importa.riepilogo()).fumettiNellAccount, 2);
      final esito = await importa.importa(
        uuidV4(),
      );

      expect(esito.fumettiNellAccount, 4);
    });
  }, skip: configurato ? false : 'stack Supabase locale non configurato');
}
