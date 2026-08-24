// Script per la verifica empirica di printingType/classificazione/description
// (Mappa — Campi bibliografici AI, #71/#72) su foto reali — non parte della
// suite. Verifica leggibilità di Tipo di stampa/Classificazione e, soprattutto,
// il tasso di allucinazione della Descrizione su fumetti noti vs. meno noti.
// Usa il provider configurato in dart_define.json (COVER_ANALYSIS_PROVIDER),
// coerente con providers.dart. Stesso pattern di tool/verify_cv_refusal.dart.
//
// Uso: dart run --define=ANTHROPIC_API_KEY=... --define=OPENAI_API_KEY=... --define=COVER_ANALYSIS_PROVIDER=... tool/verify_bibliographic_fields.dart <img1> <img2> ...
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_provider_config.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/verify_bibliographic_fields.dart <percorso immagine> [...]');
    exit(1);
  }

  final client = switch (CoverAnalysisProviderConfig.kind) {
    CoverAnalysisProviderKind.openai => OpenAiCoverAnalysisClient(),
    CoverAnalysisProviderKind.claude => ClaudeCoverAnalysisClient(),
  };
  print('Provider: ${CoverAnalysisProviderConfig.kind}');

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
