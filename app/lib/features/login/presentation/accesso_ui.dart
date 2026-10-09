import 'package:flutter/material.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

/// Testo mostrato all'utente per un errore di accesso (#171).
String messaggioErroreAccesso(AuthErrore errore) => switch (errore) {
  AuthErrore.annullato => '',
  AuthErrore.credenzialiErrate => 'Email o password non corrette.',
  AuthErrore.emailNonConfermata =>
    'Conferma prima la tua email: controlla la posta.',
  AuthErrore.emailGiaRegistrata =>
    'Esiste già un account con questa email. Accedi.',
  AuthErrore.passwordDebole =>
    'Password troppo debole: usa almeno 8 caratteri, con maiuscole, '
        'minuscole e numeri.',
  AuthErrore.linkNonValido =>
    'Il link di conferma è scaduto o è già stato usato. Prova ad accedere; '
        'se la tua email non è ancora confermata, chiedi un nuovo link.',
  AuthErrore.rete => 'Serve una connessione a Internet.',
  AuthErrore.sconosciuto => 'Accesso non riuscito. Riprova.',
};

/// Esegue un'azione di accesso mostrando l'eventuale errore in una
/// SnackBar; un annullamento dell'utente (foglio Apple/Google chiuso) non
/// mostra nulla. Restituisce `true` se l'azione è andata a buon fine.
Future<bool> eseguiAccesso(
  BuildContext context,
  Future<void> Function() azione,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await azione();
    return true;
  } on AuthException catch (e) {
    final testo = messaggioErroreAccesso(e.errore);
    if (testo.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(testo)));
    }
    return false;
  }
}

/// Pulsante a tutta larghezza alto 52 delle schermate di ingresso.
class PulsanteIngresso extends StatelessWidget {
  const PulsanteIngresso({
    required this.etichetta,
    required this.onPressed,
    this.stile = StilePulsanteIngresso.primario,
    this.icona,
    super.key,
  });

  final String etichetta;
  final VoidCallback? onPressed;
  final StilePulsanteIngresso stile;
  final Widget? icona;

  @override
  Widget build(BuildContext context) {
    final forma = RoundedRectangleBorder(borderRadius: AppRadii.lgRadius);
    final contenuto = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icona != null) ...[icona!, const SizedBox(width: AppSpacing.xs)],
        Text(etichetta),
      ],
    );
    final pulsante = switch (stile) {
      StilePulsanteIngresso.primario => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(shape: forma),
        child: contenuto,
      ),
      StilePulsanteIngresso.apple => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: forma,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        child: contenuto,
      ),
      StilePulsanteIngresso.contorno => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(shape: forma),
        child: contenuto,
      ),
      StilePulsanteIngresso.testo => TextButton(
        onPressed: onPressed,
        child: contenuto,
      ),
    };
    return SizedBox(width: double.infinity, height: 52, child: pulsante);
  }
}

enum StilePulsanteIngresso { primario, apple, contorno, testo }
