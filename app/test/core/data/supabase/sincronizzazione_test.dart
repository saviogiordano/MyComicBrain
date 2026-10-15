import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Due device dello stesso account convergono attraverso lo stack locale
/// (ADR-0008, #208): `scripts/test-contratto-supabase.sh` imposta le
/// variabili.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final url = Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final chiave = Platform.environment['SUPABASE_TEST_PUBLISHABLE_KEY'] ?? '';
  final configurato = url.isNotEmpty && chiave.isNotEmpty;

  final chiudere = <Future<void> Function()>[];
  tearDown(() async {
    for (final chiudi in chiudere.reversed) {
      await chiudi();
    }
    chiudere.clear();
  });

  Future<SupabaseClient> client() async {
    final c = SupabaseClient(
      url,
      chiave,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    chiudere.add(c.dispose);
    return c;
  }

  /// Un account e il suo primo device già autenticato.
  Future<({String email, String password, String userId})> account() async {
    final casuale = Random.secure().nextInt(1 << 32).toRadixString(36);
    final email = 'sincronizza-$casuale@example.com';
    final password = 'Sincronizza-$casuale-pw1';
    final c = await client();
    final risposta = await c.auth.signUp(email: email, password: password);
    return (email: email, password: password, userId: risposta.user!.id);
  }

  /// Un device con la sua Replica in memoria.
  Future<_Device> device(
    ({String email, String password, String userId}) a,
  ) async {
    final c = await client();
    await c.auth.signInWithPassword(email: a.email, password: a.password);
    final db = AppDatabase.replica(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    chiudere.add(db.close);
    return _Device(
      db,
      Sincronizzatore(
        db: db,
        canale: CanaleSupabase(c, userId: a.userId),
        userId: a.userId,
        // Pagine piccole: il primo download passa da più pagine.
        paginaPull: 3,
        lottoPush: 4,
      ),
    );
  }

  Future<String> titolo(_Device d, String operaId) async => (await (d.db.select(
    d.db.opere,
  )..where((o) => o.id.equals(operaId))).getSingle()).title;

  Future<CopieData?> copia(_Device d, String id) => (d.db.select(
    d.db.copie,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  group('Sincronizzazione fra due device', skip: !configurato, () {
    test(
      'primo download, aggiunta, modifica ed eliminazione convergono',
      () async {
        final a = await account();
        final uno = await device(a);
        final due = await device(a);

        // Il device uno cataloga prima che l'altro esista.
        final operaId = await uno.repo.aggiungiOpera(title: 'Sandman');
        final edizioneId = await uno.repo.aggiungiEdizione(
          operaId: operaId,
          issueNumberLabel: '1',
          coverImage: 'copertine/123.jpg',
          format: FormatoEdizione.brossurato,
        );
        final copiaId = await uno.repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
          purchaseDate: DateTime.utc(2026, 3, 4),
          purchasePrice: 4.5,
        );
        await uno.repo.impostaInVendita(id: copiaId, inVendita: true);
        final tagId = await uno.repo.aggiungiTag('horror');
        await uno.repo.collegaTagAEdizione(
          edizioneId: edizioneId,
          tagId: tagId,
        );
        for (var i = 0; i < 5; i++) {
          await uno.repo.aggiungiOpera(title: 'Riempitivo $i');
        }
        final esito = await uno.sync.sincronizza();
        expect(esito.inviate, greaterThan(4), reason: 'più lotti di push');
        expect(await RegistroModifiche(uno.db).voci(), isEmpty);

        // Primo download sul device due, a pagine.
        expect(await due.sync.stato(), isNull);
        final ricevute = <int>[];
        await due.sync.sincronizza(avanzamento: ricevute.add);
        expect(ricevute.length, greaterThan(1));
        expect(await due.sync.stato(), isNotNull);
        expect(await titolo(due, operaId), 'Sandman');
        final copiaDue = (await copia(due, copiaId))!;
        expect(copiaDue.forSale, isTrue);
        expect(copiaDue.purchaseDate, DateTime.utc(2026, 3, 4));
        expect(copiaDue.purchasePrice, 4.5);
        final edizioneDue = await (due.db.select(
          due.db.edizioni,
        )..where((e) => e.id.equals(edizioneId))).getSingle();
        expect(edizioneDue.coverImage, 'copertine/123.jpg');
        expect(edizioneDue.format, FormatoEdizione.brossurato);
        expect(
          await RegistroModifiche(due.db).voci(),
          isEmpty,
          reason: 'il pull non genera Modifiche in sospeso',
        );

        // Il device due modifica e aggiunge; il device uno elimina il Tag.
        await due.repo.aggiornaTitoloOpera(
          operaId: operaId,
          title: 'The Sandman',
        );
        final nuovaCopia = await due.repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.prestata,
        );
        final edizioneTag = await (uno.db.select(
          uno.db.edizioneTag,
        )..where((t) => t.edizioneId.equals(edizioneId))).getSingle();
        await uno.repo.rimuoviTagDaEdizione(edizioneTag.id);
        await due.sync.sincronizza();
        await uno.sync.sincronizza();
        await due.sync.sincronizza();

        for (final d in [uno, due]) {
          expect(await titolo(d, operaId), 'The Sandman');
          expect((await copia(d, nuovaCopia))!.status, StatoCopia.prestata);
          expect(await d.db.select(d.db.edizioneTag).get(), isEmpty);
        }
      },
    );

    test("conflitto: vince campo per campo l'ultima modifica fatta", () async {
      final a = await account();
      final uno = await device(a);
      final due = await device(a);
      final operaId = await uno.repo.aggiungiOpera(title: 'Watchmen');
      final edizioneId = await uno.repo.aggiungiEdizione(operaId: operaId);
      final copiaId = await uno.repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await uno.sync.sincronizza();
      await due.sync.sincronizza();

      // Offline: entrambi modificano la Copia, campi in parte diversi. Il
      // device due modifica le note per ultimo.
      await uno.repo.aggiornaCopia(id: copiaId, notes: 'uno', location: 'A1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await due.repo.aggiornaCopia(
        id: copiaId,
        notes: 'due',
        seller: 'Bottega',
      );

      // Il device due arriva per primo, il device uno dopo: vince comunque
      // la modifica fatta per ultima.
      await due.sync.sincronizza();
      await uno.sync.sincronizza();
      await due.sync.sincronizza();

      for (final d in [uno, due]) {
        final c = (await copia(d, copiaId))!;
        expect(c.notes, 'due');
        expect(c.location, 'A1');
        expect(c.seller, 'Bottega');
      }
    });

    test("l'eliminazione prevale e la modifica scartata si segnala", () async {
      final a = await account();
      final uno = await device(a);
      final due = await device(a);
      final operaId = await uno.repo.aggiungiOpera(title: 'Maus');
      final edizioneId = await uno.repo.aggiungiEdizione(operaId: operaId);
      final copiaId = await uno.repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await uno.sync.sincronizza();
      await due.sync.sincronizza();

      await uno.repo.eliminaEdizione(edizioneId);
      await due.repo.aggiornaCopia(id: copiaId, notes: 'offline');
      final orfana = await due.repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await uno.sync.sincronizza();
      final esito = await due.sync.sincronizza();

      expect(
        esito.scartate,
        containsAll(<RigaReplicata>[
          (tabella: 'copie', id: copiaId),
          (tabella: 'copie', id: orfana),
        ]),
      );
      for (final d in [uno, due]) {
        expect(await d.db.select(d.db.edizioni).get(), isEmpty);
        expect(await d.db.select(d.db.copie).get(), isEmpty);
      }
      expect(await RegistroModifiche(due.db).voci(), isEmpty);
    });

    test('lo stesso collegamento creato su due device resta uno', () async {
      final a = await account();
      final uno = await device(a);
      final due = await device(a);
      final operaId = await uno.repo.aggiungiOpera(title: 'Hellboy');
      final edizioneId = await uno.repo.aggiungiEdizione(operaId: operaId);
      final tagId = await uno.repo.aggiungiTag('horror');
      await uno.sync.sincronizza();
      await due.sync.sincronizza();

      await uno.repo.collegaTagAEdizione(edizioneId: edizioneId, tagId: tagId);
      await uno.repo.impostaGeneriEdizione(
        edizioneId: edizioneId,
        generi: {GenereEdizione.horror},
      );
      await due.repo.collegaTagAEdizione(edizioneId: edizioneId, tagId: tagId);
      await due.repo.impostaGeneriEdizione(
        edizioneId: edizioneId,
        generi: {GenereEdizione.horror},
      );
      await uno.sync.sincronizza();
      await due.sync.sincronizza();
      await uno.sync.sincronizza();

      final idUno = (await uno.db.select(uno.db.edizioneTag).getSingle()).id;
      final idDue = (await due.db.select(due.db.edizioneTag).getSingle()).id;
      expect(idDue, idUno);
      expect(await due.db.select(due.db.edizioneGenere).get(), hasLength(1));
      expect(await RegistroModifiche(due.db).voci(), isEmpty);
    });

    test('una modifica in sospeso non si perde col pull', () async {
      final a = await account();
      final uno = await device(a);
      final due = await device(a);
      final operaId = await uno.repo.aggiungiOpera(title: 'Akira');
      await uno.sync.sincronizza();
      await due.sync.sincronizza();

      await uno.repo.aggiornaTitoloOpera(operaId: operaId, title: 'Akira 1');
      await uno.sync.sincronizza();
      // Il device due modifica la stessa Opera prima di scaricare: il suo
      // campo in sospeso non viene sovrascritto dal pull e vince al push.
      await due.repo.aggiornaTitoloOpera(operaId: operaId, title: 'Akira 2');
      await due.sync.sincronizza();
      await uno.sync.sincronizza();
      expect(await titolo(uno, operaId), 'Akira 2');
      expect(await titolo(due, operaId), 'Akira 2');
    });
  });
}

class _Device {
  _Device(this.db, this.sync) : repo = DriftComicsRepository(db);

  final AppDatabase db;
  final Sincronizzatore sync;
  final DriftComicsRepository repo;
}
