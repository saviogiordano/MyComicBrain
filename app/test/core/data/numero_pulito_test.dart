import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/numero_pulito.dart';

void main() {
  group('numeroPulito', () {
    test('rimuove il prefisso # e gli spazi circostanti', () {
      expect(numeroPulito('#700'), '700');
      expect(numeroPulito('# 700'), '700');
      expect(numeroPulito('  700  '), '700');
    });

    test('null/vuota restano null', () {
      expect(numeroPulito(null), isNull);
      expect(numeroPulito(''), isNull);
      expect(numeroPulito('   '), isNull);
    });
  });

  group('numeroIntero', () {
    test('numero intero semplice', () {
      expect(numeroIntero('700'), 700);
      expect(numeroIntero('#700'), 700);
    });

    // Bug osservato da utente: una Copia con numero "679.1" veniva salvata
    // regolarmente ma non compariva nella griglia numerica di Serie (#99)
    // perché `int.tryParse('679.1')` restituisce `null` sui decimali.
    test('numero decimale usa la parte intera iniziale', () {
      expect(numeroIntero('679.1'), 679);
      expect(numeroIntero('#679.1'), 679);
    });

    test('etichette non numeriche restano null', () {
      expect(numeroIntero('Annual 1'), isNull);
      expect(numeroIntero(null), isNull);
      expect(numeroIntero(''), isNull);
    });

    // Deve restare null (comportamento voluto): un'etichetta con testo dopo
    // il numero non è un decimale, va trattata come non numerica — solo
    // `issueNumberLabel` la porta.
    test('un numero seguito da testo (variant) resta null', () {
      expect(numeroIntero('42 Variant'), isNull);
    });
  });
}
