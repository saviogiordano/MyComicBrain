import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/serie_dettaglio.dart';

/// Bottom sheet di modifica di nome/numero totale/issn di una Serie (§11,
/// **variante B** scelta fra le tre confrontate nel prototipo — deciso su
/// #99). Unico punto di scrittura UI su questi campi, finora popolati solo
/// da `aggiungiSerie()` (ingestion AI).
Future<void> mostraModificaSerieSheet(
  BuildContext context, {
  required SerieDettaglio serie,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceRaised,
    builder: (context) => _ModificaSerieSheet(serie: serie),
  );
}

class _ModificaSerieSheet extends ConsumerStatefulWidget {
  const _ModificaSerieSheet({required this.serie});

  final SerieDettaglio serie;

  @override
  ConsumerState<_ModificaSerieSheet> createState() =>
      _ModificaSerieSheetState();
}

class _ModificaSerieSheetState extends ConsumerState<_ModificaSerieSheet> {
  late final _nome = TextEditingController(text: widget.serie.nome);
  late final _totale = TextEditingController(
    text: widget.serie.numeriTotali?.toString() ?? '',
  );
  late final _issn = TextEditingController(text: widget.serie.issn ?? '');
  String? _erroreTotale;
  bool _salvando = false;

  /// Il numero totale non può scendere sotto il numero posseduto più alto:
  /// non ha senso far "sparire" un'edizione già posseduta e catalogata
  /// (deciso su #99, verificato dal vivo sul prototipo).
  int get _minimoTotale => widget.serie.numeriPosseduti.isEmpty
      ? 0
      : widget.serie.numeriPosseduti.reduce((a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _totale.addListener(_validaTotale);
  }

  @override
  void dispose() {
    _totale.removeListener(_validaTotale);
    _nome.dispose();
    _totale.dispose();
    _issn.dispose();
    super.dispose();
  }

  void _validaTotale() {
    setState(() => _erroreTotale = _erroreDi(_totale.text));
  }

  String? _erroreDi(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final n = int.tryParse(trimmed);
    if (n == null || n < 1) return 'Inserisci un numero intero positivo.';
    if (n < _minimoTotale) {
      return 'Non può essere inferiore a $_minimoTotale '
          '(numero già posseduto).';
    }
    return null;
  }

  Future<void> _salva() async {
    final erroreTotale = _erroreDi(_totale.text);
    if (erroreTotale != null) {
      setState(() => _erroreTotale = erroreTotale);
      return;
    }

    setState(() => _salvando = true);
    final nome = _nome.text.trim();
    final totaleTrimmed = _totale.text.trim();
    final issn = _issn.text.trim();

    await ref
        .read(comicsRepositoryProvider)
        .aggiornaSerie(
          id: widget.serie.serieId,
          name: nome.isEmpty ? widget.serie.nome : nome,
          totalIssues: totaleTrimmed.isEmpty ? null : int.parse(totaleTrimmed),
          issn: issn.isEmpty ? null : issn,
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
            const SectionHeader(label: 'Modifica serie'),
            const SizedBox(height: AppSpacing.md),
            _campo(_nome, 'Nome', ''),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _totale,
              'Numero totale',
              'non impostato',
              keyboardType: TextInputType.number,
              errore: _erroreTotale,
              hintSottostante: 'Minimo $_minimoTotale — il numero posseduto '
                  'più alto in collezione.',
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(_issn, 'ISSN', 'es. 1122-3344'),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_salvando || _erroreTotale != null)
                    ? null
                    : _salva,
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
    String? errore,
    String? hintSottostante,
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
            border: OutlineInputBorder(
              borderRadius: AppRadii.smRadius,
              borderSide: errore != null
                  ? const BorderSide(color: AppColors.amberStrong)
                  : BorderSide.none,
            ),
            enabledBorder: errore != null
                ? OutlineInputBorder(
                    borderRadius: AppRadii.smRadius,
                    borderSide: const BorderSide(color: AppColors.amberStrong),
                  )
                : null,
          ),
        ),
        if (errore != null || hintSottostante != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            errore ?? hintSottostante!,
            style: AppTypography.bodySmall.copyWith(
              color: errore != null
                  ? AppColors.amberStrong
                  : AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
