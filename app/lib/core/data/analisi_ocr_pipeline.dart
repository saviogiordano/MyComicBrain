import 'dart:convert';
import 'dart:io';

import 'package:mycomicbrain/core/data/claude_ocr_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';

/// Pipeline di analisi OCR di fine batch (§6.1, deciso su #27/#32): per ogni
/// Scansione appena confermata, chiama Claude, fa il parsing della risposta
/// secondo lo schema deciso (#31) e persiste il risultato — completata o
/// fallita, nessun retry automatico. Le Scansioni del batch sono processate
/// in sequenza: un batch di fine sessione non ha requisiti di concorrenza,
/// e restare sequenziali evita di sommare più chiamate in parallelo contro
/// il rate limit (vedi ricerca #28).
class AnalisiOcrPipeline {
  AnalisiOcrPipeline({required ComicsRepository repository, ClaudeOcrClient? client})
    : _repository = repository,
      _client = client ?? ClaudeOcrClient();

  final ComicsRepository _repository;
  final ClaudeOcrClient _client;

  /// Avvia l'analisi per ogni Scansione del batch, identificata dal
  /// percorso immagine già persistito (#21). Ogni Scansione è indipendente:
  /// il fallimento di una non blocca le altre.
  Future<void> avviaBatch(Iterable<String> percorsiImmagine) async {
    for (final percorso in percorsiImmagine) {
      await _avviaUna(percorso);
    }
  }

  Future<void> _avviaUna(String percorsoImmagine) async {
    final scansioneId = await _repository.idScansionePerImmagine(percorsoImmagine);
    final analisiId = await _repository.avviaAnalisiOcr(scansioneId: scansioneId);

    try {
      final bytes = await File(percorsoImmagine).readAsBytes();
      final risultato = await _client.estraiCopertina(bytes);
      await _repository.completaAnalisiOcr(
        id: analisiId,
        title: risultato.title,
        issueNumberLabel: risultato.issueNumberLabel,
        publisher: risultato.publisher,
        seriesName: risultato.seriesName,
        isbn: risultato.isbn,
        barcode: risultato.barcode,
        price: risultato.price,
        rawResponse: jsonEncode(risultato.raw),
      );
    } on Object catch (e) {
      await _repository.fallisciAnalisiOcr(id: analisiId, errorMessage: e.toString());
    }
  }
}
