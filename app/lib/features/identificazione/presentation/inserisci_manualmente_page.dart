import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';

/// Schermo "Inserisci manualmente" (§6.3, deciso su #61 — Variante B, form
/// unico; precompilato dall'AI su #63): raggiunto da `ConfermaCandidatoPage`
/// quando nessun Candidato combacia (o non ce ne sono) — tipicamente perché
/// ComicVine non copre l'edizione italiana della cover scansionata. Nessuno
/// step di ricerca preliminare — la pipeline automatica ha già interrogato
/// interno + ComicVine, quindi crea direttamente Opera/Serie/Edizione/Copia
/// da zero, stessa superficie di scrittura usata da
/// `ComicsRepository.confermaCandidato` per un Candidato `esterno`. I campi
/// arrivano precompilati con l'Analisi Copertina AI già disponibile per
/// questa Scansione (§6.1/§6.2) — l'utente li corregge invece di
/// ritrascriverli da zero, e la cover è la scansione stessa, non un
/// segnaposto. Nessun controllo di duplicati: la funzione Duplicati
/// esistente li intercetta dopo (stesso principio deciso su #53 per il
/// dedup fra Scansioni dello stesso batch).
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
  final _releaseDate = TextEditingController();
  final _coverPrice = TextEditingController();
  final _pageCount = TextEditingController();
  final _language = TextEditingController();
  final _color = TextEditingController();
  final _ean = TextEditingController();
  final _description = TextEditingController();
  final _classificazione = TextEditingController();
  final _printingType = TextEditingController();
  bool _faParteDiSerie = false;
  bool _salvando = false;
  bool _prefillFatto = false;

  String? _coverImageRelativo;
  String? _coverImageAssoluto;

  @override
  void initState() {
    super.initState();
    _caricaCover();
  }

  @override
  void dispose() {
    _titolo.dispose();
    _serie.dispose();
    _editore.dispose();
    _numero.dispose();
    _releaseDate.dispose();
    _coverPrice.dispose();
    _pageCount.dispose();
    _language.dispose();
    _color.dispose();
    _ean.dispose();
    _description.dispose();
    _classificazione.dispose();
    _printingType.dispose();
    super.dispose();
  }

  bool get _puoSalvare => _titolo.text.trim().isNotEmpty;

  /// La cover da mostrare/salvare è quella scansionata da questa Scansione
  /// (§6.3, deciso su #63): a differenza di un Candidato, il form manuale
  /// non ne porta una propria. [coverImagePerScansione] la relativizza già
  /// nel formato salvato dal resto del catalogo; [risolviCoverImage] la
  /// ricostruisce assoluta per la preview in questa stessa sessione.
  Future<void> _caricaCover() async {
    final repository = ref.read(comicsRepositoryProvider);
    final relativo = await repository.coverImagePerScansione(
      widget.scansioneId,
    );
    final assoluto = await repository.risolviCoverImage(relativo);
    if (!mounted) return;
    setState(() {
      _coverImageRelativo = relativo;
      _coverImageAssoluto = assoluto;
    });
  }

  /// Precompila i controller con l'Analisi Copertina AI di questa Scansione
  /// (§6.1/§6.2), una sola volta: chiamato da [build] a ogni rebuild finché
  /// [analisiCopertinaProvider] non ha dati, poi diventa un no-op — non deve
  /// sovrascrivere correzioni già fatte dall'utente.
  void _prefill(AnalisiCopertinaTableData analisi) {
    if (_prefillFatto) return;
    _prefillFatto = true;

    _titolo.text = _valore(analisi.title);
    final seriesName = _valore(analisi.seriesName);
    if (seriesName.isNotEmpty) {
      _faParteDiSerie = true;
      _serie.text = seriesName;
    }
    _editore.text = _valore(analisi.publisher);
    _numero.text = _valore(analisi.issueNumberLabel);
    _releaseDate.text = _valore(analisi.releaseDate);
    _coverPrice.text = _valore(analisi.price);
    _pageCount.text = analisi.pageCount?.toString() ?? '';
    _language.text = _valore(analisi.language);
    _color.text = _valore(analisi.color);
    // `barcode` prima di `isbn`: sulle edizioni italiane da edicola è quasi
    // sempre l'EAN periodico quello riportato in copertina (vedi `ean` su
    // `Edizioni`). Una stringa vuota da Claude (invece di `null`, nonostante
    // il prompt) non deve però scavalcare `isbn` come se fosse un valore
    // valido — da qui `_valore` prima del fallback, non `??` da solo.
    final barcode = _valore(analisi.barcode);
    _ean.text = barcode.isNotEmpty ? barcode : _valore(analisi.isbn);
    _description.text = _valore(analisi.description);
    _classificazione.text = _valore(analisi.classificazione);
    _printingType.text = _valore(analisi.printingType);
  }

  /// Normalizza un campo grezzo dell'Analisi Copertina: `null` e stringhe
  /// vuote/di soli spazi diventano `''` allo stesso modo, così un valore
  /// "non trovato" è sempre riconoscibile con un solo controllo invece di
  /// doverne combinare due (`== null`, `.isEmpty`) a ogni chiamata.
  String _valore(String? v) => v?.trim() ?? '';

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
    final releaseDate = _releaseDate.text.trim();
    final coverPrice = _coverPrice.text.trim();
    final pageCount = _pageCount.text.trim();
    final language = _language.text.trim();
    final color = _color.text.trim();
    final ean = _ean.text.trim();
    final description = _description.text.trim();
    final classificazione = _classificazione.text.trim();
    final printingType = _printingType.text.trim();

    final edizioneId = await repository.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: editore.isEmpty ? null : editore,
      issueNumber: numero.isEmpty ? null : int.tryParse(numero),
      issueNumberLabel: numero.isEmpty ? null : numero,
      coverImage: _coverImageRelativo,
      releaseDate: releaseDate.isEmpty ? null : releaseDate,
      coverPrice: coverPrice.isEmpty ? null : coverPrice,
      pageCount: pageCount.isEmpty ? null : int.tryParse(pageCount),
      language: language.isEmpty ? null : language,
      color: color.isEmpty ? null : color,
      ean: ean.isEmpty ? null : ean,
      description: description.isEmpty ? null : description,
      classificazione: classificazione.isEmpty ? null : classificazione,
      printingType: printingType.isEmpty ? null : printingType,
    );

    await repository.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      scansioneId: widget.scansioneId,
    );

    if (!mounted) return;
    // `context.pop()` tornerebbe a `ConfermaCandidatoPage`, ancora sullo
    // stack sotto questa pagina con un Candidato preselezionato: l'utente
    // poteva poi premere "Conferma" lì per sbaglio, creando una seconda
    // Copia per la stessa Scansione (bug osservato). `go` sostituisce
    // l'intero stack, chiudendo anche `ConfermaCandidatoPage` invece di
    // lasciarla raggiungibile.
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    ref
        .watch(analisiCopertinaProvider(widget.scansioneId))
        .whenData(_prefill);

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
            Center(child: _coverPreview()),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(label: 'Opera'),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _titolo,
              'Titolo *',
              'es. Batman',
              key: const Key('campo-titolo'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              label: 'Collana',
              trailing: Switch(
                value: _faParteDiSerie,
                activeThumbColor: AppColors.accent,
                onChanged: (v) => setState(() => _faParteDiSerie = v),
              ),
            ),
            if (_faParteDiSerie) ...[
              const SizedBox(height: AppSpacing.xs),
              _campo(
                _serie,
                'Nome collana',
                'es. Marvel Mega',
                key: const Key('campo-collana'),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(label: 'Edizione'),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _editore,
              'Editore',
              'es. Marvel Italia / Panini Comics',
              key: const Key('campo-editore'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _numero,
              'Numero',
              'es. 42 oppure 42 Variant',
              key: const Key('campo-numero'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _releaseDate,
              'Data di pubblicazione',
              'es. dicembre 2010',
              key: const Key('campo-data-pubblicazione'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _coverPrice,
              'Prezzo di copertina',
              'es. € 5,30',
              key: const Key('campo-prezzo-copertina'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _pageCount,
              'Pagine',
              'es. 112',
              key: const Key('campo-pagine'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _language,
              'Lingua',
              'es. italiano',
              key: const Key('campo-lingua'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _color,
              'Colore',
              'es. a colori',
              key: const Key('campo-colore'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _ean,
              'EAN/ISBN riportato',
              'es. 977112421890900067',
              key: const Key('campo-ean'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _printingType,
              'Tipo di stampa',
              'es. Direct Edition',
              key: const Key('campo-tipo-stampa'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _classificazione,
              'Classificazione',
              'es. Rated T+',
              key: const Key('campo-classificazione'),
            ),
            const SizedBox(height: AppSpacing.xs),
            _campo(
              _description,
              'Descrizione',
              '',
              key: const Key('campo-descrizione'),
            ),
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

  Widget _coverPreview() {
    final path = _coverImageAssoluto;
    return ClipRRect(
      borderRadius: AppRadii.mdRadius,
      child: SizedBox(
        width: 140,
        height: 210,
        child: path == null
            ? ColoredBox(
                color: AppColors.overlayCardHover,
                child: Center(
                  child: Icon(
                    Icons.hourglass_top,
                    color: AppColors.textMuted,
                    size: 28,
                  ),
                ),
              )
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: AppColors.overlayCardHover,
                  child: Center(
                    child: Icon(
                      Icons.menu_book_outlined,
                      color: AppColors.textMuted,
                      size: 28,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _campo(
    TextEditingController c,
    String label,
    String hint, {
    Key? key,
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
          key: key,
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
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
