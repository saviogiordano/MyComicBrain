part of 'supabase_comics_repository.dart';

/// Area Catalogo di [SupabaseComicsRepository] (#177): Opere, Serie,
/// Edizioni e Copie, Creator/Personaggi/Tag/Generi e la Scheda. CRUD e
/// dettaglio via PostgREST; le rimozioni multi-tabella sono le RPC atomiche
/// `rimuovi_copia`/`elimina_edizione` (ADR-0007). Ogni scrittura segnala le
/// tabelle che tocca, così i `watch*` si rileggono.
mixin _CatalogoSupabase implements ComicsRepository {
  SupabaseClient get _client;
  InvalidazioneTabelle get _invalidazione;
  Future<String> collectionId();

  // --- Opere, Serie, Edizioni, Copie ---

  @override
  Future<int> aggiungiOpera({required String title, DateTime? createdAt}) =>
      _inserisci(TabellaSupabase.opere, {
        'title': title,
        if (createdAt != null) 'created_at': _iso(createdAt),
      });

  /// Riusa la Serie con lo stesso nome (senza distinzione di maiuscole),
  /// come su drift.
  @override
  Future<int> aggiungiSerie({
    required String name,
    int? totalIssues,
    String? issn,
  }) async {
    final nome = name.trim();
    final esistente = await _client
        .from(TabellaSupabase.serie.nome)
        .select('id')
        .ilike('name', _escapeLike(nome))
        .order('id')
        .limit(1)
        .maybeSingle();
    if (esistente != null) return esistente['id'] as int;
    return _inserisci(TabellaSupabase.serie, {
      'name': nome,
      'total_issues': totalIssues,
      'issn': issn,
    });
  }

  @override
  Future<int> aggiungiEdizione({
    required int operaId,
    int? serieId,
    String? publisher,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    String? releaseDate,
    String? coverPrice,
    int? pageCount,
    String? language,
    String? color,
    String? ean,
    String? volume,
    String? description,
    String? printingType,
    String? classificazione,
    int? year,
    FormatoEdizione? format,
    DateTime? createdAt,
  }) => _inserisci(TabellaSupabase.edizioni, {
    'opera_id': operaId,
    'serie_id': serieId,
    'publisher': publisher,
    'issue_number': issueNumber,
    'issue_number_label': issueNumberLabel,
    'cover_image': coverImage,
    'release_date': releaseDate,
    'cover_price': coverPrice,
    'page_count': pageCount,
    'language': language,
    'color': color,
    'ean': ean,
    'volume': volume,
    'description': description,
    'printing_type': printingType,
    'classificazione': classificazione,
    'year': year,
    'format': format?.name,
    if (createdAt != null) 'created_at': _iso(createdAt),
  });

  @override
  Future<int> aggiungiCopia({
    required int edizioneId,
    required StatoCopia status,
    StatoLettura? readingStatus,
    CondizioneCopia? condition,
    double? purchasePrice,
    ValutaPrezzo? purchasePriceCurrency,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    double? valutazione,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? scansioneId,
  }) {
    final aggiornataIl = updatedAt ?? createdAt;
    return _inserisci(TabellaSupabase.copie, {
      'edizione_id': edizioneId,
      'status': status.name,
      'reading_status': readingStatus?.name,
      'condition': condition?.name,
      'purchase_price': purchasePrice,
      'purchase_price_currency': purchasePriceCurrency?.name,
      'purchase_date': _isoOrNull(purchaseDate),
      'seller': seller,
      'location': location,
      'notes': notes,
      'valutazione': valutazione,
      'scansione_id': scansioneId,
      if (createdAt != null) 'created_at': _iso(createdAt),
      if (aggiornataIl != null) 'updated_at': _iso(aggiornataIl),
    });
  }

  @override
  Future<void> aggiornaTitoloOpera({
    required int operaId,
    required String title,
  }) => _aggiorna(TabellaSupabase.opere, operaId, {'title': title});

  @override
  Future<void> aggiornaEdizione({
    required int id,
    int? serieId,
    String? publisher,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    String? releaseDate,
    String? coverPrice,
    int? pageCount,
    String? language,
    String? color,
    String? ean,
    String? volume,
    String? description,
    int? year,
    FormatoEdizione? format,
  }) => _aggiorna(TabellaSupabase.edizioni, id, {
    'serie_id': serieId,
    'publisher': publisher,
    'issue_number': issueNumber,
    'issue_number_label': issueNumberLabel,
    'cover_image': coverImage,
    'release_date': releaseDate,
    'cover_price': coverPrice,
    'page_count': pageCount,
    'language': language,
    'color': color,
    'ean': ean,
    'volume': volume,
    'description': description,
    'year': year,
    'format': format?.name,
  });

  @override
  Future<void> aggiornaCopia({
    required int id,
    CondizioneCopia? condition,
    double? purchasePrice,
    ValutaPrezzo? purchasePriceCurrency,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    double? valutazione,
  }) => _aggiorna(TabellaSupabase.copie, id, {
    'condition': condition?.name,
    'purchase_price': purchasePrice,
    'purchase_price_currency': purchasePriceCurrency?.name,
    'purchase_date': _isoOrNull(purchaseDate),
    'seller': seller,
    'location': location,
    'notes': notes,
    'valutazione': valutazione,
    'updated_at': _iso(DateTime.now()),
  });

  @override
  Future<void> cambiaStatoCopia({
    required int id,
    required StatoCopia status,
    StatoLettura? readingStatus,
  }) => _aggiorna(TabellaSupabase.copie, id, {
    'status': status.name,
    'reading_status': readingStatus?.name,
    'updated_at': _iso(DateTime.now()),
  });

  @override
  Future<void> impostaInVendita({required int id, required bool inVendita}) =>
      _aggiorna(TabellaSupabase.copie, id, {
        'for_sale': inVendita,
        'updated_at': _iso(DateTime.now()),
      });

  @override
  Future<int> segnaEdizioniInVendita(List<int> edizioneIds) async {
    if (edizioneIds.isEmpty) return 0;
    final scritte = await _client
        .from(TabellaSupabase.copie.nome)
        .update({'for_sale': true, 'updated_at': _iso(DateTime.now())})
        .inFilter('edizione_id', edizioneIds)
        .inFilter('status', [
          StatoCopia.posseduta.name,
          StatoCopia.prestata.name,
        ])
        .select('id');
    _invalidazione.segnala({TabellaSupabase.copie});
    return scritte.length;
  }

  @override
  Future<bool> rimuoviCopia(int id) async {
    final edizioneEliminata = await _client.rpc<bool>(
      'rimuovi_copia',
      params: {'target_copia_id': id},
    );
    _invalidazione.segnala(_tabelleDiEdizione);
    return edizioneEliminata;
  }

  @override
  Future<void> eliminaEdizione(int edizioneId) async {
    await _client.rpc<void>(
      'elimina_edizione',
      params: {'target_edizione_id': edizioneId},
    );
    _invalidazione.segnala(_tabelleDiEdizione);
  }

  @override
  Future<List<SerieTableData>> cercaSerie(String query) async => [
    for (final riga
        in await _client
            .from(TabellaSupabase.serie.nome)
            .select()
            .ilike('name', '%${_escapeLike(query)}%')
            .order('id'))
      SerieTableData(
        id: riga['id'] as int,
        name: riga['name'] as String,
        totalIssues: riga['total_issues'] as int?,
        issn: riga['issn'] as String?,
        coverImage: riga['cover_image'] as String?,
      ),
  ];

  // --- Creator, Personaggi, Tag, Generi ---

  @override
  Future<List<CreatorData>> cercaCreator(String query) async => [
    for (final riga in await _cercaPerNome(TabellaSupabase.creator, query))
      CreatorData(id: riga['id'] as int, name: riga['name'] as String),
  ];

  @override
  Future<int> aggiungiCreator(String name) =>
      _inserisci(TabellaSupabase.creator, {'name': name});

  @override
  Future<void> collegaCreatorAEdizione({
    required int edizioneId,
    required int creatorId,
    required RuoloCreator ruolo,
  }) => _inserisci(TabellaSupabase.comicCreator, {
    'edizione_id': edizioneId,
    'creator_id': creatorId,
    'ruolo': ruolo.name,
  });

  @override
  Future<void> rimuoviCreatorDaEdizione(int comicCreatorId) =>
      _elimina(TabellaSupabase.comicCreator, comicCreatorId);

  @override
  Future<List<CreatorConRuolo>> autoriDiEdizione(int edizioneId) async {
    final righe = await _client
        .from(TabellaSupabase.comicCreator.nome)
        .select(_selectAutori)
        .eq('edizione_id', edizioneId)
        .order('id');
    return righe.map(_autore).toList();
  }

  @override
  Future<List<CharacterData>> cercaCharacter(String query) async => [
    for (final riga in await _cercaPerNome(TabellaSupabase.character, query))
      CharacterData(id: riga['id'] as int, name: riga['name'] as String),
  ];

  @override
  Future<int> aggiungiCharacter(String name) =>
      _inserisci(TabellaSupabase.character, {'name': name});

  @override
  Future<void> collegaCharacterAEdizione({
    required int edizioneId,
    required int characterId,
  }) => _inserisci(TabellaSupabase.comicCharacter, {
    'edizione_id': edizioneId,
    'character_id': characterId,
  });

  @override
  Future<void> rimuoviCharacterDaEdizione(int comicCharacterId) =>
      _elimina(TabellaSupabase.comicCharacter, comicCharacterId);

  @override
  Future<List<TagTableData>> cercaTag(String query) async => [
    for (final riga in await _cercaPerNome(TabellaSupabase.tag, query))
      TagTableData(id: riga['id'] as int, name: riga['name'] as String),
  ];

  @override
  Future<int> aggiungiTag(String name) =>
      _inserisci(TabellaSupabase.tag, {'name': name});

  @override
  Future<void> collegaTagAEdizione({
    required int edizioneId,
    required int tagId,
  }) => _inserisci(TabellaSupabase.edizioneTag, {
    'edizione_id': edizioneId,
    'tag_id': tagId,
  });

  @override
  Future<void> rimuoviTagDaEdizione(int edizioneTagId) =>
      _elimina(TabellaSupabase.edizioneTag, edizioneTagId);

  /// Sostituzione intera senza transazione: elimina i Generi fuori da
  /// [generi] e inserisce i mancanti ignorando quelli già presenti. Entrambi
  /// i passi sono idempotenti, quindi un errore a metà si ripara ripetendo
  /// la chiamata.
  @override
  Future<void> impostaGeneriEdizione({
    required int edizioneId,
    required Set<GenereEdizione> generi,
  }) async {
    final nomi = [for (final genere in generi) genere.name];
    var eliminazione = _client
        .from(TabellaSupabase.edizioneGenere.nome)
        .delete()
        .eq('edizione_id', edizioneId);
    if (nomi.isNotEmpty) {
      eliminazione = eliminazione.not('genere', 'in', '(${nomi.join(',')})');
    }
    await eliminazione;
    if (nomi.isNotEmpty) {
      final collezione = await collectionId();
      await _client
          .from(TabellaSupabase.edizioneGenere.nome)
          .upsert(
            [
              for (final nome in nomi)
                {
                  'collection_id': collezione,
                  'edizione_id': edizioneId,
                  'genere': nome,
                },
            ],
            onConflict: 'edizione_id,genere',
            ignoreDuplicates: true,
          );
    }
    _invalidazione.segnala({TabellaSupabase.edizioneGenere});
  }

  // --- Valore stimato (usato dalla Scheda; il resto dell'area arriva con
  // la fetta Serie/Dashboard/Valore stimato) ---

  @override
  Future<int> avviaOrRiavviaValoreStimato({
    required int copiaId,
    DateTime? createdAt,
  }) async {
    final esistente = await _client
        .from(TabellaSupabase.valoreStimato.nome)
        .select('id')
        .eq('copia_id', copiaId)
        .maybeSingle();
    if (esistente == null) {
      return _inserisci(TabellaSupabase.valoreStimato, {
        'copia_id': copiaId,
        'status': StatoValoreStimato.inCorso.name,
        if (createdAt != null) 'created_at': _iso(createdAt),
      });
    }
    final id = esistente['id'] as int;
    await _aggiorna(TabellaSupabase.valoreStimato, id, {
      'status': StatoValoreStimato.inCorso.name,
      'error_message': null,
    });
    return id;
  }

  @override
  Future<void> completaValoreStimato({
    required int id,
    required double value,
    DateTime? completedAt,
  }) => _aggiorna(TabellaSupabase.valoreStimato, id, {
    'status': StatoValoreStimato.completata.name,
    'value': value,
    'completed_at': _iso(completedAt ?? DateTime.now()),
  });

  // --- Scheda del fumetto ---

  @override
  Stream<EdizioneDettaglio?> watchEdizione(int edizioneId) =>
      _invalidazione.osserva(_tabelleDiEdizione, () async {
        final riga = await _client
            .from(TabellaSupabase.edizioni.nome)
            .select(
              '*, opere(id, title), serie(id, name), '
              'copie(*, valore_stimato(*)), comic_creator($_selectAutori)',
            )
            .eq('id', edizioneId)
            .maybeSingle();
        return riga == null ? null : _edizioneDettaglio(riga);
      });

  @override
  Future<String?> coverImageGrezzoDi(int edizioneId) async {
    final riga = await _client
        .from(TabellaSupabase.edizioni.nome)
        .select('cover_image')
        .eq('id', edizioneId)
        .single();
    return riga['cover_image'] as String?;
  }

  Future<EdizioneDettaglio> _edizioneDettaglio(Map<String, dynamic> e) async {
    final opera = e['opere'] as Map<String, dynamic>;
    final serie = e['serie'] as Map<String, dynamic>?;
    final copie = [
      for (final c in (e['copie'] as List).cast<Map<String, dynamic>>())
        _copiaDettaglio(c),
    ]..sort((a, b) => a.id.compareTo(b.id));
    final autori =
        (e['comic_creator'] as List)
            .cast<Map<String, dynamic>>()
            .map(_autore)
            .toList()
          ..sort((a, b) => a.comicCreatorId.compareTo(b.comicCreatorId));
    return EdizioneDettaglio(
      edizioneId: e['id'] as int,
      operaId: opera['id'] as int,
      titolo: opera['title'] as String,
      serieId: serie?['id'] as int?,
      serieName: serie?['name'] as String?,
      publisher: e['publisher'] as String?,
      issueNumber: e['issue_number'] as int?,
      issueNumberLabel: e['issue_number_label'] as String?,
      coverImage: await risolviCoverImage(e['cover_image'] as String?),
      releaseDate: e['release_date'] as String?,
      year: e['year'] as int?,
      coverPrice: e['cover_price'] as String?,
      pageCount: e['page_count'] as int?,
      language: e['language'] as String?,
      color: e['color'] as String?,
      ean: e['ean'] as String?,
      volume: e['volume'] as String?,
      description: e['description'] as String?,
      printingType: e['printing_type'] as String?,
      classificazione: e['classificazione'] as String?,
      autori: autori,
      copie: copie,
    );
  }

  static CopiaDettaglio _copiaDettaglio(Map<String, dynamic> c) {
    final valore = _unaONessuna(c['valore_stimato']);
    return CopiaDettaglio(
      id: c['id'] as int,
      status: StatoCopia.values.byName(c['status'] as String),
      readingStatus: _enumOrNull(StatoLettura.values, c['reading_status']),
      condition: _enumOrNull(CondizioneCopia.values, c['condition']),
      purchasePrice: (c['purchase_price'] as num?)?.toDouble(),
      purchasePriceCurrency: _enumOrNull(
        ValutaPrezzo.values,
        c['purchase_price_currency'],
      ),
      purchaseDate: _data(c['purchase_date']),
      seller: c['seller'] as String?,
      location: c['location'] as String?,
      notes: c['notes'] as String?,
      valutazione: (c['valutazione'] as num?)?.toDouble(),
      statoValoreStimato: _enumOrNull(
        StatoValoreStimato.values,
        valore?['status'],
      ),
      valoreStimato: (valore?['value'] as num?)?.toDouble(),
      valoreStimatoErrorMessage: valore?['error_message'] as String?,
      valoreStimatoAggiornatoAl: _data(valore?['completed_at']),
      forSale: c['for_sale'] as bool,
    );
  }

  static const _selectAutori = 'id, ruolo, creator(id, name)';

  static CreatorConRuolo _autore(Map<String, dynamic> riga) {
    final creator = riga['creator'] as Map<String, dynamic>;
    return (
      comicCreatorId: riga['id'] as int,
      creatorId: creator['id'] as int,
      name: creator['name'] as String,
      ruolo: RuoloCreator.values.byName(riga['ruolo'] as String),
    );
  }

  /// Le tabelle lette da [watchEdizione], e toccate dalle rimozioni.
  static const Set<TabellaSupabase> _tabelleDiEdizione = {
    TabellaSupabase.opere,
    TabellaSupabase.serie,
    TabellaSupabase.edizioni,
    TabellaSupabase.copie,
    TabellaSupabase.valoreStimato,
    TabellaSupabase.comicCreator,
    TabellaSupabase.creator,
    TabellaSupabase.comicCharacter,
    TabellaSupabase.edizioneTag,
    TabellaSupabase.edizioneGenere,
  };

  // --- Primitive ---

  /// Inserisce una riga nella Collezione e ne restituisce l'id.
  Future<int> _inserisci(
    TabellaSupabase tabella,
    Map<String, Object?> valori,
  ) async {
    final riga = await _client
        .from(tabella.nome)
        .insert({'collection_id': await collectionId(), ...valori})
        .select('id')
        .single();
    _invalidazione.segnala({tabella});
    return riga['id'] as int;
  }

  Future<void> _aggiorna(
    TabellaSupabase tabella,
    int id,
    Map<String, Object?> valori,
  ) async {
    await _client.from(tabella.nome).update(valori).eq('id', id);
    _invalidazione.segnala({tabella});
  }

  Future<void> _elimina(TabellaSupabase tabella, int id) async {
    await _client.from(tabella.nome).delete().eq('id', id);
    _invalidazione.segnala({tabella});
  }

  /// Match parziale del nome senza distinzione di maiuscole, come `LIKE` di
  /// SQLite su drift.
  Future<List<Map<String, dynamic>>> _cercaPerNome(
    TabellaSupabase tabella,
    String query,
  ) => _client
      .from(tabella.nome)
      .select('id, name')
      .ilike('name', '%${_escapeLike(query)}%')
      .order('id');
}

String _escapeLike(String testo) =>
    testo.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Un embed PostgREST uno-a-uno arriva come oggetto o come lista, a
/// seconda di come PostgREST legge i vincoli unique della FK composita.
Map<String, dynamic>? _unaONessuna(Object? embed) => switch (embed) {
  final Map<String, dynamic> riga => riga,
  final List<dynamic> righe when righe.isNotEmpty =>
    righe.first as Map<String, dynamic>,
  _ => null,
};

T? _enumOrNull<T extends Enum>(List<T> valori, Object? nome) =>
    nome == null ? null : valori.byName(nome as String);

DateTime? _data(Object? valore) =>
    valore == null ? null : DateTime.parse(valore as String).toLocal();

String _iso(DateTime data) => data.toUtc().toIso8601String();

String? _isoOrNull(DateTime? data) => data == null ? null : _iso(data);
