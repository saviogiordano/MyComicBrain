import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _cartellaCopertine = 'copertine';

/// Timeout del download — stesso valore di `comicVineTimeout`
/// (`comic_vine_client.dart`): senza un limite esplicito una cover
/// irraggiungibile lascerebbe la conferma del Candidato bloccata a tempo
/// indeterminato.
const copertinaDownloadTimeout = Duration(seconds: 45);

/// Scarica la cover di un Candidato esterno (ComicVine) e la salva nella
/// directory `<ApplicationSupportDirectory>/copertine/` (creata se assente),
/// con nome `<millisecondsSinceEpoch>.jpg` — stesso schema di
/// `ScansioneStorage` per le Scansioni, così il catalogo ha una copia locale
/// della cover invece di dipendere dalla disponibilità futura dell'URL
/// remoto di ComicVine.
///
/// Un fallimento del download (rete, HTTP non-2xx) non deve far fallire la
/// conferma del Candidato: [scarica] ritorna `null` e il chiamante
/// (`ComicsRepository._creaEdizioneDaCandidato`) ricade sull'URL remoto
/// originale — nessun retry, stesso principio di `AnalisiCopertina`/
/// `Identificazione`.
///
/// La directory base è iniettabile per i test (vedi
/// `test/core/data/copertina_downloader_test.dart`); di default è
/// [getApplicationSupportDirectory].
class CopertinaDownloader {
  CopertinaDownloader({
    http.Client? httpClient,
    Future<Directory> Function()? baseDirectory,
  }) : _httpClient = httpClient ?? http.Client(),
       _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  final http.Client _httpClient;
  final Future<Directory> Function() _baseDirectory;

  Future<String?> scarica(String url) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(Uri.parse(url))
          .timeout(copertinaDownloadTimeout);
    } on Object {
      return null;
    }
    if (response.statusCode != 200) return null;

    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, _cartellaCopertine));
    await dir.create(recursive: true);

    final destPath = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final file = await File(destPath).writeAsBytes(response.bodyBytes);
    return file.path;
  }
}
