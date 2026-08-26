import 'dart:async';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:permission_handler/permission_handler.dart';

/// Stato di errore dello scanner (deciso su #25, riusato su #89): "permanente"
/// copre i dinieghi che richiedono di passare dalle Impostazioni di sistema —
/// mostrato come messaggio persistente perché ritentare non cambierebbe
/// nulla. Ogni altro fallimento (diniego riprovabile, scanner già attivo,
/// nessuna Activity, plugin non disponibile) resta transitorio: uno SnackBar
/// basta, l'utente può semplicemente ritoccare "Fotocamera".
enum _ErroreScanner { permanente }

/// Schermata `/scansione` (requisito 5.1, deciso su #88/#89): il bottone
/// "Fotocamera" apre la UI nativa di scansione di `cunning_document_scanner`
/// (rilevamento bordi, cattura multi-pagina, raddrizzamento prospettico —
/// tutto on-device, scelto su #87); il bottone Galleria (#17) e
/// l'impalcatura di riepilogo — filmstrip del batch in corso e "Fine" (#24)
/// — restano invariati.
///
/// A differenza della versione precedente (preview camera live con overlay a
/// 4 angoli, Variante B su #19), non c'è più una fotocamera custom né le 5
/// pillole di guida (#22): la UI di scansione è quella nativa a schermo
/// intero del plugin, che gestisce da sé anche il loop multi-scatto.
///
/// Ogni scansione/selezione da galleria apre la revisione ritaglio/rotazione
/// (#24): solo le foto confermate lì entrano nel filmstrip. "Fine" apre il
/// riepilogo di fine batch (#24) col batch confermato finora.
class ScansionePage extends ConsumerStatefulWidget {
  const ScansionePage({super.key});

  @override
  ConsumerState<ScansionePage> createState() => _ScansionePageState();
}

class _ScansionePageState extends ConsumerState<ScansionePage> {
  // "Alto" per #89: un batch tipico di cover è di poche unità, ma niente
  // vieta all'utente di scansionarne molte in una sessione — il loop
  // multi-pagina è gestito nativamente dal plugin, non da un ciclo Dart.
  static const _maxPagineBatch = 30;

  bool _scansionando = false;
  _ErroreScanner? _errore;
  final _captures = <XFile>[];

  Future<void> _apriImpostazioni() => openAppSettings();

  Future<void> _scansiona() async {
    if (_scansionando) return;
    setState(() {
      _scansionando = true;
      _errore = null;
    });

    // Check anticipato (stesso pattern di #25): un diniego permanente non
    // deve arrivare al plugin, che lo segnala solo con lo stesso codice
    // generico 'permission_denied' di un diniego riprovabile.
    final status = await Permission.camera.status;
    if (status.isPermanentlyDenied || status.isRestricted) {
      if (mounted) {
        setState(() {
          _errore = _ErroreScanner.permanente;
          _scansionando = false;
        });
      }
      return;
    }

    try {
      final percorsi = await CunningDocumentScanner.getPictures(noOfPages: _maxPagineBatch);
      if (!mounted) return;
      // null su ogni piattaforma se l'utente annulla: nessuna azione, come
      // già oggi per l'annullamento della selezione da Galleria.
      if (percorsi == null || percorsi.isEmpty) return;

      // I file restituiti dal plugin vivono in una cache non garantita
      // (ricerca #87): copiarli subito in storage permanente prima di
      // qualunque elaborazione successiva, stesso pattern già in uso per
      // l'output di `image_cropper` (#17).
      final permanenti = await ref.read(scansioneStorageProvider).salvaGrezzi(percorsi);
      await _ripulisciCacheScanner();
      if (!mounted) return;
      await _apriRevisione(permanenti);
    } on CunningDocumentScannerException catch (e) {
      // Il plugin lancia anche `ArgumentError` per un `noOfPages` non
      // valido: non catturato qui, dato che `_maxPagineBatch` è una
      // costante fissa sempre positiva — non un input utente.
      if (!mounted) return;
      await _gestisciErroreScanner(e);
    } finally {
      if (mounted) setState(() => _scansionando = false);
    }
  }

  /// Il plugin espone un solo codice generico `permission_denied` sia per un
  /// diniego riprovabile sia per uno permanente: la distinzione (#25) va
  /// ricavata ricontrollando lo stato reale del permesso dopo il fallimento.
  Future<void> _gestisciErroreScanner(CunningDocumentScannerException e) async {
    if (e.code != 'permission_denied') {
      _mostraErroreTransitorio();
      return;
    }
    final status = await Permission.camera.status;
    if (!mounted) return;
    if (status.isPermanentlyDenied || status.isRestricted) {
      setState(() => _errore = _ErroreScanner.permanente);
    } else {
      _mostraErroreTransitorio();
    }
  }

  /// Best-effort (README del plugin): libera i file temporanei dello
  /// scanner ora che ne abbiamo già una copia permanente — un suo
  /// fallimento non deve bloccare il passaggio alla revisione.
  Future<void> _ripulisciCacheScanner() async {
    try {
      await CunningDocumentScanner.cleanCache();
    } on CunningDocumentScannerException {
      // Ignorato: le copie permanenti sono già state fatte.
    }
  }

  void _mostraErroreTransitorio() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scansione non riuscita, riprova')));
  }

  Future<void> _aggiungiDaGalleria() async {
    final foto = await ImagePicker().pickMultiImage();
    if (foto.isEmpty || !mounted) return;
    await _apriRevisione([for (final f in foto) f.path]);
  }

  /// Apre la revisione (#24) sui percorsi grezzi appena acquisiti; solo le
  /// foto confermate (non "Riscatta") tornano ed entrano nel batch.
  Future<void> _apriRevisione(List<String> percorsiGrezzi) async {
    final confermate = await context.push<List<XFile>>('/scansione/revisione', extra: percorsiGrezzi);
    if (confermate == null || confermate.isEmpty || !mounted) return;
    setState(() => _captures.addAll(confermate));
  }

  /// `ScansionePage` resta montato mentre il riepilogo è in primo piano
  /// (tab dentro l'`IndexedStack` dello shell): se il batch è stato inviato
  /// alla pipeline (pop con `true` — sia da "Aggiungi altre" sia da "Vai
  /// alla Dashboard", vedi `RiepilogoPage._vaiAllaDashboard`), il filmstrip
  /// locale va svuotato — altrimenti una scansione già `completata`
  /// resterebbe nel prossimo batch e ne bloccherebbe l'elaborazione
  /// (segnalato da utente).
  Future<void> _fine() async {
    final inviato = await context.push<bool>('/scansione/riepilogo', extra: List<XFile>.of(_captures));
    if ((inviato ?? false) && mounted) setState(_captures.clear);
  }

  @override
  Widget build(BuildContext context) {
    final messaggio = _errore == _ErroreScanner.permanente
        ? _PermessoNegatoMessage(onApriImpostazioni: _apriImpostazioni)
        : const _ScannerIdleMessage();
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      body: SafeArea(
        child: Column(
          children: [
            _Filmstrip(captures: _captures, onFine: _fine),
            const Spacer(),
            messaggio,
            const SizedBox(height: AppSpacing.md),
            _BottomBar(
              lastCapture: _captures.isEmpty ? null : _captures.last,
              scansioneAbilitata: !_scansionando,
              onScansiona: _scansiona,
              onGalleria: _aggiungiDaGalleria,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// Messaggio neutro mostrato finché l'utente non ha ancora avviato una
/// scansione (nessun errore in corso).
class _ScannerIdleMessage extends StatelessWidget {
  const _ScannerIdleMessage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.document_scanner_outlined, size: 40, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.xs),
          Text('Scansiona una cover', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(
            'Tocca "Fotocamera" per aprire lo scanner',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _PermessoNegatoMessage extends StatelessWidget {
  const _PermessoNegatoMessage({required this.onApriImpostazioni});

  final VoidCallback onApriImpostazioni;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography_outlined, size: 32, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Permesso fotocamera negato',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            'Attivalo dalle Impostazioni, oppure usa la Galleria',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onApriImpostazioni, child: const Text('Apri Impostazioni')),
        ],
      ),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({required this.captures, required this.onFine});

  final List<XFile> captures;
  final VoidCallback onFine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: captures.isEmpty
                ? Text('Nessuna scansione ancora', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted))
                : SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: captures.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: AppRadii.xsRadius,
                        child: Container(
                          width: 40,
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.xsRadius,
                            border: Border.all(color: AppColors.borderStrong),
                          ),
                          child: Image.file(File(captures[i].path), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Material(
            color: AppColors.accent,
            borderRadius: AppRadii.pillRadius,
            child: InkWell(
              onTap: onFine,
              borderRadius: AppRadii.pillRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Text('Fine', style: AppTypography.labelLarge.copyWith(color: AppColors.onAccent)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.lastCapture,
    required this.scansioneAbilitata,
    required this.onScansiona,
    required this.onGalleria,
  });

  final XFile? lastCapture;
  final bool scansioneAbilitata;
  final VoidCallback onScansiona;
  final VoidCallback onGalleria;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          _GalleryThumbButton(lastCapture: lastCapture, onTap: onGalleria),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton.icon(
              onPressed: scansioneAbilitata ? onScansiona : null,
              icon: scansioneAbilitata
                  ? const Icon(Icons.document_scanner_outlined)
                  : const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent),
                    ),
              label: const Text('Fotocamera'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryThumbButton extends StatelessWidget {
  const _GalleryThumbButton({required this.lastCapture, required this.onTap});

  final XFile? lastCapture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lastCapture = this.lastCapture;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smRadius,
        child: Container(
          width: 48,
          height: 48,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.overlayCardHover,
            borderRadius: AppRadii.smRadius,
            border: Border.all(color: AppColors.borderStrong, width: 2),
          ),
          child: lastCapture == null
              ? Icon(Icons.photo_library_outlined, color: AppColors.textSecondary)
              : Image.file(File(lastCapture.path), fit: BoxFit.cover),
        ),
      ),
    );
  }
}
