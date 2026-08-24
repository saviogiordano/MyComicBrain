import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/voce_stato.dart';
import 'package:mycomicbrain/features/scheda/presentation/modifica_copia_sheet.dart';

/// Scheda del fumetto (§8, deciso su #63): punto di accesso unico a tutte
/// le informazioni bibliografiche (§8.1) e personali (§8.2), allo stato
/// (§8.3) e a tutte le operazioni su un'Edizione e sulle sue Copie (§8.4).
/// Layout "Accordion + FAB" (Variante C, deciso su #65): card hero
/// bibliografica con un solo punto di modifica, Copie come accordion (auto-
/// espansa se ce n'è una sola), FAB per aggiungerne una, "Elimina edizione"
/// sempre visibile.
class SchedaPage extends ConsumerStatefulWidget {
  const SchedaPage({required this.edizioneId, super.key});

  final int edizioneId;

  @override
  ConsumerState<SchedaPage> createState() => _SchedaPageState();
}

class _SchedaPageState extends ConsumerState<SchedaPage> {
  final Set<int> _espanse = {};
  bool _espanseInizializzate = false;

  Future<void> _scegliStato(CopiaDettaglio copia) async {
    final attuale = voceStatoDi(copia.status, copia.readingStatus);
    final scelta = await showModalBottomSheet<VoceStato>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: VoceStato.values
              .map(
                (v) => ListTile(
                  title: Text(
                    v.label,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: attuale == v
                      ? const Icon(Icons.check, color: AppColors.accent)
                      : null,
                  onTap: () => Navigator.of(context).pop(v),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (scelta == null || scelta == attuale) return;

    final valori = statoPerVoce(scelta);
    await ref
        .read(comicsRepositoryProvider)
        .cambiaStatoCopia(
          id: copia.id,
          status: valori.status,
          readingStatus: valori.readingStatus,
        );
  }

  /// Elenco leggibile dei campi §8.2 valorizzati su questa Copia — usato per
  /// rendere "esplicita" la conferma di cancellazione quando ce ne sono
  /// (deciso su #68).
  String _datiPersonaliDi(CopiaDettaglio copia) {
    final campi = <String>[
      if (copia.condition != null) 'condizione',
      if (copia.purchasePrice != null) 'prezzo di acquisto',
      if (copia.purchaseDate != null) 'data di acquisto',
      if (copia.seller != null) 'venditore',
      if (copia.location != null) 'posizione',
      if (copia.notes != null) 'note',
    ];
    return campi.join(', ');
  }

  /// Rimuove una singola Copia (§8.4). Conferma "esplicita" (deciso su #68)
  /// quando è l'ultima Copia rimasta (elimina anche l'Edizione) o quando ha
  /// dati personali già inseriti — altrimenti un avviso generico.
  Future<void> _rimuoviCopia(EdizioneDettaglio e, CopiaDettaglio copia) async {
    final ultima = e.copie.length == 1;
    final dati = _datiPersonaliDi(copia);
    final severo = ultima || dati.isNotEmpty;

    final String contenuto;
    if (ultima && dati.isNotEmpty) {
      contenuto =
          "È l'unica copia rimasta: eliminarla elimina anche l'edizione "
          '«${e.titolo}», incluso quanto già inserito su questa copia ($dati). '
          'Non è garantito poterlo annullare.';
    } else if (ultima) {
      contenuto =
          "È l'unica copia rimasta: eliminarla elimina anche l'edizione "
          '«${e.titolo}». Non è garantito poterlo annullare.';
    } else if (severo) {
      contenuto =
          'Questa copia ha dati già inseriti ($dati) che andranno persi. '
          'Non è garantito poterlo annullare.';
    } else {
      contenuto = 'La copia verrà rimossa. Non è garantito poterlo annullare.';
    }

    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(ultima ? "Eliminare l'edizione?" : 'Rimuovere la copia?'),
        content: Text(contenuto),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(ultima ? 'Conferma' : 'Rimuovi'),
          ),
        ],
      ),
    );
    if (conferma != true) return;

    final edizioneEliminata = await ref
        .read(comicsRepositoryProvider)
        .rimuoviCopia(copia.id);
    if (edizioneEliminata && mounted) context.pop();
  }

  /// Elimina l'intera Edizione (§8.4, bottone sempre visibile — #65).
  /// Conferma "esplicita" (deciso su #68) quando ci sono più Copie o
  /// qualsiasi Copia ha dati personali già inseriti.
  Future<void> _eliminaEdizione(EdizioneDettaglio e) async {
    final copieConDati = [
      for (final c in e.copie)
        if (_datiPersonaliDi(c).isNotEmpty) c,
    ];
    final severo = e.copie.length > 1 || copieConDati.isNotEmpty;

    final String contenuto;
    if (severo) {
      final dettagli = <String>[
        if (e.copie.length > 1) '${e.copie.length} copie',
        if (copieConDati.isNotEmpty)
          'dati personali già inseriti su ${copieConDati.length == 1 ? 'una copia' : '${copieConDati.length} copie'}',
      ];
      contenuto =
          'Verranno eliminati: ${dettagli.join(', ')}. '
          'Non è garantito poterlo annullare.';
    } else {
      contenuto =
          "L'edizione verrà eliminata. Non è garantito poterlo annullare.";
    }

    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text("Eliminare l'edizione?"),
        content: Text(contenuto),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    if (conferma != true) return;

    await ref.read(comicsRepositoryProvider).eliminaEdizione(e.edizioneId);
    if (mounted) context.pop();
  }

  Future<void> _aggiungiCopia() async {
    final id = await ref
        .read(comicsRepositoryProvider)
        .aggiungiCopia(
          edizioneId: widget.edizioneId,
          status: StatoCopia.posseduta,
        );
    setState(() => _espanse.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final dettaglio = ref.watch(edizioneDettaglioProvider(widget.edizioneId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Scheda'),
      ),
      body: SafeArea(
        child: dettaglio.when(
          data: (e) {
            if (e == null) {
              return Center(
                child: Text(
                  'Edizione non trovata',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              );
            }
            if (!_espanseInizializzate) {
              _espanseInizializzate = true;
              if (e.copie.length == 1) _espanse.add(e.copie.first.id);
            }
            return _corpo(e);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(
              'Errore: $err',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _corpo(EdizioneDettaglio e) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            140,
          ),
          children: [
            _heroCard(e),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(label: 'Copie (${e.copie.length})'),
            const SizedBox(height: AppSpacing.xs),
            for (final copia in e.copie) _accordionCopia(e, copia),
            const SizedBox(height: AppSpacing.xxl),
            Center(
              child: TextButton(
                onPressed: () => _eliminaEdizione(e),
                child: Text(
                  'Elimina edizione',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.amberStrong,
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          child: FloatingActionButton(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            onPressed: _aggiungiCopia,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _heroCard(EdizioneDettaglio e) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _cover(e.coverImage)),
          const SizedBox(height: AppSpacing.md),
          Text(
            e.titolo,
            style: AppTypography.pageTitle.copyWith(
              color: AppColors.textPrimary,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.2,
            children: [
              _griglia(
                'Numero',
                e.issueNumberLabel != null ? '#${e.issueNumberLabel}' : null,
              ),
              _griglia('Serie', e.serieName),
              _griglia('Editore', e.publisher),
              _griglia('Data', e.releaseDate),
              _griglia('Lingua', e.language),
              _griglia('EAN/ISBN', e.ean),
              _griglia('Volume', e.volume),
            ],
          ),
          if (e.autori.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final a in e.autori)
                  AppChip(
                    label: '${a.name} · ${a.ruolo.name}',
                    selected: false,
                  ),
              ],
            ),
          ],
          if (e.description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              e.description!,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.push('/scheda/${e.edizioneId}/modifica'),
              child: const Text('Modifica scheda'),
            ),
          ),
        ],
      ),
    );
  }

  /// La cover reale dell'Edizione se nota (percorso locale scaricato da
  /// `CopertinaDownloader`, o in fallback l'URL remoto originale), altrimenti
  /// un segnaposto — stesso schema di `_Cover` in `dashboard_page.dart`. Un
  /// percorso locale ma ormai mancante su disco ricade sullo stesso
  /// segnaposto invece di un errore visibile.
  Widget _cover(String? coverImage) {
    final segnaposto = Container(
      width: 120,
      height: 180,
      color: AppColors.overlayCardHover,
      child: Icon(
        Icons.menu_book_outlined,
        color: AppColors.textMuted,
        size: 32,
      ),
    );
    if (coverImage == null) {
      return ClipRRect(borderRadius: AppRadii.mdRadius, child: segnaposto);
    }

    final isRemote =
        coverImage.startsWith('http://') || coverImage.startsWith('https://');
    return ClipRRect(
      borderRadius: AppRadii.mdRadius,
      child: SizedBox(
        width: 120,
        height: 180,
        child: isRemote
            ? Image.network(
                coverImage,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => segnaposto,
              )
            : Image.file(
                File(coverImage),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => segnaposto,
              ),
      ),
    );
  }

  Widget _griglia(String label, String? valore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: AppColors.textMuted),
            ),
            TextSpan(text: valore ?? '—'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _accordionCopia(EdizioneDettaglio e, CopiaDettaglio copia) {
    final espansa = _espanse.contains(copia.id);
    final voce = voceStatoDi(copia.status, copia.readingStatus);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        padding: EdgeInsets.zero,
        // `Material(transparency)`: `AppCard` dipinge il fondo su un
        // `Container` semplice, non su un `Material` — senza questo
        // l'`ExpansionTile` sottostante perde ink splash/background del suo
        // `ListTile` (assertion di Flutter in debug/test).
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey(copia.id),
              initiallyExpanded: espansa,
              onExpansionChanged: (v) => setState(() {
                if (v) {
                  _espanse.add(copia.id);
                } else {
                  _espanse.remove(copia.id);
                }
              }),
              title: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: AppSpacing.xs),
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${voce.label} · ${copia.condition?.label ?? '—'}'
                      '${copia.purchasePrice != null ? ' · € ${copia.purchasePrice}' : ''}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => _scegliStato(copia),
                        child: AppChip(label: voce.label, selected: true),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _campo(
                        'Prezzo',
                        copia.purchasePrice != null
                            ? '€ ${copia.purchasePrice}'
                            : '—',
                      ),
                      _campo(
                        'Data acquisto',
                        copia.purchaseDate
                                ?.toIso8601String()
                                .split('T')
                                .first ??
                            '—',
                      ),
                      _campo('Venditore', copia.seller ?? '—'),
                      _campo('Posizione', copia.location ?? '—'),
                      _campo('Note', copia.notes ?? '—'),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                mostraModificaCopiaSheet(context, copia: copia),
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: AppColors.accent,
                            ),
                            label: Text(
                              'Modifica copia',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _rimuoviCopia(e, copia),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.amberStrong,
                            ),
                            label: Text(
                              'Rimuovi copia',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.amberStrong,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _campo(String label, String valore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valore,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
