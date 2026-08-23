import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';

/// Schermata `/scansione/riepilogo` (S-B — Lista con stato, deciso su #20):
/// una riga per Scansione appena confermata, con thumbnail e chip di stato
/// collegata allo stato reale dell'Analisi Copertina (`watchStatoAnalisiCopertina`,
/// "In sospeso"/"In corso"/"Completata"/"Fallita" — il riconoscimento AI,
/// §6.3, è fuori scope di questa mappa, vedi `CONTEXT.md`). "Aggiungi altre"
/// torna allo scanner con il batch preservato (pop, nessun valore); "Fine"
/// avvia la pipeline di analisi copertina (§6.1, §6.2, #32, #49) per
/// l'intero batch — senza attendere il risultato, vedi
/// `AnalisiCopertinaPipeline`. A differenza della versione originale (#24),
/// non naviga più via subito: restare sulla pagina è l'unico modo per
/// vedere gli stati aggiornarsi dal vivo e toccare le righe pronte per lo
/// schermo di conferma candidato (§6.3, #59), altrimenti irraggiungibile —
/// segnalato in test manuale dopo #59. Una volta avviata, "Fine" diventa
/// "Vai alla Dashboard": la pipeline resta in background anche dopo,
/// nessuna seconda chiamata possibile. Finché la pipeline non è avviata, una
/// riga si può eliminare con uno swipe (richiesta utente dopo test manuale
/// #59): dopo "Fine" le righe sono già passate ad `avviaBatch`, e
/// rimuoverne una a quel punto romperebbe la Scansione che la pipeline
/// sequenziale si aspetta di trovare — lo swipe viene quindi disabilitato.
class RiepilogoPage extends ConsumerStatefulWidget {
  const RiepilogoPage({required this.scansioni, super.key});

  final List<XFile> scansioni;

  @override
  ConsumerState<RiepilogoPage> createState() => _RiepilogoPageState();
}

class _RiepilogoPageState extends ConsumerState<RiepilogoPage> {
  late final _scansioni = List<XFile>.of(widget.scansioni);
  bool _avviato = false;

  void _fine() {
    setState(() => _avviato = true);
    unawaited(
      ref.read(analisiCopertinaPipelineProvider).avviaBatch([
        for (final s in _scansioni) s.path,
      ]),
    );
  }

  Future<bool> _confermaEliminazione(BuildContext context) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovere questa scansione?'),
        content: const Text(
          'La foto verrà eliminata e non entrerà nel riconoscimento AI.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    return conferma ?? false;
  }

  Future<void> _elimina(XFile scansione) async {
    final repository = ref.read(comicsRepositoryProvider);
    final scansioneId = await repository.idScansionePerImmagine(scansione.path);
    await repository.eliminaScansione(id: scansioneId);
    await ref.read(scansioneStorageProvider).elimina(scansione.path);
    if (!mounted) return;
    setState(() => _scansioni.remove(scansione));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Riepilogo batch',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${_scansioni.length} ${_scansioni.length == 1 ? 'scansione pronta' : 'scansioni pronte'} '
                    'per il riconoscimento AI',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                itemCount: _scansioni.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final scansione = _scansioni[i];
                  final riga = _RigaScansione(indice: i, scansione: scansione);
                  if (_avviato) return riga;
                  return Dismissible(
                    key: ValueKey(scansione.path),
                    direction: DismissDirection.endToStart,
                    background: const _SfondoEliminazione(),
                    confirmDismiss: (_) => _confermaEliminazione(context),
                    onDismissed: (_) => _elimina(scansione),
                    child: riga,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Aggiungi altre'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _avviato
                          ? () => context.go('/dashboard')
                          : _scansioni.isEmpty
                          ? null
                          : _fine,
                      child: Text(_avviato ? 'Vai alla Dashboard' : 'Fine'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sfondo rivelato dallo swipe-to-delete. Rosso Material puro, non un
/// token del design system: la palette dell'app non ne ha uno per azioni
/// distruttive (l'ambra è riservata a segnali di attenzione, mai errore —
/// vedi `AppColors`), e un rosso universale è l'affordance più immediata
/// per "elimina" su questo singolo elemento transitorio.
class _SfondoEliminazione extends StatelessWidget {
  const _SfondoEliminazione();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: AppRadii.lgRadius,
      ),
      child: const Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Icon(Icons.delete_outline, color: Colors.white),
        ),
      ),
    );
  }
}

class _RigaScansione extends ConsumerWidget {
  const _RigaScansione({required this.indice, required this.scansione});

  final int indice;
  final XFile scansione;

  /// Apre lo schermo di conferma candidato (§6.3, #59) per questa Scansione
  /// — raggiungibile una volta che l'Analisi Copertina è `completata`
  /// (l'Identificazione, agganciata in automatico su #58, è quindi già
  /// stata avviata; lo schermo gestisce da sé l'attesa se non è ancora
  /// `completata`).
  Future<void> _apriConfermaCandidato(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final scansioneId = await ref
        .read(comicsRepositoryProvider)
        .idScansionePerImmagine(scansione.path);
    if (!context.mounted) return;
    unawaited(
      context.push('/scansione/conferma-candidato', extra: scansioneId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stato = ref
        .watch(statoAnalisiCopertinaProvider(scansione.path))
        .valueOrNull;
    final pronta = stato?.stato == StatoAnalisiCopertina.completata;

    return AppCard(
      onTap: pronta ? () => _apriConfermaCandidato(context, ref) : null,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadii.smRadius,
            child: Image.file(
              File(scansione.path),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Scansione ${indice + 1}',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _ChipStatoAnalisi(
            stato: stato?.stato,
            errorMessage: stato?.errorMessage,
            onRiprova: () => ref
                .read(analisiCopertinaPipelineProvider)
                .riprova(scansione.path),
          ),
        ],
      ),
    );
  }
}

/// La chip di stato del riepilogo, collegata allo stato reale della riga
/// `AnalisiCopertinaTable` (prima era testo statico "In sospeso" a
/// prescindere dall'esito, vedi indagine su segnalazione utente): `null`
/// finché lo stream non ha ancora emesso il primo valore. Da `fallita`, la
/// chip stessa è il tasto di retry manuale (nessun retry automatico, #27) —
/// `errorMessage` compare al tocco prolungato.
class _ChipStatoAnalisi extends StatelessWidget {
  const _ChipStatoAnalisi({
    required this.stato,
    required this.errorMessage,
    required this.onRiprova,
  });

  final StatoAnalisiCopertina? stato;
  final String? errorMessage;
  final VoidCallback onRiprova;

  @override
  Widget build(BuildContext context) {
    final (String label, Color colore) = switch (stato) {
      null || StatoAnalisiCopertina.pending => ('In sospeso', AppColors.amber),
      StatoAnalisiCopertina.inCorso => ('In corso', AppColors.amber),
      StatoAnalisiCopertina.completata => ('Completata', AppColors.accent),
      StatoAnalisiCopertina.fallita => (
        'Fallita · Riprova',
        AppColors.textMuted,
      ),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colore.withValues(alpha: 0.14),
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: colore),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(color: colore),
      ),
    );

    if (stato != StatoAnalisiCopertina.fallita) return chip;

    return Tooltip(
      message: errorMessage ?? 'Motivo del fallimento non disponibile',
      child: InkWell(
        borderRadius: AppRadii.pillRadius,
        onTap: onRiprova,
        child: chip,
      ),
    );
  }
}
