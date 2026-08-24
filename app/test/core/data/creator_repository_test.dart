import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/creator.dart';

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

  Future<int> edizione() async {
    final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');
    return repo.aggiungiEdizione(operaId: operaId, issueNumberLabel: '1');
  }

  test('aggiungiEdizione persiste volume e description', () async {
    final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');

    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      volume: 'Omnibus 1',
      description: 'La prima raccolta.',
    );

    final riga = await (db.select(
      db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingle();
    expect(riga.volume, 'Omnibus 1');
    expect(riga.description, 'La prima raccolta.');
  });

  test('aggiungiCreator crea un Creator senza controllo di univocità sul nome', () async {
    final id1 = await repo.aggiungiCreator('Stan Lee');
    final id2 = await repo.aggiungiCreator('Stan Lee');

    expect(id1, isNot(id2));
  });

  test('cercaCreator trova Creator per match parziale del nome', () async {
    await repo.aggiungiCreator('Stan Lee');
    await repo.aggiungiCreator('Steve Ditko');

    final risultati = await repo.cercaCreator('Stan');

    expect(risultati, hasLength(1));
    expect(risultati.single.name, 'Stan Lee');
  });

  test("collegaCreatorAEdizione collega un Creator a un'Edizione con un ruolo", () async {
    final edizioneId = await edizione();
    final creatorId = await repo.aggiungiCreator('Stan Lee');

    await repo.collegaCreatorAEdizione(
      edizioneId: edizioneId,
      creatorId: creatorId,
      ruolo: RuoloCreator.sceneggiatore,
    );

    final autori = await repo.autoriDiEdizione(edizioneId);
    expect(autori, hasLength(1));
    expect(autori.single.creatorId, creatorId);
    expect(autori.single.name, 'Stan Lee');
    expect(autori.single.ruolo, RuoloCreator.sceneggiatore);
  });

  test(
    'un Creator può comparire più volte sulla stessa Edizione con ruoli diversi',
    () async {
      final edizioneId = await edizione();
      final creatorId = await repo.aggiungiCreator('Stan Lee');

      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.disegnatore,
      );

      final autori = await repo.autoriDiEdizione(edizioneId);
      expect(autori, hasLength(2));
      expect(
        autori.map((a) => a.ruolo),
        containsAll([RuoloCreator.sceneggiatore, RuoloCreator.disegnatore]),
      );
    },
  );

  test(
    "un'Edizione può avere più Creator con lo stesso ruolo",
    () async {
      final edizioneId = await edizione();
      final matita = await repo.aggiungiCreator('Steve Ditko');
      final chine = await repo.aggiungiCreator('John Romita');

      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: matita,
        ruolo: RuoloCreator.disegnatore,
      );
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: chine,
        ruolo: RuoloCreator.disegnatore,
      );

      final autori = await repo.autoriDiEdizione(edizioneId);
      expect(autori, hasLength(2));
      expect(
        autori.map((a) => a.creatorId),
        containsAll([matita, chine]),
      );
    },
  );

  test(
    'collegaCreatorAEdizione blocca il duplicato esatto (stesso autore, stesso ruolo, stessa edizione)',
    () async {
      final edizioneId = await edizione();
      final creatorId = await repo.aggiungiCreator('Stan Lee');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      expect(
        () => repo.collegaCreatorAEdizione(
          edizioneId: edizioneId,
          creatorId: creatorId,
          ruolo: RuoloCreator.sceneggiatore,
        ),
        throwsA(anything),
      );
    },
  );

  test('rimuoviCreatorDaEdizione rimuove solo il collegamento indicato', () async {
    final edizioneId = await edizione();
    final creatorId = await repo.aggiungiCreator('Stan Lee');
    await repo.collegaCreatorAEdizione(
      edizioneId: edizioneId,
      creatorId: creatorId,
      ruolo: RuoloCreator.sceneggiatore,
    );
    final autori = await repo.autoriDiEdizione(edizioneId);

    await repo.rimuoviCreatorDaEdizione(autori.single.comicCreatorId);

    expect(await repo.autoriDiEdizione(edizioneId), isEmpty);
  });
}
