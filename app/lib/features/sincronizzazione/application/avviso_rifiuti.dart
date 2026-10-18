import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';

/// Il testo dello snackbar per le Modifiche appena rifiutate dal server
/// (#225): un solo avviso per ciclo, con il titolo se riguardano tutte lo
/// stesso fumetto.
String avvisoRifiuti(List<ModificaRifiutata> rifiutate) {
  final titoli = {for (final r in rifiutate) r.titolo};
  final titolo = titoli.length == 1 ? titoli.single : null;
  final a = titolo == null ? '' : ' a «$titolo»';
  if (rifiutate.length == 1) {
    return 'Una modifica$a non è stata accettata dal server';
  }
  return '${rifiutate.length} modifiche$a non sono state accettate dal server';
}
