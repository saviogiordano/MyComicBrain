import 'dart:async';
import 'dart:io';

import 'package:mycomicbrain/core/data/supabase/uuid_v4.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// I bucket Storage privati di ADR-0007.
enum BucketStorage {
  covers('covers'),
  scansioni('scansioni');

  const BucketStorage(this.nome);

  final String nome;
}

/// I file di un Profilo autenticato su Storage (ADR-0007): chiavi, upload e
/// una cache su disco dei file scaricati. Le RLS di ADR-0004 restano
/// l'unica barriera.
///
/// È ciò che resta dell'adapter Supabase di `ComicsRepository` dopo
/// ADR-0008: la UI lavora sulla Replica locale e i file passano da qui con
/// la Sincronizzazione.
class StorageProfilo {
  StorageProfilo(
    this._client, {
    required this.userId,
    required Future<Directory> Function() cartellaCache,
  }) : _cartellaCache = cartellaCache;

  final SupabaseClient _client;
  final String userId;

  /// La cache del Profilo (`ReplicheProfilo.cartellaCache`), cancellata al
  /// logout.
  final Future<Directory> Function() _cartellaCache;

  Future<String>? _collectionId;
  final _downloadInCorso = <String, Future<String?>>{};

  /// La Collezione dell'utente: la riga `owner` in `collection_members`,
  /// creata dal trigger di signup (ADR-0004). Un errore (rete) non resta in
  /// memoria: la richiesta successiva riprova.
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

  /// Carica la cover in `covers/<collection_id>/<uuid>.<ext>` e restituisce
  /// la chiave dell'oggetto nel bucket. La copia in cache evita di
  /// riscaricarla.
  Future<String> caricaCover(File file) async {
    final estensione = _estensione(file.path);
    final chiave = '${await collectionId()}/${uuidV4()}.$estensione';
    await _carica(BucketStorage.covers, chiave, file, sovrascrivi: false);
    final inCache = await _fileInCache(BucketStorage.covers, chiave);
    await inCache.parent.create(recursive: true);
    await file.copy(inCache.path);
    return chiave;
  }

  /// Carica la Scansione in `scansioni/<user_id>/<nome del file>`: la
  /// chiave dipende solo dal file, quindi un upload ripetuto sovrascrive lo
  /// stesso oggetto.
  Future<String> caricaScansione(File file) async {
    final chiave = '$userId/${p.basename(file.path)}';
    await _carica(BucketStorage.scansioni, chiave, file, sovrascrivi: true);
    return chiave;
  }

  Future<void> _carica(
    BucketStorage bucket,
    String chiave,
    File file, {
    required bool sovrascrivi,
  }) => _client.storage
      .from(bucket.nome)
      .upload(
        chiave,
        file,
        fileOptions: FileOptions(
          contentType: _contentType(_estensione(file.path)),
          upsert: sovrascrivi,
        ),
      );

  /// Il file locale dell'oggetto [chiave] di [bucket], scaricato con la
  /// sessione dell'utente se non è già in cache. Le chiavi sono immutabili,
  /// quindi un file in cache non scade. `null` se l'oggetto non esiste o non
  /// è visibile all'utente.
  Future<String?> risolvi(BucketStorage bucket, String chiave) async {
    final inCache = await _fileInCache(bucket, chiave);
    if (inCache.existsSync()) return inCache.path;
    // Più widget chiedono spesso lo stesso file insieme: un solo download.
    final id = '${bucket.nome}/$chiave';
    final inCorso = _downloadInCorso[id];
    if (inCorso != null) return inCorso;
    final download = _scarica(bucket, chiave, inCache);
    _downloadInCorso[id] = download;
    try {
      return await download;
    } finally {
      unawaited(_downloadInCorso.remove(id));
    }
  }

  /// Toglie l'oggetto da Storage e dalla cache. Un errore di Storage non si
  /// propaga: un oggetto orfano nel bucket privato non è visibile a nessuno.
  Future<void> elimina(BucketStorage bucket, String chiave) async {
    try {
      await _client.storage.from(bucket.nome).remove([chiave]);
    } on StorageException {
      // Vedi sopra.
    }
    final inCache = await _fileInCache(bucket, chiave);
    if (inCache.existsSync()) await inCache.delete();
  }

  Future<String?> _scarica(
    BucketStorage bucket,
    String chiave,
    File destinazione,
  ) async {
    final List<int> bytes;
    try {
      bytes = await _client.storage.from(bucket.nome).download(chiave);
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

  Future<File> _fileInCache(BucketStorage bucket, String chiave) async {
    final base = await _cartellaCache();
    return File(p.joinAll([base.path, bucket.nome, ...chiave.split('/')]));
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
}
