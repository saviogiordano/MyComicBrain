// Script per la verifica empirica del rischio di rifiuto sul campo
// `characters` (fog item della mappa #46, vedi #49) — non parte della
// suite. Provider/chiave letti a runtime da `SettingsRepository` (§12,
// migrato su #106) invece che da dart-define: usa `SettingsRepository.inMemoria`
// perché gira con `dart run`, fuori da un binding Flutter.
//
// Uso: dart run --define=ANTHROPIC_API_KEY=... --define=OPENAI_API_KEY=... --define=COVER_ANALYSIS_PROVIDER=... tool/verify_cv_refusal.dart <img1> <img2> ...
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/verify_cv_refusal.dart <percorso immagine> [...]',
    );
    exit(1);
  }

  const anthropicKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  const openAiKey = String.fromEnvironment('OPENAI_API_KEY');
  const providerRaw = String.fromEnvironment(
    'COVER_ANALYSIS_PROVIDER',
    defaultValue: 'claude',
  );
  final provider = providerRaw == 'openai'
      ? AiProvider.openai
      : AiProvider.claude;

  final settings = SettingsRepository.inMemoria();
  await settings.impostaApiKeyAi(
    RuoloProviderAi.visivo,
    AiProvider.claude,
    anthropicKey,
  );
  await settings.impostaApiKeyAi(
    RuoloProviderAi.visivo,
    AiProvider.openai,
    openAiKey,
  );

  final client = switch (provider) {
    AiProvider.openai => OpenAiCoverAnalysisClient(
      settingsRepository: settings,
    ),
    _ => ClaudeCoverAnalysisClient(settingsRepository: settings),
  };
  print('Provider: $provider');

  for (final path in args) {
    print('=== $path ===');
    final bytes = await File(path).readAsBytes();
    try {
      final r = await client.estraiCopertina(bytes);
      print('characters: ${r.characters}');
      print('coverStyleTags: ${r.coverStyleTags}');
      print('visualElementTags: ${r.visualElementTags}');
      print('recognizedPublisherLogo: ${r.recognizedPublisherLogo}');
      print('recognizedSeriesLogo: ${r.recognizedSeriesLogo}');
      print('title: ${r.title}');
      print('raw: ${r.raw}');
    } on CoverAnalysisException catch (e) {
      print('ECCEZIONE: $e');
    }
    print('');
  }
}
