import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/repliche_profilo.dart';
import 'package:path/path.dart' as p;

/// La Replica locale di ogni Profilo e i suoi file sul device (ADR-0008).
void main() {
  late Directory temp;
  late ReplicheProfilo repliche;

  Directory dati(String idUtente) =>
      Directory(p.join(temp.path, 'support', 'profili', idUtente));
  Directory cache(String idUtente) =>
      Directory(p.join(temp.path, 'cache', 'profili', idUtente));

  ReplicheProfilo crea() => ReplicheProfilo(
    cartellaDati: () async => Directory(p.join(temp.path, 'support')),
    cartellaCache: () async => Directory(p.join(temp.path, 'cache')),
    apri: (cartella) => LazyDatabase(
      () async => NativeDatabase(
        File(
          p.join(
            (await cartella()).path,
            '${ReplicheProfilo.nomeReplica}.sqlite',
          ),
        ),
      ),
    ),
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('repliche_profilo_');
    repliche = crea();
  });

  tearDown(() async {
    await repliche.chiudi();
    await temp.delete(recursive: true);
  });

  test('la Replica di un Profilo è un file nella sua cartella', () async {
    final repo = DriftComicsRepository(repliche.database('utente-1'));
    await repo.aggiungiOpera(title: 'Dylan Dog');

    expect(
      File(p.join(dati('utente-1').path, 'replica.sqlite')).existsSync(),
      isTrue,
    );
    expect(
      (await repliche.cartellaDati('utente-1')).path,
      dati('utente-1').path,
    );
    expect(
      (await repliche.cartellaCache('utente-1')).path,
      cache('utente-1').path,
    );
  });

  test('lo stesso Profilo riusa lo stesso database', () {
    expect(
      repliche.database('utente-1'),
      same(repliche.database('utente-1')),
    );
  });

  test('ogni Profilo ha la sua Replica', () async {
    await DriftComicsRepository(
      repliche.database('utente-1'),
    ).aggiungiOpera(title: 'Dylan Dog');

    final altro = DriftComicsRepository(repliche.database('utente-2'));

    expect(await altro.haDatiDaImportare(), isFalse);
  });

  test('la Replica si ritrova dopo averla riaperta', () async {
    await DriftComicsRepository(
      repliche.database('utente-1'),
    ).aggiungiOpera(title: 'Dylan Dog');
    await repliche.chiudi();

    final riaperta = crea();
    addTearDown(riaperta.chiudi);

    expect(
      await DriftComicsRepository(
        riaperta.database('utente-1'),
      ).haDatiDaImportare(),
      isTrue,
    );
  });

  test(
    'cancella chiude la Replica e toglie i file e la cache del Profilo',
    () async {
      final db = repliche.database('utente-1');
      await DriftComicsRepository(db).aggiungiOpera(title: 'Dylan Dog');
      await File(
        p.join(cache('utente-1').path, 'covers', 'a.jpg'),
      ).create(recursive: true);
      await DriftComicsRepository(
        repliche.database('utente-2'),
      ).aggiungiOpera(title: 'Tex');

      await repliche.cancella('utente-1');

      expect(dati('utente-1').existsSync(), isFalse);
      expect(cache('utente-1').existsSync(), isFalse);
      expect(dati('utente-2').existsSync(), isTrue);
      expect(
        await DriftComicsRepository(
          repliche.database('utente-1'),
        ).haDatiDaImportare(),
        isFalse,
        reason: 'dopo la cancellazione il Profilo riparte da una Replica vuota',
      );
    },
  );

  test('cancella un Profilo mai aperto non fallisce', () async {
    await repliche.cancella('mai-visto');
  });
}
