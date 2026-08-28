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
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/locale_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openrouter_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';

const _defaultConfigPath = 'tool/cover_analysis_config.json';

// Lato lungo massimo e qualità JPEG per la ricompressione della copertina
// prima dell'invio al provider: gli scan di test possono arrivare come PNG
// non compressi a piena risoluzione (es. 4000+ px, 30+ MB), un payload che fa
// scadere il `coverAnalysisTimeout` di 45s condiviso da tutti i client
// (`cover_analysis_client.dart`) senza migliorare l'estrazione — 1568px è la
// soglia oltre la quale i modelli vision la ridimensionano comunque
// internamente.
const _latoLungoMassimo = 1568;
const _qualitaJpeg = 85;

/// Ridimensiona (se necessario) e ricomprime in JPEG l'immagine grezza letta
/// da disco, cosi da inviare al provider un payload di dimensioni ragionevoli
/// a prescindere dal formato/risoluzione del file sorgente.
Uint8List _preparaImmagine(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Formato immagine non riconosciuto.');
  }

  final latoLungo = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final ridimensionata = latoLungo > _latoLungoMassimo
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? _latoLungoMassimo : null,
          height: decoded.height > decoded.width ? _latoLungoMassimo : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  return Uint8List.fromList(
    img.encodeJpg(ridimensionata, quality: _qualitaJpeg),
  );
}

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
      await settings.impostaApiKeyAi(RuoloProviderAi.visivo, p, apiKey);
    }
    final modello = section['modello'] as String?;
    if (modello != null && modello.isNotEmpty) {
      await settings.impostaModello(RuoloProviderAi.visivo, p, modello);
    }
    if (p == AiProvider.locale) {
      final url = section['url'] as String?;
      if (url != null && url.isNotEmpty) {
        await settings.impostaUrlLocale(RuoloProviderAi.visivo, url);
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
  final bytesOriginali = await File(imagePath).readAsBytes();
  final bytes = _preparaImmagine(bytesOriginali);
  print(
    'Immagine: ${bytesOriginali.lengthInBytes} bytes -> '
    '${bytes.lengthInBytes} bytes dopo ridimensionamento/compressione JPEG.',
  );
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
