import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// La rete vista dal motore: se c'è una connessione e quando cambia.
abstract interface class Rete {
  Future<bool> disponibile();
  Stream<bool> get cambiamenti;
}

class ReteConnectivity implements Rete {
  ReteConnectivity([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> disponibile() async =>
      _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get cambiamenti =>
      _connectivity.onConnectivityChanged.map(_online).distinct();

  static bool _online(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);
}

enum FaseSincronizzazione {
  /// Non è ancora partito nessun ciclo.
  ferma,

  /// Un ciclo è in corso o sta per partire (debounce delle scritture).
  inCorso,

  /// Senza rete: si riparte quando torna.
  offline,

  /// L'ultimo ciclo è fallito: si ritenta a `prossimoTentativo`.
  errore,

  /// L'ultimo ciclo è riuscito.
  sincronizzata,
}

/// Lo stato che la UI della Sincronizzazione legge (prototipo #201).
class StatoSincronizzazione {
  const StatoSincronizzazione({
    required this.fase,
    required this.replicaScaricata,
    this.ultima,
    this.prossimoTentativo,
    this.errore,
    this.righeScaricate,
    this.cover,
  });

  final FaseSincronizzazione fase;

  /// Se il primo download è già riuscito. Finché è false la Replica è vuota
  /// e la UI mostra il primo download (o "Serve una connessione").
  final bool replicaScaricata;

  /// L'ultima sincronizzazione completa.
  final DateTime? ultima;

  /// Con [FaseSincronizzazione.errore] o [FaseSincronizzazione.offline],
  /// quando parte il prossimo tentativo da solo.
  final DateTime? prossimoTentativo;
  final Object? errore;

  /// Le righe arrivate finora durante il pull in corso: l'avanzamento del
  /// primo download.
  final int? righeScaricate;

  /// Le cover in arrivo in background dopo un ciclo, quante su quante
  /// ("Cover N/M"); null quando non se ne scaricano. Non dipende dalla
  /// fase: un ciclo può partire e finire mentre arrivano.
  final ({int scaricate, int totale})? cover;

  StatoSincronizzazione _con({
    required FaseSincronizzazione fase,
    bool? replicaScaricata,
    DateTime? ultima,
    DateTime? prossimoTentativo,
    Object? errore,
    int? righeScaricate,
  }) => StatoSincronizzazione(
    fase: fase,
    replicaScaricata: replicaScaricata ?? this.replicaScaricata,
    ultima: ultima ?? this.ultima,
    prossimoTentativo: prossimoTentativo,
    errore: errore,
    righeScaricate: righeScaricate,
    cover: cover,
  );

  StatoSincronizzazione _conCover(({int scaricate, int totale})? cover) =>
      StatoSincronizzazione(
        fase: fase,
        replicaScaricata: replicaScaricata,
        ultima: ultima,
        prossimoTentativo: prossimoTentativo,
        errore: errore,
        righeScaricate: righeScaricate,
        cover: cover,
      );
}

/// Una riga con Modifiche in sospeso tolta dalla Replica perché eliminata
/// altrove, col titolo per l'avviso "modifica non salvata" se ce l'ha.
typedef ModificaScartata = ({RigaReplicata riga, String? titolo});

/// L'esito di [MotoreSincronizzazione.sincronizzaOra].
sealed class EsitoSincronizzazione {
  const EsitoSincronizzazione();
}

class SincronizzazioneRiuscita extends EsitoSincronizzazione {
  const SincronizzazioneRiuscita(this.ciclo);

  final EsitoCiclo ciclo;
}

class SincronizzazioneFallita extends EsitoSincronizzazione {
  const SincronizzazioneFallita(this.errore, {required this.offline});

  final Object errore;

  /// Se è fallita per mancanza di rete.
  final bool offline;
}

/// Il motore di Sincronizzazione della Replica di un Profilo (ADR-0008):
/// decide quando far girare un ciclo di [Sincronizzatore] ed espone lo
/// stato alla UI.
///
/// Inneschi: [avvia] (apertura dell'app), il ritorno in primo piano, il
/// ritorno della rete, le scritture locali (debounce di [debounce]) e ogni
/// [periodo] in primo piano. Un errore si ritenta con backoff esponenziale
/// da [backoffIniziale] fino a [backoffMassimo]. In background e senza rete
/// non parte nulla. I cicli non si sovrappongono: un innesco durante un
/// ciclo ne fa partire un altro subito dopo.
///
/// Dopo ogni ciclo riuscito scarica in background le cover che mancano sul
/// device, senza bloccare i cicli successivi.
class MotoreSincronizzazione {
  MotoreSincronizzazione({
    required Sincronizzatore sincronizzatore,
    required Rete rete,
    Stream<void>? scritture,
    this.debounce = const Duration(seconds: 2),
    this.periodo = const Duration(minutes: 5),
    this.backoffIniziale = const Duration(seconds: 2),
    this.backoffMassimo = const Duration(minutes: 5),
    DateTime Function()? ora,
  }) : _sincronizzatore = sincronizzatore,
       _rete = rete,
       _scritture = scritture,
       _ora = ora ?? DateTime.now;

  final Sincronizzatore _sincronizzatore;
  final Rete _rete;
  final Stream<void>? _scritture;
  final Duration debounce;
  final Duration periodo;
  final Duration backoffIniziale;
  final Duration backoffMassimo;
  final DateTime Function() _ora;

  final _stati = StreamController<StatoSincronizzazione>.broadcast();
  final _scartate = StreamController<List<ModificaScartata>>.broadcast();
  final _rifiuti = StreamController<List<ModificaRifiutata>>.broadcast();
  var _stato = const StatoSincronizzazione(
    fase: FaseSincronizzazione.ferma,
    replicaScaricata: false,
  );

  final _iscrizioni = <StreamSubscription<Object?>>[];
  Timer? _timerDebounce;
  Timer? _timerProssimo;
  var _inPrimoPiano = true;
  var _online = true;
  var _tentativiFalliti = 0;
  var _chiuso = false;

  Future<EsitoSincronizzazione>? _cicloInCorso;
  Completer<EsitoSincronizzazione>? _cicloSuccessivo;
  Future<void>? _coverInCorso;
  var _coverDiNuovo = false;

  StatoSincronizzazione get stato => _stato;

  /// [stato] e i suoi cambiamenti, a partire da quando [avvia] ha letto
  /// dove è arrivata la Replica: prima [StatoSincronizzazione.replicaScaricata]
  /// non vale ancora nulla.
  Stream<StatoSincronizzazione> get stati async* {
    if (_avviato) yield _stato;
    yield* _stati.stream;
  }

  var _avviato = false;

  /// Le righe con Modifiche in sospeso tolte dalla Replica perché eliminate
  /// altrove: l'avviso "modifica non salvata".
  Stream<List<ModificaScartata>> get scartate => _scartate.stream;

  /// Le Modifiche appena rifiutate dal server, una volta per rifiuto: lo
  /// snackbar (#225).
  Stream<List<ModificaRifiutata>> get rifiuti => _rifiuti.stream;

  /// Le Modifiche rifiutate, aggiornate a ogni rifiuto, Riprova e Scarta:
  /// la sezione "Non accettate dal server".
  Stream<List<ModificaRifiutata>> watchRifiutate() =>
      _sincronizzatore.watchRifiutate();

  /// Riprova: la Modifica rifiutata [voce] torna nel push, con un ciclo
  /// subito se c'è rete.
  Future<void> riprova(String voce) async {
    await _sincronizzatore.riprova(voce);
    if (!_chiuso && _online) unawaited(_esegui());
  }

  /// Scarta: abbandona le Modifiche in sospeso di [riga] e la riallinea a
  /// Supabase (vedi [Sincronizzatore.scarta]). Aspetta il ciclo in corso,
  /// così non si accavalla al push della stessa riga. Serve la rete.
  Future<void> scarta(RigaReplicata riga) async {
    try {
      await _cicloInCorso;
    } on Object {
      // Già riportato nello stato.
    }
    await _sincronizzatore.scarta(riga);
  }

  /// Apertura dell'app: legge dove è arrivata la Replica, si mette in
  /// ascolto degli inneschi e fa partire il primo ciclo (il primo download,
  /// se la Replica non è ancora stata scaricata).
  Future<void> avvia() async {
    final salvato = await _sincronizzatore.stato();
    _stato = StatoSincronizzazione(
      fase: FaseSincronizzazione.ferma,
      replicaScaricata: salvato != null,
      ultima: salvato?.ultima,
    );
    _avviato = true;
    _emetti(_stato);
    _iscrizioni
      ..add(_rete.cambiamenti.listen(_cambioRete))
      ..add((_scritture ?? const Stream<void>.empty()).listen(_scrittura));
    _online = await _rete.disponibile();
    if (_chiuso) return;
    if (_online) {
      unawaited(_esegui());
    } else {
      _emetti(_stato._con(fase: FaseSincronizzazione.offline));
    }
  }

  /// Il ritorno in primo piano: un ciclo subito.
  void tornaInPrimoPiano() {
    if (_chiuso || _inPrimoPiano) return;
    _inPrimoPiano = true;
    if (_online) unawaited(_esegui());
  }

  /// In background non parte nulla: niente sincronizzazione ad app chiusa.
  void vaInBackground() {
    _inPrimoPiano = false;
    _timerDebounce?.cancel();
    _timerProssimo?.cancel();
  }

  /// Un ciclo adesso, anche durante il backoff, che parte dopo l'eventuale
  /// ciclo in corso così da includere le ultime scritture. Serve a
  /// "Sincronizza ora" e a "Sincronizza e esci" al logout.
  Future<EsitoSincronizzazione> sincronizzaOra() {
    if (_chiuso) {
      return Future.value(
        SincronizzazioneFallita(StateError('motore chiuso'), offline: false),
      );
    }
    return _esegui();
  }

  void _cambioRete(bool online) {
    final tornata = online && !_online;
    _online = online;
    if (_chiuso) return;
    if (!online) {
      _timerProssimo?.cancel();
      if (_cicloInCorso == null) {
        _emetti(_stato._con(fase: FaseSincronizzazione.offline));
      }
    } else if (tornata && _inPrimoPiano) {
      _tentativiFalliti = 0;
      unawaited(_esegui());
    }
  }

  void _scrittura(void _) {
    if (_chiuso || !_inPrimoPiano) return;
    _timerDebounce?.cancel();
    _timerDebounce = Timer(debounce, () {
      // Durante il backoff ci pensa il tentativo già programmato.
      if (_stato.fase == FaseSincronizzazione.errore || !_online) return;
      unawaited(_esegui());
    });
  }

  Future<EsitoSincronizzazione> _esegui() {
    if (_cicloInCorso != null) {
      return (_cicloSuccessivo ??= Completer()).future;
    }
    final ciclo = _ciclo();
    _cicloInCorso = ciclo;
    unawaited(
      ciclo.whenComplete(() {
        _cicloInCorso = null;
        final successivo = _cicloSuccessivo;
        _cicloSuccessivo = null;
        if (successivo == null) return;
        successivo.complete(
          _chiuso
              ? SincronizzazioneFallita(
                  StateError('motore chiuso'),
                  offline: false,
                )
              : _esegui(),
        );
      }),
    );
    return ciclo;
  }

  Future<EsitoSincronizzazione> _ciclo() async {
    _timerDebounce?.cancel();
    _timerProssimo?.cancel();
    _emetti(_stato._con(fase: FaseSincronizzazione.inCorso));
    try {
      final esito = await _sincronizzatore.sincronizza(
        avanzamento: (righe) => _emetti(
          _stato._con(
            fase: FaseSincronizzazione.inCorso,
            righeScaricate: righe,
          ),
        ),
      );
      _tentativiFalliti = 0;
      if (esito.scartate.isNotEmpty && !_chiuso) {
        _scartate.add([
          for (final riga in esito.scartate)
            (riga: riga, titolo: esito.titoli[riga]),
        ]);
      }
      if (esito.rifiutate.isNotEmpty && !_chiuso) {
        _rifiuti.add(esito.rifiutate);
      }
      _emetti(
        _stato._con(
          fase: FaseSincronizzazione.sincronizzata,
          replicaScaricata: true,
          ultima: _ora(),
        ),
      );
      _programma(periodo);
      _scaricaCover();
      return SincronizzazioneRiuscita(esito);
    } on Object catch (errore) {
      if (_chiuso) {
        return SincronizzazioneFallita(errore, offline: false);
      }
      final offline = _diRete(errore) && !(await _rete.disponibile());
      if (offline) _online = false;
      final attesa = _backoff();
      _emetti(
        _stato._con(
          fase: offline
              ? FaseSincronizzazione.offline
              : FaseSincronizzazione.errore,
          prossimoTentativo: offline ? null : _ora().add(attesa),
          errore: errore,
        ),
      );
      // Senza rete riparte al suo ritorno.
      if (!offline) _programma(attesa);
      return SincronizzazioneFallita(errore, offline: offline);
    }
  }

  /// Le cover in background. Se un ciclo finisce mentre arrivano, il giro
  /// riparte alla fine per le cover portate da quel ciclo. Un errore non
  /// cambia lo stato: le cover mancanti si riprovano dopo il ciclo
  /// successivo.
  void _scaricaCover() {
    if (_chiuso) return;
    if (_coverInCorso != null) {
      _coverDiNuovo = true;
      return;
    }
    _coverInCorso = _sincronizzatore
        .scaricaCover(
          avanzamento: (scaricate, totale) => _emetti(
            _stato._conCover((scaricate: scaricate, totale: totale)),
          ),
          interrompi: () => _chiuso,
        )
        .then<void>(
          (_) {},
          // Senza rete un nuovo giro fallirebbe subito: ci pensa il ciclo.
          onError: (Object _) {
            _coverDiNuovo = false;
          },
        )
        .whenComplete(() {
          _coverInCorso = null;
          _emetti(_stato._conCover(null));
          if (_coverDiNuovo) {
            _coverDiNuovo = false;
            _scaricaCover();
          }
        });
  }

  Duration _backoff() {
    final ms = backoffIniziale.inMilliseconds * pow(2, _tentativiFalliti++);
    return Duration(
      milliseconds: min(ms, backoffMassimo.inMilliseconds).toInt(),
    );
  }

  void _programma(Duration attesa) {
    _timerProssimo?.cancel();
    if (_chiuso || !_inPrimoPiano) return;
    _timerProssimo = Timer(attesa, () {
      if (_online && _inPrimoPiano) unawaited(_esegui());
    });
  }

  static bool _diRete(Object errore) =>
      errore is SocketException ||
      errore is http.ClientException ||
      errore is TimeoutException ||
      errore is AuthRetryableFetchException;

  void _emetti(StatoSincronizzazione stato) {
    _stato = stato;
    if (!_chiuso) _stati.add(stato);
  }

  /// Ferma gli inneschi e aspetta il ciclo in corso: al logout, prima di
  /// chiudere la Replica. Si può chiamare più volte.
  Future<void> chiudi() => _chiusura ??= _chiudi();

  Future<void>? _chiusura;

  Future<void> _chiudi() async {
    _chiuso = true;
    _timerDebounce?.cancel();
    _timerProssimo?.cancel();
    for (final i in _iscrizioni) {
      await i.cancel();
    }
    try {
      await _cicloInCorso;
    } on Object {
      // Già riportato nello stato.
    }
    await _coverInCorso;
    await _stati.close();
    await _scartate.close();
    await _rifiuti.close();
  }
}
