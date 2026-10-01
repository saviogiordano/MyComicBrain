import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';

/// Profilo autenticato senza rete (#171, variante A del prototipo #170):
/// blocco a schermo intero, niente app visibile e nessuna cache — la
/// collezione vive solo su Supabase (online-only, ADR-0005).
class OfflinePage extends ConsumerStatefulWidget {
  const OfflinePage({super.key});

  @override
  ConsumerState<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends ConsumerState<OfflinePage> {
  bool _inCorso = false;

  Future<void> _riprova() async {
    setState(() => _inCorso = true);
    await ref.read(sessionControllerProvider.notifier).riprovaConnessione();
    if (mounted) setState(() => _inCorso = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 56,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Sei offline',
                textAlign: TextAlign.center,
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'La tua collezione è salvata nel tuo account: serve una '
                'connessione per vederla e modificarla.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PulsanteIngresso(
                etichetta: _inCorso ? 'Verifica in corso…' : 'Riprova',
                onPressed: _inCorso ? null : _riprova,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
