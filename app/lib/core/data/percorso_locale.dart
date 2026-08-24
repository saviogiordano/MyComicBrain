import 'dart:io';

import 'package:path/path.dart' as p;

/// Sottocartelle note dentro la cartella base dei file locali dell'app
/// (vedi `CopertinaDownloader`) — usate da [risolvi] per riconoscere il
/// suffisso relativo di un percorso "vecchio stile" salvato prima di
/// questa migrazione.
const _cartelleFileLocali = ['copertine', 'scansioni'];

/// Il container dell'app cambia UUID a ogni aggiornamento/reinstallazione
/// su iOS: un percorso *assoluto* persistito in DB in una sessione
/// precedente punta quindi a un container che potrebbe non esistere più,
/// anche se iOS migra il file fisico nella stessa sottocartella relativa
/// (`copertine/`, `scansioni/`). `ComicsRepository` salva perciò solo il
/// percorso relativo alla cartella base da qui in avanti ([relativizza]);
/// [risolvi] lo ricostruisce assoluto sul filesystem corrente, restando
/// compatibile anche con le righe già in DB da prima della migrazione.
String relativizza(String percorsoAssoluto, Directory base) {
  return p.relative(percorsoAssoluto, from: base.path);
}

/// Ricostruisce il percorso assoluto valido *ora* per un valore letto da
/// DB: se è già relativo (salvato dopo la migrazione), lo unisce alla
/// cartella base corrente; se è assoluto "vecchio stile", ne ricava il
/// suffisso a partire dalla sottocartella nota e lo ricostruisce sotto la
/// cartella base corrente invece di quella (ormai inesistente) in cui è
/// stato scritto. Un percorso assoluto che non corrisponde a nessuna
/// sottocartella nota (es. un valore di test, o un futuro formato) torna
/// invariato — [baseDirectory] è *lazy*: non viene invocata affatto in
/// questo caso, per non toccare `path_provider` quando non serve.
Future<String> risolvi(
  String percorsoSalvato,
  Future<Directory> Function() baseDirectory,
) async {
  if (!p.isAbsolute(percorsoSalvato)) {
    final base = await baseDirectory();
    return p.join(base.path, percorsoSalvato);
  }
  for (final cartella in _cartelleFileLocali) {
    final marker = '$cartella${Platform.pathSeparator}';
    final indice = percorsoSalvato.lastIndexOf(marker);
    if (indice != -1) {
      final base = await baseDirectory();
      return p.join(base.path, percorsoSalvato.substring(indice));
    }
  }
  return percorsoSalvato;
}
