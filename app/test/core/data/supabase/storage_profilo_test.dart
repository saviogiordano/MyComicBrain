import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/supabase/storage_profilo.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// I file di un Profilo su Storage (ADR-0007/0008), contro lo stack
/// locale: `scripts/test-contratto-supabase.sh` imposta le variabili.
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
      email: 'storage-$casuale@example.com',
      password: 'Storage-$casuale-pw1',
    );
    return (c, risposta.user!.id);
  }

  /// Lo Storage del Profilo [userId] su un device con la cache [device].
  StorageProfilo storage(SupabaseClient c, String userId, String device) =>
      StorageProfilo(
        c,
        userId: userId,
        cartellaCache: () async =>
            Directory(p.join(temp.path, device))..createSync(recursive: true),
      );

  Future<File> immagine(String nome, List<int> bytes) async {
    final file = File(p.join(temp.path, 'sorgenti', nome));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('storage_profilo_');
  });

  tearDown(() async {
    for (final c in client) {
      await c.dispose();
    }
    client.clear();
    await temp.delete(recursive: true);
  });

  group('su Supabase locale', () {
    test('una cover si carica sotto la Collezione del Profilo', () async {
      final (c, userId) = await utente();
      final s = storage(c, userId, 'device-a');

      final chiave = await s.caricaCover(await immagine('a.png', [1, 2, 3]));

      expect(chiave, startsWith('${await s.collectionId()}/'));
      expect(chiave, endsWith('.png'));
    });

    test('con la cache vuota la cover si scarica da Storage', () async {
      final (c, userId) = await utente();
      final chiave = await storage(
        c,
        userId,
        'device-a',
      ).caricaCover(await immagine('a.jpg', [4, 5, 6]));

      final risolta = await storage(
        c,
        userId,
        'device-b',
      ).risolvi(BucketStorage.covers, chiave);

      expect(risolta, startsWith(p.join(temp.path, 'device-b')));
      expect(await File(risolta!).readAsBytes(), [4, 5, 6]);
    });

    test("la cover di un'altra Collezione non si risolve (RLS)", () async {
      final (c1, utente1) = await utente();
      final chiave = await storage(
        c1,
        utente1,
        'utente-1',
      ).caricaCover(await immagine('a.jpg', [7, 8, 9]));
      final (c2, utente2) = await utente();

      expect(
        await storage(c2, utente2, 'utente-2').risolvi(
          BucketStorage.covers,
          chiave,
        ),
        isNull,
      );
    });

    test(
      "una Scansione si carica sotto l'utente con il suo nome, anche due "
      'volte',
      () async {
        final (c, userId) = await utente();
        final s = storage(c, userId, 'device-a');
        final file = await immagine('1739.jpg', [0xFF, 0xD8, 1, 2]);

        final chiave = await s.caricaScansione(file);
        expect(await s.caricaScansione(file), chiave);

        expect(chiave, '$userId/1739.jpg');
        final scaricata = await storage(
          c,
          userId,
          'device-b',
        ).risolvi(BucketStorage.scansioni, chiave);
        expect(p.basename(scaricata!), '1739.jpg');
        expect(await File(scaricata).readAsBytes(), [0xFF, 0xD8, 1, 2]);
      },
    );

    test("elimina toglie l'oggetto da Storage e dalla cache", () async {
      final (c, userId) = await utente();
      final s = storage(c, userId, 'device-a');
      final chiave = await s.caricaScansione(
        await immagine('42.jpg', [0xFF, 0xD8]),
      );
      final inCache = await s.risolvi(BucketStorage.scansioni, chiave);

      await s.elimina(BucketStorage.scansioni, chiave);

      expect(await c.storage.from('scansioni').list(path: userId), isEmpty);
      expect(File(inCache!).existsSync(), isFalse);
    });
  }, skip: configurato ? false : 'Stack Supabase locale non configurato');
}
