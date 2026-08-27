// Script per la verifica empirica di printingType/classificazione/description
// (Mappa — Campi bibliografici AI, #71/#72) su foto reali — non parte della
// suite. Verifica leggibilità di Tipo di stampa/Classificazione e, soprattutto,
// il tasso di allucinazione della Descrizione su fumetti noti vs. meno noti.
// Provider/chiave letti a runtime da `SettingsRepository` (§12, migrato su
// #106) invece che da dart-define, stesso pattern di
// tool/verify_cv_refusal.dart.
//
// Uso: dart run --define=ANTHROPIC_API_KEY=... --define=OPENAI_API_KEY=... --define=COVER_ANALYSIS_PROVIDER=... tool/verify_bibliographic_fields.dart <img1> <img2> ...
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/verify_bibliographic_fields.dart <percorso immagine> [...]',
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
  await settings.impostaApiKeyAi(AiProvider.claude, anthropicKey);
  await settings.impostaApiKeyAi(AiProvider.openai, openAiKey);

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
      print('title: ${r.title}');
      print('seriesName: ${r.seriesName}');
      print('issueNumberLabel: ${r.issueNumberLabel}');
      print('printingType: ${r.printingType}');
      print('classificazione: ${r.classificazione}');
      print('description: ${r.description}');
    } on CoverAnalysisException catch (e) {
      print('ECCEZIONE: $e');
    }
    print('');
  }
}
