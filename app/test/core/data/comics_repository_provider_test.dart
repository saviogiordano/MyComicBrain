import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/repliche_profilo.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Selezione del repository in `comicsRepositoryProvider` (ADR-0008):
/// Modalità locale o Replica del Profilo, sempre `DriftComicsRepository`.
void main() {
  late AppDatabase db;
  late Directory temp;
  late ReplicheProfilo repliche;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    temp = await Directory.systemTemp.createTemp('provider_repository_');
    repliche = ReplicheProfilo(
      cartellaDati: () async => Directory(p.join(temp.path, 'support')),
      cartellaCache: () async => Directory(p.join(temp.path, 'cache')),
      apri: (cartella) => LazyDatabase(
        () async => NativeDatabase(
          File(p.join((await cartella()).path, 'replica.sqlite')),
        ),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await repliche.chiudi();
    await temp.delete(recursive: true);
  });

  ProviderContainer container(List<Override> overrides) {
    final container = ProviderContainer(
      overrides: [
        driftComicsRepositoryProvider.overrideWithValue(
          DriftComicsRepository(db),
        ),
        replicheProfiloProvider.overrideWithValue(repliche),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  final client = SupabaseClient('http://127.0.0.1:1', 'chiave-di-test');

  test('senza client Supabase (login spento) resta su drift', () {
    final c = container(const []);

    expect(c.read(idUtenteSupabaseProvider), isNull);
    expect(
      c.read(comicsRepositoryProvider),
      same(c.read(driftComicsRepositoryProvider)),
    );
  });

  test('senza sessione resta su drift', () {
    final c = container([
      supabaseClientProvider.overrideWithValue(client),
      idUtenteSupabaseProvider.overrideWithValue(null),
    ]);

    expect(
      c.read(comicsRepositoryProvider),
      same(c.read(driftComicsRepositoryProvider)),
    );
  });

  test(
    'con un Profilo autenticato lavora sulla sua Replica, non sulla '
    'Modalità locale',
    () async {
      final c = container([
        supabaseClientProvider.overrideWithValue(client),
        idUtenteSupabaseProvider.overrideWithValue('utente-1'),
      ]);

      await c.read(comicsRepositoryProvider).aggiungiOpera(title: 'Tex');

      expect(
        await DriftComicsRepository(
          repliche.database('utente-1'),
        ).haDatiDaImportare(),
        isTrue,
      );
      expect(
        await c.read(driftComicsRepositoryProvider).haDatiDaImportare(),
        isFalse,
      );
    },
  );

  test(
    'le cover e le Scansioni del Profilo stanno nella sua cartella',
    () async {
      final c = container([
        supabaseClientProvider.overrideWithValue(client),
        idUtenteSupabaseProvider.overrideWithValue('utente-1'),
      ]);
      final sorgente = File(p.join(temp.path, 'cover.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final cartella = (await repliche.cartellaDati('utente-1')).path;

      final cover = await c
          .read(comicsRepositoryProvider)
          .salvaCoverLocale(sorgente);

      expect(
        await c.read(comicsRepositoryProvider).risolviCoverImage(cover),
        startsWith(cartella),
      );
      expect(
        (await c.read(scansioneStorageProvider).cartella()).path,
        startsWith(cartella),
      );
    },
  );

  test('al logout torna su drift', () {
    final utente = StateProvider<String?>((ref) => 'utente-1');
    final c = container([
      supabaseClientProvider.overrideWithValue(client),
      idUtenteSupabaseProvider.overrideWith((ref) => ref.watch(utente)),
    ]);
    expect(
      c.read(comicsRepositoryProvider),
      isNot(same(c.read(driftComicsRepositoryProvider))),
    );

    c.read(utente.notifier).state = null;

    expect(
      c.read(comicsRepositoryProvider),
      same(c.read(driftComicsRepositoryProvider)),
    );
  });
}
