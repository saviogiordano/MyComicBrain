import 'package:flutter_test/flutter_test.dart';

import '../analisi_copertina_repository_test.dart';
import '../collezione_repository_test.dart';
import '../comics_repository_test.dart';
import '../conversazione_repository_test.dart';
import '../cover_repository_test.dart';
import '../creator_repository_test.dart';
import '../identificazione_repository_test.dart';
import '../scheda_repository_test.dart';
import '../valore_stimato_repository_test.dart';
import 'adapter_sotto_contratto.dart';

/// L'intera suite di contratto su una Replica locale: i trigger del registro
/// delle Modifiche in sospeso (ADR-0008) non devono cambiare il
/// comportamento di nessuna scrittura.
void main() {
  const crea = creaAdapterReplicaInMemoria;
  group('Replica', () {
    group('Catalogo', () => contrattoCatalogo(crea));
    group('Collezione', () => contrattoCollezione(crea));
    group('Creator', () => contrattoCreator(crea));
    group('Scheda', () => contrattoScheda(crea));
    group('Cover', () => contrattoCover(crea));
    group('Analisi Copertina', () => contrattoAnalisiCopertina(crea));
    group('Identificazione', () => contrattoIdentificazione(crea));
    group('Valore stimato', () => contrattoValoreStimato(crea));
    group('Conversazione', () => contrattoConversazione(crea));
  });
}
