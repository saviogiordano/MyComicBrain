import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
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
  );
}

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
  final _scartate = StreamController<List<RigaReplicata>>.broadcast();
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

  StatoSincronizzazione get stato => _stato;

  /// [stato] e i suoi cambiamenti.
  Stream<StatoSincronizzazione> get stati async* {
    yield _stato;
    yield* _stati.stream;
  }

  /// Le righe con Modifiche in sospeso tolte dalla Replica perché eliminate
  /// altrove: l'avviso "modifica non salvata".
  Stream<List<RigaReplicata>> get scartate => _scartate.stream;

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
      if (esito.scartate.isNotEmpty && !_chiuso) _scartate.add(esito.scartate);
      _emetti(
        _stato._con(
          fase: FaseSincronizzazione.sincronizzata,
          replicaScaricata: true,
          ultima: _ora(),
        ),
      );
      _programma(periodo);
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
    await _stati.close();
    await _scartate.close();
  }
}
