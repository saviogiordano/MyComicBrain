import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/avviso_scartate.dart';

/// L'avviso per le modifiche scartate perché la riga è stata eliminata su
/// un altro dispositivo (prototipo #201, punto 7, variante B).
void main() {
  test('una riga col titolo', () {
    expect(
      avvisoScartate([
        (riga: (tabella: 'copie', id: 'a'), titolo: 'Dylan Dog 41'),
      ]),
      'Una modifica non è stata salvata: «Dylan Dog 41» è stato eliminato su '
      'un altro dispositivo',
    );
  });

  test('più righe dello stesso fumetto contano come una', () {
    expect(
      avvisoScartate([
        (riga: (tabella: 'copie', id: 'a'), titolo: 'Maus'),
        (riga: (tabella: 'comic_creator', id: 'b'), titolo: 'Maus'),
        (riga: (tabella: 'valore_stimato', id: 'c'), titolo: null),
      ]),
      'Una modifica non è stata salvata: «Maus» è stato eliminato su un altro '
      'dispositivo',
    );
  });

  test('una riga senza titolo', () {
    expect(
      avvisoScartate([(riga: (tabella: 'scansioni', id: 'a'), titolo: null)]),
      'Una modifica non è stata salvata: era su dati eliminati su un altro '
      'dispositivo',
    );
  });

  test('più fumetti: un solo avviso con il conteggio', () {
    expect(
      avvisoScartate([
        (riga: (tabella: 'copie', id: 'a'), titolo: 'Maus'),
        (riga: (tabella: 'copie', id: 'b'), titolo: 'Tex 712'),
        (riga: (tabella: 'scansioni', id: 'c'), titolo: null),
      ]),
      '3 modifiche non sono state salvate: erano su dati eliminati su un '
      'altro dispositivo',
    );
  });
}
