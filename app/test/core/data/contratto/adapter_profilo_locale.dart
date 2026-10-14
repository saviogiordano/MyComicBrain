import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/exchange_rate_client.dart';
import 'package:mycomicbrain/core/data/supabase/archivio_conversazione_supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'adapter_sotto_contratto.dart';

/// La factory del repository di un Profilo autenticato (ADR-0008): una
/// Replica drift in memoria con la Conversazione su Supabase, contro lo
/// stack locale `supabase start`. `null` se le variabili d'ambiente mancano
/// (vedi `scripts/test-contratto-supabase.sh`). Ogni adapter è un utente
/// nuovo: dati vuoti senza pulire nulla.
CreaAdapter? creaAdapterProfiloLocale() {
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
    await client.auth.signUp(
      email: 'contratto-${_casuale()}@example.com',
      password: 'Contratto-${_casuale()}1',
    );
    final scansioni = await Directory.systemTemp.createTemp(
      'contratto_scansioni_',
    );
    return _AdapterProfiloLocale(
      client,
      AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ),
      scansioni,
    );
  };
}

String _casuale() => List.generate(
  12,
  (_) => Random.secure().nextInt(36).toRadixString(36),
).join();

class _AdapterProfiloLocale implements AdapterSottoContratto {
  _AdapterProfiloLocale(this._client, this.drift, this._scansioni)
    : _conversazione = ArchivioConversazioneSupabase(_client) {
    repo = repoCon();
  }

  final SupabaseClient _client;
  final Directory _scansioni;

  /// Condiviso con i repository di [repoCon]: le loro scritture rileggono
  /// anche gli stream di [repo].
  final ArchivioConversazioneSupabase _conversazione;

  @override
  final AppDatabase drift;

  @override
  late final ComicsRepository repo;

  @override
  ComicsRepository repoCon({
    CopertinaDownloader? copertinaDownloader,
    ExchangeRateClient? exchangeRateClient,
  }) => DriftComicsRepository(
    drift,
    copertinaDownloader: copertinaDownloader,
    exchangeRateClient: exchangeRateClient,
    conversazione: _conversazione,
  );

  @override
  Future<String> immagineScansione(String nome) =>
      scriviImmagineScansione(_scansioni, nome);

  @override
  Future<void> chiudi() async {
    await _conversazione.chiudi();
    await drift.close();
    await _client.auth.signOut();
    await _client.dispose();
    await _scansioni.delete(recursive: true);
  }
}
