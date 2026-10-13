import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/supabase/supabase_comics_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Selezione dell'adapter in `comicsRepositoryProvider` (ADR-0007).
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

  ProviderContainer container(List<Override> overrides) {
    final container = ProviderContainer(
      overrides: [
        driftComicsRepositoryProvider.overrideWithValue(
          DriftComicsRepository(db),
        ),
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
    expect(c.read(comicsRepositoryProvider), isA<DriftComicsRepository>());
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

  test('con un Profilo autenticato passa a Supabase, legato al suo utente', () {
    final c = container([
      supabaseClientProvider.overrideWithValue(client),
      idUtenteSupabaseProvider.overrideWithValue('utente-1'),
    ]);

    final repository = c.read(comicsRepositoryProvider);

    expect(
      repository,
      isA<SupabaseComicsRepository>().having(
        (r) => r.userId,
        'userId',
        'utente-1',
      ),
    );
  });

  test('al logout torna su drift', () {
    final utente = StateProvider<String?>((ref) => 'utente-1');
    final c = container([
      supabaseClientProvider.overrideWithValue(client),
      idUtenteSupabaseProvider.overrideWith((ref) => ref.watch(utente)),
    ]);
    expect(c.read(comicsRepositoryProvider), isA<SupabaseComicsRepository>());

    c.read(utente.notifier).state = null;

    expect(c.read(comicsRepositoryProvider), isA<DriftComicsRepository>());
  });
}
