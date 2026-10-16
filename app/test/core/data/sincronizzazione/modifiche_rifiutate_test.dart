import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/conversione_righe.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:path/path.dart' as p;

/// Le Modifiche rifiutate sul device (#225, #228), con un server finto.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftComicsRepository repo;
  late RegistroModifiche registro;
  late _Canale canale;
  late Directory cartella;
  late String versione;
  late Sincronizzatore sync;

  setUp(() async {
    db = AppDatabase.replica(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = DriftComicsRepository(db);
    registro = RegistroModifiche(db);
    canale = _Canale();
    cartella = await Directory.systemTemp.createTemp('rifiutate_');
    versione = '1.4.0+12';
    sync = Sincronizzatore(
      db: db,
      canale: canale,
      userId: 'u1',
      cartellaProfilo: () async => cartella,
      versioneApp: () async => versione,
    );
  });

  tearDown(() async {
    await db.close();
    await cartella.delete(recursive: true);
  });

  /// Rifiuta le operazioni su [tabella] (tutte, o solo per la riga [riga]).
  void rifiuta(String tabella, {String? riga}) =>
      canale.rifiuta = (op) =>
          op['tabella'] == tabella && (riga == null || op['riga'] == riga)
          ? (codice: '23514', messaggio: 'violates check constraint')
          : null;

  Future<({String opera, String edizione, String copia})> fumetto() async {
    final opera = await repo.aggiungiOpera(title: 'Dylan Dog');
    final edizione = await repo.aggiungiEdizione(
      operaId: opera,
      issueNumberLabel: '1',
    );
    final copia = await repo.aggiungiCopia(
      edizioneId: edizione,
      status: StatoCopia.posseduta,
    );
    return (opera: opera, edizione: edizione, copia: copia);
  }

  test('il push passa versione_app e la voce rifiutata resta nel registro, '
      'segnata, mentre le altre escono', () async {
    final f = await fumetto();
    rifiuta('copie');

    await sync.sincronizza();

    expect(canale.versioni, everyElement('1.4.0+12'));
    final voci = await registro.voci();
    expect(voci, hasLength(1));
    expect(voci.single.tabella, 'copie');
    expect(voci.single.riga, f.copia);
    expect(voci.single.rifiutataCodice, '23514');
    expect(voci.single.rifiutataMessaggio, 'violates check constraint');
    expect(voci.single.rifiutataVersione, '1.4.0+12');
    // Conta ancora fra le Modifiche in sospeso.
    expect(await registro.conteggio(), 1);
  });

  test('le voci successive della stessa riga restano trattenute, le altre '
      'righe partono', () async {
    final f = await fumetto();
    rifiuta('copie');
    await sync.sincronizza();
    canale.rifiuta = (_) => null;
    canale.inviate.clear();

    await repo.aggiornaCopia(id: f.copia, notes: 'firmata');
    await repo.aggiornaTitoloOpera(operaId: f.opera, title: 'Dylan Dog!');
    await sync.sincronizza();

    expect(canale.inviate.map((op) => op['tabella']), ['opere']);
    final voci = await registro.voci();
    expect(voci.map((v) => v.tabella), ['copie', 'copie']);
    expect(voci.last.rifiutataCodice, isNull);
  });

  test("con la stessa versione dell'app la rifiutata non si ritenta; con "
      'una nuova versione tornano nel push lei e le trattenute', () async {
    final f = await fumetto();
    rifiuta('copie');
    await sync.sincronizza();
    await repo.aggiornaCopia(id: f.copia, notes: 'firmata');
    canale.inviate.clear();

    await sync.sincronizza();
    expect(canale.inviate, isEmpty);

    versione = '1.5.0+13';
    canale.rifiuta = (_) => null;
    await sync.sincronizza();
    expect(canale.inviate.map((op) => op['tabella']), ['copie', 'copie']);
    expect(await registro.voci(), isEmpty);
  });

  test(
    "un nuovo rifiuto dopo l'aggiornamento aggiorna codice e versione",
    () async {
      await fumetto();
      rifiuta('copie');
      await sync.sincronizza();

      versione = '1.5.0+13';
      canale.rifiuta = (op) => op['tabella'] == 'copie'
          ? (codice: '22001', messaggio: 'value too long')
          : null;
      final esito = await sync.sincronizza();

      final voce = (await registro.voci()).single;
      expect(voce.rifiutataCodice, '22001');
      expect(voce.rifiutataVersione, '1.5.0+13');
      // Già nota: niente snackbar.
      expect(esito.rifiutate, isEmpty);
    },
  );

  test("l'esito porta i nuovi rifiuti, col titolo, una volta sola", () async {
    final f = await fumetto();
    rifiuta('copie');

    final primo = await sync.sincronizza();
    final secondo = await sync.sincronizza();

    expect(primo.rifiutate, hasLength(1));
    final rifiutata = primo.rifiutate.single;
    expect(rifiutata.riga, (tabella: 'copie', id: f.copia));
    expect(rifiutata.titolo, 'Dylan Dog 1');
    expect(rifiutata.descrizione, 'Copia aggiunta: Dylan Dog 1');
    expect(rifiutata.codice, '23514');
    expect(secondo.rifiutate, isEmpty);
  });

  test("un'eccezione resta transitoria: il registro non cambia", () async {
    await fumetto();
    canale.errore = const SocketException('offline');

    await expectLater(sync.sincronizza(), throwsA(isA<SocketException>()));

    final voci = await registro.voci();
    expect(voci, hasLength(3));
    expect(voci.every((v) => v.rifiutataCodice == null), isTrue);
  });

  test(
    'rifiutate() elenca le Modifiche rifiutate con i dettagli da copiare',
    () async {
      final f = await fumetto();
      rifiuta('copie');
      await sync.sincronizza();

      final elenco = await sync.rifiutate();

      expect(elenco, hasLength(1));
      expect(elenco.single.riga.id, f.copia);
      expect(elenco.single.dettagli, contains('23514'));
      expect(elenco.single.dettagli, contains('violates check constraint'));
      expect(elenco.single.dettagli, contains('copie'));
      expect(elenco.single.dettagli, contains(f.copia));
      expect(elenco.single.dettagli, contains('1.4.0+12'));
    },
  );

  test('watchRifiutate segue rifiuti, Riprova e Scarta', () async {
    await fumetto();
    rifiuta('copie');
    final stati = <int>[];
    final iscrizione = sync.watchRifiutate().listen(
      (r) => stati.add(r.length),
    );
    await pumpEventQueue();

    await sync.sincronizza();
    await pumpEventQueue();
    await sync.riprova((await sync.rifiutate()).single.voce);
    await pumpEventQueue();
    await iscrizione.cancel();

    expect(stati, [0, 1, 0]);
  });

  test('Riprova rimette la voce nel push successivo', () async {
    await fumetto();
    rifiuta('copie');
    await sync.sincronizza();
    canale.rifiuta = (_) => null;
    canale.inviate.clear();

    await sync.riprova((await sync.rifiutate()).single.voce);
    await sync.sincronizza();

    expect(canale.inviate.map((op) => op['tabella']), ['copie']);
    expect(await registro.voci(), isEmpty);
  });

  test('Scarta di una riga che il server ha: tutte le voci della riga '
      'escono e la riga torna come sul server', () async {
    final f = await fumetto();
    await sync.sincronizza();
    await repo.aggiornaTitoloOpera(operaId: f.opera, title: 'Dylan Dog?');
    rifiuta('opere');
    await sync.sincronizza();
    await repo.aggiornaTitoloOpera(operaId: f.opera, title: 'Dylan Dog!!');
    await repo.aggiornaCopia(id: f.copia, notes: 'firmata');
    canale.righe[(tabella: 'opere', id: f.opera)] = {
      'id': f.opera,
      'title': 'Dylan Dog',
      'created_at': '2026-10-15T10:00:00+00:00',
      'collection_id': 'c1',
      'created_by': 'u1',
      'hlc_campi': {'title': '1760000000000-0000-altro'},
    };

    await sync.scarta((tabella: 'opere', id: f.opera));

    final voci = await registro.voci();
    expect(voci.map((v) => v.tabella), ['copie']);
    final opera = await (db.select(
      db.opere,
    )..where((o) => o.id.equals(f.opera))).getSingle();
    expect(opera.title, 'Dylan Dog');
    // Lo scarto non genera Modifiche in sospeso.
    expect(await registro.conteggio(), 1);
  });

  test('Scarta di una riga che il server non ha: esce dalla Replica con i '
      'figli e le loro voci; un riferimento facoltativo si stacca', () async {
    final f = await fumetto();
    final altra = await repo.aggiungiOpera(title: 'Zagor');
    rifiuta('edizioni');
    await sync.sincronizza();

    await sync.scarta((tabella: 'edizioni', id: f.edizione));

    expect(await db.select(db.edizioni).get(), isEmpty);
    expect(await db.select(db.copie).get(), isEmpty);
    // L'Opera resta: è il padre, non un figlio.
    expect(
      (await db.select(db.opere).get()).map((o) => o.id),
      containsAll([f.opera, altra]),
    );
    expect(await registro.voci(), isEmpty);

    // Scarta di una Serie: l'Edizione resta, staccata.
    final serie2 = await repo.aggiungiSerie(name: 'Zagor');
    final edizione = await repo.aggiungiEdizione(
      operaId: altra,
      serieId: serie2,
      issueNumberLabel: '1',
    );
    await sync.scarta((tabella: 'serie', id: serie2));
    final riga = await (db.select(
      db.edizioni,
    )..where((e) => e.id.equals(edizione))).getSingle();
    expect(riga.serieId, isNull);
  });

  group('upload', () {
    File file(String percorso) => File(p.join(cartella.path, percorso))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    test('un file rifiutato da Storage esce dalla coda e il rifiuto si '
        'registra', () async {
      file('copertine/a.jpg');
      final opera = await repo.aggiungiOpera(title: 'Dylan Dog');
      await repo.aggiungiEdizione(
        operaId: opera,
        coverImage: 'copertine/a.jpg',
      );
      canale.erroreUpload = const FileRifiutato('413', 'Payload too large');

      await sync.sincronizza();

      expect(await db.select(db.codaFileTable).get(), isEmpty);
      expect(canale.rifiutiFile, [
        ('covers/c1/a.jpg', '413', 'Payload too large', '1.4.0+12'),
      ]);
      // Il push procede: la riga va al server.
      expect(await registro.voci(), isEmpty);
    });

    test('un errore transitorio lascia il file in coda', () async {
      file('copertine/a.jpg');
      final opera = await repo.aggiungiOpera(title: 'Dylan Dog');
      await repo.aggiungiEdizione(
        operaId: opera,
        coverImage: 'copertine/a.jpg',
      );
      canale.erroreUpload = const SocketException('offline');

      await expectLater(sync.sincronizza(), throwsA(isA<SocketException>()));

      expect(await db.select(db.codaFileTable).get(), hasLength(1));
      expect(canale.rifiutiFile, isEmpty);
    });
  });
}

class _Canale implements CanaleSincronizzazione {
  final inviate = <Map<String, Object?>>[];
  final versioni = <String>[];
  final righe = <RigaReplicata, Map<String, Object?>>{};
  final rifiutiFile = <(String, String, String, String)>[];
  ({String codice, String messaggio})? Function(Map<String, Object?> op)
  rifiuta = (_) => null;
  Exception? errore;
  Exception? erroreUpload;

  @override
  Future<String> collectionId() async => 'c1';

  @override
  Future<EsitoApplicaModifiche> applicaModifiche(
    List<Map<String, Object?>> ops, {
    required String versioneApp,
  }) async {
    if (errore case final e?) throw e;
    versioni.add(versioneApp);
    final rifiutate = <OperazioneRifiutata>[];
    for (final op in ops) {
      final r = rifiuta(op);
      if (r == null) {
        inviate.add(op);
      } else {
        rifiutate.add(
          (id: op['id']! as String, codice: r.codice, messaggio: r.messaggio),
        );
      }
    }
    return (eliminate: const <RigaReplicata>[], rifiutate: rifiutate);
  }

  @override
  Future<Map<String, Object?>?> riga(String tabella, String id) async =>
      righe[(tabella: tabella, id: id)];

  @override
  Future<void> registraRifiutoFile({
    required String file,
    required FileRifiutato rifiuto,
    required String versioneApp,
  }) async =>
      rifiutiFile.add((file, rifiuto.codice, rifiuto.messaggio, versioneApp));

  @override
  Future<PaginaCambiamenti> cambiamentiDa(
    String? cursore, {
    int limite = 1000,
  }) async => (cambiamenti: <Cambiamento>[], cursore: '7', altre: false);

  @override
  Future<void> caricaFile(
    BucketImmagine bucket,
    String chiave,
    File file,
  ) async {
    if (erroreUpload case final e?) throw e;
  }

  @override
  Future<Uint8List?> scaricaFile(BucketImmagine bucket, String chiave) async =>
      null;
}
