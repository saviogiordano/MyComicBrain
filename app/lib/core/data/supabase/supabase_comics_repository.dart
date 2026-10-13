import 'dart:async';
import 'dart:io';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/supabase/invalidazione_tabelle.dart';
import 'package:mycomicbrain/core/data/supabase/uuid_v4.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:mycomicbrain/core/domain/valore_stimato.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'supabase_catalogo.dart';

const _bucketCover = 'covers';
const _cartellaCacheCover = 'cover_supabase';

/// [ComicsRepository] su Supabase per un Profilo autenticato (ADR-0007):
/// legato a un `user_id` e alla Collezione di cui è `owner`, risolta alla
/// prima richiesta e poi riusata. Le RLS di ADR-0004 restano l'unica
/// barriera di autorizzazione.
///
/// Le aree portate stanno in file `part` (Catalogo: `supabase_catalogo.dart`).
/// Il porting procede per fette (mappa #165): i metodi non ancora portati
/// lanciano [UnimplementedError] tramite [noSuchMethod]. Il login resta
/// dietro `ACCOUNT_LOGIN` finché la suite di contratto non passa per intero
/// anche qui.
class SupabaseComicsRepository
    with _CatalogoSupabase
    implements ComicsRepository {
  SupabaseComicsRepository(
    this._client, {
    required this.userId,
    Future<Directory> Function()? cartellaCache,
    InvalidazioneTabelle? invalidazione,
  }) : _cartellaCache = cartellaCache ?? getApplicationCacheDirectory,
       _invalidazione = invalidazione ?? InvalidazioneTabelle();

  @override
  final SupabaseClient _client;
  final String userId;
  final Future<Directory> Function() _cartellaCache;
  @override
  final InvalidazioneTabelle _invalidazione;

  Future<String>? _collectionId;
  final _downloadInCorso = <String, Future<String?>>{};

  /// La Collezione dell'utente: la riga `owner` in `collection_members`,
  /// creata dal trigger di signup (ADR-0004). Un errore (rete) non resta in
  /// memoria: la richiesta successiva riprova.
  @override
  Future<String> collectionId() =>
      _collectionId ??= _risolviCollezione().then<String>(
        (id) => id,
        onError: (Object errore, StackTrace stack) {
          _collectionId = null;
          Error.throwWithStackTrace(errore, stack);
        },
      );

  Future<String> _risolviCollezione() async {
    final riga = await _client
        .from('collection_members')
        .select('collection_id')
        .eq('user_id', userId)
        .eq('role', 'owner')
        .single();
    return riga['collection_id'] as String;
  }

  /// Rilascia il segnale di invalidazione; chiamato dal provider quando il
  /// Profilo cambia.
  Future<void> chiudi() => _invalidazione.chiudi();

  // --- Cover (bucket privato `covers`, ADR-0007) ---

  /// Carica la cover in `covers/<collection_id>/<uuid>.<ext>` e restituisce
  /// la chiave dell'oggetto nel bucket, che è ciò che va in
  /// `edizioni.cover_image`. La copia in cache evita di riscaricarla.
  @override
  Future<String> salvaCoverLocale(File file) async {
    final estensione = _estensione(file.path);
    final chiave = '${await collectionId()}/${uuidV4()}.$estensione';
    await _client.storage
        .from(_bucketCover)
        .upload(
          chiave,
          file,
          fileOptions: FileOptions(contentType: _contentType(estensione)),
        );
    final inCache = await _fileInCache(chiave);
    await inCache.parent.create(recursive: true);
    await file.copy(inCache.path);
    return chiave;
  }

  /// Un URL remoto (fallback ComicVine) torna invariato; una chiave Storage
  /// diventa un file locale, scaricato con la sessione dell'utente in una
  /// cache su disco: la UI resta su `Image.file`. Le chiavi sono immutabili
  /// (un uuid per file), quindi un file in cache non scade. `null` se
  /// l'oggetto non esiste o non è visibile all'utente.
  @override
  Future<String?> risolviCoverImage(String? coverImage) async {
    if (coverImage == null) return null;
    if (coverImage.startsWith('http://') || coverImage.startsWith('https://')) {
      return coverImage;
    }
    final inCache = await _fileInCache(coverImage);
    if (inCache.existsSync()) return inCache.path;
    // Più widget chiedono spesso la stessa cover insieme: un solo download.
    final inCorso = _downloadInCorso[coverImage];
    if (inCorso != null) return inCorso;
    final download = _scarica(coverImage, inCache);
    _downloadInCorso[coverImage] = download;
    try {
      return await download;
    } finally {
      unawaited(_downloadInCorso.remove(coverImage));
    }
  }

  Future<String?> _scarica(String chiave, File destinazione) async {
    final List<int> bytes;
    try {
      bytes = await _client.storage.from(_bucketCover).download(chiave);
    } on StorageException {
      return null;
    }
    await destinazione.parent.create(recursive: true);
    // Scrittura atomica: un file a metà in cache sarebbe servito per sempre.
    final temporaneo = File('${destinazione.path}.${uuidV4()}.tmp');
    await temporaneo.writeAsBytes(bytes, flush: true);
    await temporaneo.rename(destinazione.path);
    return destinazione.path;
  }

  Future<File> _fileInCache(String chiave) async {
    final base = await _cartellaCache();
    return File(
      p.joinAll([base.path, _cartellaCacheCover, ...chiave.split('/')]),
    );
  }

  static String _estensione(String percorso) {
    final estensione = p
        .extension(percorso)
        .replaceFirst('.', '')
        .toLowerCase();
    return switch (estensione) {
      'png' || 'webp' => estensione,
      _ => 'jpg',
    };
  }

  static String _contentType(String estensione) => switch (estensione) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  /// I metodi non ancora portati (fette successive della mappa #165).
  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'SupabaseComicsRepository: ${_nome(invocation.memberName)} non ancora '
    'portato su Supabase (ADR-0007)',
  );

  static String _nome(Symbol simbolo) =>
      RegExp(r'Symbol\("(.*)"\)').firstMatch('$simbolo')?.group(1) ??
      '$simbolo';
}
