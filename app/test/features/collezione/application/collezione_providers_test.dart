import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/features/collezione/application/collezione_providers.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Copre lo scroll infinito della Collezione (§9, deciso su #112/#115):
/// finestra di [dimensionePaginaCollezione] Edizioni, `caricaAltro()`,
/// reset della finestra al cambio filtri/pre-filtro, aggiornamento
/// reattivo del catalogo sotto scroll senza perdere la posizione. Ticket
/// #117 di "Mappa — Paginazione della Collezione" (#112).
void main() {
  late AppDatabase db;
  late ComicsRepository repository;
  late SharedPreferences sharedPreferences;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repository = ComicsRepository(db);
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        comicsRepositoryProvider.overrideWithValue(repository),
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> edizionePosseduta(String titolo, {String? publisher}) async {
    final operaId = await repository.aggiungiOpera(title: titolo);
    final edizioneId = await repository.aggiungiEdizione(
      operaId: operaId,
      publisher: publisher,
    );
    await repository.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
    );
    return edizioneId;
  }

  Future<void> aggiungiEdizioniPossedute(
    int quante, {
    String prefisso = 'E',
  }) async {
    for (var i = 0; i < quante; i++) {
      await edizionePosseduta('$prefisso$i');
    }
  }

  group('prima pagina', () {
    test(
      'la finestra carica le prime dimensionePaginaCollezione Edizioni',
      () async {
        await aggiungiEdizioniPossedute(75);
        await container.read(indiceCollezioneProvider.future);

        expect(
          container.read(numeroCaricatiCollezioneProvider),
          dimensionePaginaCollezione,
        );
        final finestra = container.read(edizioniFinestraCollezioneProvider);
        expect(finestra.valueOrNull, hasLength(dimensionePaginaCollezione));
      },
    );

    test(
      'con meno Edizioni della dimensione pagina, la finestra le contiene tutte',
      () async {
        await aggiungiEdizioniPossedute(10);
        await container.read(indiceCollezioneProvider.future);

        final finestra = container.read(edizioniFinestraCollezioneProvider);
        expect(finestra.valueOrNull, hasLength(10));
      },
    );
  });

  group('caricaAltro', () {
    test("estende la finestra di un'altra pagina alla volta", () async {
      await aggiungiEdizioniPossedute(150);
      await container.read(indiceCollezioneProvider.future);

      container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();

      expect(
        container.read(numeroCaricatiCollezioneProvider),
        2 * dimensionePaginaCollezione,
      );
      expect(
        container.read(edizioniFinestraCollezioneProvider).valueOrNull,
        hasLength(2 * dimensionePaginaCollezione),
      );
    });

    test(
      'oltre il totale disponibile, la finestra resta limitata al totale',
      () async {
        await aggiungiEdizioniPossedute(70);
        await container.read(indiceCollezioneProvider.future);

        container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();

        expect(
          container.read(numeroCaricatiCollezioneProvider),
          2 * dimensionePaginaCollezione,
        );
        expect(
          container.read(edizioniFinestraCollezioneProvider).valueOrNull,
          hasLength(70),
        );
      },
    );
  });

  group('reset della finestra', () {
    test('al cambio di filtriCollezioneProvider, torna a una pagina', () async {
      await aggiungiEdizioniPossedute(150, prefisso: 'Bonelli');
      await container.read(indiceCollezioneProvider.future);
      container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();
      expect(
        container.read(numeroCaricatiCollezioneProvider),
        2 * dimensionePaginaCollezione,
      );

      container
          .read(filtriCollezioneProvider.notifier)
          .toggleValore(AsseCollezione.editore, 'inesistente');

      expect(
        container.read(numeroCaricatiCollezioneProvider),
        dimensionePaginaCollezione,
      );
    });

    test(
      'al cambio di soloAggiuntiMeseCorrenteProvider, torna a una pagina',
      () async {
        await aggiungiEdizioniPossedute(150);
        await container.read(indiceCollezioneProvider.future);
        container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();
        expect(
          container.read(numeroCaricatiCollezioneProvider),
          2 * dimensionePaginaCollezione,
        );

        container
            .read(soloAggiuntiMeseCorrenteProvider.notifier)
            .imposta(valore: true);

        expect(
          container.read(numeroCaricatiCollezioneProvider),
          dimensionePaginaCollezione,
        );
      },
    );

    test(
      'un aggiornamento reattivo del catalogo (non un cambio filtri) non '
      'resetta la finestra',
      () async {
        await aggiungiEdizioniPossedute(150);
        await container.read(indiceCollezioneProvider.future);
        container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();
        expect(
          container.read(numeroCaricatiCollezioneProvider),
          2 * dimensionePaginaCollezione,
        );

        // Simula una scansione in corso che aggiunge nuove Edizioni al
        // catalogo mentre l'utente è in scroll.
        await aggiungiEdizioniPossedute(5, prefisso: 'Nuova');
        await pumpEventQueue();

        expect(
          container.read(numeroCaricatiCollezioneProvider),
          2 * dimensionePaginaCollezione,
        );
      },
    );
  });

  group('aggiornamento reattivo della finestra sotto scroll', () {
    test(
      'la finestra riflette il nuovo catalogo mantenendo la posizione '
      'raggiunta',
      () async {
        await aggiungiEdizioniPossedute(150);
        await container.read(indiceCollezioneProvider.future);
        container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();
        final finestraPrima = container.read(
          edizioniFinestraCollezioneProvider,
        );
        expect(
          finestraPrima.valueOrNull,
          hasLength(2 * dimensionePaginaCollezione),
        );

        await aggiungiEdizioniPossedute(5, prefisso: 'Nuova');
        await pumpEventQueue();

        expect(
          container.read(indiceCollezioneProvider).valueOrNull,
          hasLength(155),
        );
        expect(
          container.read(numeroCaricatiCollezioneProvider),
          2 * dimensionePaginaCollezione,
        );
        expect(
          container.read(edizioniFinestraCollezioneProvider).valueOrNull,
          hasLength(2 * dimensionePaginaCollezione),
        );
      },
    );

    test(
      'se il catalogo scende sotto la posizione raggiunta, la finestra si '
      'riduce di conseguenza senza errori',
      () async {
        await aggiungiEdizioniPossedute(70);
        await container.read(indiceCollezioneProvider.future);
        container.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro();
        expect(
          container.read(edizioniFinestraCollezioneProvider).valueOrNull,
          hasLength(70),
        );

        final indice = await container.read(indiceCollezioneProvider.future);
        final daRimuovere = indice.first.edizioneId;
        await (db.update(
          db.copie,
        )..where((c) => c.edizioneId.equals(daRimuovere))).write(
          const CopieCompanion(status: Value(StatoCopia.venduta)),
        );
        await pumpEventQueue();

        expect(
          container.read(edizioniFinestraCollezioneProvider).valueOrNull,
          hasLength(69),
        );
      },
    );
  });

  group('hydratazioneCollezioneProvider', () {
    test(
      'hydrata la cover delle sole Edizioni nella finestra corrente',
      () async {
        final coverId = await repository.aggiungiOpera(title: 'Con cover');
        final edizioneConCoverId = await repository.aggiungiEdizione(
          operaId: coverId,
          coverImage: 'https://example.com/cover.jpg',
        );
        await repository.aggiungiCopia(
          edizioneId: edizioneConCoverId,
          status: StatoCopia.posseduta,
        );
        // 'Con cover' precede alfabeticamente "E0".."E69": resta nella prima
        // pagina con l'ordinamento titolo crescente di default.
        await aggiungiEdizioniPossedute(70);
        await container.read(indiceCollezioneProvider.future);

        final hydratazione = await container.read(
          hydratazioneCollezioneProvider.future,
        );

        expect(
          hydratazione[edizioneConCoverId],
          'https://example.com/cover.jpg',
        );

        final finestra = container
            .read(edizioniFinestraCollezioneProvider)
            .valueOrNull;
        final voceConCover = finestra!.firstWhere(
          (e) => e.edizioneId == edizioneConCoverId,
        );
        expect(voceConCover.coverHydratata, isTrue);
        expect(voceConCover.coverImage, 'https://example.com/cover.jpg');
      },
    );

    test(
      "un'Edizione fuori dalla finestra non compare come hydratata",
      () async {
        await aggiungiEdizioniPossedute(150);
        await container.read(indiceCollezioneProvider.future);

        final visibili = container.read(edizioniVisibiliProvider).valueOrNull!;
        final fuoriFinestra = visibili[dimensionePaginaCollezione].edizioneId;
        await container.read(hydratazioneCollezioneProvider.future);

        final finestra = container
            .read(edizioniFinestraCollezioneProvider)
            .valueOrNull!;
        expect(
          finestra.any((e) => e.edizioneId == fuoriFinestra),
          isFalse,
        );
      },
    );
  });
}
