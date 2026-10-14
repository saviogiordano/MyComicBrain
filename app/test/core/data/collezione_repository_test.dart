import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';

import 'contratto/adapter_sotto_contratto.dart';

void main() => contrattoCollezione(creaAdapterDriftInMemoria);

/// Area Collezione della suite di contratto di `ComicsRepository`
/// (ADR-0007): indice e idratazione della Collezione, ricerca del
/// tool-calling dell'Assistente.
void contrattoCollezione(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;

  setUp(() async {
    adapter = await crea();
    repo = adapter.repo;
  });

  tearDown(() => adapter.chiudi());

  /// Crea un'opera + un'edizione (opzionalmente in una serie, con un
  /// numero) e vi aggiunge una copia con lo [status] dato. Ritorna l'id
  /// dell'edizione.
  Future<String> edizioneConCopia({
    required String titolo,
    required StatoCopia status,
    String? serieId,
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
          const inesistente = '00000000-0000-7000-8000-000000999999';

          final mappa = await repo.watchHydratazioneCollezione([
            venduta,
            inesistente,
          ]).first;

          expect(mappa, isEmpty);
        },
      );

      test(
        "reattiva alla nuova copertina di un'Edizione già emessa",
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

          final prima = Completer<void>();
          final nuova = Completer<void>();
          final subscription = repo
              .watchHydratazioneCollezione([edizioneId])
              .listen((mappa) {
                if (!prima.isCompleted) prima.complete();
                if (mappa[edizioneId] == 'https://example.com/nuova.jpg' &&
                    !nuova.isCompleted) {
                  nuova.complete();
                }
              });
          addTearDown(subscription.cancel);
          await prima.future;

          await repo.aggiornaEdizione(
            id: edizioneId,
            coverImage: 'https://example.com/nuova.jpg',
          );

          await nuova.future.timeout(const Duration(seconds: 5));
        },
      );
    },
  );

  group('cercaSerie (§10, tool-calling Assistente, ADR-0002)', () {
    test('match parziale del nome trova la Serie', () async {
      await repo.aggiungiSerie(name: 'Dylan Dog');

      final risultati = await repo.cercaSerie('dylan');

      expect(risultati.map((s) => s.name), ['Dylan Dog']);
    });

    test('nessun match: lista vuota', () async {
      await repo.aggiungiSerie(name: 'Dylan Dog');

      expect(await repo.cercaSerie('Nathan Never'), isEmpty);
    });

    test(
      'più Serie con match parziale: tutte in lista (ambiguità visibile al chiamante)',
      () async {
        await repo.aggiungiSerie(name: 'Batman');
        await repo.aggiungiSerie(name: 'Batman Beyond');

        final risultati = await repo.cercaSerie('Batman');

        expect(risultati, hasLength(2));
      },
    );
  });

  group('cercaEdizioni (§10, tool-calling Assistente, ADR-0002)', () {
    test('filtro per titolo (match parziale)', () async {
      await edizioneConCopia(titolo: 'Dylan Dog', status: StatoCopia.posseduta);
      await edizioneConCopia(
        titolo: 'Nathan Never',
        status: StatoCopia.posseduta,
      );

      final risultato = await repo.cercaEdizioni(titolo: 'dylan');

      expect(risultato.edizioni.map((e) => e.titolo), ['Dylan Dog']);
      expect(risultato.totale, 1);
      expect(risultato.troncato, isFalse);
    });

    test(
      'filtro per serie: include tutte le Edizioni delle Serie in match parziale',
      () async {
        final batman = await repo.aggiungiSerie(name: 'Batman');
        final batmanBeyond = await repo.aggiungiSerie(name: 'Batman Beyond');
        final dylanDog = await repo.aggiungiSerie(name: 'Dylan Dog');
        await edizioneConCopia(
          titolo: 'Batman #1',
          serieId: batman,
          status: StatoCopia.posseduta,
        );
        await edizioneConCopia(
          titolo: 'Batman Beyond #1',
          serieId: batmanBeyond,
          status: StatoCopia.posseduta,
        );
        await edizioneConCopia(
          titolo: 'Dylan Dog #1',
          serieId: dylanDog,
          status: StatoCopia.posseduta,
        );

        final risultato = await repo.cercaEdizioni(serie: 'Batman');

        expect(
          risultato.edizioni.map((e) => e.titolo),
          unorderedEquals(['Batman #1', 'Batman Beyond #1']),
        );
      },
    );

    test('filtro per autore', () async {
      final conAutore = await edizioneConCopia(
        titolo: 'Con autore',
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(
        titolo: 'Senza autore',
        status: StatoCopia.posseduta,
      );
      final creatorId = await repo.aggiungiCreator('Tiziano Sclavi');
      await repo.collegaCreatorAEdizione(
        edizioneId: conAutore,
        creatorId: creatorId,
        ruolo: RuoloCreator.sceneggiatore,
      );

      final risultato = await repo.cercaEdizioni(autore: 'sclavi');

      expect(risultato.edizioni.map((e) => e.titolo), ['Con autore']);
    });

    test('filtro per editore', () async {
      final operaId = await repo.aggiungiOpera(title: 'Con editore');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        publisher: 'Sergio Bonelli Editore',
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(
        titolo: 'Senza editore',
        status: StatoCopia.posseduta,
      );

      final risultato = await repo.cercaEdizioni(editore: 'bonelli');

      expect(risultato.edizioni.map((e) => e.titolo), ['Con editore']);
    });

    test('filtro per personaggio', () async {
      final conPersonaggio = await edizioneConCopia(
        titolo: 'Con personaggio',
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(
        titolo: 'Senza personaggio',
        status: StatoCopia.posseduta,
      );
      final characterId = await repo.aggiungiCharacter('Joker');
      await repo.collegaCharacterAEdizione(
        edizioneId: conPersonaggio,
        characterId: characterId,
      );

      final risultato = await repo.cercaEdizioni(personaggio: 'joker');

      expect(risultato.edizioni.map((e) => e.titolo), ['Con personaggio']);
    });

    test('filtro per tag', () async {
      final conTag = await edizioneConCopia(
        titolo: 'Con tag',
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(titolo: 'Senza tag', status: StatoCopia.posseduta);
      final tagId = await repo.aggiungiTag('preferito');
      await repo.collegaTagAEdizione(edizioneId: conTag, tagId: tagId);

      final risultato = await repo.cercaEdizioni(tag: 'preferito');

      expect(risultato.edizioni.map((e) => e.titolo), ['Con tag']);
    });

    test('filtro per numero', () async {
      await edizioneConCopia(
        titolo: 'Numero 4',
        issueNumber: 4,
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(
        titolo: 'Numero 5',
        issueNumber: 5,
        status: StatoCopia.posseduta,
      );

      final risultato = await repo.cercaEdizioni(numero: 4);

      expect(risultato.edizioni.map((e) => e.titolo), ['Numero 4']);
    });

    test('filtro per isbn confronta Edizioni.ean', () async {
      final operaId = await repo.aggiungiOpera(title: 'Con EAN');
      final edizioneId = await repo.aggiungiEdizione(
        operaId: operaId,
        ean: '9781234567897',
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(titolo: 'Senza EAN', status: StatoCopia.posseduta);

      final risultato = await repo.cercaEdizioni(isbn: '9781234567897');

      expect(risultato.edizioni.map((e) => e.titolo), ['Con EAN']);
    });

    test(
      'testoLibero cerca su più campi (titolo, serie, editore, autore, personaggio, tag)',
      () async {
        final serieId = await repo.aggiungiSerie(name: 'Zagor');
        await edizioneConCopia(
          titolo: 'Altro',
          serieId: serieId,
          status: StatoCopia.posseduta,
        );
        await edizioneConCopia(
          titolo: 'Non correlato',
          status: StatoCopia.posseduta,
        );

        final risultato = await repo.cercaEdizioni(testoLibero: 'zagor');

        expect(risultato.edizioni.map((e) => e.titolo), ['Altro']);
      },
    );

    test('filtri multipli si combinano in AND', () async {
      final serieId = await repo.aggiungiSerie(name: 'Dylan Dog');
      await edizioneConCopia(
        titolo: 'Dylan Dog #1',
        serieId: serieId,
        issueNumber: 1,
        status: StatoCopia.posseduta,
      );
      await edizioneConCopia(
        titolo: 'Dylan Dog #2',
        serieId: serieId,
        issueNumber: 2,
        status: StatoCopia.posseduta,
      );

      final risultato = await repo.cercaEdizioni(serie: 'Dylan', numero: 1);

      expect(risultato.edizioni.map((e) => e.titolo), ['Dylan Dog #1']);
    });

    test('nessun filtro: tetto di 30 risultati con conteggio totale', () async {
      for (var n = 1; n <= 31; n++) {
        await edizioneConCopia(
          titolo: 'Fumetto $n',
          status: StatoCopia.posseduta,
        );
      }

      final risultato = await repo.cercaEdizioni();

      expect(risultato.edizioni, hasLength(30));
      expect(risultato.totale, 31);
      expect(risultato.troncato, isTrue);
    });
  });
}
