import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';

/// Il testo dell'avviso per le Modifiche in sospeso scartate perché la riga
/// è stata eliminata su un altro dispositivo (prototipo #201, punto 7): un
/// solo avviso per ciclo. Le righe dello stesso fumetto (la Copia, i suoi
/// autori) contano come una modifica sola.
String avvisoScartate(List<ModificaScartata> scartate) {
  final titoli = {for (final s in scartate) ?s.titolo};
  final senzaTitolo = scartate.where((s) => s.titolo == null).length;
  if (titoli.length == 1) {
    return 'Una modifica non è stata salvata: «${titoli.single}» è stato '
        'eliminato su un altro dispositivo';
  }
  if (scartate.length == 1 && senzaTitolo == 1) {
    return 'Una modifica non è stata salvata: era su dati eliminati su un '
        'altro dispositivo';
  }
  return '${titoli.length + senzaTitolo} modifiche non sono state salvate: '
      'erano su dati eliminati su un altro dispositivo';
}
