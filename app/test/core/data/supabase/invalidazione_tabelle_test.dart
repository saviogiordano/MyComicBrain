import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/supabase/invalidazione_tabelle.dart';

void main() {
  late InvalidazioneTabelle invalidazione;

  setUp(() => invalidazione = InvalidazioneTabelle());
  tearDown(() => invalidazione.chiudi());

  test('emette la lettura iniziale e rilegge a ogni segnale sulle sue '
      'tabelle', () async {
    var valore = 0;
    final emessi = <int>[];
    final sottoscrizione = invalidazione
        .osserva({TabellaSupabase.copie}, () async => valore)
        .listen(emessi.add);
    await pumpEventQueue();

    valore = 1;
    invalidazione.segnala({TabellaSupabase.copie, TabellaSupabase.edizioni});
    await pumpEventQueue();

    expect(emessi, [0, 1]);
    await sottoscrizione.cancel();
  });

  test('ignora i segnali su altre tabelle', () async {
    var letture = 0;
    final sottoscrizione = invalidazione
        .osserva({TabellaSupabase.serie}, () async => ++letture)
        .listen((_) {});
    await pumpEventQueue();

    invalidazione.segnala({TabellaSupabase.messaggio});
    await pumpEventQueue();

    expect(letture, 1);
    await sottoscrizione.cancel();
  });

  test('segnali arrivati durante una lettura ne provocano una sola in più, '
      "che vede l'ultima scrittura", () async {
    var valore = 0;
    var letture = 0;
    final inCorso = <Completer<void>>[];
    final emessi = <int>[];
    final sottoscrizione = invalidazione
        .osserva({TabellaSupabase.copie}, () async {
          letture++;
          final letto = valore;
          final completer = Completer<void>();
          inCorso.add(completer);
          await completer.future;
          return letto;
        })
        .listen(emessi.add);
    await pumpEventQueue();

    valore = 1;
    invalidazione.segnala({TabellaSupabase.copie});
    valore = 2;
    invalidazione.segnala({TabellaSupabase.copie});
    inCorso.removeAt(0).complete();
    await pumpEventQueue();
    inCorso.removeAt(0).complete();
    await pumpEventQueue();

    expect(letture, 2);
    expect(emessi, [0, 2]);
    await sottoscrizione.cancel();
  });

  test('un errore di lettura arriva sullo stream senza chiuderlo', () async {
    var fallisci = true;
    final emessi = <Object>[];
    final sottoscrizione = invalidazione
        .osserva({TabellaSupabase.copie}, () async {
          if (fallisci) throw StateError('rete');
          return 'ok';
        })
        .listen(emessi.add, onError: emessi.add);
    await pumpEventQueue();

    fallisci = false;
    invalidazione.segnala({TabellaSupabase.copie});
    await pumpEventQueue();

    expect(emessi.first, isA<StateError>());
    expect(emessi.last, 'ok');
    await sottoscrizione.cancel();
  });

  test('dopo la cancellazione non rilegge più', () async {
    var letture = 0;
    final sottoscrizione = invalidazione
        .osserva({TabellaSupabase.copie}, () async => ++letture)
        .listen((_) {});
    await pumpEventQueue();
    await sottoscrizione.cancel();

    invalidazione.segnala({TabellaSupabase.copie});
    await pumpEventQueue();

    expect(letture, 1);
  });
}
