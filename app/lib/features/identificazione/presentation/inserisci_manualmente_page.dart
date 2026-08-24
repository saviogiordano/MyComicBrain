import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';

/// Schermo "Inserisci manualmente" (§6.3, deciso su #61 — Variante B, form
/// unico): raggiunto da `ConfermaCandidatoPage` quando nessun Candidato
/// combacia (o non ce ne sono). Nessuno step di ricerca preliminare — la
/// pipeline automatica ha già interrogato interno + ComicVine, quindi crea
/// direttamente Opera/Serie/Edizione/Copia da zero, stessa superficie di
/// scrittura usata da `ComicsRepository.confermaCandidato` per un
/// Candidato `esterno`. Nessun controllo di duplicati: la funzione
/// Duplicati esistente li intercetta dopo (stesso principio deciso su #53
/// per il dedup fra Scansioni dello stesso batch).
class InserisciManualmentePage extends ConsumerStatefulWidget {
  const InserisciManualmentePage({required this.scansioneId, super.key});

  final int scansioneId;

  @override
  ConsumerState<InserisciManualmentePage> createState() =>
      _InserisciManualmentePageState();
}

class _InserisciManualmentePageState
    extends ConsumerState<InserisciManualmentePage> {
  final _titolo = TextEditingController();
  final _serie = TextEditingController();
  final _editore = TextEditingController();
  final _numero = TextEditingController();
  bool _faParteDiSerie = false;
  bool _salvando = false;

  @override
  void dispose() {
    _titolo.dispose();
    _serie.dispose();
    _editore.dispose();
    _numero.dispose();
    super.dispose();
  }

  bool get _puoSalvare => _titolo.text.trim().isNotEmpty;

  Future<void> _salva() async {
    setState(() => _salvando = true);

    final repository = ref.read(comicsRepositoryProvider);
    final operaId = await repository.aggiungiOpera(
      title: _titolo.text.trim(),
    );

    int? serieId;
    final nomeSerie = _serie.text.trim();
    if (_faParteDiSerie && nomeSerie.isNotEmpty) {
      serieId = await repository.aggiungiSerie(name: nomeSerie);
    }

    final numero = _numero.text.trim();
    final editore = _editore.text.trim();
    final edizioneId = await repository.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: editore.isEmpty ? null : editore,
      issueNumber: numero.isEmpty ? null : int.tryParse(numero),
      issueNumberLabel: numero.isEmpty ? null : numero,
    );

    await repository.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      scansioneId: widget.scansioneId,
    );

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Inserisci manualmente'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SectionHeader(label: 'Opera'),
            const SizedBox(height: AppSpacing.xs),
            _campo(_titolo, 'Titolo *', 'es. Batman'),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              label: 'Serie',
              trailing: Switch(
                value: _faParteDiSerie,
                activeThumbColor: AppColors.accent,
                onChanged: (v) => setState(() => _faParteDiSerie = v),
              ),
            ),
            if (_faParteDiSerie) ...[
              const SizedBox(height: AppSpacing.xs),
              _campo(_serie, 'Nome serie', 'es. Batman (2016)'),
            ],
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(label: 'Edizione'),
            const SizedBox(height: AppSpacing.xs),
            _campo(_editore, 'Editore', 'es. Panini Comics'),
            const SizedBox(height: AppSpacing.xs),
            _campo(_numero, 'Numero', 'es. 42 oppure 42 Variant'),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_puoSalvare && !_salvando) ? _salva : null,
                child: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salva'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(TextEditingController c, String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        TextField(
          controller: c,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.bodyLarge.copyWith(
              color: AppColors.textMuted,
            ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadii.smRadius),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
