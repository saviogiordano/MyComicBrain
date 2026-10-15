import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/conversione_righe.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:path/path.dart' as p;

/// I file della Replica su Storage (ADR-0008, #209): la coda degli upload
/// svuotata prima del push e il download delle cover dopo il pull.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory cartella;
  late _Canale canale;

  setUp(() async {
    cartella = await Directory.systemTemp.createTemp('file_replica_');
    canale = _Canale();
  });

  tearDown(() => cartella.delete(recursive: true));

  AppDatabase memoria({bool replica = true}) {
    final connessione = DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    );
    return replica
        ? AppDatabase.replica(connessione)
        : AppDatabase(connessione);
  }

  Sincronizzatore sincronizzatore(AppDatabase db) => Sincronizzatore(
    db: db,
    canale: canale,
    userId: 'u1',
    cartellaProfilo: () async => cartella,
  );

  File file(String percorso, [List<int> bytes = const [1, 2, 3]]) =>
      File(p.join(cartella.path, percorso))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  Future<List<(String, String)>> coda(AppDatabase db) async => [
    for (final f in await (db.select(
      db.codaFileTable,
    )..orderBy([(f) => OrderingTerm.asc(f.percorso)])).get())
      (f.bucket, f.percorso),
  ];

  group('coda', () {
    late AppDatabase db;
    late DriftComicsRepository repo;

    setUp(() {
      db = memoria();
      repo = DriftComicsRepository(db);
    });

    tearDown(() => db.close());

    test('le scritture sul device mettono in coda i file delle colonne '
        'immagine, non gli URL', () async {
      final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: 'copertine/a.jpg',
      );
      await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: 'https://comicvine.example/b.jpg',
      );
      await repo.aggiungiScansione(image: 'scansioni/s.jpg');
      await (db.update(db.edizioni)..where((e) => e.id.equals(edizioneId)))
          .write(const EdizioniCompanion(coverImage: Value('copertine/c.jpg')));

      expect(await coda(db), [
        ('covers', 'copertine/a.jpg'),
        ('covers', 'copertine/c.jpg'),
        ('scansioni', 'scansioni/s.jpg'),
      ]);
    });

    test('ciò che arriva dal server non va in coda', () async {
      final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
      await RegistroModifiche(db).senzaRegistro(
        () => repo.aggiungiEdizione(
          operaId: operaId,
          coverImage: 'copertine/a.jpg',
        ),
      );
      expect(await coda(db), isEmpty);
    });

    test('la Modalità locale non ha la coda', () async {
      final locale = memoria(replica: false);
      addTearDown(locale.close);
      final repoLocale = DriftComicsRepository(locale);
      await repoLocale.aggiungiEdizione(
        operaId: await repoLocale.aggiungiOpera(title: 'Tex'),
        coverImage: 'copertine/a.jpg',
      );
      expect(await coda(locale), isEmpty);
    });

    test('il push carica i file in coda prima delle operazioni che li '
        'usano', () async {
      file('copertine/a.jpg', [7]);
      file('scansioni/s.jpg', [8]);
      final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
      await repo.aggiungiEdizione(
        operaId: operaId,
        // Una cover presa da una Scansione: sta in scansioni/, va in covers.
        coverImage: 'scansioni/s.jpg',
      );
      await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: 'copertine/a.jpg',
      );
      await repo.aggiungiScansione(image: 'scansioni/s.jpg');

      await sincronizzatore(db).sincronizza();

      expect(canale.eventi, [
        'carica covers c1/s.jpg [8]',
        'carica covers c1/a.jpg [7]',
        'carica scansioni u1/s.jpg [8]',
        'applica',
        'pull',
      ]);
      expect(await coda(db), isEmpty);
      expect(await RegistroModifiche(db).voci(), isEmpty);
    });

    test('un file che non è più sul device esce dalla coda senza '
        'upload', () async {
      await repo.aggiungiEdizione(
        operaId: await repo.aggiungiOpera(title: 'Tex'),
        coverImage: 'copertine/sparita.jpg',
      );

      await sincronizzatore(db).sincronizza();

      expect(canale.eventi, ['applica', 'pull']);
      expect(await coda(db), isEmpty);
    });

    test('se un upload fallisce non parte il push e la coda resta', () async {
      file('copertine/a.jpg');
      file('copertine/b.jpg');
      final operaId = await repo.aggiungiOpera(title: 'Tex');
      await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: 'copertine/a.jpg',
      );
      await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: 'copertine/b.jpg',
      );
      canale.uploadFallisce = 'c1/b.jpg';

      await expectLater(
        sincronizzatore(db).sincronizza(),
        throwsA(isA<SocketException>()),
      );

      expect(canale.eventi, ['carica covers c1/a.jpg [1, 2, 3]']);
      expect(await coda(db), [('covers', 'copertine/b.jpg')]);
      expect(await RegistroModifiche(db).voci(), hasLength(3));
    });
  });

  test('la coda sopravvive alla chiusura della Replica', () async {
    file('copertine/a.jpg');
    final percorsoDb = p.join(cartella.path, 'replica.sqlite');
    final primo = AppDatabase.replica(NativeDatabase(File(percorsoDb)));
    final repo = DriftComicsRepository(primo);
    await repo.aggiungiEdizione(
      operaId: await repo.aggiungiOpera(title: 'Tex'),
      coverImage: 'copertine/a.jpg',
    );
    await primo.close();

    final riaperto = AppDatabase.replica(NativeDatabase(File(percorsoDb)));
    addTearDown(riaperto.close);
    expect(await coda(riaperto), [('covers', 'copertine/a.jpg')]);

    await sincronizzatore(riaperto).sincronizza();
    expect(canale.eventi.first, 'carica covers c1/a.jpg [1, 2, 3]');
    expect(await coda(riaperto), isEmpty);
  });

  group('download delle cover', () {
    late AppDatabase db;
    late DriftComicsRepository repo;
    late String operaId;

    setUp(() async {
      db = memoria();
      repo = DriftComicsRepository(db);
      operaId = await RegistroModifiche(
        db,
      ).senzaRegistro(() => repo.aggiungiOpera(title: 'Dylan Dog'));
    });

    tearDown(() => db.close());

    Cambiamento edizione(String id, String? cover) => (
      tabella: 'edizioni',
      id: id,
      riga: {
        'id': id,
        'opera_id': operaId,
        'cover_image': cover,
        'created_at': '2026-10-15T10:00:00+00:00',
        'hlc_campi': <String, Object?>{},
      },
    );

    test('scarica le cover arrivate col pull che mancano sul device, con '
        "l'avanzamento", () async {
      file('copertine/c.jpg');
      canale
        ..pagine.add([
          edizione('e1', 'c1/a.jpg'),
          edizione('e2', 'c1/b.jpg'),
          edizione('e3', 'c1/c.jpg'),
          edizione('e4', 'https://comicvine.example/d.jpg'),
          edizione('e5', null),
        ])
        ..suStorage['covers/c1/a.jpg'] = [4]
        ..suStorage['covers/c1/b.jpg'] = [5];
      final sync = sincronizzatore(db);
      await sync.sincronizza();

      final avanzamento = <(int, int)>[];
      await sync.scaricaCover(avanzamento: (n, m) => avanzamento.add((n, m)));

      expect(avanzamento, [(0, 2), (1, 2), (2, 2)]);
      expect(File(p.join(cartella.path, 'copertine/a.jpg')).readAsBytesSync(), [
        4,
      ]);
      expect(File(p.join(cartella.path, 'copertine/b.jpg')).readAsBytesSync(), [
        5,
      ]);
      expect(
        cartella
            .listSync(recursive: true)
            .where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );

      // Già tutte sul device: niente da fare.
      avanzamento.clear();
      await sync.scaricaCover(avanzamento: (n, m) => avanzamento.add((n, m)));
      expect(avanzamento, isEmpty);
    });

    test('una cover che Storage non ha non si richiede di nuovo', () async {
      canale.pagine.add([edizione('e1', 'c1/manca.jpg')]);
      final sync = sincronizzatore(db);
      await sync.sincronizza();

      await sync.scaricaCover();
      await sync.scaricaCover();

      expect(
        canale.eventi.where((e) => e.startsWith('scarica')),
        ['scarica covers c1/manca.jpg'],
      );
      expect(
        File(p.join(cartella.path, 'copertine/manca.jpg')).existsSync(),
        isFalse,
      );
    });

    test('le query sulle Edizioni si rileggono quando arrivano le '
        'cover', () async {
      canale
        ..pagine.add([edizione('e1', 'c1/a.jpg')])
        ..suStorage['covers/c1/a.jpg'] = [4];
      final sync = sincronizzatore(db);
      await sync.sincronizza();

      final emissioni = <void>[];
      final iscrizione = db.select(db.edizioni).watch().listen(emissioni.add);
      addTearDown(iscrizione.cancel);
      await pumpEventQueue();
      final prima = emissioni.length;

      await sync.scaricaCover();
      await pumpEventQueue();

      expect(emissioni.length, greaterThan(prima));
    });

    test('si ferma quando viene interrotto', () async {
      canale.pagine.add([
        for (var i = 0; i < 6; i++) edizione('e$i', 'c1/$i.jpg'),
      ]);
      for (var i = 0; i < 6; i++) {
        canale.suStorage['covers/c1/$i.jpg'] = [i];
      }
      final sync = sincronizzatore(db);
      await sync.sincronizza();

      var interrotto = false;
      await sync.scaricaCover(
        avanzamento: (n, _) => interrotto = n >= 1,
        interrompi: () => interrotto,
      );

      // I primi quattro partono insieme, poi si ferma.
      expect(canale.eventi.where((e) => e.startsWith('scarica')), hasLength(4));
    });
  });
}

class _Canale implements CanaleSincronizzazione {
  final pagine = <List<Cambiamento>>[];
  final eventi = <String>[];
  final suStorage = <String, List<int>>{};
  String? uploadFallisce;

  @override
  Future<String> collectionId() async => 'c1';

  @override
  Future<List<RigaReplicata>> applicaModifiche(
    List<Map<String, Object?>> ops,
  ) async {
    eventi.add('applica');
    return const [];
  }

  @override
  Future<PaginaCambiamenti> cambiamentiDa(
    String? cursore, {
    int limite = 1000,
  }) async {
    eventi.add('pull');
    final pagina = pagine.isEmpty ? <Cambiamento>[] : pagine.removeAt(0);
    return (cambiamenti: pagina, cursore: '7', altre: pagine.isNotEmpty);
  }

  @override
  Future<void> caricaFile(
    BucketImmagine bucket,
    String chiave,
    File file,
  ) async {
    if (chiave == uploadFallisce) throw const SocketException('offline');
    final bytes = await file.readAsBytes();
    eventi.add('carica ${bucket.name} $chiave $bytes');
    suStorage['${bucket.name}/$chiave'] = bytes;
  }

  @override
  Future<Uint8List?> scaricaFile(BucketImmagine bucket, String chiave) async {
    eventi.add('scarica ${bucket.name} $chiave');
    final bytes = suStorage['${bucket.name}/$chiave'];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }
}
