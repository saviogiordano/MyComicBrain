import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/domain/creator.dart';

import 'contratto/adapter_sotto_contratto.dart';

void main() => contrattoCreator(creaAdapterDriftInMemoria);

/// Area Creator della suite di contratto di `ComicsRepository` (ADR-0007).
void contrattoCreator(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;

  setUp(() async {
    adapter = await crea();
    repo = adapter.repo;
  });

  tearDown(() => adapter.chiudi());

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

    final dettaglio = await repo.watchEdizione(edizioneId).first;
    expect(dettaglio!.volume, 'Omnibus 1');
    expect(dettaglio.description, 'La prima raccolta.');
  });

  test(
    'aggiungiCreator crea un Creator senza controllo di univocità sul nome',
    () async {
      final id1 = await repo.aggiungiCreator('Stan Lee');
      final id2 = await repo.aggiungiCreator('Stan Lee');

      expect(id1, isNot(id2));
    },
  );

  test('cercaCreator trova Creator per match parziale del nome', () async {
    await repo.aggiungiCreator('Stan Lee');
    await repo.aggiungiCreator('Steve Ditko');

    final risultati = await repo.cercaCreator('Stan');

    expect(risultati, hasLength(1));
    expect(risultati.single.name, 'Stan Lee');
  });

  test(
    'cercaCharacter e cercaTag trovano per match parziale del nome',
    () async {
      await repo.aggiungiCharacter('Rorschach');
      await repo.aggiungiCharacter('Ozymandias');
      await repo.aggiungiTag('capolavoro');
      await repo.aggiungiTag('da rileggere');

      expect((await repo.cercaCharacter('rorsch')).single.name, 'Rorschach');
      expect((await repo.cercaTag('lavoro')).single.name, 'capolavoro');
    },
  );

  test(
    "collegaCreatorAEdizione collega un Creator a un'Edizione con un ruolo",
    () async {
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
    },
  );

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

  test(
    "autoriDiEdizione e cercaCreator seguono l'ordine di inserimento",
    () async {
      final edizioneId = await edizione();
      final primo = await repo.aggiungiCreator('Stan Lee');
      final secondo = await repo.aggiungiCreator('Steve Ditko');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: primo,
        ruolo: RuoloCreator.sceneggiatore,
      );
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: secondo,
        ruolo: RuoloCreator.disegnatore,
      );

      expect(
        (await repo.autoriDiEdizione(edizioneId)).map((a) => a.creatorId),
        [primo, secondo],
      );
      expect(
        (await repo.cercaCreator('St')).map((c) => c.id),
        [primo, secondo],
      );
    },
  );

  test(
    'rimuoviCreatorDaEdizione rimuove solo il collegamento indicato',
    () async {
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
    },
  );
}
