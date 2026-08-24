import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';

/// Bottom sheet di modifica dei campi personali §8.2 di una singola Copia —
/// un flusso separato per copia, distinto da quello bibliografico
/// (`ModificaSchedaPage`), deciso su #67. Lo stato (§8.3) non è qui: si
/// cambia dal selettore dedicato nell'accordion della Scheda.
Future<void> mostraModificaCopiaSheet(
  BuildContext context, {
  required CopiaDettaglio copia,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceRaised,
    builder: (context) => _ModificaCopiaSheet(copia: copia),
  );
}

class _ModificaCopiaSheet extends ConsumerStatefulWidget {
  const _ModificaCopiaSheet({required this.copia});

  final CopiaDettaglio copia;

  @override
  ConsumerState<_ModificaCopiaSheet> createState() =>
      _ModificaCopiaSheetState();
}

class _ModificaCopiaSheetState extends ConsumerState<_ModificaCopiaSheet> {
  late final _prezzo = TextEditingController(
    text: widget.copia.purchasePrice?.toString() ?? '',
  );
  late final _venditore = TextEditingController(
    text: widget.copia.seller ?? '',
  );
  late final _posizione = TextEditingController(
    text: widget.copia.location ?? '',
  );
  late final _note = TextEditingController(text: widget.copia.notes ?? '');
  late CondizioneCopia? _condizione = widget.copia.condition;
  late DateTime? _dataAcquisto = widget.copia.purchaseDate;
  bool _salvando = false;

  @override
  void dispose() {
    _prezzo.dispose();
    _venditore.dispose();
    _posizione.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _scegliData() async {
    final scelta = await showDatePicker(
      context: context,
      initialDate: _dataAcquisto ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (scelta == null) return;
    setState(() => _dataAcquisto = scelta);
  }

  Future<void> _salva() async {
    setState(() => _salvando = true);
    final prezzo = _prezzo.text.trim();
    final venditore = _venditore.text.trim();
    final posizione = _posizione.text.trim();
    final note = _note.text.trim();

    await ref
        .read(comicsRepositoryProvider)
        .aggiornaCopia(
          id: widget.copia.id,
          condition: _condizione,
          purchasePrice: prezzo.isEmpty
              ? null
              : double.tryParse(prezzo.replaceAll(',', '.')),
          purchaseDate: _dataAcquisto,
          seller: venditore.isEmpty ? null : venditore,
          location: posizione.isEmpty ? null : posizione,
          notes: note.isEmpty ? null : note,
        );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionHeader(label: 'Modifica copia'),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Condizione',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in CondizioneCopia.values)
                  AppChip(
                    label: c.label,
                    selected: _condizione == c,
                    onTap: () => setState(
                      () => _condizione = _condizione == c ? null : c,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _campo(
              _prezzo,
              'Prezzo di acquisto',
              'es. 5.30',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Data di acquisto',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            OutlinedButton(
              onPressed: _scegliData,
              child: Text(
                _dataAcquisto == null
                    ? 'Scegli data'
                    : _dataAcquisto!.toIso8601String().split('T').first,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(_venditore, 'Venditore', 'es. Fumetteria Century'),
            const SizedBox(height: AppSpacing.xs),
            _campo(_posizione, 'Posizione', 'es. Scatola 3 — soggiorno'),
            const SizedBox(height: AppSpacing.xs),
            _campo(_note, 'Note', 'es. prima ristampa italiana'),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _salvando ? null : _salva,
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

  Widget _campo(
    TextEditingController c,
    String label,
    String hint, {
    TextInputType? keyboardType,
  }) {
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
          keyboardType: keyboardType,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.bodyLarge.copyWith(
              color: AppColors.textMuted,
            ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadii.smRadius),
          ),
        ),
      ],
    );
  }
}
