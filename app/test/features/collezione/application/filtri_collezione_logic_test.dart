import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';

/// Copre gli scenari guidati del prototipo `filtri_collezione_prototype.html`
/// (ticket #85 di #79): AND fra assi, OR nello stesso asse, regola "almeno
/// una copia", ordinamento primario+secondario, "Senza serie" (#94).
void main() {
  EdizioneCollezioneIndice edizione({
    required int id,
    required String titolo,
    String? serieName,
    String? publisher,
    int? year,
    List<CopiaAsseCollezione> copie = const [],
  }) {
    return EdizioneCollezioneIndice(
      edizioneId: id,
      titolo: titolo,
      serieId: null,
      serieName: serieName,
      publisher: publisher,
      issueNumber: null,
      issueNumberLabel: null,
      year: year,
      format: null,
      language: null,
      autori: const [],
      personaggi: const [],
      generi: const [],
      tag: const [],
      copiePossedute: copie,
    );
  }

  CopiaAsseCollezione copia({
    StatoLettura? readingStatus,
    CondizioneCopia? condition,
    String? location,
  }) {
    return CopiaAsseCollezione(
      readingStatus: readingStatus,
      condition: condition,
      location: location,
      createdAt: DateTime(2026),
    );
  }

  group('applicaFiltri', () {
    test('nessun filtro attivo: passano tutte le Edizioni', () {
      final edizioni = [
        edizione(id: 1, titolo: 'A'),
        edizione(id: 2, titolo: 'B'),
      ];
      expect(applicaFiltri(edizioni, const FiltriCollezioneState()), edizioni);
    });

    test('AND fra assi diversi: entrambe le condizioni devono valere', () {
      final a = edizione(id: 1, titolo: 'A', publisher: 'Bonelli', year: 2020);
      final b = edizione(id: 2, titolo: 'B', publisher: 'Bonelli', year: 2021);
      final c = edizione(id: 3, titolo: 'C', publisher: 'Panini', year: 2020);

      const stato = FiltriCollezioneState(
        filtri: {
          AsseCollezione.editore: {'Bonelli'},
          AsseCollezione.anno: {'2020'},
        },
      );

      expect(applicaFiltri([a, b, c], stato), [a]);
    });

    test(
      'OR dentro lo stesso asse: basta un valore fra quelli selezionati',
      () {
        final a = edizione(id: 1, titolo: 'A', publisher: 'Bonelli');
        final b = edizione(id: 2, titolo: 'B', publisher: 'Panini');
        final c = edizione(id: 3, titolo: 'C', publisher: 'Star Comics');

        const stato = FiltriCollezioneState(
          filtri: {
            AsseCollezione.editore: {'Bonelli', 'Panini'},
          },
        );

        expect(applicaFiltri([a, b, c], stato), [a, b]);
      },
    );

    test('regola "almeno una copia" per gli assi per-Copia (#80)', () {
      final conCopiaLetta = edizione(
        id: 1,
        titolo: 'A',
        copie: [
          copia(readingStatus: StatoLettura.letto),
          copia(readingStatus: StatoLettura.daLeggere),
        ],
      );
      final senzaCopiaLetta = edizione(
        id: 2,
        titolo: 'B',
        copie: [copia(readingStatus: StatoLettura.daLeggere)],
      );

      final stato = FiltriCollezioneState(
        filtri: {
          AsseCollezione.statoLettura: {StatoLettura.letto.name},
        },
      );

      expect(applicaFiltri([conCopiaLetta, senzaCopiaLetta], stato), [
        conCopiaLetta,
      ]);
    });

    test('combinazione impossibile: nessun risultato', () {
      final a = edizione(id: 1, titolo: 'A', publisher: 'Bonelli', year: 2020);

      const stato = FiltriCollezioneState(
        filtri: {
          AsseCollezione.editore: {'Bonelli'},
          AsseCollezione.anno: {'1999'},
        },
      );

      expect(applicaFiltri([a], stato), isEmpty);
    });

    test(
      '"Senza serie" (#94): raggiungibile solo con quel valore esplicito',
      () {
        final conSerie = edizione(
          id: 1,
          titolo: 'Dylan Dog',
          serieName: 'Dylan Dog',
        );
        final senzaSerie = edizione(id: 2, titolo: 'Watchmen');

        const stato = FiltriCollezioneState(
          filtri: {
            AsseCollezione.serie: {senzaSerieValore},
          },
        );

        expect(applicaFiltri([conSerie, senzaSerie], stato), [senzaSerie]);
      },
    );
  });

  group('applicaOrdinamento', () {
    test('titolo crescente per default', () {
      final b = edizione(id: 1, titolo: 'Berserk');
      final a = edizione(id: 2, titolo: 'Astro Boy');

      expect(applicaOrdinamento([b, a], const OrdinamentoCollezione()), [a, b]);
    });

    test('criterio secondario come pareggio quando il primario è a parità', () {
      final vecchiaEdizioneA = edizione(
        id: 1,
        titolo: 'Stessa serie',
        publisher: 'Panini',
        year: 2020,
      );
      final vecchiaEdizioneB = edizione(
        id: 2,
        titolo: 'Stessa serie',
        publisher: 'Bonelli',
        year: 2020,
      );

      const ordinamento = OrdinamentoCollezione(
        primario: CriterioOrdinamento.anno,
        secondario: CriterioOrdinamento.editore,
      );

      expect(
        applicaOrdinamento([vecchiaEdizioneA, vecchiaEdizioneB], ordinamento),
        [
          vecchiaEdizioneB,
          vecchiaEdizioneA,
        ],
      );
    });

    test("direzione decrescente inverte l'ordinamento primario", () {
      final a = edizione(id: 1, titolo: 'A');
      final b = edizione(id: 2, titolo: 'B');

      const ordinamento = OrdinamentoCollezione(
        direzionePrimario: DirezioneOrdinamento.decrescente,
      );

      expect(applicaOrdinamento([a, b], ordinamento), [b, a]);
    });
  });

  group('FiltriCollezioneState', () {
    test('toggleValore aggiunge, poi rimuove lo stesso valore', () {
      var stato = const FiltriCollezioneState();
      stato = stato.toggleValore(AsseCollezione.editore, 'Bonelli');
      expect(stato.valoriSelezionati(AsseCollezione.editore), {'Bonelli'});

      stato = stato.toggleValore(AsseCollezione.editore, 'Bonelli');
      expect(stato.valoriSelezionati(AsseCollezione.editore), isEmpty);
      expect(stato.haFiltriAttivi, isFalse);
    });

    test("azzeraTutti svuota i filtri ma mantiene l'ordinamento", () {
      const ordinamento = OrdinamentoCollezione(
        primario: CriterioOrdinamento.anno,
      );
      var stato = const FiltriCollezioneState(
        filtri: {
          AsseCollezione.editore: {'Bonelli'},
        },
      ).conOrdinamento(ordinamento);

      stato = stato.azzeraTutti();

      expect(stato.haFiltriAttivi, isFalse);
      expect(stato.ordinamento, ordinamento);
    });

    test(
      'numeroAssiAttivi conta solo gli assi con almeno un valore selezionato',
      () {
        const stato = FiltriCollezioneState(
          filtri: {
            AsseCollezione.editore: {'Bonelli'},
            AsseCollezione.autore: {},
            AsseCollezione.lingua: {'Italiano', 'Inglese'},
          },
        );

        expect(stato.numeroAssiAttivi, 2);
      },
    );
  });

  group('valoriAsseInCollezione', () {
    test(
      'solo i valori davvero presenti in collezione, "Senza serie" sempre in coda',
      () {
        final edizioni = [
          edizione(id: 1, titolo: 'A', serieName: 'Zeta'),
          edizione(id: 2, titolo: 'B', serieName: 'Alfa'),
          edizione(id: 3, titolo: 'C'),
        ];

        expect(
          valoriAsseInCollezione(edizioni, AsseCollezione.serie),
          ['Alfa', 'Zeta', senzaSerieValore],
        );
      },
    );
  });

  group('etichettaValoreAsse', () {
    test('valori enum mostrano la label italiana, non il nome tecnico', () {
      expect(
        etichettaValoreAsse(
          AsseCollezione.formato,
          FormatoEdizione.tankobon.name,
        ),
        'Tankōbon',
      );
    });

    test('"Senza serie" ha un\'etichetta dedicata', () {
      expect(
        etichettaValoreAsse(AsseCollezione.serie, senzaSerieValore),
        'Senza serie',
      );
    });
  });
}
