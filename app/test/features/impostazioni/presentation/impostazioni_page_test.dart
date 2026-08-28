import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/features/impostazioni/presentation/impostazioni_page.dart';

/// [CoverAnalysisClient] finto per "Verifica connessione" (#108/#111): non
/// implementa [estraiCopertina] (non usato da questo schermo).
class _FakeCoverAnalysisClient implements CoverAnalysisClient {
  _FakeCoverAnalysisClient({this.eccezione});

  final CoverAnalysisException? eccezione;

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) =>
      throw UnimplementedError();

  @override
  Future<void> verificaConnessione() async {
    final eccezione = this.eccezione;
    if (eccezione != null) throw eccezione;
  }
}

/// [ComicVineClient] finto per "Verifica connessione" (#108/#111): non
/// implementa [cercaIssue] (non usato da questo schermo).
class _FakeComicVineClient implements ComicVineClient {
  _FakeComicVineClient({this.eccezione});

  final ComicVineException? eccezione;

  @override
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  }) => throw UnimplementedError();

  @override
  Future<void> verificaConnessione() async {
    final eccezione = this.eccezione;
    if (eccezione != null) throw eccezione;
  }
}

void main() {
  late SettingsRepository repo;

  setUp(() {
    repo = SettingsRepository.inMemoria();
  });

  Future<void> pumpImpostazioni(
    WidgetTester tester, {
    AiProvider? aiClientPer,
    CoverAnalysisClient? aiClient,
    ComicVineClient? comicVineClient,
  }) async {
    // Viewport ingrandita (§12, dopo #111): con le 4 card provider AI sempre
    // espanse il contenuto eccede gli 800x600 di default e lo `SliverList`
    // non costruisce affatto i widget fuori dall'area visibile+cache — non
    // solo non li fa colpire dal tap, proprio non esistono nell'albero — per
    // cui servirebbe scrollare prima di ogni asserzione/tap. Più semplice
    // rendere l'intera schermata visibile in un colpo solo.
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          if (aiClient != null)
            coverAnalysisClientPerProvider(
              aiClientPer ?? AiProvider.claude,
            ).overrideWithValue(aiClient),
          if (comicVineClient != null)
            comicVineClientProvider.overrideWithValue(comicVineClient),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ImpostazioniPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Individua la riga [titoloRiga] (es. "API key", "Attivo") dentro la card
  /// del provider AI [labelProvider] (es. "Claude") — con tutte e quattro le
  /// card sempre visibili (§12, dopo #111), `find.text('API key')` da solo
  /// non basta più a identificare quella di un provider specifico.
  Finder rigaProvider(String labelProvider, String titoloRiga) {
    final card = find
        .ancestor(of: find.text(labelProvider), matching: find.byType(AppCard))
        .first;
    return find.descendant(of: card, matching: find.text(titoloRiga));
  }

  testWidgets('senza provider salvato mostra il default Claude', (
    tester,
  ) async {
    await pumpImpostazioni(tester);

    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('claude-sonnet-5'), findsOneWidget);
    // 4 card provider AI + ComicVine, nessuna con API key impostata.
    expect(find.text('Non impostata'), findsNWidgets(5));
  });

  testWidgets('modificare la API key AI la persiste nel repository', (
    tester,
  ) async {
    await pumpImpostazioni(tester);

    await tester.tap(rigaProvider('Claude', 'API key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'chiave-claude');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('••••••••'), findsOneWidget);
    expect(await repo.apiKeyAi(AiProvider.claude), 'chiave-claude');
  });

  testWidgets(
    'selezionare "Attivo" su un altro provider persiste la scelta',
    (
      tester,
    ) async {
      await repo.impostaApiKeyAi(AiProvider.openai, 'chiave-openai');
      await pumpImpostazioni(tester);

      await tester.tap(rigaProvider('OpenAI', 'Attivo'));
      await tester.pumpAndSettle();

      expect(repo.providerAi, AiProvider.openai);
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.text('gpt-5.6-terra'), findsOneWidget);
    },
  );

  testWidgets(
    'URL non valido per il provider Locale mostra un errore e non salva',
    (
      tester,
    ) async {
      await repo.impostaProviderAi(AiProvider.locale);
      await pumpImpostazioni(tester);

      await tester.tap(find.text('URL API'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'non-una-url');
      await tester.tap(find.text('Salva'));
      await tester.pump();

      expect(find.textContaining('URL non valido'), findsOneWidget);
      expect(repo.urlLocale, isNull);

      await tester.enterText(
        find.byType(TextField),
        'http://localhost:11434/v1',
      );
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(repo.urlLocale, 'http://localhost:11434/v1');
      expect(find.text('http://localhost:11434/v1'), findsOneWidget);
    },
  );

  testWidgets('modificare la API key ComicVine la persiste nel repository', (
    tester,
  ) async {
    await pumpImpostazioni(tester);

    await tester.tap(find.text('API key').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'chiave-comicvine');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(await repo.apiKeyComics, 'chiave-comicvine');
  });

  group(
    '"Verifica connessione" (#111/#112: test reale del provider, per card)',
    () {
      testWidgets(
        'con AI raggiungibile mostra "OK" solo sulla card verificata',
        (
          tester,
        ) async {
          await pumpImpostazioni(
            tester,
            aiClientPer: AiProvider.claude,
            aiClient: _FakeCoverAnalysisClient(),
            comicVineClient: _FakeComicVineClient(),
          );

          // 4 card provider AI + ComicVine, nessuna ancora verificata.
          expect(find.text('Non verificata'), findsNWidgets(5));

          await tester.tap(rigaProvider('Claude', 'Verifica connessione'));
          await tester.pumpAndSettle();

          expect(find.text('OK'), findsOneWidget);
          expect(find.text('Non verificata'), findsNWidgets(4));
        },
      );

      testWidgets(
        'con la chiave AI non valida mostra il motivo del fallimento',
        (
          tester,
        ) async {
          await pumpImpostazioni(
            tester,
            aiClientPer: AiProvider.claude,
            aiClient: _FakeCoverAnalysisClient(
              eccezione: CoverAnalysisException(
                'Claude API 401: chiave non valida',
              ),
            ),
            comicVineClient: _FakeComicVineClient(),
          );

          await tester.tap(rigaProvider('Claude', 'Verifica connessione'));
          await tester.pumpAndSettle();

          // Il motivo del fallimento compare per esteso in un popup (oltre che,
          // troncato, nella riga) — un messaggio lungo nella sola riga a una
          // riga con ellissi risultava illeggibile. Il titolo del popup è il
          // nome del provider verificato (#112: più card verificabili
          // singolarmente, non più un titolo fisso "Provider AI").
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Claude'),
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('Claude API 401: chiave non valida'),
            findsNWidgets(2),
          );

          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        },
      );

      testWidgets(
        'con ComicVine raggiungibile mostra "OK" solo nella sezione ComicVine',
        (
          tester,
        ) async {
          await pumpImpostazioni(
            tester,
            comicVineClient: _FakeComicVineClient(),
          );

          await tester.tap(find.text('Verifica connessione').last);
          await tester.pumpAndSettle();

          expect(find.text('OK'), findsOneWidget);
          // Le 4 card provider AI restano "Non verificata".
          expect(find.text('Non verificata'), findsNWidgets(4));
        },
      );

      testWidgets(
        'con la chiave ComicVine non valida mostra il motivo del fallimento',
        (
          tester,
        ) async {
          await pumpImpostazioni(
            tester,
            aiClient: _FakeCoverAnalysisClient(),
            comicVineClient: _FakeComicVineClient(
              eccezione: ComicVineException(
                'ComicVine status_code 100: chiave non valida',
              ),
            ),
          );

          await tester.tap(find.text('Verifica connessione').last);
          await tester.pumpAndSettle();

          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Provider fumetti'), findsOneWidget);
          expect(
            find.textContaining('ComicVine status_code 100'),
            findsNWidgets(2),
          );

          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        },
      );
    },
  );
}
