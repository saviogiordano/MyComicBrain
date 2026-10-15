import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';

/// Inneschi, backoff e stato del motore di Sincronizzazione (ADR-0008), con
/// un ciclo finto e il tempo simulato.
void main() {
  late _Sincronizzatore sync;
  late _Rete rete;
  late StreamController<void> scritture;
  late MotoreSincronizzazione motore;
  late DateTime adesso;

  void crea(FakeAsync async, {bool scaricata = true, bool online = true}) {
    adesso = DateTime.utc(2026, 10, 15, 12);
    sync = _Sincronizzatore(scaricata: scaricata);
    rete = _Rete(online: online);
    scritture = StreamController<void>.broadcast();
    motore = MotoreSincronizzazione(
      sincronizzatore: sync,
      rete: rete,
      scritture: scritture.stream,
      ora: () => adesso.add(async.elapsed),
    );
    unawaited(motore.avvia());
    async.flushMicrotasks();
  }

  test("all'avvio fa il primo download e poi è sincronizzata", () {
    fakeAsync((async) {
      crea(async, scaricata: false);
      expect(motore.stato.fase, FaseSincronizzazione.inCorso);
      expect(motore.stato.replicaScaricata, isFalse);
      sync.avanzamento!(40);
      expect(motore.stato.righeScaricate, 40);

      sync.termina();
      async.flushMicrotasks();
      expect(motore.stato.fase, FaseSincronizzazione.sincronizzata);
      expect(motore.stato.replicaScaricata, isTrue);
      expect(motore.stato.ultima, adesso);
      expect(sync.cicli, 1);
    });
  });

  test("senza rete all'avvio resta offline e riparte quando torna", () {
    fakeAsync((async) {
      crea(async, scaricata: false, online: false);
      expect(motore.stato.fase, FaseSincronizzazione.offline);
      expect(sync.cicli, 0);

      rete.cambia(online: true);
      async.flushMicrotasks();
      expect(sync.cicli, 1);
    });
  });

  test('una scrittura locale sincronizza dopo circa 2 s di quiete', () {
    fakeAsync((async) {
      crea(async);
      sync.termina();
      async.flushMicrotasks();

      scritture.add(null);
      async.elapse(const Duration(milliseconds: 1500));
      scritture.add(null);
      async.elapse(const Duration(milliseconds: 1500));
      expect(sync.cicli, 1, reason: 'il debounce riparte a ogni scrittura');
      async.elapse(const Duration(milliseconds: 600));
      expect(sync.cicli, 2);
    });
  });

  test('ogni 5 minuti in primo piano, mai in background', () {
    fakeAsync((async) {
      crea(async);
      sync.termina();
      async
        ..flushMicrotasks()
        ..elapse(const Duration(minutes: 5));
      expect(sync.cicli, 2);
      sync.termina();
      async.flushMicrotasks();

      motore.vaInBackground();
      scritture.add(null);
      async.elapse(const Duration(minutes: 20));
      expect(sync.cicli, 2);

      motore.tornaInPrimoPiano();
      async.flushMicrotasks();
      expect(sync.cicli, 3);
    });
  });

  test('un errore si ritenta con backoff esponenziale fino a 5 minuti', () {
    fakeAsync((async) {
      crea(async);
      final attese = <Duration>[];
      for (var i = 0; i < 10; i++) {
        final prima = async.elapsed;
        sync.fallisci(StateError('500'));
        async.flushMicrotasks();
        expect(motore.stato.fase, FaseSincronizzazione.errore);
        final prossimo = motore.stato.prossimoTentativo!;
        async.elapse(prossimo.difference(adesso.add(async.elapsed)));
        expect(sync.cicli, i + 2);
        attese.add(async.elapsed - prima);
      }
      expect(attese.first, const Duration(seconds: 2));
      expect(attese[1], const Duration(seconds: 4));
      expect(attese.last, const Duration(minutes: 5));

      sync.termina();
      async.flushMicrotasks();
      expect(motore.stato.fase, FaseSincronizzazione.sincronizzata);
      async.elapse(const Duration(minutes: 5));
      sync.fallisci(StateError('500'));
      async.flushMicrotasks();
      expect(
        motore.stato.prossimoTentativo!.difference(adesso.add(async.elapsed)),
        const Duration(seconds: 2),
        reason: 'un successo azzera il backoff',
      );
    });
  });

  test('un errore di rete senza connessione porta offline', () {
    fakeAsync((async) {
      crea(async);
      rete.online = false;
      sync.fallisci(const SocketException('no route'));
      async.flushMicrotasks();
      expect(motore.stato.fase, FaseSincronizzazione.offline);
      async.elapse(const Duration(minutes: 10));
      expect(sync.cicli, 1);

      rete.cambia(online: true);
      async.flushMicrotasks();
      expect(sync.cicli, 2);
    });
  });

  test(
    "sincronizzaOra durante un ciclo ne fa un altro dopo e ne dà l'esito",
    () {
      fakeAsync((async) {
        crea(async);
        EsitoSincronizzazione? esito;
        unawaited(motore.sincronizzaOra().then((e) => esito = e));
        async.flushMicrotasks();
        expect(sync.cicli, 1);

        sync.termina();
        async.flushMicrotasks();
        expect(sync.cicli, 2);
        expect(esito, isNull);

        sync.fallisci(StateError('500'));
        async.flushMicrotasks();
        expect(esito, isA<SincronizzazioneFallita>());
      });
    },
  );

  test('dopo un ciclo riuscito scarica le cover in background, con '
      "l'avanzamento nello stato", () {
    fakeAsync((async) {
      crea(async);
      expect(sync.giriCover, 0);
      sync.termina();
      async.flushMicrotasks();
      expect(sync.giriCover, 1);
      expect(motore.stato.cover, isNull);

      sync.avanzamentoCover!(3, 10);
      expect(motore.stato.cover, (scaricate: 3, totale: 10));
      expect(motore.stato.fase, FaseSincronizzazione.sincronizzata);

      // Un ciclo durante il download conserva l'avanzamento.
      unawaited(motore.sincronizzaOra());
      async.flushMicrotasks();
      expect(motore.stato.fase, FaseSincronizzazione.inCorso);
      expect(motore.stato.cover, (scaricate: 3, totale: 10));
      sync.termina();
      async.flushMicrotasks();
      expect(sync.giriCover, 1, reason: 'non si sovrappone');

      sync.finisciCover();
      async.flushMicrotasks();
      expect(sync.giriCover, 2, reason: 'le cover portate dal secondo ciclo');
      expect(motore.stato.cover, isNull);
      sync.finisciCover();
      async.flushMicrotasks();
      expect(sync.giriCover, 2);
    });
  });

  test('un errore nel download delle cover non cambia lo stato', () {
    fakeAsync((async) {
      crea(async);
      sync.termina();
      async.flushMicrotasks();
      sync
        ..avanzamentoCover!(0, 4)
        ..fallisciCover(const SocketException('offline'));
      async.flushMicrotasks();
      expect(motore.stato.fase, FaseSincronizzazione.sincronizzata);
      expect(motore.stato.cover, isNull);
      expect(sync.giriCover, 1);
    });
  });

  // Con il tempo reale: `chiudi` aspetta la cancellazione delle iscrizioni,
  // che fakeAsync non fa avanzare.
  test('chiudere interrompe il download delle cover e lo aspetta', () async {
    sync = _Sincronizzatore(scaricata: true);
    motore = MotoreSincronizzazione(
      sincronizzatore: sync,
      rete: _Rete(online: true),
    );
    await motore.avvia();
    sync.termina();
    await pumpEventQueue();
    expect(sync.interrompiCover!(), isFalse);

    var chiuso = false;
    unawaited(motore.chiudi().then((_) => chiuso = true));
    await pumpEventQueue();
    expect(sync.interrompiCover!(), isTrue);
    expect(chiuso, isFalse);

    sync.finisciCover();
    await pumpEventQueue();
    expect(chiuso, isTrue);
  });

  test('le righe scartate arrivano alla UI', () {
    fakeAsync((async) {
      crea(async);
      final scartate = <Object>[];
      motore.scartate.listen(scartate.add);
      sync.termina(scartate: [(tabella: 'copie', id: 'x')]);
      async.flushMicrotasks();
      expect(scartate, [
        [(tabella: 'copie', id: 'x')],
      ]);
    });
  });
}

class _Sincronizzatore implements Sincronizzatore {
  _Sincronizzatore({required bool scaricata}) : _scaricata = scaricata;

  bool _scaricata;
  int cicli = 0;
  late Completer<EsitoCiclo> _ciclo;
  void Function(int)? avanzamento;

  @override
  Future<StatoSincronizzazioneReplica?> stato() async => _scaricata
      ? StatoSincronizzazioneReplica(
          id: 1,
          cursore: '1',
          ultima: DateTime.utc(2026),
        )
      : null;

  @override
  Future<EsitoCiclo> sincronizza({void Function(int)? avanzamento}) {
    cicli++;
    this.avanzamento = avanzamento;
    return (_ciclo = Completer()).future;
  }

  void termina({List<({String tabella, String id})> scartate = const []}) {
    _scaricata = true;
    _ciclo.complete(
      EsitoCiclo(inviate: 0, ricevute: 0, scartate: scartate),
    );
  }

  void fallisci(Object errore) => _ciclo.completeError(errore);

  int giriCover = 0;
  late Completer<void> _cover;
  void Function(int, int)? avanzamentoCover;
  bool Function()? interrompiCover;

  @override
  Future<void> scaricaCover({
    void Function(int, int)? avanzamento,
    bool Function()? interrompi,
  }) {
    giriCover++;
    avanzamentoCover = avanzamento;
    interrompiCover = interrompi;
    return (_cover = Completer()).future;
  }

  void finisciCover() => _cover.complete();

  void fallisciCover(Object errore) => _cover.completeError(errore);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Rete implements Rete {
  _Rete({required this.online});

  bool online;
  final _cambiamenti = StreamController<bool>.broadcast();

  void cambia({required bool online}) {
    this.online = online;
    _cambiamenti.add(online);
  }

  @override
  Future<bool> disponibile() async => online;

  @override
  Stream<bool> get cambiamenti => _cambiamenti.stream;
}
