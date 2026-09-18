import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

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
/// sequenziale si aspetta di trovare — lo swipe viene quindi disabilitato
/// (eccetto su un batch [ripresa], vedi sotto). "Elimina tutte" applica la
/// stessa regola all'intero batch in un colpo solo (richiesta utente).
class RiepilogoPage extends ConsumerStatefulWidget {
  const RiepilogoPage({
    required this.scansioni,
    this.ripresa = false,
    super.key,
  });

  final List<XFile> scansioni;

  /// True quando il riepilogo è stato riaperto dalla Dashboard per un batch
  /// lasciato a metà (uscita prima di "Vai alla Dashboard"/"Aggiungi altre")
  /// invece che dal flusso di scansione appena concluso — vedi
  /// `scansioniNonConfermateProvider`. Alcune righe possono già avere una
  /// pipeline avviata in background da quella sessione precedente: lo swipe
  /// e "Elimina tutte" restano comunque sempre disponibili qui (richiesta
  /// utente, a differenza del batch appena confermato, dove restano bloccati
  /// dopo "Fine" — vedi sopra), perché sono sicuri anche in quel caso —
  /// `AnalisiCopertinaPipeline._avviaUna` salta silenziosamente una
  /// Scansione cancellata prima di raggiungerla nel `for` sequenziale,
  /// invece di interrompere il resto del batch (stesso principio del bug
  /// #86 che il filtro di `_fine` già previene lato invio).
  final bool ripresa;

  @override
  ConsumerState<RiepilogoPage> createState() => _RiepilogoPageState();
}

class _RiepilogoPageState extends ConsumerState<RiepilogoPage> {
  late final _scansioni = List<XFile>.of(widget.scansioni);
  bool _avviato = false;

  /// Solo le righe ancora `In sospeso` (nessuna `AnalisiCopertina` già
  /// creata per quella Scansione) entrano in `avviaBatch` — anche col
  /// filmstrip di `ScansionePage` correttamente svuotato tra un batch e
  /// l'altro (#86), questo stesso riepilogo può comunque mostrare righe già
  /// `Completata`/`In corso`/`Fallita` (es. uscita col back fisico invece di
  /// "Aggiungi altre"/"Vai alla Dashboard" mentre la pipeline di un "Fine"
  /// precedente è già partita). Rimandarle ad `avviaAnalisiCopertina`
  /// creerebbe una seconda riga `AnalisiCopertina` per lo stesso
  /// scansioneId, mandando in errore `identifica()` a valle (`getSingle` su
  /// due righe) e bloccando il resto del batch (stesso meccanismo del bug
  /// segnalato da utente su #86) — oltre a richiamare `estraiCopertina` una
  /// seconda volta a vuoto. Le righe `Fallita`/`Completata` hanno il proprio
  /// retry manuale dalla chip (`riprova`), non passano da qui.
  void _fine() {
    setState(() => _avviato = true);
    final daInviare = _scansioni.where((s) {
      final stato = ref
          .read(statoAnalisiCopertinaProvider(s.path))
          .valueOrNull
          ?.stato;
      return stato == null || stato == StatoAnalisiCopertina.pending;
    });
    unawaited(
      ref.read(analisiCopertinaPipelineProvider).avviaBatch([
        for (final s in daInviare) s.path,
      ]),
    );
  }

  /// `ScansionePage` resta montato (tab dentro l'`IndexedStack` dello shell,
  /// #86) mentre questo riepilogo è in primo piano: se non gli segnaliamo
  /// che il batch è stato inviato alla pipeline, il suo filmstrip locale
  /// resta popolato e una scansione successiva ci si aggiunge — la Scansione
  /// già `completata` viene rimandata ad `avviaBatch`, che crea una seconda
  /// riga `AnalisiCopertina` per lo stesso id e manda in errore
  /// l'Identificazione a valle (`getSingle` su due righe), bloccando l'intero
  /// batch prima di arrivare alla scansione davvero nuova (segnalato da
  /// utente). Il valore del pop (`true` = batch inviato) dice a
  /// `ScansionePage._fine` di svuotare il proprio filmstrip: vale sia
  /// "Aggiungi altre" (anche dopo l'invio: quelle righe sono già irrevocabili,
  /// vedi sopra) sia "Vai alla Dashboard".
  void _vaiAllaDashboard() {
    context
      ..pop(true)
      ..go('/dashboard');
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

  Future<bool> _confermaEliminazioneTutte(BuildContext context) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovere tutte le scansioni?'),
        content: Text(
          'Le ${_scansioni.length} foto verranno eliminate e non entreranno '
          'nel riconoscimento AI.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi tutte'),
          ),
        ],
      ),
    );
    return conferma ?? false;
  }

  Future<void> _eliminaTutte() async {
    if (!await _confermaEliminazioneTutte(context) || !mounted) return;
    final repository = ref.read(comicsRepositoryProvider);
    final storage = ref.read(scansioneStorageProvider);
    final daEliminare = List<XFile>.of(_scansioni);
    for (final scansione in daEliminare) {
      final scansioneId = await repository.idScansionePerImmagine(
        scansione.path,
      );
      await repository.eliminaScansione(id: scansioneId);
      await storage.elimina(scansione.path);
    }
    if (!mounted) return;
    setState(() => _scansioni.removeWhere(daEliminare.contains));
  }

  @override
  Widget build(BuildContext context) {
    final avviato = _avviato;
    // Su un batch ripreso lo swipe e "Elimina tutte" restano disponibili
    // anche a pipeline già avviata (richiesta utente) — vedi
    // `RiepilogoPage.ripresa`.
    final eliminabile = widget.ripresa || !avviato;
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Riepilogo batch',
                          style: AppTypography.titleLarge.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (eliminabile && _scansioni.isNotEmpty)
                        TextButton(
                          onPressed: _eliminaTutte,
                          child: const Text('Elimina tutte'),
                        ),
                    ],
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
                  if (!eliminabile) return riga;
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
                      onPressed: () => context.pop(avviato),
                      child: const Text('Aggiungi altre'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: avviato
                          ? _vaiAllaDashboard
                          : _scansioni.isEmpty
                          ? null
                          : _fine,
                      child: Text(avviato ? 'Vai alla Dashboard' : 'Fine'),
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
    final confermata =
        ref.watch(scansioneConfermataProvider(scansione.path)).valueOrNull ??
        false;
    final pronta =
        stato?.stato == StatoAnalisiCopertina.completata && !confermata;

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
              // File non più leggibile a questo percorso: icona invece dello
              // spazio vuoto silenzioso di default di `Image` (segnalato da
              // utente dopo test manuale, stesso fallback del banner
              // "in sospeso" della Dashboard).
              errorBuilder: (context, error, stackTrace) => Container(
                width: 48,
                height: 48,
                color: AppColors.overlayCard,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ),
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
            confermata: confermata,
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
/// `errorMessage` compare al tocco prolungato. Quando il fallimento è per
/// provider AI non configurato (nessuna API key, deciso su #108), la chip
/// diventa un link diretto alle Impostazioni invece del retry: riprovare
/// senza aver configurato nulla fallirebbe di nuovo con lo stesso errore.
/// `confermata` (già esiste una `Copia` per questa Scansione, richiesta
/// utente) scavalca sempre lo stato di `AnalisiCopertina`: una riga già
/// confermata resta "Salvata" per distinguerla da quelle ancora da
/// confermare, e la riga smette di essere selezionabile (vedi `pronta` in
/// `_RigaScansione`) per impedire una seconda conferma. Anche la chip
/// "Completata" (non ancora confermata) è tappabile, sullo stesso modello:
/// richiede all'utente di rieseguire l'Analisi Copertina da capo (richiesta
/// utente), scartando il risultato corrente — `AnalisiCopertinaPipeline.
/// riprova` riusa la riga esistente e riaggancia l'Identificazione a valle
/// senza duplicarla (#58). Il resto della riga (`AppCard.onTap` in
/// `_RigaScansione`) resta la via per aprire la conferma candidato: le due
/// zone di tocco coesistono, la chip vince sul proprio piccolo riquadro
/// (nested `InkWell`, stesso meccanismo della chip "Fallita").
class _ChipStatoAnalisi extends StatelessWidget {
  const _ChipStatoAnalisi({
    required this.stato,
    required this.confermata,
    required this.errorMessage,
    required this.onRiprova,
  });

  final StatoAnalisiCopertina? stato;
  final bool confermata;
  final String? errorMessage;
  final VoidCallback onRiprova;

  @override
  Widget build(BuildContext context) {
    final configurazioneMancante =
        stato == StatoAnalisiCopertina.fallita &&
        erroreConfigurazioneMancante(errorMessage);
    final riesguibile =
        stato == StatoAnalisiCopertina.completata && !confermata;

    final (String label, Color colore) = switch (stato) {
      _ when confermata => ('Salvata', AppColors.accent),
      null || StatoAnalisiCopertina.pending => ('In sospeso', AppColors.amber),
      StatoAnalisiCopertina.inCorso => ('In corso', AppColors.amber),
      StatoAnalisiCopertina.completata => ('Completata', AppColors.accent),
      StatoAnalisiCopertina.fallita when configurazioneMancante => (
        'Configura provider',
        AppColors.amberStrong,
      ),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: colore),
          ),
          if (riesguibile) ...[
            const SizedBox(width: 4),
            Icon(Icons.refresh, size: 14, color: colore),
          ],
        ],
      ),
    );

    if (stato != StatoAnalisiCopertina.fallita && !riesguibile) return chip;

    return Tooltip(
      message: switch (true) {
        _ when riesguibile => "Tocca per rieseguire l'analisi",
        _ when configurazioneMancante =>
          '${errorMessage ?? ''} · tocca per aprire le Impostazioni',
        _ => errorMessage ?? 'Motivo del fallimento non disponibile',
      },
      child: InkWell(
        borderRadius: AppRadii.pillRadius,
        onTap: configurazioneMancante
            ? () => context.go('/impostazioni')
            : onRiprova,
        child: chip,
      ),
    );
  }
}
