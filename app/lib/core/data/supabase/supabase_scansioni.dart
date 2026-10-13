part of 'supabase_comics_repository.dart';

/// Area Scansioni e Analisi Copertina di [SupabaseComicsRepository] (#178).
/// Scansioni e Analisi sono private all'utente (ADR-0004): niente
/// `collection_id` nelle policy, `user_id` lo mette il default
/// `auth.uid()`.
///
/// La UI identifica una Scansione con il percorso del file salvato da
/// `ScansioneStorage`. Nel DB c'è la chiave Storage
/// `<user_id>/<nome-file>` (deciso su #178, scostamento da `<uuid>.jpg` di
/// ADR-0007): il
/// nome del file locale (`<millisecondi>.jpg`) è già unico sul device, e
/// così percorso e chiave si traducono senza tabelle di appoggio. Una
/// Scansione senza file locale (importata, o scattata su un altro device)
/// viene scaricata nella cache su disco, con lo stesso nome di file.
mixin _ScansioniSupabase implements ComicsRepository {
  SupabaseClient get _client;
  InvalidazioneTabelle get _invalidazione;
  String get userId;
  Future<Directory> Function() get _cartellaScansioni;
  Future<String> collectionId();
  Future<String?> _risolviInCache(_Bucket bucket, String chiave);
  Future<File> _fileInCache(_Bucket bucket, String chiave);

  /// La chiave Storage (e il valore di `scansioni.image`) per il file
  /// [percorso]: vale sia per il file di `ScansioneStorage` sia per la sua
  /// copia scaricata in cache, che ha lo stesso nome.
  String _chiaveScansione(String percorso) => '$userId/${p.basename(percorso)}';

  /// Il percorso locale della Scansione con chiave [chiave]: il file di
  /// `ScansioneStorage` se è su questo device, altrimenti la copia in
  /// cache, scaricata se serve. Se l'oggetto non è scaricabile il percorso
  /// resta quello della cache (file assente): la Scansione resta visibile e
  /// si può eliminare.
  Future<String> _percorsoScansione(String chiave) async {
    final locale = File(
      p.join((await _cartellaScansioni()).path, p.basename(chiave)),
    );
    if (locale.existsSync()) return locale.path;
    return await _risolviInCache(_Bucket.scansioni, chiave) ??
        (await _fileInCache(_Bucket.scansioni, chiave)).path;
  }

  // --- Scansioni ---

  /// Carica l'immagine e crea la riga. L'upload sovrascrive: un tentativo
  /// ripetuto dopo un errore sulla riga non trova la chiave occupata.
  @override
  Future<int> aggiungiScansione({
    required String image,
    DateTime? createdAt,
  }) async {
    final chiave = _chiaveScansione(image);
    await _client.storage
        .from(_Bucket.scansioni.nome)
        .upload(
          chiave,
          File(image),
          fileOptions: FileOptions(
            contentType: SupabaseComicsRepository._contentType(
              SupabaseComicsRepository._estensione(image),
            ),
            upsert: true,
          ),
        );
    final riga = await _client
        .from(TabellaSupabase.scansioni.nome)
        .insert({
          'image': chiave,
          'collection_id': await collectionId(),
          if (createdAt != null) 'created_at': _iso(createdAt),
        })
        .select('id')
        .single();
    _invalidazione.segnala({TabellaSupabase.scansioni});
    return riga['id'] as int;
  }

  @override
  Future<int> idScansionePerImmagine(String image) async {
    final riga = await _client
        .from(TabellaSupabase.scansioni.nome)
        .select('id')
        .eq('image', _chiaveScansione(image))
        .single();
    return riga['id'] as int;
  }

  /// Elimina la riga (Analisi e Identificazione seguono a cascata, le Copie
  /// perdono il collegamento) e poi, senza far fallire l'eliminazione,
  /// l'oggetto su Storage e la copia in cache.
  @override
  Future<void> eliminaScansione({required int id}) async {
    final righe = await _client
        .from(TabellaSupabase.scansioni.nome)
        .delete()
        .eq('id', id)
        .select('image');
    _invalidazione.segnala({
      TabellaSupabase.scansioni,
      TabellaSupabase.analisiCopertina,
      TabellaSupabase.identificazione,
      TabellaSupabase.candidati,
      TabellaSupabase.copie,
    });
    for (final riga in righe) {
      final chiave = riga['image'] as String;
      try {
        await _client.storage.from(_Bucket.scansioni.nome).remove([chiave]);
      } on StorageException {
        // Un oggetto orfano nel bucket privato dell'utente non è visibile a
        // nessuno: non vale un errore all'utente.
      }
      final inCache = await _fileInCache(_Bucket.scansioni, chiave);
      if (inCache.existsSync()) await inCache.delete();
    }
  }

  @override
  Stream<bool> watchScansioneConfermata(String image) => _invalidazione.osserva(
    {TabellaSupabase.scansioni, TabellaSupabase.copie},
    () async {
      final riga = await _client
          .from(TabellaSupabase.scansioni.nome)
          .select('id, copie(id)')
          .eq('image', _chiaveScansione(image))
          .maybeSingle();
      return riga != null && (riga['copie'] as List).isNotEmpty;
    },
  );

  @override
  Stream<List<String>> watchImmaginiScansioniNonConfermate() =>
      _invalidazione.osserva(
        {TabellaSupabase.scansioni, TabellaSupabase.copie},
        () async {
          final righe = await _client
              .from(TabellaSupabase.scansioni.nome)
              .select('image, copie(id)')
              .order('created_at', ascending: true)
              .order('id', ascending: true);
          return [
            for (final riga in righe)
              if ((riga['copie'] as List).isEmpty)
                await _percorsoScansione(riga['image'] as String),
          ];
        },
      );

  // --- Analisi Copertina ---

  @override
  Future<int> avviaAnalisiCopertina({
    required int scansioneId,
    DateTime? createdAt,
  }) async {
    final riga = await _client
        .from(TabellaSupabase.analisiCopertina.nome)
        .insert({
          'scansione_id': scansioneId,
          'status': StatoAnalisiCopertina.inCorso.name,
          if (createdAt != null) 'created_at': _iso(createdAt),
        })
        .select('id')
        .single();
    _invalidazione.segnala({TabellaSupabase.analisiCopertina});
    return riga['id'] as int;
  }

  @override
  Future<void> completaAnalisiCopertina({
    required int id,
    required String rawResponse,
    String? title,
    String? issueNumberLabel,
    String? publisher,
    String? seriesName,
    String? isbn,
    String? barcode,
    String? price,
    String? releaseDate,
    int? year,
    int? pageCount,
    String? language,
    String? color,
    String? issn,
    List<String> characters = const [],
    List<String> coverStyleTags = const [],
    List<String> visualElementTags = const [],
    String? recognizedPublisherLogo,
    String? recognizedSeriesLogo,
    String? printingType,
    String? classificazione,
    String? description,
    DateTime? completedAt,
  }) => _aggiornaAnalisi(id, {
    'title': title,
    'issue_number_label': issueNumberLabel,
    'publisher': publisher,
    'series_name': seriesName,
    'isbn': isbn,
    'barcode': barcode,
    'price': price,
    'release_date': releaseDate,
    'year': year,
    'page_count': pageCount,
    'language': language,
    'color': color,
    'issn': issn,
    'characters': characters,
    'cover_style_tags': coverStyleTags,
    'visual_element_tags': visualElementTags,
    'recognized_publisher_logo': recognizedPublisherLogo,
    'recognized_series_logo': recognizedSeriesLogo,
    'printing_type': printingType,
    'classificazione': classificazione,
    'description': description,
    'raw_response': rawResponse,
    'status': StatoAnalisiCopertina.completata.name,
    'completed_at': _iso(completedAt ?? DateTime.now()),
  });

  @override
  Future<void> fallisciAnalisiCopertina({
    required int id,
    required String errorMessage,
    DateTime? completedAt,
  }) => _aggiornaAnalisi(id, {
    'status': StatoAnalisiCopertina.fallita.name,
    'error_message': errorMessage,
    'completed_at': _iso(completedAt ?? DateTime.now()),
  });

  @override
  Future<void> riavviaAnalisiCopertina({required int id}) =>
      _aggiornaAnalisi(id, {
        'status': StatoAnalisiCopertina.inCorso.name,
        'error_message': null,
        'completed_at': null,
      });

  @override
  Future<int> idAnalisiCopertinaPerScansione(int scansioneId) async =>
      (await analisiCopertinaPerScansione(scansioneId)).id;

  @override
  Future<AnalisiCopertinaTableData> analisiCopertinaPerScansione(
    int scansioneId,
  ) async {
    final a = await _client
        .from(TabellaSupabase.analisiCopertina.nome)
        .select()
        .eq('scansione_id', scansioneId)
        .single();
    List<String> lista(String chiave) => (a[chiave] as List).cast<String>();
    return AnalisiCopertinaTableData(
      id: a['id'] as int,
      scansioneId: a['scansione_id'] as int,
      title: a['title'] as String?,
      issueNumberLabel: a['issue_number_label'] as String?,
      publisher: a['publisher'] as String?,
      seriesName: a['series_name'] as String?,
      isbn: a['isbn'] as String?,
      barcode: a['barcode'] as String?,
      price: a['price'] as String?,
      releaseDate: a['release_date'] as String?,
      year: a['year'] as int?,
      pageCount: a['page_count'] as int?,
      language: a['language'] as String?,
      color: a['color'] as String?,
      issn: a['issn'] as String?,
      characters: lista('characters'),
      coverStyleTags: lista('cover_style_tags'),
      visualElementTags: lista('visual_element_tags'),
      recognizedPublisherLogo: a['recognized_publisher_logo'] as String?,
      recognizedSeriesLogo: a['recognized_series_logo'] as String?,
      printingType: a['printing_type'] as String?,
      classificazione: a['classificazione'] as String?,
      description: a['description'] as String?,
      rawResponse: a['raw_response'] as String?,
      status: StatoAnalisiCopertina.values.byName(a['status'] as String),
      errorMessage: a['error_message'] as String?,
      completedAt: _data(a['completed_at']),
      createdAt: _data(a['created_at'])!,
    );
  }

  /// Lo stato dell'Analisi della Scansione [image]: `pending` finché la
  /// pipeline non ha creato la riga, come su drift.
  @override
  Stream<StatoAnalisiScansione> watchStatoAnalisiCopertina(String image) =>
      _invalidazione.osserva(
        {TabellaSupabase.scansioni, TabellaSupabase.analisiCopertina},
        () async {
          final riga = await _client
              .from(TabellaSupabase.scansioni.nome)
              .select('analisi_copertina(status, error_message)')
              .eq('image', _chiaveScansione(image))
              .maybeSingle();
          final analisi = _unaONessuna(riga?['analisi_copertina']);
          return (
            stato:
                _enumOrNull(
                  StatoAnalisiCopertina.values,
                  analisi?['status'],
                ) ??
                StatoAnalisiCopertina.pending,
            errorMessage: analisi?['error_message'] as String?,
          );
        },
      );

  Future<void> _aggiornaAnalisi(int id, Map<String, Object?> valori) async {
    await _client
        .from(TabellaSupabase.analisiCopertina.nome)
        .update(valori)
        .eq('id', id);
    _invalidazione.segnala({TabellaSupabase.analisiCopertina});
  }
}
