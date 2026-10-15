import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/avanzamento_primo_download.dart';

/// L'avanzamento del primo download (prototipo #201, punto 3): le righe
/// arrivate da `cambiamenti_da` sul totale delle tabelle replicate,
/// raccontate in fumetti.
void main() {
  test('senza totale: nessuna percentuale, si sta scaricando', () {
    final a = AvanzamentoPrimoDownload.da(righe: 120, dimensioni: null);
    expect(a.frazione, isNull);
    expect(a.fumetti, isNull);
    expect(a.passo, PassoPrimoDownload.scarico);
  });

  test('a metà delle righe, metà dei fumetti', () {
    final a = AvanzamentoPrimoDownload.da(
      righe: 500,
      dimensioni: (righe: 1000, fumetti: 162),
    );
    expect(a.frazione, 0.5);
    expect(a.percentuale, 50);
    expect(a.fumetti, (scaricati: 81, totale: 162));
    expect(a.passo, PassoPrimoDownload.scarico);
  });

  test('tutte le righe arrivate: si salva sul device', () {
    final a = AvanzamentoPrimoDownload.da(
      righe: 1003,
      dimensioni: (righe: 1000, fumetti: 162),
    );
    expect(a.frazione, 1);
    expect(a.fumetti, (scaricati: 162, totale: 162));
    expect(a.passo, PassoPrimoDownload.salvo);
  });

  test('collezione vuota: niente da scaricare', () {
    final a = AvanzamentoPrimoDownload.da(
      righe: null,
      dimensioni: (righe: 0, fumetti: 0),
    );
    expect(a.frazione, 0);
    expect(a.fumetti, (scaricati: 0, totale: 0));
    expect(a.passo, PassoPrimoDownload.scarico);
  });
}
