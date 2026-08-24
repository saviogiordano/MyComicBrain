import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

/// Schermo "Possibile corrispondenza" (§6.3, deciso su #54 — Variante B,
/// elenco ordinato): tutti i Candidati di un'Identificazione visibili subito
/// come righe selezionabili ordinate per Punteggio di confidenza, ciascuna
/// con cover/titolo/tag sorgente/punteggio. "Conferma" agisce sul Candidato
/// selezionato (collega/crea la Copia risultante, vedi
/// `ComicsRepository.confermaCandidato`); "Inserisci manualmente" apre
/// `InserisciManualmentePage` (Variante B, deciso su #61/#62).
class ConfermaCandidatoPage extends ConsumerStatefulWidget {
  const ConfermaCandidatoPage({required this.scansioneId, super.key});

  final int scansioneId;

  @override
  ConsumerState<ConfermaCandidatoPage> createState() =>
      _ConfermaCandidatoPageState();
}

class _ConfermaCandidatoPageState extends ConsumerState<ConfermaCandidatoPage> {
  int _selezionato = 0;
  bool _confermando = false;

  void _inserisciManualmente() {
    context.push(
      '/scansione/inserisci-manualmente',
      extra: widget.scansioneId,
    );
  }

  Future<void> _conferma(Candidato candidato) async {
    setState(() => _confermando = true);
    await ref
        .read(comicsRepositoryProvider)
        .confermaCandidato(
          candidato: candidato,
          scansioneId: widget.scansioneId,
        );
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final esito = ref
        .watch(identificazioneProvider(widget.scansioneId))
        .valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Possibile corrispondenza'),
      ),
      body: SafeArea(child: _corpo(esito)),
    );
  }

  Widget _corpo(EsitoIdentificazione? esito) {
    if (esito == null ||
        esito.stato == StatoIdentificazione.pending ||
        esito.stato == StatoIdentificazione.inCorso) {
      return const Center(child: CircularProgressIndicator());
    }

    if (esito.stato == StatoIdentificazione.fallita) {
      return _ErroreIdentificazione(
        errorMessage: esito.errorMessage,
        onInserisciManualmente: _inserisciManualmente,
      );
    }

    if (esito.candidati.isEmpty) {
      return _EmptyState(onInserisciManualmente: _inserisciManualmente);
    }

    if (_selezionato >= esito.candidati.length) _selezionato = 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SectionHeader(
              label: '${esito.candidati.length} candidati, per confidenza',
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: esito.candidati.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) {
              final c = esito.candidati[i];
              return _RigaCandidato(
                candidato: c,
                selezionato: i == _selezionato,
                onTap: () => setState(() => _selezionato = i),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confermando
                      ? null
                      : () => _conferma(esito.candidati[_selezionato]),
                  child: _confermando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conferma'),
                ),
              ),
              TextButton(
                onPressed: _confermando ? null : _inserisciManualmente,
                child: const Text('Inserisci manualmente'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RigaCandidato extends StatelessWidget {
  const _RigaCandidato({
    required this.candidato,
    required this.selezionato,
    required this.onTap,
  });

  final Candidato candidato;
  final bool selezionato;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: AppRadii.mdRadius,
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            selezionato ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selezionato ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: AppSpacing.xs),
          _CoverThumb(url: candidato.coverImageUrl, width: 48, height: 74),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidato.title ??
                      candidato.seriesName ??
                      'Titolo non riconosciuto',
                  style: AppTypography.titleMedium.copyWith(
                    color: candidato.title == null
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _sottotitolo(candidato),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _SourceTag(source: candidato.source),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _ConfidenzaBadge(punteggio: candidato.punteggio),
          IconButton(
            icon: Icon(Icons.info_outline, color: AppColors.textMuted),
            iconSize: 20,
            tooltip: 'Dettagli',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _DettagliCandidatoDialog(candidato: candidato),
            ),
          ),
        ],
      ),
    );
  }
}

/// Popup dei dettagli di un Candidato (§6.3): cover a piena larghezza e
/// tutti i campi grezzi, comprese le informazioni non mostrate nella riga
/// compatta (anno, sorgente per esteso). Sola lettura — la selezione
/// resta un'azione separata sulla riga, non duplicata qui (deciso in
/// sessione: icona info dedicata, il tap sulla riga continua a
/// selezionare come prima).
class _DettagliCandidatoDialog extends StatelessWidget {
  const _DettagliCandidatoDialog({required this.candidato});

  final Candidato candidato;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.lgRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _CoverThumb(
                url: candidato.coverImageUrl,
                width: 140,
                height: 210,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              candidato.title ??
                  candidato.seriesName ??
                  'Titolo non riconosciuto',
              style: AppTypography.titleLarge.copyWith(
                color: candidato.title == null
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SourceTag(source: candidato.source),
            const SizedBox(height: AppSpacing.md),
            _rigaDettaglio('Serie', candidato.seriesName),
            _rigaDettaglio('Numero', candidato.issueNumberLabel),
            _rigaDettaglio('Editore', candidato.publisher),
            _rigaDettaglio(
              'Anno',
              candidato.year != null ? '${candidato.year}' : null,
            ),
            _rigaDettaglio('Confidenza', '${candidato.punteggio.round()}%'),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Chiudi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rigaDettaglio(String label, String? valore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valore ?? '—',
              style: AppTypography.bodyMedium.copyWith(
                color: valore == null
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Riga di sottotitolo: "Numero 42 · DC Comics · 2019", saltando i campi
/// `null` (OCR incompleto — deciso su #52: esclusi, non penalizzati).
String _sottotitolo(Candidato c) {
  final parti = <String>[
    ?c.issueNumberLabel != null ? 'Numero ${c.issueNumberLabel}' : null,
    ?c.publisher,
    ?c.year != null ? '${c.year}' : null,
  ];
  return parti.isEmpty
      ? "Dati insufficienti dall'analisi copertina"
      : parti.join(' · ');
}

/// Badge di confidenza: colore come canale semantico, non solo il numero
/// (stessa convenzione di [KpiCard] — ambra per richiamare attenzione).
class _ConfidenzaBadge extends StatelessWidget {
  const _ConfidenzaBadge({required this.punteggio});

  final double punteggio;

  @override
  Widget build(BuildContext context) {
    final color = punteggio >= 85
        ? AppColors.accent
        : punteggio >= 60
        ? AppColors.amber
        : AppColors.textTertiary;
    return Text(
      '${punteggio.round()}%',
      style: AppTypography.monoLabel.copyWith(color: color),
    );
  }
}

/// Distingue le due conseguenze molto diverse di "Conferma" (decise su #50):
/// interno aggiunge solo una Copia a un'Edizione già catalogata, esterno
/// crea Opera/Edizione/Copia da zero via ComicVine.
class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.source});

  final FonteCandidato source;

  @override
  Widget build(BuildContext context) {
    final interno = source == FonteCandidato.interno;
    final color = interno ? AppColors.accent : AppColors.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: interno
            ? AppColors.accentAlpha(0.12)
            : AppColors.overlayCardHover,
        borderRadius: AppRadii.pillRadius,
        border: Border.all(
          color: interno ? AppColors.accent : AppColors.borderStrong,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 3,
        ),
        child: Text(
          interno ? 'Già in collezione' : 'Nuovo · ComicVine',
          style: AppTypography.labelMedium.copyWith(color: color),
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({
    required this.url,
    required this.width,
    required this.height,
  });

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ClipRRect(
      borderRadius: AppRadii.mdRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: switch (url) {
          null => _placeholder(),
          // Un Candidato `interno` porta il percorso locale già scaricato
          // dell'Edizione catalogata (§6.3) — solo un Candidato `esterno`
          // porta un vero URL remoto ComicVine. Stessa distinzione di
          // `_Cover` in dashboard_page.dart.
          _ when url.startsWith('http://') || url.startsWith('https://') =>
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _placeholder(loading: true),
            ),
          _ => Image.file(
            File(url),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(),
          ),
        },
      ),
    );
  }

  Widget _placeholder({bool loading = false}) {
    return ColoredBox(
      color: AppColors.overlayCardHover,
      child: Center(
        child: Icon(
          loading ? Icons.hourglass_top : Icons.menu_book_outlined,
          color: AppColors.textMuted,
          size: 28,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onInserisciManualmente});

  final VoidCallback onInserisciManualmente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nessuna corrispondenza trovata',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Catalogo interno e ComicVine non hanno restituito candidati sufficientemente affidabili.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onInserisciManualmente,
                child: const Text('Inserisci manualmente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallimento tecnico dell'Identificazione (es. ComicVine irraggiungibile) —
/// distinto dallo stato vuoto: nessun retry, come `AnalisiCopertina` (#53).
class _ErroreIdentificazione extends StatelessWidget {
  const _ErroreIdentificazione({
    required this.errorMessage,
    required this.onInserisciManualmente,
  });

  final String? errorMessage;
  final VoidCallback onInserisciManualmente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Identificazione non riuscita',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              errorMessage ?? 'Motivo non disponibile',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onInserisciManualmente,
                child: const Text('Inserisci manualmente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
