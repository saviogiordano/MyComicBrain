import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';

import 'contratto/adapter_sotto_contratto.dart';

void main() => contrattoAnalisiCopertina(creaAdapterDriftInMemoria);

/// Area Scansioni e AnalisiCopertina della suite di contratto di
/// `ComicsRepository` (ADR-0007). Le Scansioni nascono da file immagine
/// reali ([AdapterSottoContratto.immagineScansione]), come quelli di
/// `ScansioneStorage`: la UI le identifica con quel percorso.
void contrattoAnalisiCopertina(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;
  late String immagine;

  setUp(() async {
    adapter = await crea();
    repo = adapter.repo;
  });

  tearDown(() => adapter.chiudi());

  Future<String> scansione() async {
    immagine = await adapter.immagineScansione('1.jpg');
    return repo.aggiungiScansione(image: immagine);
  }

  /// Attende che [condizione] sia vera: su Supabase gli stream si rileggono
  /// dalla rete dopo ogni scrittura.
  Future<void> finche(bool Function() condizione) async {
    for (var i = 0; i < 250 && !condizione(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(condizione(), isTrue, reason: 'condizione mai raggiunta');
  }

  test(
    "idScansionePerImmagine trova l'id dalla Scansione persistita",
    () async {
      final id = await scansione();

      expect(await repo.idScansionePerImmagine(immagine), id);
    },
  );

  test(
    'eliminaScansione rimuove solo la riga indicata (swipe-to-delete nel riepilogo, #59)',
    () async {
      final id = await scansione();
      final altra = await adapter.immagineScansione('2.jpg');
      final altroId = await repo.aggiungiScansione(image: altra);

      await repo.eliminaScansione(id: id);

      expect(await repo.idScansionePerImmagine(altra), altroId);
      await expectLater(
        repo.idScansionePerImmagine(immagine),
        throwsA(anything),
      );
      expect(await repo.watchImmaginiScansioniNonConfermate().first, [altra]);
    },
  );

  test('avviaAnalisiCopertina crea una riga in stato inCorso', () async {
    final scansioneId = await scansione();

    final analisiId = await repo.avviaAnalisiCopertina(
      scansioneId: scansioneId,
    );

    expect(await repo.idAnalisiCopertinaPerScansione(scansioneId), analisiId);
    final riga = await repo.analisiCopertinaPerScansione(scansioneId);
    expect(riga.id, analisiId);
    expect(riga.scansioneId, scansioneId);
    expect(riga.status, StatoAnalisiCopertina.inCorso);
    expect(riga.title, isNull);
    expect(riga.characters, isEmpty);
    expect(riga.coverStyleTags, isEmpty);
    expect(riga.visualElementTags, isEmpty);
    expect(riga.recognizedPublisherLogo, isNull);
    expect(riga.recognizedSeriesLogo, isNull);
    expect(riga.completedAt, isNull);
  });

  test(
    'completaAnalisiCopertina registra i campi grezzi e lo stato completata',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

      await repo.completaAnalisiCopertina(
        id: analisiId,
        rawResponse: '{"authors":["Stan Lee"]}',
        title: 'Amazing Spider-Man',
        issueNumberLabel: '1',
        publisher: 'Marvel',
        seriesName: 'The Amazing Spider-Man',
        barcode: '123',
        price: r'$1',
        year: 1963,
        pageCount: 36,
        characters: const ['Spider-Man'],
        coverStyleTags: const ['stile realistico'],
        visualElementTags: const ['sfondo con esplosione'],
        recognizedPublisherLogo: 'Marvel',
        printingType: 'Direct Edition',
        classificazione: 'Rated T+',
        description: 'Peter Parker affronta Venom in un confronto decisivo.',
      );

      final riga = await repo.analisiCopertinaPerScansione(scansioneId);
      expect(riga.status, StatoAnalisiCopertina.completata);
      expect(riga.title, 'Amazing Spider-Man');
      expect(riga.issueNumberLabel, '1');
      expect(riga.seriesName, 'The Amazing Spider-Man');
      expect(riga.price, r'$1');
      expect(riga.year, 1963);
      expect(riga.pageCount, 36);
      expect(riga.rawResponse, '{"authors":["Stan Lee"]}');
      expect(riga.characters, ['Spider-Man']);
      expect(riga.coverStyleTags, ['stile realistico']);
      expect(riga.visualElementTags, ['sfondo con esplosione']);
      expect(riga.recognizedPublisherLogo, 'Marvel');
      expect(riga.recognizedSeriesLogo, isNull);
      expect(riga.printingType, 'Direct Edition');
      expect(riga.classificazione, 'Rated T+');
      expect(
        riga.description,
        'Peter Parker affronta Venom in un confronto decisivo.',
      );
      expect(riga.completedAt, isNotNull);
    },
  );

  test(
    'completaAnalisiCopertina senza campi di computer vision lascia le liste vuote',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');

      final riga = await repo.analisiCopertinaPerScansione(scansioneId);
      expect(riga.characters, isEmpty);
      expect(riga.coverStyleTags, isEmpty);
      expect(riga.visualElementTags, isEmpty);
      expect(riga.printingType, isNull);
      expect(riga.classificazione, isNull);
      expect(riga.description, isNull);
    },
  );

  test(
    'fallisciAnalisiCopertina registra il motivo e lo stato fallita',
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

      await repo.fallisciAnalisiCopertina(
        id: analisiId,
        errorMessage: 'timeout',
      );

      final riga = await repo.analisiCopertinaPerScansione(scansioneId);
      expect(riga.status, StatoAnalisiCopertina.fallita);
      expect(riga.errorMessage, 'timeout');
      expect(riga.completedAt, isNotNull);
      expect(riga.title, isNull);
    },
  );

  test(
    "riavviaAnalisiCopertina torna inCorso e cancella l'errore",
    () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repo.fallisciAnalisiCopertina(
        id: analisiId,
        errorMessage: 'timeout',
      );

      await repo.riavviaAnalisiCopertina(id: analisiId);

      final riga = await repo.analisiCopertinaPerScansione(scansioneId);
      expect(riga.status, StatoAnalisiCopertina.inCorso);
      expect(riga.errorMessage, isNull);
      expect(riga.completedAt, isNull);
    },
  );

  group('watchStatoAnalisiCopertina', () {
    test('pending finché la pipeline non ha ancora creato la riga', () async {
      await scansione();

      final stato = await repo.watchStatoAnalisiCopertina(immagine).first;

      expect(stato.stato, StatoAnalisiCopertina.pending);
      expect(stato.errorMessage, isNull);
    });

    test('inCorso mentre la pipeline chiama il provider AI', () async {
      final scansioneId = await scansione();
      await repo.avviaAnalisiCopertina(scansioneId: scansioneId);

      final stato = await repo.watchStatoAnalisiCopertina(immagine).first;

      expect(stato.stato, StatoAnalisiCopertina.inCorso);
    });

    test('completata dopo completaAnalisiCopertina', () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');

      final stato = await repo.watchStatoAnalisiCopertina(immagine).first;

      expect(stato.stato, StatoAnalisiCopertina.completata);
    });

    test('fallita con errorMessage dopo fallisciAnalisiCopertina', () async {
      final scansioneId = await scansione();
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repo.fallisciAnalisiCopertina(
        id: analisiId,
        errorMessage: 'timeout',
      );

      final stato = await repo.watchStatoAnalisiCopertina(immagine).first;

      expect(stato.stato, StatoAnalisiCopertina.fallita);
      expect(stato.errorMessage, 'timeout');
    });

    test('emette un nuovo valore quando lo stato cambia', () async {
      final scansioneId = await scansione();
      final valori = <StatoAnalisiCopertina>[];
      final sub = repo
          .watchStatoAnalisiCopertina(immagine)
          .listen((s) => valori.add(s.stato));
      addTearDown(sub.cancel);

      await finche(() => valori.isNotEmpty);
      final analisiId = await repo.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await finche(() => valori.last == StatoAnalisiCopertina.inCorso);
      await repo.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');
      await finche(() => valori.last == StatoAnalisiCopertina.completata);

      // Un adapter può riemettere lo stesso stato: conta la sequenza.
      final sequenza = [
        for (var i = 0; i < valori.length; i++)
          if (i == 0 || valori[i] != valori[i - 1]) valori[i],
      ];
      expect(sequenza, [
        StatoAnalisiCopertina.pending,
        StatoAnalisiCopertina.inCorso,
        StatoAnalisiCopertina.completata,
      ]);
    });
  });

  group('watchScansioneConfermata', () {
    test('diventa true quando una Copia punta alla Scansione', () async {
      final scansioneId = await scansione();
      final valori = <bool>[];
      final sub = repo.watchScansioneConfermata(immagine).listen(valori.add);
      addTearDown(sub.cancel);
      await finche(() => valori.isNotEmpty);
      expect(valori.last, isFalse);

      final operaId = await repo.aggiungiOpera(title: 'Titolo');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        scansioneId: scansioneId,
      );

      await finche(() => valori.last);
    });
  });

  group(
    'watchImmaginiScansioniNonConfermate (Dashboard, batch in sospeso)',
    () {
      test('nessuna Scansione: lista vuota', () async {
        final immagini = await repo.watchImmaginiScansioniNonConfermate().first;
        expect(immagini, isEmpty);
      });

      test(
        'include le Scansioni senza Copia collegata, in ordine di creazione',
        () async {
          final a = await adapter.immagineScansione('a.jpg');
          final b = await adapter.immagineScansione('b.jpg');
          await repo.aggiungiScansione(
            image: a,
            createdAt: DateTime(2026, 1, 2),
          );
          await repo.aggiungiScansione(
            image: b,
            createdAt: DateTime(2026, 1, 1),
          );

          final immagini = await repo
              .watchImmaginiScansioniNonConfermate()
              .first;
          expect(immagini, [b, a]);
        },
      );

      test(
        'esclude le Scansioni già confermate (con una Copia collegata)',
        () async {
          final confermata = await adapter.immagineScansione('confermata.jpg');
          final daConfermare = await adapter.immagineScansione(
            'da-confermare.jpg',
          );
          final scansioneId = await repo.aggiungiScansione(image: confermata);
          await repo.aggiungiScansione(image: daConfermare);
          final operaId = await repo.aggiungiOpera(title: 'Titolo');
          final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
          await repo.aggiungiCopia(
            edizioneId: edizioneId,
            status: StatoCopia.posseduta,
            scansioneId: scansioneId,
          );

          final immagini = await repo
              .watchImmaginiScansioniNonConfermate()
              .first;
          expect(immagini, [daConfermare]);
        },
      );
    },
  );
}
