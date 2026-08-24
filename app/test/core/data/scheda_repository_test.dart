import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';

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

  Future<int> opera({String title = 'The Amazing Spider-Man'}) =>
      repo.aggiungiOpera(title: title);

  Future<int> edizione({int? operaId, int? serieId}) async {
    return repo.aggiungiEdizione(
      operaId: operaId ?? await opera(),
      serieId: serieId,
      issueNumberLabel: '1',
    );
  }

  test('watchEdizione ritorna null per un\'Edizione inesistente', () async {
    expect(await repo.watchEdizione(999).first, isNull);
  });

  test('watchEdizione risolve titolo (Opera), Copie e Autori', () async {
    final operaId = await opera(title: 'Batman');
    final serieId = await repo.aggiungiSerie(name: 'Batman (2016)');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: 'Panini Comics',
    );
    await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
    );
    final creatorId = await repo.aggiungiCreator('Grant Morrison');
    await repo.collegaCreatorAEdizione(
      edizioneId: edizioneId,
      creatorId: creatorId,
      ruolo: RuoloCreator.sceneggiatore,
    );

    final dettaglio = await repo.watchEdizione(edizioneId).first;

    expect(dettaglio, isNotNull);
    expect(dettaglio!.titolo, 'Batman');
    expect(dettaglio.serieName, 'Batman (2016)');
    expect(dettaglio.publisher, 'Panini Comics');
    expect(dettaglio.copie, hasLength(1));
    expect(dettaglio.autori, hasLength(1));
    expect(dettaglio.autori.single.name, 'Grant Morrison');
  });

  test(
    'watchEdizione con più Copie e più Autori non li mischia (prodotto cartesiano raggruppato correttamente)',
    () async {
      final edizioneId = await edizione();
      final copia1 = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      final copia2 = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.venduta,
      );
      final autore1 = await repo.aggiungiCreator('Dan Slott');
      final autore2 = await repo.aggiungiCreator('Humberto Ramos');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: autore1,
        ruolo: RuoloCreator.sceneggiatore,
      );
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: autore2,
        ruolo: RuoloCreator.disegnatore,
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;

      expect(
        dettaglio!.copie.map((c) => c.id),
        unorderedEquals([copia1, copia2]),
      );
      expect(
        dettaglio.autori.map((a) => a.creatorId),
        unorderedEquals([autore1, autore2]),
      );
    },
  );

  test(
    'CopiaDettaglio.haDatiPersonali è false quando nessun campo §8.2 è valorizzato',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;
      expect(dettaglio!.copie.single.haDatiPersonali, isFalse);
    },
  );

  test(
    'CopiaDettaglio.haDatiPersonali è true se anche un solo campo §8.2 è valorizzato',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        notes: 'prima ristampa',
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;
      expect(dettaglio!.copie.single.haDatiPersonali, isTrue);
    },
  );

  test(
    'aggiornaTitoloOpera aggiorna il titolo sulla Opera, non sulla Edizione',
    () async {
      final operaId = await opera(title: 'Vecchio titolo');
      await repo.aggiornaTitoloOpera(operaId: operaId, title: 'Nuovo titolo');

      final riga = await (db.select(
        db.opere,
      )..where((o) => o.id.equals(operaId))).getSingle();
      expect(riga.title, 'Nuovo titolo');
    },
  );

  test('aggiornaEdizione aggiorna i campi bibliografici §8.1', () async {
    final edizioneId = await edizione();

    await repo.aggiornaEdizione(
      id: edizioneId,
      publisher: 'Marvel Italia',
      issueNumber: 67,
      issueNumberLabel: '67',
      volume: 'Vol. 3',
      description: 'Descrizione aggiornata',
    );

    final riga = await (db.select(
      db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingle();
    expect(riga.publisher, 'Marvel Italia');
    expect(riga.issueNumber, 67);
    expect(riga.volume, 'Vol. 3');
    expect(riga.description, 'Descrizione aggiornata');
  });

  test('aggiornaCopia aggiorna i campi §8.2 senza toccare lo stato', () async {
    final edizioneId = await edizione();
    final copiaId = await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      readingStatus: StatoLettura.letto,
    );

    await repo.aggiornaCopia(
      id: copiaId,
      condition: CondizioneCopia.veryFine,
      purchasePrice: 3.5,
      seller: 'Fumetteria Century',
      notes: 'Prima ristampa italiana.',
    );

    final riga = await (db.select(
      db.copie,
    )..where((c) => c.id.equals(copiaId))).getSingle();
    expect(riga.condition, CondizioneCopia.veryFine);
    expect(riga.purchasePrice, 3.5);
    expect(riga.seller, 'Fumetteria Century');
    expect(riga.status, StatoCopia.posseduta, reason: 'invariato');
    expect(riga.readingStatus, StatoLettura.letto, reason: 'invariato');
  });

  test(
    'cambiaStatoCopia scrive solo status/readingStatus, lasciando invariati i campi §8.2',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        readingStatus: StatoLettura.daLeggere,
        seller: 'Edicola di zona',
      );

      await repo.cambiaStatoCopia(id: copiaId, status: StatoCopia.prestata);

      final riga = await (db.select(
        db.copie,
      )..where((c) => c.id.equals(copiaId))).getSingle();
      expect(riga.status, StatoCopia.prestata);
      expect(riga.readingStatus, isNull);
      expect(riga.seller, 'Edicola di zona', reason: 'invariato');
    },
  );

  test(
    'rimuoviCopia rimuove solo la Copia quando ne restano altre',
    () async {
      final edizioneId = await edizione();
      final copia1 = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.venduta,
      );

      final edizioneEliminata = await repo.rimuoviCopia(copia1);

      expect(edizioneEliminata, isFalse);
      final copieRimaste = await (db.select(
        db.copie,
      )..where((c) => c.edizioneId.equals(edizioneId))).get();
      expect(copieRimaste, hasLength(1));
      final edizioneRiga = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(edizioneId))).getSingleOrNull();
      expect(edizioneRiga, isNotNull);
    },
  );

  test(
    "rimuoviCopia sull'ultima Copia elimina anche l'Edizione (deciso su #68: nessuno stato orfana)",
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final edizioneEliminata = await repo.rimuoviCopia(copiaId);

      expect(edizioneEliminata, isTrue);
      final edizioneRiga = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(edizioneId))).getSingleOrNull();
      expect(edizioneRiga, isNull);
    },
  );

  test(
    'rimuoviCopia sull\'ultima Copia rimuove anche i collegamenti Autore dell\'Edizione',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      final creatorId = await repo.aggiungiCreator('Stan Lee');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      await repo.rimuoviCopia(copiaId);

      final legami = await (db.select(
        db.comicCreator,
      )..where((c) => c.edizioneId.equals(edizioneId))).get();
      expect(legami, isEmpty);
    },
  );

  test(
    'eliminaEdizione elimina Edizione, tutte le Copie e i collegamenti Autore',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.prestata,
      );
      final creatorId = await repo.aggiungiCreator('Stan Lee');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      await repo.eliminaEdizione(edizioneId);

      final edizioneRiga = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(edizioneId))).getSingleOrNull();
      expect(edizioneRiga, isNull);
      final copieRimaste = await (db.select(
        db.copie,
      )..where((c) => c.edizioneId.equals(edizioneId))).get();
      expect(copieRimaste, isEmpty);
      final legami = await (db.select(
        db.comicCreator,
      )..where((c) => c.edizioneId.equals(edizioneId))).get();
      expect(legami, isEmpty);
    },
  );
}
