import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/indicatore_sincronizzazione.dart';

/// Che cosa dice l'indicatore della Sincronizzazione (prototipo #201, punto
/// 1): offline › errore › in corso › cover N/M › sincronizzato.
void main() {
  final ora = DateTime.utc(2026, 10, 15, 12);

  StatoSincronizzazione stato(
    FaseSincronizzazione fase, {
    DateTime? prossimoTentativo,
    ({int scaricate, int totale})? cover,
    DateTime? ultima,
  }) => StatoSincronizzazione(
    fase: fase,
    replicaScaricata: true,
    prossimoTentativo: prossimoTentativo,
    cover: cover,
    ultima: ultima,
  );

  IndicatoreSincronizzazione indicatore(
    StatoSincronizzazione s, {
    int inSospeso = 0,
  }) => IndicatoreSincronizzazione.da(s, inSospeso: inSospeso, ora: ora);

  test('offline, con e senza Modifiche in sospeso', () {
    final senza = indicatore(stato(FaseSincronizzazione.offline));
    expect(senza.tono, TonoIndicatore.offline);
    expect(senza.breve, 'Offline');
    expect(
      senza.spiegazione,
      'Sei offline. Puoi continuare a usare la collezione.',
    );

    final con = indicatore(stato(FaseSincronizzazione.offline), inSospeso: 3);
    expect(con.breve, 'Offline · 3 in attesa');
    expect(
      con.spiegazione,
      'Sei offline. 3 modifiche verranno sincronizzate al ritorno della rete.',
    );
    expect(
      indicatore(stato(FaseSincronizzazione.offline), inSospeso: 1).spiegazione,
      'Sei offline. 1 modifica verrà sincronizzata al ritorno della rete.',
    );
  });

  test('offline copre le cover in arrivo', () {
    final i = indicatore(
      stato(FaseSincronizzazione.offline, cover: (scaricate: 4, totale: 9)),
    );
    expect(i.tono, TonoIndicatore.offline);
  });

  test('errore con il prossimo tentativo in minuti', () {
    final i = indicatore(
      stato(
        FaseSincronizzazione.errore,
        prossimoTentativo: ora.add(const Duration(minutes: 3, seconds: 10)),
      ),
      inSospeso: 2,
    );
    expect(i.tono, TonoIndicatore.errore);
    expect(i.breve, 'Non sincronizzato · riprovo tra 4 min');
    expect(
      i.spiegazione,
      'La sincronizzazione non è riuscita. 2 modifiche restano su questo '
      'telefono. Riprovo tra 4 min.',
    );
  });

  test('errore con un tentativo entro il minuto', () {
    final i = indicatore(
      stato(
        FaseSincronizzazione.errore,
        prossimoTentativo: ora.add(const Duration(seconds: 8)),
      ),
    );
    expect(i.breve, 'Non sincronizzato · riprovo a breve');
  });

  test('in corso, anche durante il debounce dopo una scrittura', () {
    final inCorso = indicatore(stato(FaseSincronizzazione.inCorso));
    expect(inCorso.tono, TonoIndicatore.inCorso);
    expect(inCorso.breve, 'Sincronizzo…');
    expect(inCorso.gira, isTrue);

    // Sincronizzata ma con una scrittura appena fatta: il ciclo parte fra
    // poco.
    final debounce = indicatore(
      stato(FaseSincronizzazione.sincronizzata),
      inSospeso: 2,
    );
    expect(debounce.tono, TonoIndicatore.inCorso);
    expect(debounce.breve, 'Sincronizzo 2…');
  });

  test("prima dell'avvio del primo ciclo conta come in corso", () {
    expect(
      indicatore(stato(FaseSincronizzazione.ferma)).tono,
      TonoIndicatore.inCorso,
    );
  });

  test('cover in arrivo, solo quando tutto il resto è a posto', () {
    final cover = indicatore(
      stato(
        FaseSincronizzazione.sincronizzata,
        cover: (scaricate: 40, totale: 162),
      ),
    );
    expect(cover.tono, TonoIndicatore.cover);
    expect(cover.breve, 'Cover 40/162');
    expect(
      cover.spiegazione,
      'Collezione aggiornata. Scarico le cover: 40 di 162.',
    );

    expect(
      indicatore(
        stato(
          FaseSincronizzazione.inCorso,
          cover: (scaricate: 40, totale: 162),
        ),
      ).tono,
      TonoIndicatore.inCorso,
    );
  });

  test('sincronizzato, con quando', () {
    final i = indicatore(
      stato(
        FaseSincronizzazione.sincronizzata,
        ultima: ora.subtract(const Duration(minutes: 7)),
      ),
    );
    expect(i.tono, TonoIndicatore.sincronizzato);
    expect(i.breve, 'Sincronizzato');
    expect(i.spiegazione, 'Tutto sincronizzato · 7 min fa.');
  });

  test("l'ultima sincronizzazione detta a parole", () {
    String fa(Duration d) => ultimaSincronizzazione(ora.subtract(d), ora);
    expect(ultimaSincronizzazione(null, ora), 'mai');
    expect(fa(const Duration(seconds: 30)), 'adesso');
    expect(fa(const Duration(minutes: 1)), '1 min fa');
    expect(fa(const Duration(minutes: 59)), '59 min fa');
    expect(fa(const Duration(hours: 2, minutes: 5)), '2 h fa');
    expect(fa(const Duration(days: 3)), '3 giorni fa');
    expect(fa(const Duration(days: 1, hours: 2)), 'ieri');
  });
}
