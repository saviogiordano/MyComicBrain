// Script temporaneo per la verifica empirica del rischio di rifiuto di
// Claude sul campo `characters` (fog item della mappa #46, vedi #49) — non
// parte della suite, non pensato per essere committato.
//
// Uso: dart run --dart-define-from-file=dart_define.json tool/verify_cv_refusal.dart <img1> <img2> ...
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/verify_cv_refusal.dart <percorso immagine> [...]');
    exit(1);
  }

  final client = ClaudeCoverAnalysisClient();

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
