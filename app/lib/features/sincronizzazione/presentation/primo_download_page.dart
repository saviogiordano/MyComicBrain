import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/avanzamento_primo_download.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/indicatore_sincronizzazione.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/sincronizzazione_providers.dart';

/// Un Profilo autenticato senza ancora una Replica su questo device (login
/// o reinstallazione, prototipo #201 punti 3 e 4): il primo download
/// bloccante con l'avanzamento, o "Serve una connessione" se manca la
/// rete. Il router ne esce da solo quando la Replica è scaricata, e il
/// download riparte da solo al ritorno della rete.
class PrimoDownloadPage extends ConsumerWidget {
  const PrimoDownloadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stato = ref.watch(statoSincronizzazioneProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: switch (stato?.fase) {
            null => const Center(child: CircularProgressIndicator()),
            FaseSincronizzazione.offline => const _ServeUnaConnessione(),
            _ => _Download(stato: stato!),
          },
        ),
      ),
    );
  }
}

void _riprova(WidgetRef ref) =>
    unawaited(ref.read(motoreSincronizzazioneProvider)?.sincronizzaOra());

TextStyle get _titolo =>
    AppTypography.titleLarge.copyWith(color: AppColors.textPrimary);
TextStyle get _testo =>
    AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary);

class _ServeUnaConnessione extends ConsumerWidget {
  const _ServeUnaConnessione();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 56, color: AppColors.amber),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Serve una connessione',
          textAlign: TextAlign.center,
          style: _titolo,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'È il primo accesso su questo dispositivo: la collezione va '
          'scaricata una volta, poi funziona anche senza rete. Il download '
          'parte da solo appena torna la connessione.',
          textAlign: TextAlign.center,
          style: _testo,
        ),
        const SizedBox(height: AppSpacing.xl),
        PulsanteIngresso(etichetta: 'Riprova', onPressed: () => _riprova(ref)),
      ],
    );
  }
}

class _Download extends ConsumerWidget {
  const _Download({required this.stato});

  final StatoSincronizzazione stato;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avanzamento = AvanzamentoPrimoDownload.da(
      righe: stato.righeScaricate,
      dimensioni: ref.watch(dimensioniCollezioneProvider).valueOrNull,
    );
    final errore = stato.fase == FaseSincronizzazione.errore;
    final fumetti = avanzamento.fumetti;
    final ora = ref.watch(oraProvider).valueOrNull ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Icon(Icons.download_rounded, size: 56, color: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        Text('Scarico la tua collezione', style: _titolo),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Serve solo la prima volta su questo dispositivo. Poi la '
          'collezione funziona anche senza rete.',
          style: _testo,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (avanzamento.frazione case final frazione?)
          AppProgressBar(value: frazione)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: const LinearProgressIndicator(
              minHeight: 6,
              color: AppColors.accent,
              backgroundColor: AppColors.borderDefault,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        if (fumetti != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${fumetti.scaricati} di ${fumetti.totale} fumetti',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              Text(
                '${avanzamento.percentuale}%',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        _Passo(
          etichetta: 'Catalogo, Copie e Scansioni',
          fatto: avanzamento.passo == PassoPrimoDownload.salvo,
          attivo: avanzamento.passo == PassoPrimoDownload.scarico,
        ),
        _Passo(
          etichetta: 'Salvataggio su questo dispositivo',
          fatto: false,
          attivo: avanzamento.passo == PassoPrimoDownload.salvo,
        ),
        const _Passo(etichetta: 'Pronto', fatto: false, attivo: false),
        if (errore) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Il download non è riuscito: riprovo '
            '${traQuanto(stato.prossimoTentativo, ora)}.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.dangerLight,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => _riprova(ref),
            child: const Text('Riprova'),
          ),
        ],
        const Spacer(),
        Text(
          "Le immagini delle cover arrivano dopo, mentre usi l'app. Se l'app "
          'si chiude, il download riparte alla prossima apertura.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({
    required this.etichetta,
    required this.fatto,
    required this.attivo,
  });

  final String etichetta;
  final bool fatto;
  final bool attivo;

  @override
  Widget build(BuildContext context) {
    final colore = fatto
        ? AppColors.success
        : attivo
        ? AppColors.accent
        : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(
            fatto
                ? Icons.check_circle
                : attivo
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: colore,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            etichetta,
            style: AppTypography.bodyMedium.copyWith(
              color: fatto || attivo
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
