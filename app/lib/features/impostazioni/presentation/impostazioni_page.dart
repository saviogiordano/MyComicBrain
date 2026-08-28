import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/impostazioni/application/ai_provider.dart';

/// Schermo Impostazioni (§12, deciso su #104): elenco di righe stile
/// impostazioni di sistema — il valore corrente in trailing, ogni riga apre
/// una bottom sheet per modificarla. Ogni modifica scrive subito nel
/// `SettingsRepository` (#105): nessun pulsante "Salva" a livello di
/// schermo, coerente col pattern "modifica singolo campo" del layout #104.
///
/// I provider AI sono mostrati tutti insieme, ciascuno con la propria card
/// sempre espansa (§12, richiesto dall'utente dopo #111: le config per
/// provider erano già salvate separatamente in `SettingsRepository` — API
/// key e modello sono mappe per `AiProvider`, non sovrascritte al cambio —
/// ma la UI ne mostrava una sola alla volta dietro una bottom sheet di
/// selezione, obbligando a riaprire il selettore per rivedere/modificare la
/// config di un provider non attivo). Il chip "Attivo" seleziona quale dei
/// quattro è il provider usato a runtime da `coverAnalysisClientProvider`.
class ImpostazioniPage extends ConsumerStatefulWidget {
  const ImpostazioniPage({super.key});

  @override
  ConsumerState<ImpostazioniPage> createState() => _ImpostazioniPageState();
}

class _ImpostazioniPageState extends ConsumerState<ImpostazioniPage> {
  bool _caricamento = true;
  AiProvider _providerAttivo = AiProvider.claude;
  final Map<AiProvider, String> _apiKeyAi = {};
  final Map<AiProvider, String> _modello = {};
  String _urlLocale = '';

  String _apiKeyComics = '';

  final Map<AiProvider, ({bool loading, EsitoVerifica? esito})> _verificaAi = {
    for (final p in AiProvider.values) p: (loading: false, esito: null),
  };

  ({bool loading, EsitoVerifica? esito}) _verificaComicVine = (
    loading: false,
    esito: null,
  );

  @override
  void initState() {
    super.initState();
    _caricaImpostazioni();
  }

  /// Precarica lo stato dal `SettingsRepository` (#105): il provider AI
  /// attivo e i modelli sono sincroni (`shared_preferences`), le API key
  /// passano da `flutter_secure_storage` e vanno attese — una per provider,
  /// in parallelo. Default a Claude quando l'utente non ha ancora scelto un
  /// provider — stesso default di `coverAnalysisClientProvider`
  /// (`core/data/providers.dart`).
  Future<void> _caricaImpostazioni() async {
    final repo = ref.read(settingsRepositoryProvider);
    final provider =
        repo.providerAi(RuoloProviderAi.visivo) ?? AiProvider.claude;
    final apiKeys = await Future.wait([
      for (final p in AiProvider.values)
        repo.apiKeyAi(RuoloProviderAi.visivo, p),
    ]);
    final apiKeyComics = await repo.apiKeyComics;
    if (!mounted) return;
    setState(() {
      _providerAttivo = provider;
      for (final (i, p) in AiProvider.values.indexed) {
        _apiKeyAi[p] = apiKeys[i] ?? '';
        _modello[p] =
            repo.modello(RuoloProviderAi.visivo, p) ??
            p.modelloDefault(RuoloProviderAi.visivo);
      }
      _urlLocale = repo.urlLocale(RuoloProviderAi.visivo) ?? '';
      _apiKeyComics = apiKeyComics ?? '';
      _caricamento = false;
    });
  }

  Future<void> _selezionaProviderAttivo(AiProvider provider) async {
    if (provider == _providerAttivo) return;
    await ref
        .read(settingsRepositoryProvider)
        .impostaProviderAi(RuoloProviderAi.visivo, provider);
    if (!mounted) return;
    setState(() => _providerAttivo = provider);
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

  Future<void> _apriSheetModello(AiProvider provider) async {
    final attuale =
        _modello[provider] ?? provider.modelloDefault(RuoloProviderAi.visivo);
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
      if (scelto != null) await _salvaModello(provider, scelto);
      return;
    }
    final testo = await _apriSheetTestoLibero(
      titolo: 'Modello',
      valoreIniziale: attuale,
      hint: provider == AiProvider.locale ? 'es. llama3' : null,
    );
    if (testo != null) await _salvaModello(provider, testo);
  }

  Future<void> _salvaModello(AiProvider provider, String modello) async {
    await ref
        .read(settingsRepositoryProvider)
        .impostaModello(RuoloProviderAi.visivo, provider, modello);
    if (!mounted) return;
    setState(() => _modello[provider] = modello);
  }

  Future<void> _modificaApiKeyAi(AiProvider provider) async {
    final v = await _apriSheetTestoLibero(
      titolo: 'API key',
      valoreIniziale: _apiKeyAi[provider] ?? '',
      mascherato: true,
    );
    if (v == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .impostaApiKeyAi(RuoloProviderAi.visivo, provider, v);
    if (!mounted) return;
    setState(() => _apiKeyAi[provider] = v);
  }

  Future<void> _modificaUrlLocale() async {
    final v = await _apriSheetTestoLibero(
      titolo: 'URL API',
      valoreIniziale: _urlLocale,
      hint: 'http://localhost:11434/v1',
      validatore: (testo) {
        if (testo.trim().isEmpty) return null;
        return urlLocaleValido(testo)
            ? null
            : 'URL non valido: usa un endpoint http/https completo.';
      },
    );
    if (v == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .impostaUrlLocale(RuoloProviderAi.visivo, v);
    if (!mounted) return;
    setState(() => _urlLocale = v);
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
                  const SectionHeader(label: 'Provider AI'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final provider in AiProvider.values) ...[
                    _ProviderCard(
                      provider: provider,
                      attivo: provider == _providerAttivo,
                      apiKey: _apiKeyAi[provider] ?? '',
                      modello:
                          _modello[provider] ??
                          provider.modelloDefault(RuoloProviderAi.visivo),
                      urlLocale: _urlLocale,
                      verifica: _verificaAi[provider]!,
                      onSelezionaAttivo: () =>
                          _selezionaProviderAttivo(provider),
                      onModificaApiKey: () => _modificaApiKeyAi(provider),
                      onModificaModello: () => _apriSheetModello(provider),
                      onModificaUrl: _modificaUrlLocale,
                      onVerifica: _verificaAi[provider]!.loading
                          ? null
                          : () => _verificaConnessioneAi(provider),
                    ),
                    if (provider != AiProvider.values.last)
                      const SizedBox(height: AppSpacing.sm),
                  ],
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
  final ({bool loading, EsitoVerifica? esito}) verifica;
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
          const _Divisore(),
          _Riga(
            titolo: 'Verifica connessione',
            valore: switch ((verifica.loading, verifica.esito)) {
              (true, _) => 'In corso…',
              (false, null) => 'Non verificata',
              (false, EsitoVerifica(:final ok, :final messaggio)) =>
                ok ? 'OK' : messaggio,
            },
            valoreColore: switch ((verifica.loading, verifica.esito)) {
              (true, _) => AppColors.textSecondary,
              (false, null) => AppColors.textMuted,
              (false, EsitoVerifica(:final ok)) =>
                ok ? AppColors.accent : AppColors.amberStrong,
            },
            onTap: onVerifica,
            mostraChevron: false,
          ),
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
