import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  /// Crea un'opera + un'edizione (opzionalmente in una serie, con un
  /// numero) e vi aggiunge una copia con lo [status] dato. Ritorna l'id
  /// dell'edizione.
  Future<int> edizioneConCopia({
    required String titolo,
    required StatoCopia status,
    int? serieId,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    double? purchasePrice,
    DateTime? createdAt,
    DateTime? edizioneCreatedAt,
  }) async {
    final operaId = await repo.aggiungiOpera(title: titolo);
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      issueNumber: issueNumber,
      issueNumberLabel: issueNumberLabel,
      coverImage: coverImage,
      createdAt: edizioneCreatedAt,
    );
    await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: status,
      purchasePrice: purchasePrice,
      createdAt: createdAt,
    );
    return edizioneId;
  }

  group('collezione vuota', () {
    test('tutti i KPI sono zero, nessuna eccezione', () async {
      final kpis = await repo.watchDashboardKpis().first;

      expect(kpis.totaleCopie, 0);
      expect(kpis.numeroSerie, 0);
      expect(kpis.serieComplete, 0);
      expect(kpis.duplicati, 0);
      expect(kpis.numeriMancanti, 0);
      expect(kpis.spesoFinora, 0.0);
      expect(kpis.aggiuntiMeseCorrente, 0);
    });

    test('nessuna serie incompleta', () async {
      expect(await repo.watchSerieIncomplete().first, isEmpty);
    });
  });

  group('N fumetti (totale copie)', () {
    test('conta posseduta e prestata, non venduta o persa', () async {
      final operaId = await repo.aggiungiOpera(title: 'Opera');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      for (final status in StatoCopia.values) {
        await repo.aggiungiCopia(edizioneId: edizioneId, status: status);
      }

      final kpis = await repo.watchDashboardKpis().first;

      // posseduta + prestata contano, venduta e persa no (CONTEXT.md:
      // "prestata conta ancora come posseduta").
      expect(kpis.totaleCopie, 2);
    });
  });

  group('N serie', () {
    test('conta solo serie con almeno un edizione posseduta', () async {
      final serieId = await repo.aggiungiSerie(name: 'Con edizione posseduta');
      await edizioneConCopia(
        titolo: 'A',
        serieId: serieId,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );

      final serieSenzaPossesso = await repo.aggiungiSerie(name: 'Solo venduta');
      await edizioneConCopia(
        titolo: 'B',
        serieId: serieSenzaPossesso,
        issueNumber: 1,
        status: StatoCopia.venduta,
      );

      // Volume unico: edizione senza serie non entra nel conteggio.
      final operaOneShot = await repo.aggiungiOpera(title: 'One-shot');
      final edizioneOneShot = await repo.aggiungiEdizione(
        operaId: operaOneShot,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneOneShot,
        status: StatoCopia.posseduta,
      );

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.numeroSerie, 1);
    });

    test('più edizioni della stessa collana riusano la stessa Serie', () async {
      final serieId1 = await repo.aggiungiSerie(name: 'Batman');
      final serieId2 = await repo.aggiungiSerie(
        name: 'batman',
      ); // stesso nome, case diverso
      final serieId3 = await repo.aggiungiSerie(
        name: '  Batman  ',
      ); // spazi extra

      expect(serieId2, serieId1);
      expect(serieId3, serieId1);

      for (var i = 1; i <= 3; i++) {
        await edizioneConCopia(
          titolo: 'Batman #$i',
          serieId: serieId1,
          issueNumber: i,
          status: StatoCopia.posseduta,
        );
      }

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.numeroSerie, 1);
    });
  });

  group('unisciSerieDuplicate', () {
    test(
      'unisce Serie con lo stesso nome create prima della deduplica, riassegna le Edizioni '
      'alla superstite (id più basso) e ne conserva "numeri totali"/ISSN se noti',
      () async {
        // Simula i dati creati prima del fix su `aggiungiSerie`: più righe
        // `serie` con lo stesso nome, inserite direttamente (bypassando la
        // deduplica ora in `aggiungiSerie`).
        final serieVecchia = await db
            .into(db.serieTable)
            .insert(SerieTableCompanion.insert(name: 'Batman'));
        final serieNuova = await db
            .into(db.serieTable)
            .insert(
              SerieTableCompanion.insert(
                name: 'batman', // case diverso, stesso nome
                totalIssues: const Value(12),
              ),
            );

        final edizioneVecchia = await edizioneConCopia(
          titolo: 'Batman #1',
          serieId: serieVecchia,
          issueNumber: 1,
          status: StatoCopia.posseduta,
        );
        final edizioneNuova = await edizioneConCopia(
          titolo: 'Batman #2',
          serieId: serieNuova,
          issueNumber: 2,
          status: StatoCopia.posseduta,
        );

        await repo.unisciSerieDuplicate();

        final serieRimaste = await db.select(db.serieTable).get();
        expect(serieRimaste, hasLength(1));
        expect(serieRimaste.single.id, serieVecchia);
        expect(
          serieRimaste.single.totalIssues,
          12,
        ); // recuperato dalla duplicata

        final edizioni = await db.select(db.edizioni).get();
        expect(
          edizioni.map((e) => e.serieId),
          everyElement(serieVecchia),
          reason: 'entrambe le Edizioni devono puntare alla Serie superstite',
        );
        expect(
          edizioni.map((e) => e.id),
          containsAll([edizioneVecchia, edizioneNuova]),
        );

        final kpis = await repo.watchDashboardKpis().first;
        expect(kpis.numeroSerie, 1);
      },
    );

    test('non tocca Serie con nomi diversi', () async {
      final serieA = await repo.aggiungiSerie(name: 'Batman');
      final serieB = await db
          .into(db.serieTable)
          .insert(SerieTableCompanion.insert(name: 'Superman'));

      await repo.unisciSerieDuplicate();

      final serieRimaste = await db.select(db.serieTable).get();
      expect(serieRimaste.map((s) => s.id), containsAll([serieA, serieB]));
      expect(serieRimaste, hasLength(2));
    });

    test('è idempotente: una seconda chiamata non rompe nulla', () async {
      await db
          .into(db.serieTable)
          .insert(SerieTableCompanion.insert(name: 'Batman'));
      await db
          .into(db.serieTable)
          .insert(SerieTableCompanion.insert(name: 'Batman'));

      await repo.unisciSerieDuplicate();
      await repo.unisciSerieDuplicate();

      final serieRimaste = await db.select(db.serieTable).get();
      expect(serieRimaste, hasLength(1));
    });
  });

  group('N duplicati', () {
    test('edizione con due copie possedute conta come duplicato', () async {
      final operaId = await repo.aggiungiOpera(title: 'Opera duplicata');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.duplicati, 1);
    });

    test('due copie di cui una venduta non è un duplicato', () async {
      final operaId = await repo.aggiungiOpera(title: 'Opera non duplicata');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.venduta,
      );

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.duplicati, 0);
    });
  });

  group('numeri mancanti e serie complete', () {
    test(
      'serie con buchi interni: variant copre il buco del suo numero',
      () async {
        final serieId = await repo.aggiungiSerie(
          name: 'Spider-Man',
          totalIssues: 10,
        );
        for (final n in [1, 2, 3, 5, 6]) {
          await edizioneConCopia(
            titolo: 'Spider-Man #$n',
            serieId: serieId,
            issueNumber: n,
            status: StatoCopia.posseduta,
          );
        }
        // #10 posseduto solo come variant: copre comunque il buco del #10.
        await edizioneConCopia(
          titolo: 'Spider-Man #10 Variant',
          serieId: serieId,
          issueNumber: 10,
          issueNumberLabel: '10 Variant',
          status: StatoCopia.posseduta,
        );

        final kpis = await repo.watchDashboardKpis().first;
        expect(
          kpis.numeriMancanti,
          4,
        ); // 4, 7, 8, 9 — il #10 è coperto dalla variant
      },
    );

    test('serie completa (nessun numero mancante)', () async {
      final serieId = await repo.aggiungiSerie(
        name: 'Dylan Dog',
        totalIssues: 3,
      );
      for (final n in [1, 2, 3]) {
        await edizioneConCopia(
          titolo: 'Dylan Dog #$n',
          serieId: serieId,
          issueNumber: n,
          status: StatoCopia.posseduta,
        );
      }
      // Seconda copia del #3: duplicato, non un buco.
      final operaId = await repo.aggiungiOpera(title: 'Dylan Dog #3 bis');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
        issueNumber: 3,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.numeriMancanti, 0);
      expect(kpis.serieComplete, 1);
    });

    test(
      'serie senza "numeri totali" non è valutabile: esclusa da entrambi i KPI',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Senza totale');
        await edizioneConCopia(
          titolo: 'X #1',
          serieId: serieId,
          issueNumber: 1,
          status: StatoCopia.posseduta,
        );

        final kpis = await repo.watchDashboardKpis().first;
        expect(kpis.numeriMancanti, 0);
        expect(kpis.serieComplete, 0);
        expect(await repo.watchSerieIncomplete().first, isEmpty);
      },
    );
  });

  group('serie incomplete con percentuale', () {
    test(
      'elenca solo le serie con numeri totali noti e mancanti, con la percentuale',
      () async {
        final kaiju = await repo.aggiungiSerie(
          name: 'Kaiju Bianco',
          totalIssues: 42,
        );
        for (final n in [1, 2, 3, 5, 6, 10]) {
          await edizioneConCopia(
            titolo: 'Kaiju Bianco #$n',
            serieId: kaiju,
            issueNumber: n,
            status: StatoCopia.posseduta,
          );
        }

        // Serie completa: non deve comparire fra le incomplete.
        final dylanDog = await repo.aggiungiSerie(
          name: 'Dylan Dog',
          totalIssues: 1,
        );
        await edizioneConCopia(
          titolo: 'Dylan Dog #1',
          serieId: dylanDog,
          issueNumber: 1,
          status: StatoCopia.posseduta,
        );

        final incomplete = await repo.watchSerieIncomplete().first;

        expect(incomplete, hasLength(1));
        final serie = incomplete.single;
        expect(serie.nome, 'Kaiju Bianco');
        expect(serie.numeriTotali, 42);
        expect(serie.numeriPosseduti, 6);
        expect(serie.numeriMancanti, [
          4,
          7,
          8,
          9,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19,
          20,
          21,
          22,
          23,
          24,
          25,
          26,
          27,
          28,
          29,
          30,
          31,
          32,
          33,
          34,
          35,
          36,
          37,
          38,
          39,
          40,
          41,
          42,
        ]);
        expect(serie.percentualeCompletamento, closeTo(6 / 42, 0.0001));
      },
    );
  });

  group('watchSerieLista (§11)', () {
    test('collezione vuota: nessuna sezione', () async {
      final lista = await repo.watchSerieLista().first;
      expect(lista.isEmpty, isTrue);
      expect(lista.incomplete, isEmpty);
      expect(lista.complete, isEmpty);
      expect(lista.senzaTotale, isEmpty);
    });

    test('raggruppa nelle tre sezioni e ordina ciascuna secondo #97', () async {
      // Incomplete, in ordine di % di completamento crescente attesa:
      // "B" 1/4 (25%), "A" 1/2 (50%).
      final serieA = await repo.aggiungiSerie(
        name: 'A incompleta',
        totalIssues: 2,
      );
      await edizioneConCopia(
        titolo: 'A #1',
        serieId: serieA,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );
      final serieB = await repo.aggiungiSerie(
        name: 'B incompleta',
        totalIssues: 4,
      );
      await edizioneConCopia(
        titolo: 'B #1',
        serieId: serieB,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );

      // Complete, alfabetiche.
      final serieZeta = await repo.aggiungiSerie(
        name: 'Zeta completa',
        totalIssues: 1,
      );
      await edizioneConCopia(
        titolo: 'Zeta #1',
        serieId: serieZeta,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );
      final serieAlfa = await repo.aggiungiSerie(
        name: 'Alfa completa',
        totalIssues: 1,
      );
      await edizioneConCopia(
        titolo: 'Alfa #1',
        serieId: serieAlfa,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );

      // Senza numero totale, alfabetiche.
      final serieRho = await repo.aggiungiSerie(name: 'Rho senza totale');
      await edizioneConCopia(
        titolo: 'Rho #1',
        serieId: serieRho,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );
      final serieBeta = await repo.aggiungiSerie(name: 'Beta senza totale');
      await edizioneConCopia(
        titolo: 'Beta #1',
        serieId: serieBeta,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );

      final lista = await repo.watchSerieLista().first;

      expect(lista.incomplete.map((s) => s.nome), [
        'B incompleta',
        'A incompleta',
      ]);
      expect(lista.complete.map((s) => s.nome), [
        'Alfa completa',
        'Zeta completa',
      ]);
      expect(lista.senzaTotale.map((s) => s.nome), [
        'Beta senza totale',
        'Rho senza totale',
      ]);
    });

    test(
      'una serie senza edizioni possedute non compare (stesso filtro del KPI "serie")',
      () async {
        final serieId = await repo.aggiungiSerie(
          name: 'Solo venduta',
          totalIssues: 3,
        );
        await edizioneConCopia(
          titolo: 'Solo venduta #1',
          serieId: serieId,
          issueNumber: 1,
          status: StatoCopia.venduta,
        );

        final lista = await repo.watchSerieLista().first;
        expect(lista.isEmpty, isTrue);
      },
    );

    test('ogni riga porta la cover della prima Edizione posseduta', () async {
      final serieId = await repo.aggiungiSerie(
        name: 'Con cover',
        totalIssues: 1,
      );
      await edizioneConCopia(
        titolo: 'Con cover #1',
        serieId: serieId,
        issueNumber: 1,
        status: StatoCopia.posseduta,
        coverImage: 'https://example.com/cover.jpg',
      );

      final lista = await repo.watchSerieLista().first;
      expect(lista.complete.single.coverImage, 'https://example.com/cover.jpg');
    });
  });

  group('watchSerieDettaglio (§11)', () {
    test('serie inesistente: null', () async {
      expect(await repo.watchSerieDettaglio(999999).first, isNull);
    });

    test('numeri posseduti, editore/anno derivati e duplicati', () async {
      final serieId = await repo.aggiungiSerie(
        name: 'Kaiju Bianco',
        totalIssues: 5,
        issn: '1122-3344',
      );

      final opera1 = await repo.aggiungiOpera(title: 'Kaiju Bianco #1');
      final edizione1 = await repo.aggiungiEdizione(
        operaId: opera1,
        serieId: serieId,
        issueNumber: 1,
        publisher: 'Bao Publishing',
        year: 2019,
      );
      await repo.aggiungiCopia(
        edizioneId: edizione1,
        status: StatoCopia.posseduta,
      );
      // Seconda copia dello stesso #1: duplicato.
      await repo.aggiungiCopia(
        edizioneId: edizione1,
        status: StatoCopia.posseduta,
      );

      final opera2 = await repo.aggiungiOpera(title: 'Kaiju Bianco #2');
      final edizione2 = await repo.aggiungiEdizione(
        operaId: opera2,
        serieId: serieId,
        issueNumber: 2,
        publisher: 'Bao Publishing',
        year: 2018,
      );
      await repo.aggiungiCopia(
        edizioneId: edizione2,
        status: StatoCopia.posseduta,
      );

      final opera3 = await repo.aggiungiOpera(title: 'Kaiju Bianco #3');
      final edizione3 = await repo.aggiungiEdizione(
        operaId: opera3,
        serieId: serieId,
        issueNumber: 3,
        publisher: 'Altro editore',
      );
      await repo.aggiungiCopia(
        edizioneId: edizione3,
        status: StatoCopia.posseduta,
      );

      final dettaglio = await repo.watchSerieDettaglio(serieId).first;

      expect(dettaglio, isNotNull);
      expect(dettaglio!.nome, 'Kaiju Bianco');
      expect(dettaglio.issn, '1122-3344');
      expect(dettaglio.numeriTotali, 5);
      expect(dettaglio.numeriPosseduti, [1, 2, 3]);
      expect(dettaglio.numeriMancanti, [4, 5]);
      expect(dettaglio.completa, isFalse);
      expect(dettaglio.duplicati, 1);
      expect(dettaglio.publisher, 'Bao Publishing'); // più frequente (2 su 3)
      expect(
        dettaglio.annoInizio,
        2018,
      ); // minimo fra le edizioni con anno noto
    });

    test(
      'senza numero totale: numeriMancanti vuota e non è mai completa',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Senza totale');
        final opera = await repo.aggiungiOpera(title: 'X #1');
        final edizione = await repo.aggiungiEdizione(
          operaId: opera,
          serieId: serieId,
          issueNumber: 1,
        );
        await repo.aggiungiCopia(
          edizioneId: edizione,
          status: StatoCopia.posseduta,
        );

        final dettaglio = await repo.watchSerieDettaglio(serieId).first;

        expect(dettaglio!.numeriTotali, isNull);
        expect(dettaglio.numeriPosseduti, [1]);
        expect(dettaglio.numeriMancanti, isEmpty);
        expect(dettaglio.completa, isFalse);
      },
    );

    test(
      'cover di default: la prima Edizione posseduta per numero, non per data di catalogazione',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Cover default');
        // Il #2 è stato catalogato per primo (createdAt più vecchio) ma il
        // #1 ha un numero più basso — vince il numero, non l'ordine di
        // inserimento.
        await edizioneConCopia(
          titolo: 'X #2',
          serieId: serieId,
          issueNumber: 2,
          status: StatoCopia.posseduta,
          coverImage: 'https://example.com/2.jpg',
          edizioneCreatedAt: DateTime(2020),
        );
        await edizioneConCopia(
          titolo: 'X #1',
          serieId: serieId,
          issueNumber: 1,
          status: StatoCopia.posseduta,
          coverImage: 'https://example.com/1.jpg',
          edizioneCreatedAt: DateTime(2021),
        );

        final dettaglio = await repo.watchSerieDettaglio(serieId).first;
        expect(dettaglio!.coverImage, 'https://example.com/1.jpg');
        expect(dettaglio.coverImageOverride, isNull);
      },
    );

    test(
      'cover di default: ignora le Edizioni senza copie possedute',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Cover default 2');
        await edizioneConCopia(
          titolo: 'Y #1',
          serieId: serieId,
          issueNumber: 1,
          status: StatoCopia.venduta,
          coverImage: 'https://example.com/venduta.jpg',
          edizioneCreatedAt: DateTime(2019),
        );
        await edizioneConCopia(
          titolo: 'Y #2',
          serieId: serieId,
          issueNumber: 2,
          status: StatoCopia.posseduta,
          coverImage: 'https://example.com/posseduta.jpg',
          edizioneCreatedAt: DateTime(2022),
        );

        final dettaglio = await repo.watchSerieDettaglio(serieId).first;
        expect(dettaglio!.coverImage, 'https://example.com/posseduta.jpg');
      },
    );

    test('cover override: vince sempre sulla cover di default', () async {
      final serieId = await repo.aggiungiSerie(name: 'Cover override');
      await edizioneConCopia(
        titolo: 'Z #1',
        serieId: serieId,
        issueNumber: 1,
        status: StatoCopia.posseduta,
        coverImage: 'https://example.com/default.jpg',
      );
      await repo.aggiornaSerie(
        id: serieId,
        name: 'Cover override',
        coverImage: 'https://example.com/scelta.jpg',
      );

      final dettaglio = await repo.watchSerieDettaglio(serieId).first;
      expect(dettaglio!.coverImage, 'https://example.com/scelta.jpg');
      expect(dettaglio.coverImageOverride, 'https://example.com/scelta.jpg');
    });
  });

  group('aggiornaSerie (§11, deciso su #99)', () {
    test(
      'scrive nome/numero totale/issn — finora popolati solo da aggiungiSerie',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Ombre di Marte');

        await repo.aggiornaSerie(
          id: serieId,
          name: 'Ombre di Marte',
          totalIssues: 16,
          issn: '5566-7788',
        );

        final dettaglio = await repo.watchSerieDettaglio(serieId).first;
        expect(dettaglio!.numeriTotali, 16);
        expect(dettaglio.issn, '5566-7788');
      },
    );

    test(
      'totale/issn null: torna una serie senza numero totale/issn',
      () async {
        final serieId = await repo.aggiungiSerie(
          name: 'Con totale',
          totalIssues: 10,
          issn: '1111-2222',
        );

        await repo.aggiornaSerie(id: serieId, name: 'Con totale');

        final dettaglio = await repo.watchSerieDettaglio(serieId).first;
        expect(dettaglio!.numeriTotali, isNull);
        expect(dettaglio.issn, isNull);
      },
    );

    test(
      "coverImage null: azzera l'override, torna alla cover di default",
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Ombre di Marte');
        await edizioneConCopia(
          titolo: 'Ombre #1',
          serieId: serieId,
          issueNumber: 1,
          status: StatoCopia.posseduta,
          coverImage: 'https://example.com/default.jpg',
        );
        await repo.aggiornaSerie(
          id: serieId,
          name: 'Ombre di Marte',
          coverImage: 'https://example.com/scelta.jpg',
        );
        expect(
          (await repo.watchSerieDettaglio(serieId).first)!.coverImageOverride,
          isNotNull,
        );

        await repo.aggiornaSerie(id: serieId, name: 'Ombre di Marte');

        final dettaglio = await repo.watchSerieDettaglio(serieId).first;
        expect(dettaglio!.coverImageOverride, isNull);
        expect(dettaglio.coverImage, 'https://example.com/default.jpg');
      },
    );
  });

  group('edizioniPosseduteDiSerie / coverDefaultDiSerie', () {
    test(
      'edizioniPosseduteDiSerie: solo possedute, ordinate per numero poi data',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Variant');
        await edizioneConCopia(
          titolo: 'V #4 variant',
          serieId: serieId,
          issueNumber: 4,
          issueNumberLabel: '4 Variant',
          status: StatoCopia.posseduta,
          edizioneCreatedAt: DateTime(2022),
        );
        await edizioneConCopia(
          titolo: 'V #4',
          serieId: serieId,
          issueNumber: 4,
          issueNumberLabel: '4',
          status: StatoCopia.posseduta,
          edizioneCreatedAt: DateTime(2021),
        );
        await edizioneConCopia(
          titolo: 'V #1',
          serieId: serieId,
          issueNumber: 1,
          status: StatoCopia.posseduta,
        );
        await edizioneConCopia(
          titolo: 'V #2 venduta',
          serieId: serieId,
          issueNumber: 2,
          status: StatoCopia.venduta,
        );

        final edizioni = await repo.edizioniPosseduteDiSerie(serieId);

        expect(edizioni.map((e) => e.issueNumberLabel ?? '${e.issueNumber}'), [
          '1',
          '4', // createdAt 2021, prima del variant
          '4 Variant',
        ]);
      },
    );

    test('coverDefaultDiSerie: null se nessuna Edizione posseduta', () async {
      final serieId = await repo.aggiungiSerie(name: 'Vuota');
      expect(await repo.coverDefaultDiSerie(serieId), isNull);
    });
  });

  group('€ speso finora', () {
    test(
      'somma i prezzi delle copie possedute, ignora quelle senza prezzo',
      () async {
        final operaConPrezzo = await repo.aggiungiOpera(title: 'Con prezzo');
        final edizioneConPrezzo = await repo.aggiungiEdizione(
          operaId: operaConPrezzo,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneConPrezzo,
          status: StatoCopia.posseduta,
          purchasePrice: 12.5,
        );

        final operaSenzaPrezzo = await repo.aggiungiOpera(
          title: 'Senza prezzo',
        );
        final edizioneSenzaPrezzo = await repo.aggiungiEdizione(
          operaId: operaSenzaPrezzo,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneSenzaPrezzo,
          status: StatoCopia.posseduta,
        );

        final operaVenduta = await repo.aggiungiOpera(
          title: 'Venduta con prezzo',
        );
        final edizioneVenduta = await repo.aggiungiEdizione(
          operaId: operaVenduta,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneVenduta,
          status: StatoCopia.venduta,
          purchasePrice: 999,
        );

        final kpis = await repo.watchDashboardKpis().first;
        expect(kpis.spesoFinora, closeTo(12.5, 0.0001));
      },
    );
  });

  group('N aggiunti nel mese corrente', () {
    test(
      'conta solo le copie possedute create nel mese solare corrente',
      () async {
        final ora = DateTime.now();
        final meseScorso = DateTime(ora.year, ora.month - 1, 15);

        final operaId = await repo.aggiungiOpera(title: 'Opera');
        final edizioneQuestoMese = await repo.aggiungiEdizione(
          operaId: operaId,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneQuestoMese,
          status: StatoCopia.posseduta,
          createdAt: ora,
        );

        final edizioneMeseScorso = await repo.aggiungiEdizione(
          operaId: operaId,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneMeseScorso,
          status: StatoCopia.posseduta,
          createdAt: meseScorso,
        );

        final kpis = await repo.watchDashboardKpis().first;
        expect(kpis.aggiuntiMeseCorrente, 1);
      },
    );
  });

  group('aggiunti di recente', () {
    test('nessuna copia posseduta: lista vuota', () async {
      expect(await repo.watchAggiuntiDiRecente().first, isEmpty);
    });

    test('conta posseduta e prestata, non venduta o persa', () async {
      for (final status in StatoCopia.values) {
        await edizioneConCopia(titolo: status.name, status: status);
      }

      final recenti = await repo.watchAggiuntiDiRecente().first;
      expect(
        recenti.map((c) => c.titolo),
        unorderedEquals([
          StatoCopia.posseduta.name,
          StatoCopia.prestata.name,
        ]),
      );
    });

    test('ordina per data di aggiunta, più recente prima', () async {
      await edizioneConCopia(
        titolo: 'Meno recente',
        status: StatoCopia.posseduta,
        createdAt: DateTime(2025),
      );
      await edizioneConCopia(
        titolo: 'Più recente',
        status: StatoCopia.posseduta,
        createdAt: DateTime(2026),
      );

      final recenti = await repo.watchAggiuntiDiRecente().first;
      expect(recenti.map((c) => c.titolo), ['Più recente', 'Meno recente']);
    });

    test('porta titolo, editore e numero da opera/edizione', () async {
      final operaId = await repo.aggiungiOpera(title: 'Notturno');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        publisher: 'Kodama Manga',
        issueNumber: 4,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final recente = (await repo.watchAggiuntiDiRecente().first).single;
      expect(recente.edizioneId, edizioneId);
      expect(recente.titolo, 'Notturno');
      expect(recente.editore, 'Kodama Manga');
      expect(recente.numero, 4);
      expect(recente.numeroVisualizzato, '#4');
    });

    test('porta anche il nome della serie, se l\'Edizione ne ha una', () async {
      final serieId = await repo.aggiungiSerie(name: 'Dylan Dog');
      final operaId = await repo.aggiungiOpera(title: 'Dylan Dog 407');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final recente = (await repo.watchAggiuntiDiRecente().first).single;
      expect(recente.serieName, 'Dylan Dog');
    });

    test(
      'un\'Edizione senza Serie ha serieName null',
      () async {
        final operaId = await repo.aggiungiOpera(title: 'One-shot');
        final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        final recente = (await repo.watchAggiuntiDiRecente().first).single;
        expect(recente.serieName, isNull);
      },
    );

    test(
      'numero testuale ("4 Variant") ha priorità sul numero intero in visualizzazione',
      () async {
        final operaId = await repo.aggiungiOpera(title: 'Notturno');
        final edizioneId = await repo.aggiungiEdizione(
          operaId: operaId,
          issueNumber: 4,
          issueNumberLabel: '4 Variant',
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        final recente = (await repo.watchAggiuntiDiRecente().first).single;
        expect(recente.numeroVisualizzato, '#4 Variant');
      },
    );

    test('coverImage null se assente', () async {
      final operaId = await repo.aggiungiOpera(title: 'Senza cover');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final recente = (await repo.watchAggiuntiDiRecente().first).single;
      expect(recente.coverImage, null);
    });

    // La risoluzione di un coverImage non-null (relativo, assoluto
    // "vecchio stile", URL remoto, o assoluto senza sottocartella nota) è
    // coperta dai test dedicati sotto — vedi `percorso_locale.dart` sul
    // perché il valore grezzo in DB non basta mai da solo.

    test(
      'URL remoto: passa invariato, nessuna dipendenza da path_provider',
      () async {
        final operaId = await repo.aggiungiOpera(title: 'Cover remota');
        final edizioneId = await repo.aggiungiEdizione(
          operaId: operaId,
          coverImage: 'https://comicvine.example/cover.jpg',
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        // `repo` (dal `setUp`) usa il `CopertinaDownloader` di default, la
        // cui `baseDirectory` è il vero `path_provider` — non mockato in
        // questo ambiente di test. Se questa chiamata anche solo la
        // invocasse, il test fallirebbe con `MissingPluginException`.
        final recente = (await repo.watchAggiuntiDiRecente().first).single;
        expect(recente.coverImage, 'https://comicvine.example/cover.jpg');
      },
    );

    test(
      'percorso assoluto senza sottocartella nota: passa invariato, nessuna '
      'dipendenza da path_provider',
      () async {
        final operaId = await repo.aggiungiOpera(title: 'Cover di test');
        final edizioneId = await repo.aggiungiEdizione(
          operaId: operaId,
          coverImage: '${Directory.systemTemp.path}/una_cover.png',
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        final recente = (await repo.watchAggiuntiDiRecente().first).single;
        expect(
          recente.coverImage,
          '${Directory.systemTemp.path}/una_cover.png',
        );
      },
    );

    test(
      'percorso relativo (salvato dopo la migrazione): risolto sulla '
      'cartella base corrente',
      () async {
        final tempBase = await Directory.systemTemp.createTemp(
          'comics_repository_cover_relativo_',
        );
        addTearDown(() => tempBase.delete(recursive: true));
        final repoConBase = ComicsRepository(
          db,
          copertinaDownloader: CopertinaDownloader(
            baseDirectory: () async => tempBase,
          ),
        );

        final operaId = await repoConBase.aggiungiOpera(
          title: 'Con cover relativa',
        );
        final edizioneId = await repoConBase.aggiungiEdizione(
          operaId: operaId,
          coverImage: p.join('copertine', '1.jpg'),
        );
        await repoConBase.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        final recente =
            (await repoConBase.watchAggiuntiDiRecente().first).single;
        expect(recente.coverImage, p.join(tempBase.path, 'copertine', '1.jpg'));
      },
    );

    test(
      'percorso assoluto "vecchio stile" (container di un\'installazione '
      'precedente): ricostruito sulla cartella base corrente — bug '
      'osservato: la cover spariva dopo un nuovo `flutter run`',
      () async {
        final tempBase = await Directory.systemTemp.createTemp(
          'comics_repository_cover_legacy_',
        );
        addTearDown(() => tempBase.delete(recursive: true));
        final repoConBase = ComicsRepository(
          db,
          copertinaDownloader: CopertinaDownloader(
            baseDirectory: () async => tempBase,
          ),
        );

        final operaId = await repoConBase.aggiungiOpera(
          title: 'Con cover legacy',
        );
        // Simula un percorso persistito con un container ormai inesistente
        // (installazione precedente): assoluto, con lo stesso suffisso
        // relativo `copertine/<file>` che iOS migra fisicamente al
        // riavvio, ma sotto un prefisso diverso da `tempBase`.
        final edizioneId = await repoConBase.aggiungiEdizione(
          operaId: operaId,
          coverImage:
              '/var/mobile/Containers/Data/Application/VECCHIO-UUID/'
              'Library/Application Support/copertine/1.jpg',
        );
        await repoConBase.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        final recente =
            (await repoConBase.watchAggiuntiDiRecente().first).single;
        expect(recente.coverImage, p.join(tempBase.path, 'copertine', '1.jpg'));
      },
    );
  });

  group('watchIndiceCollezione (§9, indice leggero deciso su #113)', () {
    test(
      'solo le Edizioni con almeno una copia posseduta/prestata compaiono',
      () async {
        await edizioneConCopia(
          titolo: 'Posseduta',
          status: StatoCopia.posseduta,
        );
        await edizioneConCopia(titolo: 'Prestata', status: StatoCopia.prestata);
        await edizioneConCopia(titolo: 'Venduta', status: StatoCopia.venduta);
        await edizioneConCopia(titolo: 'Persa', status: StatoCopia.persa);

        final indice = await repo.watchIndiceCollezione().first;

        expect(indice.map((e) => e.titolo).toSet(), {
          'Posseduta',
          'Prestata',
        });
      },
    );

    test(
      'il badge duplicato conta le copie possedute/prestate, non vendute/perse',
      () async {
        final operaId = await repo.aggiungiOpera(title: 'Con copie miste');
        final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.prestata,
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.venduta,
        );

        final edizione = (await repo.watchIndiceCollezione().first).single;

        expect(edizione.numeroCopie, 2);
      },
    );

    test(
      "serie, editore, anno, formato e lingua risolti dai campi dell'Edizione",
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Dylan Dog');
        final operaId = await repo.aggiungiOpera(title: 'Dylan Dog 407');
        final edizioneId = await repo.aggiungiEdizione(
          operaId: operaId,
          serieId: serieId,
          publisher: 'Bonelli',
          year: 2021,
          format: FormatoEdizione.bonellide,
          language: 'Italiano',
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );

        final edizione = (await repo.watchIndiceCollezione().first).single;

        expect(edizione.serieName, 'Dylan Dog');
        expect(edizione.publisher, 'Bonelli');
        expect(edizione.year, 2021);
        expect(edizione.format, FormatoEdizione.bonellide);
        expect(edizione.language, 'Italiano');
      },
    );

    test(
      'un\'Edizione senza Serie ha serieName null (asse "Senza serie" a carico della UI)',
      () async {
        final edizioneId = await edizioneConCopia(
          titolo: 'One-shot',
          status: StatoCopia.posseduta,
        );
        final edizione = (await repo.watchIndiceCollezione().first).firstWhere(
          (e) => e.edizioneId == edizioneId,
        );

        expect(edizione.serieName, isNull);
      },
    );

    test('autori, personaggi, tag e generi aggregati per Edizione', () async {
      final operaId = await repo.aggiungiOpera(title: 'Watchmen');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final autoreId = await repo.aggiungiCreator('Alan Moore');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: autoreId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      final personaggioId = await repo.aggiungiCharacter('Rorschach');
      await repo.collegaCharacterAEdizione(
        edizioneId: edizioneId,
        characterId: personaggioId,
      );

      final tagId = await repo.aggiungiTag('capolavoro');
      await repo.collegaTagAEdizione(edizioneId: edizioneId, tagId: tagId);

      await repo.impostaGeneriEdizione(
        edizioneId: edizioneId,
        generi: {GenereEdizione.supereroi, GenereEdizione.drammatico},
      );

      final edizione = (await repo.watchIndiceCollezione().first).single;

      expect(edizione.autori, ['Alan Moore']);
      expect(edizione.personaggi, ['Rorschach']);
      expect(edizione.tag, ['capolavoro']);
      expect(edizione.generi.toSet(), {
        GenereEdizione.supereroi,
        GenereEdizione.drammatico,
      });
    });

    test(
      'gli assi per-Copia (stato di lettura, condizione, posizione) riflettono solo le copie '
      'possedute/prestate — regola "almeno una copia" (#80)',
      () async {
        final operaId = await repo.aggiungiOpera(title: 'Batman: Anno Uno');
        final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
          readingStatus: StatoLettura.letto,
          condition: CondizioneCopia.good,
          location: 'Scaffale A',
        );
        await repo.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.venduta,
          readingStatus: StatoLettura.daLeggere,
          condition: CondizioneCopia.poor,
          location: 'Scatola 1',
        );

        final edizione = (await repo.watchIndiceCollezione().first).single;

        expect(edizione.copiePossedute, hasLength(1));
        expect(
          edizione.copiePossedute.single.readingStatus,
          StatoLettura.letto,
        );
        expect(edizione.copiePossedute.single.condition, CondizioneCopia.good);
        expect(edizione.copiePossedute.single.location, 'Scaffale A');
      },
    );
  });

  group(
    'watchHydratazioneCollezione (§9, hydration paginata deciso su #113)',
    () {
      test('lista di id vuota produce una mappa vuota senza query', () async {
        final mappa = await repo.watchHydratazioneCollezione(const []).first;

        expect(mappa, isEmpty);
      });

      test('risolve la cover delle sole Edizioni richieste', () async {
        final dentroId = await edizioneConCopia(
          titolo: 'Dentro la finestra',
          status: StatoCopia.posseduta,
          coverImage: 'https://example.com/dentro.jpg',
        );
        final fuoriId = await edizioneConCopia(
          titolo: 'Fuori dalla finestra',
          status: StatoCopia.posseduta,
          coverImage: 'https://example.com/fuori.jpg',
        );

        final mappa = await repo.watchHydratazioneCollezione([dentroId]).first;

        expect(mappa, {dentroId: 'https://example.com/dentro.jpg'});
        expect(mappa.containsKey(fuoriId), isFalse);
      });

      test(
        'un\'Edizione posseduta senza cover impostata compare con valore null',
        () async {
          final edizioneId = await edizioneConCopia(
            titolo: 'Senza cover',
            status: StatoCopia.posseduta,
          );

          final mappa = await repo.watchHydratazioneCollezione([
            edizioneId,
          ]).first;

          expect(mappa, {edizioneId: null});
        },
      );

      test(
        'un\'Edizione non (più) posseduta è omessa dalla mappa, mai presente '
        'con valore null',
        () async {
          final venduta = await edizioneConCopia(
            titolo: 'Venduta',
            status: StatoCopia.venduta,
            coverImage: 'https://example.com/venduta.jpg',
          );
          const inesistente = 999999;

          final mappa = await repo.watchHydratazioneCollezione([
            venduta,
            inesistente,
          ]).first;

          expect(mappa, isEmpty);
        },
      );

      test(
        'reattiva alla nuova copertina di un\'Edizione già emessa',
        () async {
          final operaId = await repo.aggiungiOpera(title: 'Reattiva');
          final edizioneId = await repo.aggiungiEdizione(
            operaId: operaId,
            coverImage: 'https://example.com/vecchia.jpg',
          );
          await repo.aggiungiCopia(
            edizioneId: edizioneId,
            status: StatoCopia.posseduta,
          );

          final emissioni = <Map<int, String?>>[];
          final subscription = repo
              .watchHydratazioneCollezione([edizioneId])
              .listen(emissioni.add);
          addTearDown(subscription.cancel);
          await pumpEventQueue();

          await (db.update(
            db.edizioni,
          )..where((e) => e.id.equals(edizioneId))).write(
            const EdizioniCompanion(
              coverImage: Value('https://example.com/nuova.jpg'),
            ),
          );
          await pumpEventQueue();

          expect(emissioni.last, {
            edizioneId: 'https://example.com/nuova.jpg',
          });
        },
      );
    },
  );
}
