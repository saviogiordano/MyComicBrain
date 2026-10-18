import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';

/// Il colore dell'indicatore, uno per stato.
enum TonoIndicatore {
  offline,
  errore,
  inCorso,
  daControllare,
  cover,
  sincronizzato,
}

/// Che cosa racconta l'indicatore della Sincronizzazione (prototipo #201,
/// punto 1, variante A): la pillola in Dashboard ([breve]) e lo sheet o
/// Impostazioni ([spiegazione]). Una sola regola di priorità:
/// offline › errore › in corso › da controllare (#225) › cover N/M ›
/// sincronizzato.
class IndicatoreSincronizzazione {
  const IndicatoreSincronizzazione._({
    required this.tono,
    required this.breve,
    required this.spiegazione,
    this.gira = false,
  });

  /// [inSospeso] sono le righe con Modifiche in sospeso, comprese quelle
  /// trattenute dalle Modifiche [rifiutate]; [ora] serve al conto alla
  /// rovescia del prossimo tentativo e a "N min fa".
  factory IndicatoreSincronizzazione.da(
    StatoSincronizzazione stato, {
    required int inSospeso,
    required DateTime ora,
    List<ModificaRifiutata> rifiutate = const [],
  }) {
    final n = inSospeso;
    switch (stato.fase) {
      case FaseSincronizzazione.offline:
        return IndicatoreSincronizzazione._(
          tono: TonoIndicatore.offline,
          breve: n == 0 ? 'Offline' : 'Offline · $n in attesa',
          spiegazione: n == 0
              ? 'Sei offline. Puoi continuare a usare la collezione.'
              : n == 1
              ? 'Sei offline. 1 modifica verrà sincronizzata al ritorno '
                    'della rete.'
              : 'Sei offline. $n modifiche verranno sincronizzate al '
                    'ritorno della rete.',
        );
      case FaseSincronizzazione.errore:
        final tra = traQuanto(stato.prossimoTentativo, ora);
        return IndicatoreSincronizzazione._(
          tono: TonoIndicatore.errore,
          breve: 'Non sincronizzato · riprovo $tra',
          spiegazione:
              'La sincronizzazione non è riuscita. '
              '${switch (n) {
                0 => '',
                1 => '1 modifica resta su questo telefono. ',
                _ => '$n modifiche restano su questo telefono. ',
              }}'
              'Riprovo $tra.',
        );
      case FaseSincronizzazione.ferma || FaseSincronizzazione.inCorso:
        return IndicatoreSincronizzazione._inCorso(n);
      case FaseSincronizzazione.sincronizzata:
        // Una scrittura appena fatta: il ciclo parte dopo il debounce. Le
        // righe con una Modifica rifiutata restano in sospeso ma il push le
        // salta.
        final trattenute = {for (final r in rifiutate) r.riga}.length;
        if (n > trattenute) {
          return IndicatoreSincronizzazione._inCorso(n - trattenute);
        }
        if (rifiutate.isNotEmpty) {
          final r = rifiutate.length;
          return IndicatoreSincronizzazione._(
            tono: TonoIndicatore.daControllare,
            breve: '$r da controllare',
            spiegazione:
                '${r == 1 ? '1 modifica non è stata accettata' : '$r modifiche non sono state accettate'} '
                'dal server. Le altre si sincronizzano normalmente.',
          );
        }
        final cover = stato.cover;
        if (cover != null) {
          return IndicatoreSincronizzazione._(
            tono: TonoIndicatore.cover,
            breve: 'Cover ${cover.scaricate}/${cover.totale}',
            spiegazione:
                'Collezione aggiornata. Scarico le cover: '
                '${cover.scaricate} di ${cover.totale}.',
          );
        }
        return IndicatoreSincronizzazione._(
          tono: TonoIndicatore.sincronizzato,
          breve: 'Sincronizzato',
          spiegazione:
              'Tutto sincronizzato · '
              '${ultimaSincronizzazione(stato.ultima, ora)}.',
        );
    }
  }

  const IndicatoreSincronizzazione._inCorso(int n)
    : this._(
        tono: TonoIndicatore.inCorso,
        breve: n == 0 ? 'Sincronizzo…' : 'Sincronizzo $n…',
        spiegazione: 'Sincronizzazione in corso.',
        gira: true,
      );

  final TonoIndicatore tono;
  final String breve;
  final String spiegazione;

  /// L'icona che gira, mentre la sincronizzazione è in corso.
  final bool gira;
}

/// "adesso", "N min fa", "N h fa", "ieri", "N giorni fa"; "mai" se non c'è
/// ancora stata.
String ultimaSincronizzazione(DateTime? ultima, DateTime ora) {
  if (ultima == null) return 'mai';
  final fa = ora.difference(ultima);
  if (fa.inMinutes < 1) return 'adesso';
  if (fa.inHours < 1) return '${fa.inMinutes} min fa';
  if (fa.inDays < 1) return '${fa.inHours} h fa';
  if (fa.inDays == 1) return 'ieri';
  return '${fa.inDays} giorni fa';
}

/// Quando parte il prossimo tentativo: "tra N min", o "a breve" entro il
/// minuto.
String traQuanto(DateTime? quando, DateTime ora) {
  if (quando == null) return 'a breve';
  final secondi = quando.difference(ora).inSeconds;
  if (secondi < 60) return 'a breve';
  return 'tra ${(secondi / 60).ceil()} min';
}
