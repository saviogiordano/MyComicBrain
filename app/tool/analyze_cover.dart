// Script per invocare manualmente il provider AI configurato su una singola
// copertina e stamparne l'output completo (#110) — non parte della suite.
// A differenza di tool/verify_*.dart, legge provider/chiave/modello da un
// file JSON locale (default tool/cover_analysis_config.json, gitignored) a
// runtime invece che da `--define` passato a mano a ogni invocazione: evita
// di dover ricompilare/ripetere le chiavi, senza duplicare la logica HTTP,
// popolando comunque `SettingsRepository.inMemoria()` (§12, migrato su #106)
// come fanno gli script esistenti — stesso client usato dall'app.
//
// Uso:
//   cp tool/cover_analysis_config.example.json tool/cover_analysis_config.json
//   # valorizza la sezione del provider scelto in cover_analysis_config.json
//   dart run tool/analyze_cover.dart <percorso immagine> [--config <percorso json>]
import 'dart:convert';
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/locale_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openrouter_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';

const _defaultConfigPath = 'tool/cover_analysis_config.json';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/analyze_cover.dart <percorso immagine> '
      '[--config <percorso json>]',
    );
    exit(1);
  }

  String? imagePath;
  var configPath = _defaultConfigPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--config') {
      if (i + 1 >= args.length) {
        stderr.writeln('--config richiede un percorso.');
        exit(1);
      }
      configPath = args[++i];
    } else {
      imagePath = args[i];
    }
  }
  if (imagePath == null) {
    stderr.writeln('Percorso immagine mancante.');
    exit(1);
  }

  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    stderr.writeln(
      "File di configurazione '$configPath' non trovato. Copia "
      'tool/cover_analysis_config.example.json e valorizzalo.',
    );
    exit(1);
  }
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;

  final provider = AiProvider.values.asNameMap()[config['provider']];
  if (provider == null) {
    stderr.writeln(
      "Campo 'provider' mancante o non valido in $configPath (attesi: "
      '${AiProvider.values.map((p) => p.name).join(', ')}).',
    );
    exit(1);
  }

  final settings = SettingsRepository.inMemoria();
  for (final p in AiProvider.values) {
    final section = config[p.name] as Map<String, dynamic>?;
    if (section == null) continue;
    final apiKey = section['apiKey'] as String?;
    if (apiKey != null && apiKey.isNotEmpty) {
      await settings.impostaApiKeyAi(p, apiKey);
    }
    final modello = section['modello'] as String?;
    if (modello != null && modello.isNotEmpty) {
      await settings.impostaModello(p, modello);
    }
    if (p == AiProvider.locale) {
      final url = section['url'] as String?;
      if (url != null && url.isNotEmpty) {
        await settings.impostaUrlLocale(url);
      }
    }
  }

  final client = switch (provider) {
    AiProvider.openai => OpenAiCoverAnalysisClient(
      settingsRepository: settings,
    ),
    AiProvider.claude => ClaudeCoverAnalysisClient(
      settingsRepository: settings,
    ),
    AiProvider.openRouter => OpenRouterCoverAnalysisClient(
      settingsRepository: settings,
    ),
    AiProvider.locale => LocaleCoverAnalysisClient(
      settingsRepository: settings,
    ),
  };

  print('Provider: ${provider.label}');
  final bytes = await File(imagePath).readAsBytes();
  try {
    final r = await client.estraiCopertina(bytes);
    print('title: ${r.title}');
    print('issueNumberLabel: ${r.issueNumberLabel}');
    print('publisher: ${r.publisher}');
    print('seriesName: ${r.seriesName}');
    print('isbn: ${r.isbn}');
    print('barcode: ${r.barcode}');
    print('price: ${r.price}');
    print('releaseDate: ${r.releaseDate}');
    print('year: ${r.year}');
    print('pageCount: ${r.pageCount}');
    print('language: ${r.language}');
    print('color: ${r.color}');
    print('issn: ${r.issn}');
    print('characters: ${r.characters}');
    print('coverStyleTags: ${r.coverStyleTags}');
    print('visualElementTags: ${r.visualElementTags}');
    print('recognizedPublisherLogo: ${r.recognizedPublisherLogo}');
    print('recognizedSeriesLogo: ${r.recognizedSeriesLogo}');
    print('printingType: ${r.printingType}');
    print('classificazione: ${r.classificazione}');
    print('description: ${r.description}');
    print('raw: ${const JsonEncoder.withIndent('  ').convert(r.raw)}');
  } on CoverAnalysisException catch (e) {
    stderr.writeln('ECCEZIONE: $e');
    exit(1);
  }
}
