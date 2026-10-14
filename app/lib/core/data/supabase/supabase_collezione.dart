part of 'supabase_comics_repository.dart';

/// Area Collezione di [SupabaseComicsRepository] (#193): indice e
/// idratazione della Collezione, ricerca del tool-calling dell'Assistente.
/// L'indice è la funzione `indice_collezione` (un solo jsonb, nessun tetto
/// di righe PostgREST); l'idratazione legge solo la finestra richiesta.
mixin _CollezioneSupabase implements ComicsRepository {
  SupabaseClient get _client;
  InvalidazioneTabelle get _invalidazione;
  Future<String> collectionId();

  /// Le tabelle lette da [watchIndiceCollezione].
  static const Set<TabellaSupabase> _tabelleIndice = {
    TabellaSupabase.opere,
    TabellaSupabase.serie,
    TabellaSupabase.edizioni,
    TabellaSupabase.copie,
    TabellaSupabase.creator,
    TabellaSupabase.comicCreator,
    TabellaSupabase.character,
    TabellaSupabase.comicCharacter,
    TabellaSupabase.tag,
    TabellaSupabase.edizioneTag,
    TabellaSupabase.edizioneGenere,
  };

  static const _statiPosseduti = ['posseduta', 'prestata'];

  @override
  Stream<List<EdizioneCollezioneIndice>> watchIndiceCollezione() =>
      _invalidazione.osserva(_tabelleIndice, _leggiIndice);

  Future<List<EdizioneCollezioneIndice>> _leggiIndice() async {
    final righe = await _client.rpc<List<dynamic>>(
      'indice_collezione',
      params: {'target_collection_id': await collectionId()},
    );
    return [
      for (final riga in righe.cast<Map<String, dynamic>>())
        _edizioneIndice(riga),
    ];
  }

  @override
  Stream<Map<String, String?>> watchHydratazioneCollezione(
    List<String> edizioneIds,
  ) {
    if (edizioneIds.isEmpty) return Stream.value(const <String, String?>{});
    return _invalidazione.osserva(
      {TabellaSupabase.edizioni, TabellaSupabase.copie},
      () async {
        // `!inner` con il filtro sullo stato: solo le Edizioni ancora
        // possedute, come su drift.
        final righe = await _client
            .from(TabellaSupabase.edizioni.nome)
            .select('id, cover_image, copie!inner(id)')
            .inFilter('id', edizioneIds)
            .inFilter('copie.status', _statiPosseduti);
        return {
          for (final riga in righe)
            riga['id'] as String: await risolviCoverImage(
              riga['cover_image'] as String?,
            ),
        };
      },
    );
  }

  @override
  Future<RisultatoCercaEdizioni> cercaEdizioni({
    String? titolo,
    String? serie,
    String? autore,
    String? editore,
    String? personaggio,
    String? tag,
    int? numero,
    String? isbn,
    String? testoLibero,
  }) async => filtraIndiceCollezione(
    await _leggiIndice(),
    titolo: titolo,
    serieIds: serie == null
        ? null
        : {for (final s in await cercaSerie(serie)) s.id},
    autore: autore,
    editore: editore,
    personaggio: personaggio,
    tag: tag,
    numero: numero,
    isbn: isbn,
    testoLibero: testoLibero,
  );

  static EdizioneCollezioneIndice _edizioneIndice(Map<String, dynamic> e) {
    List<String> nomi(String chiave) => (e[chiave] as List).cast<String>();
    return EdizioneCollezioneIndice(
      edizioneId: e['id'] as String,
      titolo: e['titolo'] as String,
      serieId: e['serie_id'] as String?,
      serieName: e['serie_name'] as String?,
      publisher: e['publisher'] as String?,
      issueNumber: e['issue_number'] as int?,
      issueNumberLabel: e['issue_number_label'] as String?,
      year: e['year'] as int?,
      format: _enumOrNull(FormatoEdizione.values, e['format']),
      language: e['language'] as String?,
      ean: e['ean'] as String?,
      autori: nomi('autori'),
      personaggi: nomi('personaggi'),
      tag: nomi('tag'),
      generi: [for (final g in nomi('generi')) GenereEdizione.values.byName(g)],
      copiePossedute: [
        for (final c in (e['copie'] as List).cast<Map<String, dynamic>>())
          CopiaAsseCollezione(
            readingStatus: _enumOrNull(
              StatoLettura.values,
              c['reading_status'],
            ),
            condition: _enumOrNull(CondizioneCopia.values, c['condition']),
            location: c['location'] as String?,
            createdAt: _data(c['created_at'])!,
            forSale: c['for_sale'] as bool,
          ),
      ],
    );
  }
}
