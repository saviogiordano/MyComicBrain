import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Timeout per il download di una cover remota durante un export (PDF o
/// zip dati) — stesso valore di `copertinaDownloadTimeout`
/// (`copertina_downloader.dart`): una copia irraggiungibile non deve
/// bloccare a tempo indeterminato l'intero export.
const caricaCopertinaTimeout = Duration(seconds: 45);

/// Legge i byte di una cover già risolta (vedi
/// `ComicsRepository.risolviCoverImage`): file locale o URL remoto, stesso
/// principio di `CopertinaDownloader.scarica`. Qualsiasi fallimento (file
/// assente, HTTP non 200, timeout) torna `null`, mai un errore — condiviso
/// dal PDF/catalogo stampabile e dallo zip dell'export dati.
Future<Uint8List?> caricaBytesCopertina(String coverImage) async {
  try {
    if (coverImage.startsWith('http://') || coverImage.startsWith('https://')) {
      final response = await http
          .get(Uri.parse(coverImage))
          .timeout(caricaCopertinaTimeout);
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    }
    final file = File(coverImage);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  } on Object {
    return null;
  }
}
