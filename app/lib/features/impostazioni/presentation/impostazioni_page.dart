import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/importazione_schema.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/impostazioni/application/ai_provider.dart';
import 'package:mycomicbrain/features/impostazioni/application/esportazione_service.dart';
import 'package:mycomicbrain/features/impostazioni/application/importazione_service.dart';

/// Schermo Impostazioni (§12, deciso su #104): elenco di righe stile
/// impostazioni di sistema — il valore corrente in trailing, ogni riga apre
/// una bottom sheet per modificarla. Ogni modifica scrive subito nel
/// `SettingsRepository` (#105): nessun pulsante "Salva" a livello di
/// schermo, coerente col pattern "modifica singolo campo" del layout #104.
///
/// I provider AI sono mostrati in due sezioni indipendenti, una per
/// `RuoloProviderAi` (Visivo/Testuale, schema deciso su #127): ciascuna con
/// le sue quattro card sempre espanse (§12, richiesto dall'utente dopo #111,
/// vedi sotto), entrambe con la riga "Verifica connessione" (§10, #129 —
/// arrivata per il Testuale con l'implementazione dell'Assistente/
/// tool-calling, #126). Il chip "Attivo" di una sezione seleziona quale dei
/// quattro è il provider usato a runtime per quel ruolo
/// (`coverAnalysisClientProvider` per il Visivo, `assistenteClientProvider`
/// per il Testuale).
///
/// Le card restano sempre espanse invece che dietro un selettore (§12, dopo
/// #111: le config per provider erano già salvate separatamente in
/// `SettingsRepository` — API key e modello sono mappe per `AiProvider`, non
/// sovrascritte al cambio — ma la UI ne mostrava una sola alla volta dietro
/// una bottom sheet di selezione, obbligando a riaprire il selettore per
/// rivedere/modificare la config di un provider non attivo).
class ImpostazioniPage extends ConsumerStatefulWidget {
  const ImpostazioniPage({super.key});

  @override
  ConsumerState<ImpostazioniPage> createState() => _ImpostazioniPageState();
}

class _ImpostazioniPageState extends ConsumerState<ImpostazioniPage> {
  bool _caricamento = true;

  // Stato per (ruolo, provider): Visivo e Testuale hanno configurazioni
  // pienamente indipendenti (ADR-0001, #127).
  final Map<RuoloProviderAi, AiProvider> _providerAttivo = {
    for (final r in RuoloProviderAi.values) r: AiProvider.claude,
  };
  final Map<RuoloProviderAi, Map<AiProvider, String>> _apiKeyAi = {
    for (final r in RuoloProviderAi.values) r: {},
  };
  final Map<RuoloProviderAi, Map<AiProvider, String>> _modello = {
    for (final r in RuoloProviderAi.values) r: {},
  };
  final Map<RuoloProviderAi, String> _urlLocale = {
    for (final r in RuoloProviderAi.values) r: '',
  };

  String _apiKeyComics = '';

  // Stato di "Verifica connessione" per provider, indipendente fra i due
  // ruoli (vedi commento sulla classe): ciascuno ha il proprio client e
  // quindi il proprio esito.
  final Map<AiProvider, ({bool loading, EsitoVerifica? esito})> _verificaAi = {
    for (final p in AiProvider.values) p: (loading: false, esito: null),
  };
  final Map<AiProvider, ({bool loading, EsitoVerifica? esito})>
  _verificaAssistente = {
    for (final p in AiProvider.values) p: (loading: false, esito: null),
  };

  ({bool loading, EsitoVerifica? esito}) _verificaComicVine = (
    loading: false,
    esito: null,
  );

  // Stato di "Esportazione in corso" (§16, deciso su #140): un solo export
  // alla volta, condiviso fra CSV e JSON — non ha senso avviarne due in
  // parallelo dalla stessa schermata.
  bool _esportazioneInCorso = false;

  // Stato di "Import in corso" (§16, deciso su #142), stesso pattern di
  // [_esportazioneInCorso].
  bool _importazioneInCorso = false;

  @override
  void initState() {
    super.initState();
    _caricaImpostazioni();
  }

  /// Precarica lo stato dal `SettingsRepository` (#105), per entrambi i
  /// ruoli (#129): il provider AI attivo e i modelli sono sincroni
  /// (`shared_preferences`), le API key passano da `flutter_secure_storage`
  /// e vanno attese — una per provider, in parallelo entro ciascun ruolo.
  /// Default a Claude quando l'utente non ha ancora scelto un provider per
  /// quel ruolo — stesso default di `coverAnalysisClientProvider`
  /// (`core/data/providers.dart`) per il Visivo.
  Future<void> _caricaImpostazioni() async {
    final repo = ref.read(settingsRepositoryProvider);
    final apiKeyComics = await repo.apiKeyComics;
    final perRuolo = <RuoloProviderAi, (AiProvider, List<String?>)>{};
    for (final ruolo in RuoloProviderAi.values) {
      final provider = repo.providerAi(ruolo) ?? AiProvider.claude;
      final apiKeys = await Future.wait([
        for (final p in AiProvider.values) repo.apiKeyAi(ruolo, p),
      ]);
      perRuolo[ruolo] = (provider, apiKeys);
    }
    if (!mounted) return;
    setState(() {
      for (final ruolo in RuoloProviderAi.values) {
        final (provider, apiKeys) = perRuolo[ruolo]!;
        _providerAttivo[ruolo] = provider;
        for (final (i, p) in AiProvider.values.indexed) {
          _apiKeyAi[ruolo]![p] = apiKeys[i] ?? '';
          _modello[ruolo]![p] =
              repo.modello(ruolo, p) ?? p.modelloDefault(ruolo);
        }
        _urlLocale[ruolo] = repo.urlLocale(ruolo) ?? '';
      }
      _apiKeyComics = apiKeyComics ?? '';
      _caricamento = false;
    });
  }

  Future<void> _selezionaProviderAttivo(
    RuoloProviderAi ruolo,
    AiProvider provider,
  ) async {
    if (provider == _providerAttivo[ruolo]) return;
    await ref
        .read(settingsRepositoryProvider)
        .impostaProviderAi(ruolo, provider);
    _invalidaAssistenteConfiguratoSe(ruolo);
    if (!mounted) return;
    setState(() => _providerAttivo[ruolo] = provider);
  }

  /// Il banner bloccante di Cerca (§10, #123/#137) osserva
  /// `assistenteConfiguratoProvider`, che non ha modo di sapere da solo
  /// quando `SettingsRepository` cambia — va invalidato esplicitamente ad
  /// ogni scrittura sul ruolo Testuale perché si sblocchi "senza refresh
  /// manuale" come deciso su #123.
  void _invalidaAssistenteConfiguratoSe(RuoloProviderAi ruolo) {
    if (ruolo == RuoloProviderAi.testuale) {
      ref.invalidate(assistenteConfiguratoProvider);
    }
  }

  Future<void> _verificaConnessioneAi(AiProvider provider) async {
    setState(
      () => _verificaAi[provider] = (loading: true, esito: null),
    );
    final esito = await verificaProviderAi(
      aiClient: () => ref.read(coverAnalysisClientPerProvider(provider)),
    );
    if (!mounted) return;
    setState(() => _verificaAi[provider] = (loading: false, esito: esito));
    if (!esito.ok) {
      await _mostraErroreVerifica(provider.label, esito.messaggio);
    }
  }

  Future<void> _verificaConnessioneAssistente(AiProvider provider) async {
    setState(
      () => _verificaAssistente[provider] = (loading: true, esito: null),
    );
    final esito = await verificaProviderAssistente(
      assistenteClient: () => ref.read(assistenteClientPerProvider(provider)),
    );
    if (!mounted) return;
    setState(
      () => _verificaAssistente[provider] = (loading: false, esito: esito),
    );
    if (!esito.ok) {
      await _mostraErroreVerifica(provider.label, esito.messaggio);
    }
  }

  Future<void> _verificaConnessioneComicVine() async {
    setState(() => _verificaComicVine = (loading: true, esito: null));
    final esito = await verificaProviderComicVine(
      comicVineClient: () => ref.read(comicVineClientProvider),
    );
    if (!mounted) return;
    setState(() => _verificaComicVine = (loading: false, esito: esito));
    if (!esito.ok) {
      await _mostraErroreVerifica('Provider fumetti', esito.messaggio);
    }
  }

  /// Esporta l'intera collezione (§16, "Importa/Esporta dati", deciso su
  /// #139/#140) nel [formato] scelto e la consegna tramite lo share sheet
  /// di sistema (`EsportazioneService`) — un solo export alla volta
  /// ([_esportazioneInCorso]), errori riusano lo stesso popup esteso di
  /// "Verifica connessione" ([_mostraErroreVerifica]).
  Future<void> _esporta(FormatoEsportazione formato) async {
    if (_esportazioneInCorso) return;
    setState(() => _esportazioneInCorso = true);
    try {
      await ref.read(esportazioneServiceProvider).esporta(formato);
    } on Object catch (e) {
      if (!mounted) return;
      await _mostraErroreVerifica(
        'Esportazione',
        'Esportazione non riuscita: $e',
      );
    } finally {
      if (mounted) setState(() => _esportazioneInCorso = false);
    }
  }

  /// Importa collezione da CSV/JSON (§16, "Importa/Esporta dati", deciso su
  /// #139/#142): selezione file tramite `file_picker`
  /// (`ImportazioneService`), import additivo semplice — righe malformate
  /// vengono saltate, non bloccano le altre. Al termine mostra un riepilogo
  /// (N importate, M saltate con motivo, [_mostraRiepilogoImportazione]);
  /// se l'utente annulla la selezione del file non succede nulla. Errori di
  /// file/parsing riusano lo stesso popup esteso di "Verifica connessione"
  /// ([_mostraErroreVerifica]).
  Future<void> _importa() async {
    if (_importazioneInCorso) return;
    setState(() => _importazioneInCorso = true);
    try {
      final risultato = await ref.read(importazioneServiceProvider).importa();
      if (!mounted || risultato == null) return;
      await _mostraRiepilogoImportazione(risultato);
    } on Object catch (e) {
      if (!mounted) return;
      await _mostraErroreVerifica('Import', 'Import non riuscito: $e');
    } finally {
      if (mounted) setState(() => _importazioneInCorso = false);
    }
  }

  /// Riepilogo finale dell'import (§16, deciso su #142): conteggio righe
  /// importate/saltate, con il motivo di ciascuno scarto per farlo
  /// individuare nel file originale.
  Future<void> _mostraRiepilogoImportazione(
    RisultatoAnalisiImportazione risultato,
  ) {
    final scartate = risultato.scartate;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Import completato'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${risultato.valide.length} importate, '
                  '${scartate.length} saltate.',
                ),
                if (scartate.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  for (final riga in scartate)
                    Text('Riga ${riga.numeroRiga}: ${riga.motivo}'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Mostra il motivo del fallimento per esteso in un popup (§12, richiesto
  /// dall'utente dopo #111: il valore in `_Riga` è su una riga sola con
  /// ellissi — un messaggio d'errore lungo, tipico soprattutto per
  /// "Configurazione mancante: ..." (`errore_configurazione.dart`), risultava
  /// tagliato e illeggibile lì).
  Future<void> _mostraErroreVerifica(String titolo, String messaggio) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(titolo),
        content: Text(messaggio),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _apriSheetModello(
    RuoloProviderAi ruolo,
    AiProvider provider,
  ) async {
    final attuale =
        _modello[ruolo]![provider] ?? provider.modelloDefault(ruolo);
    final curati = provider.modelliCurati;
    if (curati != null) {
      final scelto = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surfaceRaised,
        builder: (context) => _SheetLista(
          titolo: 'Modello',
          children: [
            for (final m in curati)
              ListTile(
                title: Text(
                  m,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: m == attuale
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      );
      if (scelto != null) await _salvaModello(ruolo, provider, scelto);
      return;
    }
    final testo = await _apriSheetTestoLibero(
      titolo: 'Modello',
      valoreIniziale: attuale,
      hint: provider == AiProvider.locale ? 'es. llama3' : null,
    );
    if (testo != null) await _salvaModello(ruolo, provider, testo);
  }

  Future<void> _salvaModello(
    RuoloProviderAi ruolo,
    AiProvider provider,
    String modello,
  ) async {
    await ref
        .read(settingsRepositoryProvider)
        .impostaModello(ruolo, provider, modello);
    if (!mounted) return;
    setState(() => _modello[ruolo]![provider] = modello);
  }

  Future<void> _modificaApiKeyAi(
    RuoloProviderAi ruolo,
    AiProvider provider,
  ) async {
    final v = await _apriSheetTestoLibero(
      titolo: 'API key',
      valoreIniziale: _apiKeyAi[ruolo]![provider] ?? '',
      mascherato: true,
    );
    if (v == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .impostaApiKeyAi(ruolo, provider, v);
    _invalidaAssistenteConfiguratoSe(ruolo);
    if (!mounted) return;
    setState(() => _apiKeyAi[ruolo]![provider] = v);
  }

  Future<void> _modificaUrlLocale(RuoloProviderAi ruolo) async {
    final v = await _apriSheetTestoLibero(
      titolo: 'URL API',
      valoreIniziale: _urlLocale[ruolo] ?? '',
      hint: 'http://localhost:11434/v1',
      validatore: (testo) {
        if (testo.trim().isEmpty) return null;
        return urlLocaleValido(testo)
            ? null
            : 'URL non valido: usa un endpoint http/https completo.';
      },
    );
    if (v == null) return;
    await ref.read(settingsRepositoryProvider).impostaUrlLocale(ruolo, v);
    _invalidaAssistenteConfiguratoSe(ruolo);
    if (!mounted) return;
    setState(() => _urlLocale[ruolo] = v);
  }

  Future<String?> _apriSheetTestoLibero({
    required String titolo,
    required String valoreIniziale,
    String? hint,
    bool mascherato = false,
    String? Function(String)? validatore,
  }) {
    final ctrl = TextEditingController(text: valoreIniziale);
    String? errore;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.md,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titolo,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: ctrl,
                obscureText: mascherato,
                autofocus: true,
                decoration: InputDecoration(hintText: hint),
              ),
              if (errore != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errore!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.amberStrong,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () {
                  final messaggio = validatore?.call(ctrl.text);
                  if (messaggio != null) {
                    setSheetState(() => errore = messaggio);
                    return;
                  }
                  Navigator.pop(context, ctrl.text);
                },
                child: const Text('Salva'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Le quattro card provider AI per [ruolo] (§12), con la riga "Verifica
  /// connessione" pilotata da [verificaState]/[onVerifica] — stato ed
  /// handler indipendenti fra Visivo e Testuale (vedi commento sulla
  /// classe).
  List<Widget> _cardsProviderAi(
    RuoloProviderAi ruolo, {
    required Map<AiProvider, ({bool loading, EsitoVerifica? esito})>
    verificaState,
    required void Function(AiProvider) onVerifica,
  }) {
    return [
      for (final provider in AiProvider.values) ...[
        _ProviderCard(
          provider: provider,
          attivo: provider == _providerAttivo[ruolo],
          apiKey: _apiKeyAi[ruolo]![provider] ?? '',
          modello: _modello[ruolo]![provider] ?? provider.modelloDefault(ruolo),
          urlLocale: _urlLocale[ruolo] ?? '',
          verifica: verificaState[provider],
          onSelezionaAttivo: () => _selezionaProviderAttivo(ruolo, provider),
          onModificaApiKey: () => _modificaApiKeyAi(ruolo, provider),
          onModificaModello: () => _apriSheetModello(ruolo, provider),
          onModificaUrl: () => _modificaUrlLocale(ruolo),
          onVerifica: verificaState[provider]!.loading
              ? null
              : () => onVerifica(provider),
        ),
        if (provider != AiProvider.values.last)
          const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Impostazioni'),
      ),
      body: SafeArea(
        child: _caricamento
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xxl,
                ),
                children: [
                  const SectionHeader(label: 'Provider AI Visivo'),
                  const SizedBox(height: AppSpacing.sm),
                  Column(
                    key: const ValueKey('sezione-provider-ai-visivo'),
                    children: _cardsProviderAi(
                      RuoloProviderAi.visivo,
                      verificaState: _verificaAi,
                      onVerifica: _verificaConnessioneAi,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(label: 'Provider AI Testuale'),
                  const SizedBox(height: AppSpacing.sm),
                  Column(
                    key: const ValueKey('sezione-provider-ai-testuale'),
                    children: _cardsProviderAi(
                      RuoloProviderAi.testuale,
                      verificaState: _verificaAssistente,
                      onVerifica: _verificaConnessioneAssistente,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(label: 'Provider fumetti'),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        const _Riga(titolo: 'Provider', valore: 'ComicVine'),
                        const _Divisore(),
                        _Riga(
                          titolo: 'API key',
                          valore: _apiKeyComics.isEmpty
                              ? 'Non impostata'
                              : '••••••••',
                          onTap: () async {
                            final v = await _apriSheetTestoLibero(
                              titolo: 'API key',
                              valoreIniziale: _apiKeyComics,
                              mascherato: true,
                            );
                            if (v == null) return;
                            await ref
                                .read(settingsRepositoryProvider)
                                .impostaApiKeyComics(v);
                            if (!mounted) return;
                            setState(() => _apiKeyComics = v);
                          },
                        ),
                        const _Divisore(),
                        _Riga(
                          titolo: 'Verifica connessione',
                          valore: switch ((
                            _verificaComicVine.loading,
                            _verificaComicVine.esito,
                          )) {
                            (true, _) => 'In corso…',
                            (false, null) => 'Non verificata',
                            (
                              false,
                              EsitoVerifica(:final ok, :final messaggio),
                            ) =>
                              ok ? 'OK' : messaggio,
                          },
                          valoreColore: switch ((
                            _verificaComicVine.loading,
                            _verificaComicVine.esito,
                          )) {
                            (true, _) => AppColors.textSecondary,
                            (false, null) => AppColors.textMuted,
                            (false, EsitoVerifica(:final ok)) =>
                              ok ? AppColors.accent : AppColors.amberStrong,
                          },
                          onTap: _verificaComicVine.loading
                              ? null
                              : _verificaConnessioneComicVine,
                          mostraChevron: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(label: 'Importa/Esporta dati'),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _Riga(
                          titolo: 'Esporta in CSV',
                          valore: _esportazioneInCorso ? 'In corso…' : '',
                          onTap: _esportazioneInCorso
                              ? null
                              : () => _esporta(FormatoEsportazione.csv),
                        ),
                        const _Divisore(),
                        _Riga(
                          titolo: 'Esporta in JSON',
                          valore: _esportazioneInCorso ? 'In corso…' : '',
                          onTap: _esportazioneInCorso
                              ? null
                              : () => _esporta(FormatoEsportazione.json),
                        ),
                        const _Divisore(),
                        _Riga(
                          titolo: 'Importa collezione',
                          valore: _importazioneInCorso ? 'In corso…' : '',
                          onTap: _importazioneInCorso ? null : _importa,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Card di un singolo provider AI: sempre espansa (§12, tutte e quattro
/// visibili insieme, deciso dopo #111 — vedi commento su [ImpostazioniPage])
/// con API key/modello/URL propri e il chip "Attivo" per selezionarlo come
/// provider usato a runtime.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.attivo,
    required this.apiKey,
    required this.modello,
    required this.urlLocale,
    required this.verifica,
    required this.onSelezionaAttivo,
    required this.onModificaApiKey,
    required this.onModificaModello,
    required this.onModificaUrl,
    required this.onVerifica,
  });

  final AiProvider provider;
  final bool attivo;
  final String apiKey;
  final String modello;
  final String urlLocale;
  final ({bool loading, EsitoVerifica? esito})? verifica;
  final VoidCallback onSelezionaAttivo;
  final VoidCallback onModificaApiKey;
  final VoidCallback onModificaModello;
  final VoidCallback onModificaUrl;
  final VoidCallback? onVerifica;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  provider.label,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AppChip(
                  label: 'Attivo',
                  selected: attivo,
                  onTap: attivo ? null : onSelezionaAttivo,
                ),
              ],
            ),
          ),
          const _Divisore(),
          _Riga(
            titolo: 'API key',
            valore: apiKey.isEmpty ? 'Non impostata' : '••••••••',
            onTap: onModificaApiKey,
          ),
          const _Divisore(),
          _Riga(
            titolo: 'Modello',
            valore: modello.isEmpty ? 'Non impostato' : modello,
            onTap: onModificaModello,
          ),
          if (provider.richiedeUrl) ...[
            const _Divisore(),
            _Riga(
              titolo: 'URL API',
              valore: urlLocale.isEmpty ? 'Non impostato' : urlLocale,
              onTap: onModificaUrl,
            ),
          ],
          if (verifica != null) ...[
            const _Divisore(),
            _Riga(
              titolo: 'Verifica connessione',
              valore: switch ((verifica!.loading, verifica!.esito)) {
                (true, _) => 'In corso…',
                (false, null) => 'Non verificata',
                (false, EsitoVerifica(:final ok, :final messaggio)) =>
                  ok ? 'OK' : messaggio,
              },
              valoreColore: switch ((verifica!.loading, verifica!.esito)) {
                (true, _) => AppColors.textSecondary,
                (false, null) => AppColors.textMuted,
                (false, EsitoVerifica(:final ok)) =>
                  ok ? AppColors.accent : AppColors.amberStrong,
              },
              onTap: onVerifica,
              mostraChevron: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetLista extends StatelessWidget {
  const _SheetLista({required this.titolo, required this.children});

  final String titolo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              titolo,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({
    required this.titolo,
    required this.valore,
    this.onTap,
    this.valoreColore,
    this.mostraChevron = true,
  });

  final String titolo;
  final String valore;
  final VoidCallback? onTap;
  final Color? valoreColore;
  final bool mostraChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Text(
              titolo,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                valore,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.bodyMedium.copyWith(
                  color: valoreColore ?? AppColors.textSecondary,
                ),
              ),
            ),
            if (onTap != null && mostraChevron) ...[
              const SizedBox(width: AppSpacing.xxs),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Divisore extends StatelessWidget {
  const _Divisore();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: AppColors.borderSubtle,
      indent: AppSpacing.md,
      endIndent: AppSpacing.md,
    );
  }
}
