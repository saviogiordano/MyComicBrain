import 'dart:io';
import 'dart:math';

import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/exchange_rate_client.dart';
import 'package:mycomicbrain/core/data/supabase/supabase_comics_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'adapter_sotto_contratto.dart';

/// La factory dell'adapter Supabase contro lo stack locale `supabase
/// start`, o `null` se le variabili d'ambiente mancano (vedi
/// `scripts/test-contratto-supabase.sh`). Ogni adapter è un utente nuovo,
/// con la sua Collezione creata dal trigger di signup: dati vuoti senza
/// pulire nulla.
CreaAdapter? creaAdapterSupabaseLocale() {
  final url = Platform.environment['SUPABASE_TEST_URL'];
  final chiave = Platform.environment['SUPABASE_TEST_PUBLISHABLE_KEY'];
  if (url == null || url.isEmpty || chiave == null || chiave.isEmpty) {
    return null;
  }
  return () async {
    final client = SupabaseClient(
      url,
      chiave,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    final risposta = await client.auth.signUp(
      email: 'contratto-${_casuale()}@example.com',
      password: 'Contratto-${_casuale()}1',
    );
    final cache = await Directory.systemTemp.createTemp('contratto_supabase_');
    final scansioni = await Directory.systemTemp.createTemp(
      'contratto_scansioni_',
    );
    return _AdapterSupabaseLocale(
      client,
      risposta.user!.id,
      cache,
      scansioni,
    );
  };
}

String _casuale() => List.generate(
  12,
  (_) => Random.secure().nextInt(36).toRadixString(36),
).join();

class _AdapterSupabaseLocale implements AdapterSottoContratto {
  _AdapterSupabaseLocale(
    this._client,
    String userId,
    this._cache,
    this._scansioni,
  ) : repo = SupabaseComicsRepository(
        _client,
        userId: userId,
        cartellaCache: () async => _cache,
        cartellaScansioni: () async => _scansioni,
      );

  final SupabaseClient _client;
  final Directory _cache;
  final Directory _scansioni;

  @override
  final SupabaseComicsRepository repo;

  /// Stesso utente e stessa cache: l'adapter non usa ancora le dipendenze
  /// sostituibili (arriveranno con le fette che scaricano cover ComicVine e
  /// leggono il tasso di cambio).
  @override
  ComicsRepository repoCon({
    CopertinaDownloader? copertinaDownloader,
    ExchangeRateClient? exchangeRateClient,
  }) => repo;

  @override
  AppDatabase get drift => throw StateError(
    "Test che legge righe drift: va riscritto sull'interfaccia "
    'ComicsRepository per girare su Supabase (ADR-0007)',
  );

  @override
  Future<String> immagineScansione(String nome) =>
      scriviImmagineScansione(_scansioni, nome);

  @override
  Future<void> chiudi() async {
    await repo.chiudi();
    await _client.auth.signOut();
    await _client.dispose();
    await _cache.delete(recursive: true);
    await _scansioni.delete(recursive: true);
  }
}
