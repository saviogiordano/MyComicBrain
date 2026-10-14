import 'dart:math';

final _casuale = Random.secure();

/// Genera UUID v7 (RFC 9562): 48 bit di millisecondi, poi `rand_a` usato come
/// contatore monotono e 62 bit casuali. Ordinati nel tempo, così `order by
/// id` resta l'ordine di creazione (ADR-0008). Gli id di uno stesso
/// generatore sono sempre crescenti, anche nello stesso millisecondo o se
/// l'orologio torna indietro.
class GeneratoreUuidV7 {
  var _ultimoMs = 0;
  var _contatore = 0;

  String genera({DateTime? adesso}) {
    var ms = (adesso ?? DateTime.now()).millisecondsSinceEpoch;
    if (ms > _ultimoMs) {
      _ultimoMs = ms;
      _contatore = _casuale.nextInt(0x400);
    } else {
      ms = _ultimoMs;
      _contatore++;
      if (_contatore > 0xfff) {
        ms = ++_ultimoMs;
        _contatore = 0;
      }
    }
    final bytes = List<int>.generate(16, (_) => _casuale.nextInt(256));
    for (var i = 0; i < 6; i++) {
      bytes[i] = (ms >> (8 * (5 - i))) & 0xff;
    }
    bytes[6] = 0x70 | (_contatore >> 8);
    bytes[7] = _contatore & 0xff;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

final _generatore = GeneratoreUuidV7();

/// Un nuovo UUID v7 dal generatore dell'app: è l'id di ogni riga creata
/// sul device.
String uuidV7() => _generatore.genera();
