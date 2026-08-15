import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stato di navigazione "sono dentro l'app o alla schermata di login".
///
/// Non è autenticazione reale (fuori scope di questa mappa): il Login
/// mostra solo UI, e i suoi pulsanti chiamano [enter] per far passare la
/// sessione a "dentro l'app". Lo stato non è persistito — riparte da
/// [SessionNotifier.build] a ogni avvio (niente `riverpod_generator`,
/// deciso su #9).
class SessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;
}

final sessionProvider = NotifierProvider<SessionNotifier, bool>(
  SessionNotifier.new,
);
