import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/conversione_righe.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
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
    final cartella = await Directory.systemTemp.createTemp('device_');
    chiudere.add(() => cartella.delete(recursive: true));
    return _Device(
      db,
      c,
      cartella,
      Sincronizzatore(
        db: db,
        canale: CanaleSupabase(c, userId: a.userId),
        userId: a.userId,
        cartellaProfilo: () async => cartella,
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
    test("una cover aggiunta su un device arriva sull'altro", () async {
      final a = await account();
      final uno = await device(a);
      final due = await device(a);
      final bytes = List<int>.generate(64, (i) => i);
      File('${uno.cartella.path}/copertine/0199f0c0-cover.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      final edizioneId = await uno.repo.aggiungiEdizione(
        operaId: await uno.repo.aggiungiOpera(title: 'Sandman'),
        coverImage: 'copertine/0199f0c0-cover.jpg',
      );
      await uno.sync.sincronizza();

      await due.sync.sincronizza();
      final avanzamento = <(int, int)>[];
      await due.sync.scaricaCover(
        avanzamento: (n, m) => avanzamento.add((n, m)),
      );

      final edizioneDue = await (due.db.select(
        due.db.edizioni,
      )..where((e) => e.id.equals(edizioneId))).getSingle();
      expect(edizioneDue.coverImage, 'copertine/0199f0c0-cover.jpg');
      expect(avanzamento.last, (1, 1));
      expect(
        File(
          '${due.cartella.path}/copertine/0199f0c0-cover.jpg',
        ).readAsBytesSync(),
        bytes,
      );

      // Un oggetto che Storage non ha non è un errore.
      final canale = CanaleSupabase(due.client, userId: a.userId);
      expect(
        await canale.scaricaFile(
          BucketImmagine.covers,
          '${await canale.collectionId()}/inesistente.jpg',
        ),
        isNull,
      );
    });

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

    test(
      'una Scansione analizzata, identificata e confermata su un device '
      "arriva sull'altro (#210)",
      () async {
        final a = await account();
        final uno = await device(a);
        final due = await device(a);
        final scansioneId = await uno.repo.aggiungiScansione(
          image: 'scansioni/0199f0c0-scan.jpg',
        );
        final analisiId = await uno.repo.accodaAnalisiCopertina(
          scansioneId: scansioneId,
        );
        await uno.sync.sincronizza();
        await uno.repo.riavviaAnalisiCopertina(id: analisiId);
        await uno.repo.completaAnalisiCopertina(
          id: analisiId,
          rawResponse: '{}',
          title: 'Tex',
          characters: const ['Tex Willer'],
        );
        final identificazioneId = await uno.repo.avviaIdentificazione(
          scansioneId: scansioneId,
        );
        final candidatoId = await uno.repo.aggiungiCandidato(
          identificazioneId: identificazioneId,
          source: FonteCandidato.esterno,
          punteggio: 0.9,
          title: 'Tex',
          issueNumberLabel: '1',
        );
        await uno.repo.completaIdentificazione(id: identificazioneId);
        final copiaId = await uno.repo.aggiungiCopia(
          edizioneId: await uno.repo.aggiungiEdizione(
            operaId: await uno.repo.aggiungiOpera(title: 'Tex'),
          ),
          status: StatoCopia.posseduta,
          scansioneId: scansioneId,
        );
        await uno.sync.sincronizza();
        expect(await RegistroModifiche(uno.db).voci(), isEmpty);

        await due.sync.sincronizza();

        final esito = await due.repo.watchIdentificazione(scansioneId).first;
        expect(esito.stato, StatoIdentificazione.completata);
        expect(esito.candidati.single.id, candidatoId);
        expect((await copia(due, copiaId))?.scansioneId, scansioneId);
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

    test(
      'le dimensioni della collezione sono le righe del primo download',
      () async {
        final a = await account();
        final uno = await device(a);
        final operaId = await uno.repo.aggiungiOpera(title: 'Maus');
        final edizioneId = await uno.repo.aggiungiEdizione(operaId: operaId);
        for (var i = 0; i < 2; i++) {
          await uno.repo.aggiungiCopia(
            edizioneId: edizioneId,
            status: StatoCopia.posseduta,
          );
        }
        await uno.sync.sincronizza();

        final due = await device(a);
        final dimensioni = await CanaleSupabase(
          due.client,
          userId: a.userId,
        ).dimensioni();
        final esito = await due.sync.sincronizza();

        expect(dimensioni.fumetti, 2);
        expect(dimensioni.righe, esito.ricevute);
      },
    );

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
      expect(esito.titoli, {
        (tabella: 'copie', id: copiaId): 'Maus',
        (tabella: 'copie', id: orfana): 'Maus',
      });
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
  _Device(this.db, this.client, this.cartella, this.sync)
    : repo = DriftComicsRepository(db);

  final AppDatabase db;
  final SupabaseClient client;

  /// La cartella del Profilo, base dei percorsi delle immagini.
  final Directory cartella;
  final Sincronizzatore sync;
  final DriftComicsRepository repo;
}
