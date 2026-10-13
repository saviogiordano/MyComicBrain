import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/supabase/importazione_modalita_locale.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/importazione/application/importazione_controller.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';

/// Prompt di importazione della Modalità locale a schermo intero, prima di
/// entrare nell'app (ADR-0005, variante A del prototipo #170): prompt,
/// avanzamento bloccante, errore con Riprova / "Esci e riprova più tardi",
/// fine.
class ImportazionePage extends ConsumerWidget {
  const ImportazionePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stato = ref.watch(importazioneControllerProvider);
    final controller = ref.read(importazioneControllerProvider.notifier);

    final (contenuto, azioni) = switch (stato) {
      RiepilogoInCaricamento() => (
        const Center(child: CircularProgressIndicator()),
        const <Widget>[],
      ),
      PromptImportazione(:final riepilogo, :final ripresa) => (
        _Prompt(riepilogo: riepilogo, ripresa: ripresa),
        [
          PulsanteIngresso(
            etichetta: ripresa
                ? "Riprendi l'importazione"
                : 'Importa nel mio account',
            onPressed: controller.importa,
          ),
          PulsanteIngresso(
            etichetta: 'Non importare',
            stile: StilePulsanteIngresso.testo,
            onPressed: () => _confermaRifiuto(context, controller, riepilogo),
          ),
        ],
      ),
      ImportazioneInCorso(:final avanzamento) => (
        _InCorso(avanzamento: avanzamento),
        [
          Text(
            "Se l'app si chiude, l'importazione riprende alla prossima "
            'apertura.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
      ImportazioneFallita(:final avanzamento) => (
        _Fallita(avanzamento: avanzamento),
        [
          PulsanteIngresso(etichetta: 'Riprova', onPressed: controller.riprova),
          PulsanteIngresso(
            etichetta: 'Esci e riprova più tardi',
            stile: StilePulsanteIngresso.testo,
            onPressed: controller.esciERiprovaPiuTardi,
          ),
        ],
      ),
      ImportazioneCompletata(:final esito) => (
        _Titolo(
          icona: Icons.check_circle_outline,
          titolo: 'Fatto!',
          testo:
              'La collezione ora è nel tuo account: '
              '${_fumetti(esito.fumettiNellAccount)} in totale.',
        ),
        [
          PulsanteIngresso(
            etichetta: 'Vai alla collezione',
            onPressed: controller.continua,
          ),
        ],
      ),
    };

    // Bloccante: il "indietro" di sistema non porta da nessuna parte finché
    // l'importazione non è risolta.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: SingleChildScrollView(child: contenuto)),
                for (final azione in azioni) ...[
                  const SizedBox(height: AppSpacing.xs),
                  azione,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confermaRifiuto(
    BuildContext context,
    ImportazioneController controller,
    RiepilogoModalitaLocale riepilogo,
  ) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare i dati locali?'),
        content: Text(
          '${_iFumetti(riepilogo.fumetti)} e le scansioni su questo '
          'dispositivo verranno eliminati definitivamente. '
          "L'operazione non si può annullare.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amberStrong,
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('Elimina dati locali'),
          ),
        ],
      ),
    );
    if (conferma ?? false) await controller.rifiuta();
  }
}

String _fumetti(int n) => n == 1 ? '1 fumetto' : '$n fumetti';

String _iFumetti(int n) => n == 1 ? 'Il fumetto' : 'I $n fumetti';

String _scansioni(int n) =>
    n == 1 ? '1 scansione da completare' : '$n scansioni da completare';

/// "12 fumetti e 3 scansioni da completare", senza la parte che vale zero.
String _cosaCe(RiepilogoModalitaLocale r) => [
  if (r.fumetti > 0 || r.scansioniDaCompletare == 0) _fumetti(r.fumetti),
  if (r.scansioniDaCompletare > 0) _scansioni(r.scansioniDaCompletare),
].join(' e ');

class _Prompt extends StatelessWidget {
  const _Prompt({required this.riepilogo, required this.ripresa});

  final RiepilogoModalitaLocale riepilogo;
  final bool ripresa;

  @override
  Widget build(BuildContext context) {
    if (ripresa) {
      return _Titolo(
        icona: Icons.cloud_upload_outlined,
        titolo: "L'importazione non è finita",
        testo:
            'I tuoi ${_cosaCe(riepilogo)} sono ancora su questo dispositivo: '
            'riprendiamo da dove si era fermata.',
      );
    }
    final account = riepilogo.fumettiNellAccount;
    return _Titolo(
      icona: Icons.cloud_upload_outlined,
      titolo: 'Abbiamo trovato ${_cosaCe(riepilogo)} su questo dispositivo',
      testo: account > 0
          ? 'Il tuo account ha già ${_fumetti(account)}. Quelli di questo '
                'dispositivo verranno aggiunti alla stessa collezione.'
          : 'Importali nel tuo account per ritrovarli su ogni dispositivo.',
      nota: "La conversazione con l'Assistente non viene importata.",
    );
  }
}

class _InCorso extends StatelessWidget {
  const _InCorso({required this.avanzamento});

  final AvanzamentoImportazione? avanzamento;

  @override
  Widget build(BuildContext context) {
    final fase = avanzamento?.fase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Titolo(
          icona: Icons.cloud_upload_outlined,
          titolo: 'Importazione in corso…',
          testo: "Tieni l'app aperta e connessa. Ci vorrà qualche minuto.",
        ),
        const SizedBox(height: AppSpacing.lg),
        _Barra(avanzamento: avanzamento, colore: AppColors.accent),
        const SizedBox(height: AppSpacing.lg),
        // Nell'ordine in cui avvengono: le immagini vanno su Storage prima
        // che le righe che le riferiscono entrino nel database (ADR-0007).
        for (final (passo, etichetta) in const [
          (FaseImportazione.cover, 'Immagini delle cover'),
          (FaseImportazione.scansioni, 'Scansioni da completare'),
          (
            FaseImportazione.catalogo,
            'Catalogo (opere, edizioni, copie, serie)',
          ),
        ])
          _Passo(
            etichetta: etichetta,
            fatto: fase != null && fase.index > passo.index,
            attuale: fase == passo,
          ),
      ],
    );
  }
}

class _Fallita extends StatelessWidget {
  const _Fallita({required this.avanzamento});

  final AvanzamentoImportazione? avanzamento;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Titolo(
          icona: Icons.error_outline,
          coloreIcona: AppColors.amber,
          titolo: 'Importazione interrotta',
          testo:
              "Non siamo riusciti a completare l'importazione. Non è andato "
              'perso nulla: i tuoi fumetti sono ancora su questo dispositivo.',
        ),
        if (avanzamento != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _Barra(avanzamento: avanzamento, colore: AppColors.amber),
        ],
      ],
    );
  }
}

class _Titolo extends StatelessWidget {
  const _Titolo({
    required this.icona,
    required this.titolo,
    required this.testo,
    this.nota,
    this.coloreIcona = AppColors.accent,
  });

  final IconData icona;
  final Color coloreIcona;
  final String titolo;
  final String testo;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(icona, size: 48, color: coloreIcona),
        const SizedBox(height: AppSpacing.lg),
        Text(
          titolo,
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          testo,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (nota != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            nota!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.avanzamento, required this.colore});

  final AvanzamentoImportazione? avanzamento;
  final Color colore;

  @override
  Widget build(BuildContext context) {
    final frazione = avanzamento?.frazione ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadii.lgRadius,
          child: LinearProgressIndicator(
            value: frazione,
            minHeight: 6,
            color: colore,
            backgroundColor: AppColors.borderSubtle,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${(frazione * 100).round()}%',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({
    required this.etichetta,
    required this.fatto,
    required this.attuale,
  });

  final String etichetta;
  final bool fatto;
  final bool attuale;

  @override
  Widget build(BuildContext context) {
    final colore = fatto || attuale
        ? AppColors.textPrimary
        : AppColors.textTertiary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            fatto
                ? Icons.check_circle
                : attuale
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: fatto ? AppColors.accent : colore,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              etichetta,
              style: AppTypography.bodyMedium.copyWith(color: colore),
            ),
          ),
        ],
      ),
    );
  }
}
