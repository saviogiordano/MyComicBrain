import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
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
    double? purchasePrice,
    DateTime? createdAt,
  }) async {
    final operaId = await repo.aggiungiOpera(title: titolo);
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      issueNumber: issueNumber,
      issueNumberLabel: issueNumberLabel,
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
      final edizioneOneShot = await repo.aggiungiEdizione(operaId: operaOneShot);
      await repo.aggiungiCopia(edizioneId: edizioneOneShot, status: StatoCopia.posseduta);

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.numeroSerie, 1);
    });

    test('più edizioni della stessa collana riusano la stessa Serie', () async {
      final serieId1 = await repo.aggiungiSerie(name: 'Batman');
      final serieId2 = await repo.aggiungiSerie(name: 'batman'); // stesso nome, case diverso
      final serieId3 = await repo.aggiungiSerie(name: '  Batman  '); // spazi extra

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
    test('unisce Serie con lo stesso nome create prima della deduplica, riassegna le Edizioni '
        'alla superstite (id più basso) e ne conserva "numeri totali"/ISSN se noti', () async {
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
      expect(serieRimaste.single.totalIssues, 12); // recuperato dalla duplicata

      final edizioni = await db.select(db.edizioni).get();
      expect(
        edizioni.map((e) => e.serieId),
        everyElement(serieVecchia),
        reason: 'entrambe le Edizioni devono puntare alla Serie superstite',
      );
      expect(edizioni.map((e) => e.id), containsAll([edizioneVecchia, edizioneNuova]));

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.numeroSerie, 1);
    });

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
      await db.into(db.serieTable).insert(SerieTableCompanion.insert(name: 'Batman'));
      await db.into(db.serieTable).insert(SerieTableCompanion.insert(name: 'Batman'));

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
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.duplicati, 1);
    });

    test('due copie di cui una venduta non è un duplicato', () async {
      final operaId = await repo.aggiungiOpera(title: 'Opera non duplicata');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.venduta);

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.duplicati, 0);
    });
  });

  group('numeri mancanti e serie complete', () {
    test('serie con buchi interni: variant copre il buco del suo numero', () async {
      final serieId = await repo.aggiungiSerie(name: 'Spider-Man', totalIssues: 10);
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
      expect(kpis.numeriMancanti, 4); // 4, 7, 8, 9 — il #10 è coperto dalla variant
    });

    test('serie completa (nessun numero mancante)', () async {
      final serieId = await repo.aggiungiSerie(name: 'Dylan Dog', totalIssues: 3);
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
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.numeriMancanti, 0);
      expect(kpis.serieComplete, 1);
    });

    test('serie senza "numeri totali" non è valutabile: esclusa da entrambi i KPI', () async {
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
    });
  });

  group('serie incomplete con percentuale', () {
    test('elenca solo le serie con numeri totali noti e mancanti, con la percentuale', () async {
      final kaiju = await repo.aggiungiSerie(name: 'Kaiju Bianco', totalIssues: 42);
      for (final n in [1, 2, 3, 5, 6, 10]) {
        await edizioneConCopia(
          titolo: 'Kaiju Bianco #$n',
          serieId: kaiju,
          issueNumber: n,
          status: StatoCopia.posseduta,
        );
      }

      // Serie completa: non deve comparire fra le incomplete.
      final dylanDog = await repo.aggiungiSerie(name: 'Dylan Dog', totalIssues: 1);
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
      expect(serie.numeriMancanti, [4, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42]);
      expect(serie.percentualeCompletamento, closeTo(6 / 42, 0.0001));
    });
  });

  group('€ speso finora', () {
    test('somma i prezzi delle copie possedute, ignora quelle senza prezzo', () async {
      final operaConPrezzo = await repo.aggiungiOpera(title: 'Con prezzo');
      final edizioneConPrezzo = await repo.aggiungiEdizione(operaId: operaConPrezzo);
      await repo.aggiungiCopia(
        edizioneId: edizioneConPrezzo,
        status: StatoCopia.posseduta,
        purchasePrice: 12.5,
      );

      final operaSenzaPrezzo = await repo.aggiungiOpera(title: 'Senza prezzo');
      final edizioneSenzaPrezzo = await repo.aggiungiEdizione(operaId: operaSenzaPrezzo);
      await repo.aggiungiCopia(edizioneId: edizioneSenzaPrezzo, status: StatoCopia.posseduta);

      final operaVenduta = await repo.aggiungiOpera(title: 'Venduta con prezzo');
      final edizioneVenduta = await repo.aggiungiEdizione(operaId: operaVenduta);
      await repo.aggiungiCopia(
        edizioneId: edizioneVenduta,
        status: StatoCopia.venduta,
        purchasePrice: 999,
      );

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.spesoFinora, closeTo(12.5, 0.0001));
    });
  });

  group('N aggiunti nel mese corrente', () {
    test('conta solo le copie possedute create nel mese solare corrente', () async {
      final ora = DateTime.now();
      final meseScorso = DateTime(ora.year, ora.month - 1, 15);

      final operaId = await repo.aggiungiOpera(title: 'Opera');
      final edizioneQuestoMese = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneQuestoMese,
        status: StatoCopia.posseduta,
        createdAt: ora,
      );

      final edizioneMeseScorso = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneMeseScorso,
        status: StatoCopia.posseduta,
        createdAt: meseScorso,
      );

      final kpis = await repo.watchDashboardKpis().first;
      expect(kpis.aggiuntiMeseCorrente, 1);
    });
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
      expect(recenti.map((c) => c.titolo), unorderedEquals([
        StatoCopia.posseduta.name,
        StatoCopia.prestata.name,
      ]));
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
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      final recente = (await repo.watchAggiuntiDiRecente().first).single;
      expect(recente.edizioneId, edizioneId);
      expect(recente.titolo, 'Notturno');
      expect(recente.editore, 'Kodama Manga');
      expect(recente.numero, 4);
      expect(recente.numeroVisualizzato, '#4');
    });

    test('numero testuale ("4 Variant") ha priorità sul numero intero in visualizzazione', () async {
      final operaId = await repo.aggiungiOpera(title: 'Notturno');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        issueNumber: 4,
        issueNumberLabel: '4 Variant',
      );
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      final recente = (await repo.watchAggiuntiDiRecente().first).single;
      expect(recente.numeroVisualizzato, '#4 Variant');
    });

    test('coverImage null se assente', () async {
      final operaId = await repo.aggiungiOpera(title: 'Senza cover');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

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
        await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

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
        await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

        final recente = (await repo.watchAggiuntiDiRecente().first).single;
        expect(recente.coverImage, '${Directory.systemTemp.path}/una_cover.png');
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

        final operaId = await repoConBase.aggiungiOpera(title: 'Con cover relativa');
        final edizioneId = await repoConBase.aggiungiEdizione(
          operaId: operaId,
          coverImage: p.join('copertine', '1.jpg'),
        );
        await repoConBase.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

        final recente = (await repoConBase.watchAggiuntiDiRecente().first).single;
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

        final operaId = await repoConBase.aggiungiOpera(title: 'Con cover legacy');
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
        await repoConBase.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

        final recente = (await repoConBase.watchAggiuntiDiRecente().first).single;
        expect(recente.coverImage, p.join(tempBase.path, 'copertine', '1.jpg'));
      },
    );
  });
}
