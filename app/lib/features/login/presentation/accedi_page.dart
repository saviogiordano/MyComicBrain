import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/requisiti_password.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';

enum ModoAccesso { registrati, accedi }

/// Schermata unica "Crea il tuo account" / "Accedi" (#171, prototipo #170):
/// Apple e Google in alto, sotto email+password. Raggiunta dal benvenuto e
/// da Impostazioni (Modalità locale). Su accesso riuscito si chiude: il
/// router porta comunque dentro l'app quando nasce la sessione.
class AccediPage extends ConsumerStatefulWidget {
  const AccediPage({required this.modo, super.key});

  final ModoAccesso modo;

  @override
  ConsumerState<AccediPage> createState() => _AccediPageState();
}

class _AccediPageState extends ConsumerState<AccediPage> {
  late ModoAccesso _modo = widget.modo;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _inCorso = false;
  bool _passwordVisibile = false;

  @override
  void initState() {
    super.initState();
    // Ricostruisce la checklist dei requisiti mentre si scrive.
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _registrazione => _modo == ModoAccesso.registrati;

  bool get _puoInviare =>
      !_inCorso &&
      (!_registrazione || requisitiMancanti(_password.text).isEmpty);

  Future<void> _esegui(Future<void> Function() azione) async {
    setState(() => _inCorso = true);
    final riuscito = await eseguiAccesso(context, azione);
    if (!mounted) return;
    setState(() => _inCorso = false);
    if (riuscito) await Navigator.of(context).maybePop();
  }

  Future<void> _inviaEmail() async {
    final controller = ref.read(sessionControllerProvider.notifier);
    final email = _email.text.trim();
    final password = _password.text;
    if (!_registrazione) {
      return _esegui(() => controller.accediConEmail(email, password));
    }
    final messenger = ScaffoldMessenger.of(context);
    await _esegui(() async {
      await controller.registratiConEmail(email, password);
      messenger.showSnackBar(
        SnackBar(content: Text('Link di conferma inviato a $email')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(sessionControllerProvider.notifier);
    final testoSecondario = AppTypography.bodyMedium.copyWith(
      color: AppColors.textTertiary,
    );

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xs,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          children: [
            Text(
              _registrazione ? 'Crea il tuo account' : 'Accedi',
              style: AppTypography.headline.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _registrazione
                  ? 'La collezione sarà salvata nel tuo account e la '
                        'ritroverai su ogni dispositivo.'
                  : 'Ritrova la tua collezione.',
              style: testoSecondario,
            ),
            const SizedBox(height: AppSpacing.lg),
            PulsanteIngresso(
              etichetta: 'Continua con Apple',
              stile: StilePulsanteIngresso.apple,
              icona: const Icon(Icons.apple, size: 20),
              onPressed: _inCorso
                  ? null
                  : () => _esegui(controller.accediConApple),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
            PulsanteIngresso(
              etichetta: 'Continua con Google',
              stile: StilePulsanteIngresso.contorno,
              onPressed: _inCorso
                  ? null
                  : () => _esegui(controller.accediConGoogle),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'oppure con email',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textDisabled,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _password,
              obscureText: !_passwordVisibile,
              autofillHints: [
                if (_registrazione)
                  AutofillHints.newPassword
                else
                  AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _passwordVisibile
                      ? 'Nascondi password'
                      : 'Mostra password',
                  icon: Icon(
                    _passwordVisibile
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(
                    () => _passwordVisibile = !_passwordVisibile,
                  ),
                ),
              ),
            ),
            if (_registrazione) ...[
              const SizedBox(height: AppSpacing.xs),
              _RequisitiPassword(mancanti: requisitiMancanti(_password.text)),
            ],
            const SizedBox(height: AppSpacing.md),
            PulsanteIngresso(
              etichetta: _registrazione ? 'Crea account' : 'Accedi',
              onPressed: _puoInviare ? _inviaEmail : null,
            ),
            TextButton(
              onPressed: () => setState(
                () => _modo = _registrazione
                    ? ModoAccesso.accedi
                    : ModoAccesso.registrati,
              ),
              child: Text(
                _registrazione
                    ? 'Ho già un account'
                    : 'Non hai un account? Creane uno',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checklist dei requisiti della password in registrazione: ogni voce si
/// spunta quando è soddisfatta.
class _RequisitiPassword extends StatelessWidget {
  const _RequisitiPassword({required this.mancanti});

  final Set<RequisitoPassword> mancanti;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final requisito in RequisitoPassword.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
            child: Row(
              children: [
                Icon(
                  mancanti.contains(requisito)
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                  size: 16,
                  color: mancanti.contains(requisito)
                      ? AppColors.textDisabled
                      : AppColors.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  requisito.descrizione,
                  style: AppTypography.bodySmall.copyWith(
                    color: mancanti.contains(requisito)
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
