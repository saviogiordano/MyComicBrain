import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';

/// Modifica dei campi bibliografici §8.1 di un'Edizione (Autori inclusi) —
/// una schermata dedicata stile `InserisciManualmentePage`, deciso su #67.
/// I campi personali §8.2 di ogni Copia si modificano altrove, in
/// `ModificaCopiaSheet` (flusso separato per copia, stesso #67); qui non
/// compaiono.
class ModificaSchedaPage extends ConsumerStatefulWidget {
  const ModificaSchedaPage({required this.edizioneId, super.key});

  final int edizioneId;

  @override
  ConsumerState<ModificaSchedaPage> createState() => _ModificaSchedaPageState();
}

class _ModificaSchedaPageState extends ConsumerState<ModificaSchedaPage> {
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
  final _volume = TextEditingController();
  final _description = TextEditingController();
  final _nuovoAutoreNome = TextEditingController();
  final _nuovoAutoreFocusNode = FocusNode();

  bool _faParteDiSerie = false;
  bool _prefillFatto = false;
  bool _salvando = false;
  int? _serieIdOriginale;
  String? _serieNomeOriginale;
  RuoloCreator _nuovoAutoreRuolo = RuoloCreator.sceneggiatore;

  // Autocomplete sui Creator esistenti nel campo "Nuovo autore" (#78, UX
  // decisa su #77): un tocco su un suggerimento riempie il campo e ricorda
  // qui il Creator esatto, cosicché "Aggiungi autore" possa collegarlo senza
  // ripassare da un'altra ricerca per nome.
  CreatorData? _autoreSelezionato;
  List<CreatorData> _ultimeOpzioniAutore = const [];
  late final _Debounceable<List<CreatorData>?, String> _cercaCreatorDebounced;

  String? _coverImageRelativo;
  String? _coverImageAssoluto;

  @override
  void initState() {
    super.initState();
    _cercaCreatorDebounced = _debounce<List<CreatorData>?, String>(
      (query) => ref.read(comicsRepositoryProvider).cercaCreator(query),
    );
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
    _volume.dispose();
    _description.dispose();
    _nuovoAutoreNome.dispose();
    _nuovoAutoreFocusNode.dispose();
    super.dispose();
  }

  bool get _puoSalvare => _titolo.text.trim().isNotEmpty;

  void _prefill(EdizioneDettaglio e) {
    if (_prefillFatto) return;
    _prefillFatto = true;

    _titolo.text = e.titolo;
    _faParteDiSerie = e.serieId != null;
    _serie.text = e.serieName ?? '';
    _serieIdOriginale = e.serieId;
    _serieNomeOriginale = e.serieName;
    _editore.text = e.publisher ?? '';
    _numero.text = e.issueNumberLabel ?? '';
    _releaseDate.text = e.releaseDate ?? '';
    _coverPrice.text = e.coverPrice ?? '';
    _pageCount.text = e.pageCount?.toString() ?? '';
    _language.text = e.language ?? '';
    _color.text = e.color ?? '';
    _ean.text = e.ean ?? '';
    _volume.text = e.volume ?? '';
    _description.text = e.description ?? '';
    _coverImageAssoluto = e.coverImage;

    unawaited(
      ref
          .read(comicsRepositoryProvider)
          .coverImageGrezzoDi(widget.edizioneId)
          .then((raw) {
            if (!mounted) return;
            setState(() => _coverImageRelativo = raw);
          }),
    );
  }

  Future<void> _scegliCover() async {
    final scelta = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (scelta == null) return;

    final repository = ref.read(comicsRepositoryProvider);
    final relativo = await repository.salvaCoverLocale(File(scelta.path));
    final assoluto = await repository.risolviCoverImage(relativo);
    if (!mounted) return;
    setState(() {
      _coverImageRelativo = relativo;
      _coverImageAssoluto = assoluto;
    });
  }

  Future<void> _aggiungiAutore() async {
    final nome = _nuovoAutoreNome.text.trim();
    if (nome.isEmpty) return;

    final repository = ref.read(comicsRepositoryProvider);
    int creatorId;
    if (_autoreSelezionato != null && _autoreSelezionato!.name == nome) {
      // Suggerimento toccato in #78: collega il Creator selezionato,
      // saltando aggiungiCreator.
      creatorId = _autoreSelezionato!.id;
    } else {
      // Testo libero senza selezione (comportamento invariato da #67): un
      // match esatto sul nome riusa il Creator esistente invece di crearne
      // uno identico ogni volta che lo stesso autore viene aggiunto a
      // un'altra Edizione.
      final esistenti = await repository.cercaCreator(nome);
      final match = esistenti.where(
        (c) => c.name.toLowerCase() == nome.toLowerCase(),
      );
      creatorId = match.isNotEmpty
          ? match.first.id
          : await repository.aggiungiCreator(nome);
    }

    await repository.collegaCreatorAEdizione(
      edizioneId: widget.edizioneId,
      creatorId: creatorId,
      ruolo: _nuovoAutoreRuolo,
    );
    _nuovoAutoreNome.clear();
    setState(() => _autoreSelezionato = null);
  }

  Future<Iterable<CreatorData>> _opzioniAutore(TextEditingValue value) async {
    final query = value.text.trim();
    if (query.length < 2) {
      _ultimeOpzioniAutore = const [];
      return const Iterable<CreatorData>.empty();
    }

    final risultati = await _cercaCreatorDebounced(query);
    if (risultati == null) {
      // Ricerca superata da una più recente (debounce): tieni le ultime
      // opzioni finché quella nuova non risolve.
      return _ultimeOpzioniAutore;
    }
    _ultimeOpzioniAutore = risultati;
    return risultati;
  }

  Future<void> _rimuoviAutore(CreatorConRuolo autore) {
    return ref
        .read(comicsRepositoryProvider)
        .rimuoviCreatorDaEdizione(autore.comicCreatorId);
  }

  Future<void> _salva() async {
    setState(() => _salvando = true);
    final repository = ref.read(comicsRepositoryProvider);

    await repository.aggiornaTitoloOpera(
      operaId: _operaId!,
      title: _titolo.text.trim(),
    );

    int? serieId;
    final nomeSerie = _serie.text.trim();
    if (_faParteDiSerie && nomeSerie.isNotEmpty) {
      serieId = (nomeSerie == _serieNomeOriginale && _serieIdOriginale != null)
          ? _serieIdOriginale
          : await repository.aggiungiSerie(name: nomeSerie);
    }

    final numero = _numero.text.trim();
    final editore = _editore.text.trim();
    final releaseDate = _releaseDate.text.trim();
    final coverPrice = _coverPrice.text.trim();
    final pageCount = _pageCount.text.trim();
    final language = _language.text.trim();
    final color = _color.text.trim();
    final ean = _ean.text.trim();
    final volume = _volume.text.trim();
    final description = _description.text.trim();

    await repository.aggiornaEdizione(
      id: widget.edizioneId,
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
      volume: volume.isEmpty ? null : volume,
      description: description.isEmpty ? null : description,
    );

    if (!mounted) return;
    context.pop();
  }

  int? _operaId;

  @override
  Widget build(BuildContext context) {
    final dettaglio = ref.watch(edizioneDettaglioProvider(widget.edizioneId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Modifica scheda'),
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
            _operaId = e.operaId;
            _prefill(e);
            return _form(e.autori);
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

  Widget _form(List<CreatorConRuolo> autori) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(child: _coverPreview()),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            onPressed: _scegliCover,
            child: const Text('Cambia cover'),
          ),
        ),
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
          _volume,
          'Volume',
          'es. Omnibus 1',
          key: const Key('campo-volume'),
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
          _description,
          'Descrizione',
          '',
          key: const Key('campo-descrizione'),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(label: 'Autori'),
        const SizedBox(height: AppSpacing.xs),
        for (final a in autori)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${a.name} · ${a.ruolo.name}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppColors.textMuted, size: 18),
                  onPressed: () => _rimuoviAutore(a),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nuovo autore',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Autocomplete<CreatorData>(
                    focusNode: _nuovoAutoreFocusNode,
                    textEditingController: _nuovoAutoreNome,
                    displayStringForOption: (c) => c.name,
                    optionsBuilder: _opzioniAutore,
                    onSelected: (selection) =>
                        setState(() => _autoreSelezionato = selection),
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            key: const Key('campo-nuovo-autore'),
                            controller: controller,
                            focusNode: focusNode,
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'es. Stan Lee',
                              hintStyle: AppTypography.bodyLarge.copyWith(
                                color: AppColors.textMuted,
                              ),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: AppRadii.smRadius,
                              ),
                            ),
                            onChanged: (text) {
                              if (_autoreSelezionato != null &&
                                  text != _autoreSelezionato!.name) {
                                setState(() => _autoreSelezionato = null);
                              }
                            },
                            onSubmitted: (_) => onFieldSubmitted(),
                          );
                        },
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            DropdownButton<RuoloCreator>(
              value: _nuovoAutoreRuolo,
              dropdownColor: AppColors.surfaceRaised,
              items: [
                for (final r in RuoloCreator.values)
                  DropdownMenuItem(value: r, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => _nuovoAutoreRuolo = v!),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _aggiungiAutore,
            child: const Text('Aggiungi autore'),
          ),
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
                    Icons.menu_book_outlined,
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

const Duration _autoreDebounceDuration = Duration(milliseconds: 250);

typedef _Debounceable<S, T> = Future<S?> Function(T parameter);

/// Restituisce una versione debounced della funzione data: la funzione
/// originale viene invocata solo dopo che non arrivano nuove chiamate per
/// `_autoreDebounceDuration` (soglia decisa su #77/#78 per l'autocomplete
/// Creator). Adattato dall'esempio ufficiale Flutter per `Autocomplete`
/// asincrono con debounce.
_Debounceable<S, T> _debounce<S, T>(_Debounceable<S?, T> function) {
  _DebounceTimer? debounceTimer;

  return (T parameter) async {
    if (debounceTimer != null && !debounceTimer!.isCompleted) {
      debounceTimer!.cancel();
    }
    debounceTimer = _DebounceTimer();
    try {
      await debounceTimer!.future;
    } on _CancelException {
      return null;
    }
    return function(parameter);
  };
}

class _DebounceTimer {
  _DebounceTimer() {
    _timer = Timer(_autoreDebounceDuration, _onComplete);
  }

  late final Timer _timer;
  final Completer<void> _completer = Completer<void>();

  void _onComplete() {
    _completer.complete();
  }

  Future<void> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void cancel() {
    _timer.cancel();
    _completer.completeError(const _CancelException());
  }
}

class _CancelException implements Exception {
  const _CancelException();
}
