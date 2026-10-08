import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';

/// Conferma ogni accesso riuscito e riporta alla Dashboard (#171). Sta alla
/// radice dell'app, così copre tutti gli ingressi: Apple, Google, email,
/// link di conferma della mail e ritorno dall'OAuth via browser su
/// Android. Una sessione ripristinata all'avvio non è un accesso: nessun
/// avviso.
class AvvisoAccesso extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sessionControllerProvider.select((s) => s.profilo), (
      prima,
      dopo,
    ) {
      if (prima != null || dopo == null) return;
      vaiAllaDashboard();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(messaggio(dopo))));
    });
    return child;
  }
}
