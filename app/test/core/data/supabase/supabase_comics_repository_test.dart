import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/supabase/supabase_comics_repository.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Comportamento proprio dell'adapter Supabase (cache, RLS), contro lo
/// stack locale: `scripts/test-contratto-supabase.sh` imposta le variabili.
/// Ciò che vale per ogni adapter sta nella suite di contratto.
void main() {
  final url = Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final chiave = Platform.environment['SUPABASE_TEST_PUBLISHABLE_KEY'] ?? '';
  final configurato = url.isNotEmpty && chiave.isNotEmpty;

  late Directory temp;
  final client = <SupabaseClient>[];

  Future<(SupabaseClient, String)> utente() async {
    final c = SupabaseClient(
      url,
      chiave,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    client.add(c);
    final casuale = Random.secure().nextInt(1 << 32).toRadixString(36);
    final risposta = await c.auth.signUp(
      email: 'adapter-$casuale@example.com',
      password: 'Adapter-$casuale-pw1',
    );
    return (c, risposta.user!.id);
  }

  SupabaseComicsRepository repository(
    SupabaseClient c,
    String userId,
    String cache,
  ) => SupabaseComicsRepository(
    c,
    userId: userId,
    cartellaCache: () async =>
        Directory(p.join(temp.path, cache))..createSync(recursive: true),
  );

  Future<File> immagine(List<int> bytes) async =>
      File(p.join(temp.path, 'cover.jpg')).writeAsBytes(bytes);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('adapter_supabase_');
  });

  tearDown(() async {
    for (final c in client) {
      await c.dispose();
    }
    client.clear();
    await temp.delete(recursive: true);
  });

  group('su Supabase locale', () {
    test('salvaCoverLocale salva sotto la Collezione del Profilo', () async {
      final (c, userId) = await utente();
      final repo = repository(c, userId, 'cache');

      final chiave = await repo.salvaCoverLocale(await immagine([1, 2, 3]));

      expect(chiave, startsWith('${await repo.collectionId()}/'));
      expect(chiave, endsWith('.jpg'));
    });

    test('con la cache vuota la cover si scarica da Storage', () async {
      final (c, userId) = await utente();
      final chiave = await repository(
        c,
        userId,
        'device-a',
      ).salvaCoverLocale(await immagine([4, 5, 6]));

      final risolta = await repository(
        c,
        userId,
        'device-b',
      ).risolviCoverImage(chiave);

      expect(risolta, startsWith(p.join(temp.path, 'device-b')));
      expect(await File(risolta!).readAsBytes(), [4, 5, 6]);
    });

    test("la cover di un'altra Collezione non si risolve (RLS)", () async {
      final (c1, utente1) = await utente();
      final chiave = await repository(
        c1,
        utente1,
        'utente-1',
      ).salvaCoverLocale(await immagine([7, 8, 9]));
      final (c2, utente2) = await utente();

      expect(
        await repository(c2, utente2, 'utente-2').risolviCoverImage(chiave),
        isNull,
      );
    });

    test('un metodo non ancora portato lancia UnimplementedError', () async {
      final (c, userId) = await utente();

      expect(
        () => repository(c, userId, 'cache').watchDashboardKpis(),
        throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('watchDashboardKpis'),
          ),
        ),
      );
    });
  }, skip: configurato ? false : 'Stack Supabase locale non configurato');
}
