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

/// Il pull applicato alla Replica (ADR-0008), con un server finto: ciò che
/// il test di convergenza su Supabase non riesce a mettere in fila.
void main() {
  late AppDatabase db;
  late DriftComicsRepository repo;
  late _Canale canale;
  late Sincronizzatore sync;

  setUp(() {
    db = AppDatabase.replica(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = DriftComicsRepository(db);
    canale = _Canale();
    sync = Sincronizzatore(
      db: db,
      canale: canale,
      userId: 'u1',
      // I file non ci sono: escono dalla coda senza upload.
      cartellaProfilo: () async => Directory.systemTemp,
    );
  });

  tearDown(() => db.close());

  Map<String, Object?> edizione(String id, String operaId, {String? cover}) => {
    'id': id,
    'opera_id': operaId,
    'issue_number_label': '2',
    'cover_image': cover,
    'created_at': '2026-10-15T10:00:00+00:00',
    'collection_id': 'c1',
    'created_by': 'u1',
    'hlc_campi': {'issue_number_label': '1760000000000-0000-altro'},
  };

  test('il pull non sovrascrive i campi con Modifiche in sospeso', () async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      issueNumberLabel: '1',
      publisher: 'Bonelli',
    );
    // Il push porta via tutto; poi, prima del pull, una nuova modifica.
    canale.dopoIlPush = () => repo.aggiornaEdizione(
      id: edizioneId,
      issueNumberLabel: '1',
      publisher: 'Sergio Bonelli',
    );
    canale.pagine.add([
      (
        tabella: 'edizioni',
        id: edizioneId,
        riga: {
          ...edizione(edizioneId, operaId),
          'publisher': 'Bonelli Editore',
        },
      ),
    ]);

    await sync.sincronizza();

    final riga = await (db.select(
      db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingle();
    expect(riga.publisher, 'Sergio Bonelli', reason: 'in sospeso');
    expect(riga.issueNumberLabel, '2', reason: 'arrivato dal server');
    expect(
      (await RegistroModifiche(db).voci()).single.valori,
      contains('Sergio Bonelli'),
    );
    expect(
      (await RegistroModifiche(db).dispositivo()).isNotEmpty,
      isTrue,
    );
  });

  test(
    'una cover che sul server ha la chiave dello stesso file resta il '
    'percorso locale',
    () async {
      final operaId = await repo.aggiungiOpera(title: 'Tex');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: 'scansioni/42.jpg',
      );
      canale.pagine.add([
        (
          tabella: 'edizioni',
          id: edizioneId,
          riga: edizione(edizioneId, operaId, cover: 'c1/42.jpg'),
        ),
        (
          tabella: 'edizioni',
          id: 'altra',
          riga: edizione('altra', operaId, cover: 'c1/77.jpg'),
        ),
      ]);

      await sync.sincronizza();

      Future<String?> cover(String id) async => (await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(id))).getSingle()).coverImage;
      expect(await cover(edizioneId), 'scansioni/42.jpg');
      expect(await cover('altra'), 'copertine/77.jpg');
      expect(
        canale.inviate.firstWhere(
          (op) => op['tabella'] == 'edizioni',
        )['valori'],
        containsPair('cover_image', 'c1/42.jpg'),
      );
    },
  );

  test("l'orologio passa oltre i timestamp arrivati", () async {
    final operaId = await repo.aggiungiOpera(title: 'Zagor');
    canale.pagine.add([
      (
        tabella: 'edizioni',
        id: 'e9',
        riga: {
          ...edizione('e9', operaId),
          'hlc_campi': {'issue_number_label': '9999999999999-0000-altro'},
        },
      ),
    ]);
    await sync.sincronizza();
    await repo.aggiornaTitoloOpera(operaId: operaId, title: 'Zagor!');
    expect(
      (await RegistroModifiche(db).voci()).single.hlc,
      startsWith('9999999999999-0001-'),
    );
  });
}

class _Canale implements CanaleSincronizzazione {
  final pagine = <List<Cambiamento>>[];
  final inviate = <Map<String, Object?>>[];
  Future<void> Function()? dopoIlPush;

  @override
  Future<String> collectionId() async => 'c1';

  @override
  Future<List<RigaReplicata>> applicaModifiche(
    List<Map<String, Object?>> ops,
  ) async {
    inviate.addAll(ops);
    return const [];
  }

  @override
  Future<PaginaCambiamenti> cambiamentiDa(
    String? cursore, {
    int limite = 1000,
  }) async {
    await dopoIlPush?.call();
    dopoIlPush = null;
    final pagina = pagine.isEmpty ? <Cambiamento>[] : pagine.removeAt(0);
    return (cambiamenti: pagina, cursore: '7', altre: pagine.isNotEmpty);
  }

  @override
  Future<void> caricaFile(
    BucketImmagine bucket,
    String chiave,
    File file,
  ) async {}

  @override
  Future<Uint8List?> scaricaFile(BucketImmagine bucket, String chiave) async =>
      null;
}
