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

/// [CoverAnalysisClient] finto per "Verifica configurazione" (#108): non
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

/// [ComicVineClient] finto per "Verifica configurazione" (#108): non
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
    CoverAnalysisClient? aiClient,
    ComicVineClient? comicVineClient,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          if (aiClient != null)
            coverAnalysisClientProvider.overrideWithValue(aiClient),
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

  testWidgets('senza provider salvato mostra il default Claude', (
    tester,
  ) async {
    await pumpImpostazioni(tester);

    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('claude-sonnet-5'), findsOneWidget);
    expect(find.text('Non impostata'), findsNWidgets(2));
  });

  testWidgets('modificare la API key AI la persiste nel repository', (
    tester,
  ) async {
    await pumpImpostazioni(tester);

    await tester.tap(find.text('API key').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'chiave-claude');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('••••••••'), findsOneWidget);
    expect(await repo.apiKeyAi(AiProvider.claude), 'chiave-claude');
  });

  testWidgets(
    'cambiare provider persiste la scelta e ricarica la sua API key',
    (
      tester,
    ) async {
      await repo.impostaApiKeyAi(AiProvider.openai, 'chiave-openai');
      await pumpImpostazioni(tester);

      await tester.tap(find.text('Provider').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI'));
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

  group('"Verifica configurazione" (#108: test reale del provider)', () {
    testWidgets('con AI e ComicVine entrambi raggiungibili mostra "OK"', (
      tester,
    ) async {
      await pumpImpostazioni(
        tester,
        aiClient: _FakeCoverAnalysisClient(),
        comicVineClient: _FakeComicVineClient(),
      );

      expect(find.text('Non verificata'), findsOneWidget);

      await tester.tap(find.text('Verifica configurazione'));
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('con la chiave AI non valida mostra il motivo del fallimento', (
      tester,
    ) async {
      await pumpImpostazioni(
        tester,
        aiClient: _FakeCoverAnalysisClient(
          eccezione: CoverAnalysisException(
            'Claude API 401: chiave non valida',
          ),
        ),
        comicVineClient: _FakeComicVineClient(),
      );

      await tester.tap(find.text('Verifica configurazione'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('AI: Claude API 401: chiave non valida'),
        findsOneWidget,
      );
    });

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

        await tester.tap(find.text('Verifica configurazione'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('ComicVine: ComicVine status_code 100'),
          findsOneWidget,
        );
      },
    );
  });
}
