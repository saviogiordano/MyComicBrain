import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/avviso_rifiuti.dart';

/// Lo snackbar per le Modifiche appena rifiutate dal server (#225).
void main() {
  ModificaRifiutata rifiutata(String voce, {String? titolo}) =>
      ModificaRifiutata(
        voce: voce,
        riga: (tabella: 'copie', id: voce),
        tipo: TipoVoceRegistro.modifica,
        titolo: titolo,
        descrizione: 'Copia modificata',
        codice: '23514',
        messaggio: 'violazione del vincolo',
      );

  test('una modifica col titolo', () {
    expect(
      avvisoRifiuti([rifiutata('a', titolo: 'Dylan Dog 41')]),
      'Una modifica a «Dylan Dog 41» non è stata accettata dal server',
    );
  });

  test('una modifica senza titolo', () {
    expect(
      avvisoRifiuti([rifiutata('a')]),
      'Una modifica non è stata accettata dal server',
    );
  });

  test('più modifiche dello stesso fumetto', () {
    expect(
      avvisoRifiuti([
        rifiutata('a', titolo: 'Maus'),
        rifiutata('b', titolo: 'Maus'),
      ]),
      '2 modifiche a «Maus» non sono state accettate dal server',
    );
  });

  test('più modifiche di fumetti diversi', () {
    expect(
      avvisoRifiuti([
        rifiutata('a', titolo: 'Maus'),
        rifiutata('b', titolo: 'Watchmen'),
        rifiutata('c'),
      ]),
      '3 modifiche non sono state accettate dal server',
    );
  });
}
