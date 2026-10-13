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
    cartellaScansioni: () async =>
        Directory(p.join(temp.path, cache, 'scansioni'))
          ..createSync(recursive: true),
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

    test(
      'una Scansione senza file locale si scarica in cache con lo stesso nome',
      () async {
        final (c, userId) = await utente();
        final deviceA = repository(c, userId, 'device-a');
        final scattata = File(
          p.join(temp.path, 'device-a', 'scansioni', '1739.jpg'),
        );
        await scattata.parent.create(recursive: true);
        await scattata.writeAsBytes([0xFF, 0xD8, 1, 2]);
        final id = await deviceA.aggiungiScansione(image: scattata.path);

        final deviceB = repository(c, userId, 'device-b');
        final immagini = await deviceB
            .watchImmaginiScansioniNonConfermate()
            .first;

        expect(immagini.single, startsWith(p.join(temp.path, 'device-b')));
        expect(p.basename(immagini.single), '1739.jpg');
        expect(await File(immagini.single).readAsBytes(), [0xFF, 0xD8, 1, 2]);
        expect(await deviceB.idScansionePerImmagine(immagini.single), id);
        expect(
          await deviceA.watchImmaginiScansioniNonConfermate().first,
          [scattata.path],
          reason: "sul device che l'ha scattata resta il file locale",
        );
      },
    );

    test("eliminaScansione rimuove anche l'oggetto su Storage", () async {
      final (c, userId) = await utente();
      final repo = repository(c, userId, 'cache');
      final file = File(p.join(temp.path, 'cache', 'scansioni', '42.jpg'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([0xFF, 0xD8]);
      final id = await repo.aggiungiScansione(image: file.path);
      expect(
        await c.storage.from('scansioni').list(path: userId),
        hasLength(1),
      );

      await repo.eliminaScansione(id: id);

      expect(await c.storage.from('scansioni').list(path: userId), isEmpty);
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
