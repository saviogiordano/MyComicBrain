import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';

/// Conferma ogni accesso riuscito e riporta alla Dashboard (#171). Sta alla
/// radice dell'app, così copre tutti gli ingressi: Apple, Google, email,
/// link di conferma della mail e ritorno dall'OAuth via browser su
/// Android. Una sessione ripristinata all'avvio non è un accesso: nessun
/// avviso. Mostra anche l'errore di un link della mail non valido.
class AvvisoAccesso extends ConsumerStatefulWidget {
  const AvvisoAccesso({
    required this.vaiAllaDashboard,
    required this.child,
    super.key,
  });

  final VoidCallback vaiAllaDashboard;
  final Widget child;

  static String messaggio(Profilo profilo) =>
      // L'email di Apple è spesso un indirizzo di inoltro illeggibile.
      profilo.metodo == MetodoAccesso.apple || profilo.email.isEmpty
      ? 'Accesso effettuato'
      : 'Accesso effettuato come ${profilo.email}';

  @override
  ConsumerState<AvvisoAccesso> createState() => _AvvisoAccessoState();
}

class _AvvisoAccessoState extends ConsumerState<AvvisoAccesso> {
  late final StreamSubscription<AuthErrore> _erroriLink;

  @override
  void initState() {
    super.initState();
    _erroriLink = ref
        .read(authGatewayProvider)
        .erroriLink
        .listen((errore) => _mostra(messaggioErroreAccesso(errore)));
  }

  @override
  void dispose() {
    unawaited(_erroriLink.cancel());
    super.dispose();
  }

  void _mostra(String testo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(testo)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider.select((s) => s.profilo), (
      prima,
      dopo,
    ) {
      if (prima != null || dopo == null) return;
      widget.vaiAllaDashboard();
      _mostra(AvvisoAccesso.messaggio(dopo));
    });
    return widget.child;
  }
}
