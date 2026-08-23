import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/copia.dart';

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

    test("porta coverImage dall'edizione, null se assente", () async {
      final operaId = await repo.aggiungiOpera(title: 'Con cover');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        coverImage: '/copertine/1.jpg',
      );
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      final senzaCoverOperaId = await repo.aggiungiOpera(title: 'Senza cover');
      final senzaCoverEdizioneId = await repo.aggiungiEdizione(operaId: senzaCoverOperaId);
      await repo.aggiungiCopia(edizioneId: senzaCoverEdizioneId, status: StatoCopia.posseduta);

      final recenti = await repo.watchAggiuntiDiRecente().first;
      expect(
        recenti.firstWhere((c) => c.edizioneId == edizioneId).coverImage,
        '/copertine/1.jpg',
      );
      expect(
        recenti.firstWhere((c) => c.edizioneId == senzaCoverEdizioneId).coverImage,
        null,
      );
    });
  });
}
