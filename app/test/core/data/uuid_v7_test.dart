import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/uuid_v7.dart';

void main() {
  final formatoV7 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('genera uuid v7 nel formato standard', () {
    expect(uuidV7(), matches(formatoV7));
  });

  test("i primi 48 bit sono i millisecondi dell'istante di creazione", () {
    final id = GeneratoreUuidV7().genera(
      adesso: DateTime.utc(2026, 10, 14, 12),
    );
    // 2026-10-14T12:00:00Z = 1791979200000 ms = 0x01a1_3a48_9e00.
    expect(id.substring(0, 13), '01a13a48-9e00');
  });

  test(
    'id generati in sequenza nello stesso millisecondo restano ordinati',
    () {
      final generatore = GeneratoreUuidV7();
      final istante = DateTime.utc(2026, 10, 14);
      final ids = [
        for (var i = 0; i < 5000; i++) generatore.genera(adesso: istante),
      ];
      expect([...ids]..sort(), ids);
      expect(ids.toSet(), hasLength(ids.length));
    },
  );

  test("un orologio che torna indietro non rompe l'ordine", () {
    final generatore = GeneratoreUuidV7();
    final dopo = generatore.genera(adesso: DateTime.utc(2026, 10, 14, 12));
    final prima = generatore.genera(adesso: DateTime.utc(2026, 10, 14, 11));
    expect(prima.compareTo(dopo), greaterThan(0));
  });
}
