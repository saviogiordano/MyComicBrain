import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:mycomicbrain/core/domain/valore_stimato.dart';

import 'contratto/adapter_sotto_contratto.dart';

void main() => contrattoScheda(creaAdapterDriftInMemoria);

/// Area Scheda della suite di contratto di `ComicsRepository` (ADR-0007).
void contrattoScheda(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;

  setUp(() async {
    adapter = await crea();
    repo = adapter.repo;
  });

  tearDown(() => adapter.chiudi());

  Future<String> opera({String title = 'The Amazing Spider-Man'}) =>
      repo.aggiungiOpera(title: title);

  Future<String> edizione({String? operaId, String? serieId}) async {
    return repo.aggiungiEdizione(
      operaId: operaId ?? await opera(),
      serieId: serieId,
      issueNumberLabel: '1',
    );
  }

  Future<EdizioneDettaglio?> dettaglioDi(String edizioneId) =>
      repo.watchEdizione(edizioneId).first;

  Future<CopiaDettaglio> copiaDi(String edizioneId, String copiaId) async =>
      (await dettaglioDi(
        edizioneId,
      ))!.copie.singleWhere((c) => c.id == copiaId);

  test('watchEdizione ritorna null per un\'Edizione inesistente', () async {
    expect(await repo.watchEdizione('00000000-0000-7000-8000-000000000999').first, isNull);
  });

  test('watchEdizione risolve titolo (Opera), Copie e Autori', () async {
    final operaId = await opera(title: 'Batman');
    final serieId = await repo.aggiungiSerie(name: 'Batman (2016)');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: 'Panini Comics',
    );
    await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
    );
    final creatorId = await repo.aggiungiCreator('Grant Morrison');
    await repo.collegaCreatorAEdizione(
      edizioneId: edizioneId,
      creatorId: creatorId,
      ruolo: RuoloCreator.sceneggiatore,
    );

    final dettaglio = await repo.watchEdizione(edizioneId).first;

    expect(dettaglio, isNotNull);
    expect(dettaglio!.titolo, 'Batman');
    expect(dettaglio.serieName, 'Batman (2016)');
    expect(dettaglio.publisher, 'Panini Comics');
    expect(dettaglio.copie, hasLength(1));
    expect(dettaglio.autori, hasLength(1));
    expect(dettaglio.autori.single.name, 'Grant Morrison');
  });

  test(
    'watchEdizione con più Copie e più Autori non li mischia (prodotto cartesiano raggruppato correttamente)',
    () async {
      final edizioneId = await edizione();
      final copia1 = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      final copia2 = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.venduta,
      );
      final autore1 = await repo.aggiungiCreator('Dan Slott');
      final autore2 = await repo.aggiungiCreator('Humberto Ramos');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: autore1,
        ruolo: RuoloCreator.sceneggiatore,
      );
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: autore2,
        ruolo: RuoloCreator.disegnatore,
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;

      expect(
        dettaglio!.copie.map((c) => c.id),
        unorderedEquals([copia1, copia2]),
      );
      expect(
        dettaglio.autori.map((a) => a.creatorId),
        unorderedEquals([autore1, autore2]),
      );
    },
  );

  test(
    'watchEdizione senza Valore stimato calcolato: CopiaDettaglio ha i campi §35 tutti null',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;

      final copia = dettaglio!.copie.single;
      expect(copia.statoValoreStimato, isNull);
      expect(copia.valoreStimato, isNull);
      expect(copia.valoreStimatoErrorMessage, isNull);
      expect(copia.valoreStimatoAggiornatoAl, isNull);
    },
  );

  test(
    'watchEdizione risolve il Valore stimato completato di ciascuna Copia (§35)',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      final valoreStimatoId = await repo.avviaOrRiavviaValoreStimato(
        copiaId: copiaId,
      );
      await repo.completaValoreStimato(id: valoreStimatoId, value: 15.5);

      final dettaglio = await repo.watchEdizione(edizioneId).first;

      final copia = dettaglio!.copie.single;
      expect(copia.statoValoreStimato, StatoValoreStimato.completata);
      expect(copia.valoreStimato, 15.5);
      expect(copia.valoreStimatoAggiornatoAl, isNotNull);
    },
  );

  test(
    'CopiaDettaglio.haDatiPersonali è false quando nessun campo §8.2 è valorizzato',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;
      expect(dettaglio!.copie.single.haDatiPersonali, isFalse);
    },
  );

  test(
    'CopiaDettaglio.haDatiPersonali è true se anche un solo campo §8.2 è valorizzato',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        notes: 'prima ristampa',
      );

      final dettaglio = await repo.watchEdizione(edizioneId).first;
      expect(dettaglio!.copie.single.haDatiPersonali, isTrue);
    },
  );

  test(
    'aggiornaTitoloOpera aggiorna il titolo sulla Opera, non sulla Edizione',
    () async {
      final operaId = await opera(title: 'Vecchio titolo');
      final edizioneId = await edizione(operaId: operaId);
      await repo.aggiornaTitoloOpera(operaId: operaId, title: 'Nuovo titolo');

      final dettaglio = await dettaglioDi(edizioneId);
      expect(dettaglio!.titolo, 'Nuovo titolo');
      expect(dettaglio.operaId, operaId);
    },
  );

  test('aggiornaEdizione aggiorna i campi bibliografici §8.1', () async {
    final edizioneId = await edizione();

    await repo.aggiornaEdizione(
      id: edizioneId,
      publisher: 'Marvel Italia',
      issueNumber: 67,
      issueNumberLabel: '67',
      volume: 'Vol. 3',
      description: 'Descrizione aggiornata',
    );

    final riga = (await dettaglioDi(edizioneId))!;
    expect(riga.publisher, 'Marvel Italia');
    expect(riga.issueNumber, 67);
    expect(riga.issueNumberLabel, '67');
    expect(riga.volume, 'Vol. 3');
    expect(riga.description, 'Descrizione aggiornata');
  });

  test('aggiornaCopia aggiorna i campi §8.2 senza toccare lo stato', () async {
    final edizioneId = await edizione();
    final copiaId = await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      readingStatus: StatoLettura.letto,
    );

    await repo.aggiornaCopia(
      id: copiaId,
      condition: CondizioneCopia.veryFine,
      purchasePrice: 3.5,
      seller: 'Fumetteria Century',
      notes: 'Prima ristampa italiana.',
    );

    final riga = await copiaDi(edizioneId, copiaId);
    expect(riga.condition, CondizioneCopia.veryFine);
    expect(riga.purchasePrice, 3.5);
    expect(riga.seller, 'Fumetteria Century');
    expect(riga.status, StatoCopia.posseduta, reason: 'invariato');
    expect(riga.readingStatus, StatoLettura.letto, reason: 'invariato');
  });

  test(
    'aggiornaCopia scrive purchasePriceCurrency e valutazione, letti '
    'indietro su CopiaDettaglio (§35, valutazione manuale distinta dal '
    'calcolo automatico)',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      await repo.aggiornaCopia(
        id: copiaId,
        purchasePrice: 3.99,
        purchasePriceCurrency: ValutaPrezzo.usd,
        valutazione: 12,
      );

      final copia = await copiaDi(edizioneId, copiaId);
      expect(copia.purchasePrice, 3.99);
      expect(copia.purchasePriceCurrency, ValutaPrezzo.usd);
      expect(copia.valutazione, 12);
    },
  );

  test(
    'cambiaStatoCopia scrive solo status/readingStatus, lasciando invariati i campi §8.2',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        readingStatus: StatoLettura.daLeggere,
        seller: 'Edicola di zona',
      );

      await repo.cambiaStatoCopia(id: copiaId, status: StatoCopia.prestata);

      final riga = await copiaDi(edizioneId, copiaId);
      expect(riga.status, StatoCopia.prestata);
      expect(riga.readingStatus, isNull);
      expect(riga.seller, 'Edicola di zona', reason: 'invariato');
    },
  );

  test(
    'impostaInVendita scrive solo forSale, lasciando invariati gli altri campi',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        readingStatus: StatoLettura.letto,
        seller: 'Edicola di zona',
      );

      await repo.impostaInVendita(id: copiaId, inVendita: true);

      final riga = await copiaDi(edizioneId, copiaId);
      expect(riga.forSale, isTrue);
      expect(riga.status, StatoCopia.posseduta, reason: 'invariato');
      expect(riga.readingStatus, StatoLettura.letto, reason: 'invariato');
      expect(riga.seller, 'Edicola di zona', reason: 'invariato');

      await repo.impostaInVendita(id: copiaId, inVendita: false);
      final rigaSpenta = await copiaDi(edizioneId, copiaId);
      expect(rigaSpenta.forSale, isFalse);
    },
  );

  test(
    'segnaEdizioniInVendita marca solo le copie possedute/prestate delle '
    'edizioni indicate (§163/§164)',
    () async {
      final edizioneA = await edizione();
      final edizioneB = await edizione();
      final edizioneC = await edizione();

      final copiaAPosseduta = await repo.aggiungiCopia(
        edizioneId: edizioneA,
        status: StatoCopia.posseduta,
      );
      final copiaAPrestata = await repo.aggiungiCopia(
        edizioneId: edizioneA,
        status: StatoCopia.prestata,
      );
      final copiaAVenduta = await repo.aggiungiCopia(
        edizioneId: edizioneA,
        status: StatoCopia.venduta,
      );
      final copiaB = await repo.aggiungiCopia(
        edizioneId: edizioneB,
        status: StatoCopia.posseduta,
      );
      final copiaC = await repo.aggiungiCopia(
        edizioneId: edizioneC,
        status: StatoCopia.posseduta,
      );

      final scritte = await repo.segnaEdizioniInVendita([
        edizioneA,
        edizioneB,
      ]);

      expect(scritte, 3, reason: 'copiaAPosseduta + copiaAPrestata + copiaB');

      Future<bool> forSaleDi(String edizioneId, String id) async =>
          (await copiaDi(edizioneId, id)).forSale;

      expect(await forSaleDi(edizioneA, copiaAPosseduta), isTrue);
      expect(await forSaleDi(edizioneA, copiaAPrestata), isTrue);
      expect(
        await forSaleDi(edizioneA, copiaAVenduta),
        isFalse,
        reason: 'venduta, non "posseduta"',
      );
      expect(await forSaleDi(edizioneB, copiaB), isTrue);
      expect(
        await forSaleDi(edizioneC, copiaC),
        isFalse,
        reason: 'edizione non indicata nella selezione',
      );
    },
  );

  test('segnaEdizioniInVendita con lista vuota non scrive nulla', () async {
    expect(await repo.segnaEdizioniInVendita(const []), 0);
  });

  test(
    'rimuoviCopia rimuove solo la Copia quando ne restano altre',
    () async {
      final edizioneId = await edizione();
      final copia1 = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.venduta,
      );

      final edizioneEliminata = await repo.rimuoviCopia(copia1);

      expect(edizioneEliminata, isFalse);
      final dettaglio = await dettaglioDi(edizioneId);
      expect(dettaglio, isNotNull);
      expect(dettaglio!.copie, hasLength(1));
    },
  );

  test(
    "rimuoviCopia sull'ultima Copia elimina anche l'Edizione (deciso su #68: nessuno stato orfana)",
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final edizioneEliminata = await repo.rimuoviCopia(copiaId);

      expect(edizioneEliminata, isTrue);
      expect(await dettaglioDi(edizioneId), isNull);
    },
  );

  test(
    'rimuoviCopia sull\'ultima Copia rimuove anche i collegamenti Autore dell\'Edizione',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      final creatorId = await repo.aggiungiCreator('Stan Lee');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      await repo.rimuoviCopia(copiaId);

      expect(await repo.autoriDiEdizione(edizioneId), isEmpty);
    },
  );

  test(
    'eliminaEdizione elimina Edizione, tutte le Copie e i collegamenti Autore',
    () async {
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.prestata,
      );
      final creatorId = await repo.aggiungiCreator('Stan Lee');
      await repo.collegaCreatorAEdizione(
        edizioneId: edizioneId,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      await repo.eliminaEdizione(edizioneId);

      expect(await dettaglioDi(edizioneId), isNull);
      expect(await repo.autoriDiEdizione(edizioneId), isEmpty);
    },
  );

  test(
    'eliminaEdizione elimina anche Personaggi, Tag, Generi e il Valore '
    'stimato delle Copie',
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);
      await repo.collegaCharacterAEdizione(
        edizioneId: edizioneId,
        characterId: await repo.aggiungiCharacter('Rorschach'),
      );
      await repo.collegaTagAEdizione(
        edizioneId: edizioneId,
        tagId: await repo.aggiungiTag('capolavoro'),
      );
      await repo.impostaGeneriEdizione(
        edizioneId: edizioneId,
        generi: {GenereEdizione.supereroi},
      );

      await repo.eliminaEdizione(edizioneId);

      expect(await dettaglioDi(edizioneId), isNull);
    },
  );

  test(
    "rimuoviCopia sull'ultima Copia con Valore stimato elimina anche "
    "l'Edizione",
    () async {
      final edizioneId = await edizione();
      final copiaId = await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);

      expect(await repo.rimuoviCopia(copiaId), isTrue);
      expect(await dettaglioDi(edizioneId), isNull);
    },
  );

  test(
    'coverImageGrezzoDi restituisce il valore salvato, non risolto',
    () async {
      final edizioneId = await repo.aggiungiEdizione(
        operaId: await opera(),
        coverImage: 'cartella/cover.jpg',
      );

      expect(await repo.coverImageGrezzoDi(edizioneId), 'cartella/cover.jpg');
    },
  );

  test('watchEdizione riemette dopo una scrittura sulle sue Copie', () async {
    final edizioneId = await edizione();
    final prima = Completer<void>();
    final conCopia = Completer<void>();
    final sottoscrizione = repo.watchEdizione(edizioneId).listen((d) {
      if (!prima.isCompleted) prima.complete();
      if (d!.copie.length == 1 && !conCopia.isCompleted) conCopia.complete();
    });
    await prima.future;

    await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
    );

    await conCopia.future.timeout(const Duration(seconds: 5));
    await sottoscrizione.cancel();
  });

  test('impostaGeneriEdizione sostituisce per intero i Generi', () async {
    final edizioneId = await edizione();
    await repo.impostaGeneriEdizione(
      edizioneId: edizioneId,
      generi: {GenereEdizione.supereroi, GenereEdizione.horror},
    );
    await repo.impostaGeneriEdizione(
      edizioneId: edizioneId,
      generi: {GenereEdizione.horror, GenereEdizione.fantasy},
    );
    await repo.impostaGeneriEdizione(edizioneId: edizioneId, generi: {});
    await repo.impostaGeneriEdizione(
      edizioneId: edizioneId,
      generi: {GenereEdizione.fantasy},
    );

    // Nessuna lettura dei Generi nella Scheda: il contratto qui è che le
    // sostituzioni ripetute non falliscano (vincolo unique su Supabase).
    expect(await dettaglioDi(edizioneId), isNotNull);
  });
}
