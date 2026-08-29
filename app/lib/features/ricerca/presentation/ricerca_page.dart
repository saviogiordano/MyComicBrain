import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/speech_to_text_service.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';

/// I 5 esempi di richiesta documentati in `docs/requisiti.md` §10, mostrati
/// come chip nello stato vuoto.
const _esempiRichiesta = [
  'Batman numeri 1-50 che mi mancano',
  'Quali numeri di Dylan Dog mi mancano?',
  'Quanti fumetti Marvel ho?',
  'Quali sono le serie quasi complete?',
  'Trova i duplicati.',
];

const _testoBloccato =
    "Configura il Provider AI Testuale per usare l'Assistente.";

/// Copy del Messaggio di sistema per il fallback STT Android — verbatim da
/// `docs/requisiti.md` §24 (deciso su #124, implementato su #138):
/// informativo, non un errore, la trascrizione è comunque riuscita, solo
/// non è rimasta sul device.
const _testoFallbackStt =
    'Ho usato il riconoscimento vocale in rete perché quello offline non è '
    'disponibile sul tuo dispositivo.';

/// Schermo Cerca (§10, chat dell'Assistente) — variante A del prototipo
/// (bubble chat classica, deciso su
/// [Design della schermata Cerca](https://github.com/saviogiordano/MyComicBrain/issues/125)):
/// bubble utente/assistente, blocco Edizioni annidato nella bubble
/// dell'assistente, stato vuoto con chip di esempio, indicatore "sta
/// scrivendo", bubble di sistema per errori/avvisi (§24, #124) e banner
/// bloccante quando il Provider AI Testuale non è configurato (§10, #123).
/// Fonde in sé il vecchio `AssistentePage` (#118) — nessuna logica di
/// tool-calling qui, solo presentazione di ciò che
/// `AssistenteOrchestrator` (#132) ha già persistito su
/// Conversazione/Messaggio.
///
/// Il microfono avvia una sessione [SpeechToTextService] (§10, #138): STT
/// on-device → testo, mai audio verso il Provider AI Testuale. Un fallback
/// Android al riconoscimento di rete (sotto API 31 o senza modello
/// scaricato) aggiunge prima un Messaggio di sistema informativo
/// (`SottotipoSistema.infoSttFallback`, §24/#124), poi invia il transcript
/// come Messaggio utente.
class RicercaPage extends ConsumerWidget {
  const RicercaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuratoAsync = ref.watch(assistenteConfiguratoProvider);
    final conversazioneIdAsync = ref.watch(conversazioneIdProvider);

    // Il primo caricamento (config + id Conversazione) è quasi istantaneo
    // (preferenze locali + una query SQLite) — uno spinner a schermo intero
    // qui non è un problema di percezione, a differenza di un flash del
    // banner bloccante seguito subito dallo sblocco.
    if (!configuratoAsync.hasValue || !conversazioneIdAsync.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _Cerca(
      configurato: configuratoAsync.requireValue,
      conversazioneId: conversazioneIdAsync.requireValue,
    );
  }
}

class _Cerca extends ConsumerStatefulWidget {
  const _Cerca({required this.configurato, required this.conversazioneId});

  final bool configurato;
  final int conversazioneId;

  @override
  ConsumerState<_Cerca> createState() => _CercaState();
}

class _CercaState extends ConsumerState<_Cerca> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _inviando = false;
  bool _ascoltando = false;
  int _ultimaLunghezzaMessaggi = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Svuota la chat (§10) cancellando l'intera Conversazione — mai singoli
  /// Messaggi, stesso vincolo di `ComicsRepository.eliminaConversazione`
  /// (#122/#128) — e invalidando [conversazioneIdProvider] così che
  /// `getOrCreaConversazione` ne semini una nuova, vuota, al prossimo
  /// accesso (stesso pattern di singleton applicativo).
  Future<void> _svuotaChat() async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Svuotare la chat?'),
        content: const Text(
          'Tutti i messaggi di questa conversazione verranno eliminati. '
          'Non è garantito poterlo annullare.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (conferma != true || !mounted) return;

    await ref
        .read(comicsRepositoryProvider)
        .eliminaConversazione(widget.conversazioneId);
    if (mounted) ref.invalidate(conversazioneIdProvider);
  }

  Future<void> _invia(String testo) async {
    final testoPulito = testo.trim();
    if (testoPulito.isEmpty || !widget.configurato || _inviando) return;
    _controller.clear();
    setState(() => _inviando = true);
    _scrollAFondo();
    try {
      await ref
          .read(assistenteOrchestratorProvider)
          .inviaMessaggio(testoPulito);
    } finally {
      if (mounted) setState(() => _inviando = false);
    }
  }

  /// Avvia/interrompe una sessione di ascolto sul microfono incorporato
  /// (§10, #138). Un fallback di rete su Android (sotto API 31 o senza
  /// modello scaricato, §4.2 della ricerca #120) persiste prima il
  /// Messaggio di sistema informativo, poi invia il transcript come
  /// Messaggio utente tramite [_invia] — stesso ordine descritto sul ticket.
  Future<void> _toggleMicrofono() async {
    final servizio = ref.read(speechToTextServiceProvider);
    if (_ascoltando) {
      await servizio.annulla();
      if (mounted) setState(() => _ascoltando = false);
      return;
    }

    setState(() => _ascoltando = true);
    final risultato = await servizio.ascolta(
      onParziale: (parziale) => _controller
        ..text = parziale
        ..selection = TextSelection.collapsed(offset: parziale.length),
    );
    if (mounted) setState(() => _ascoltando = false);

    final testo = risultato.testo?.trim();
    if (testo == null || testo.isEmpty) return;

    if (risultato.fallbackRete) {
      final conversazioneId = await ref.read(conversazioneIdProvider.future);
      await ref
          .read(comicsRepositoryProvider)
          .aggiungiMessaggio(
            conversazioneId: conversazioneId,
            ruolo: RuoloMessaggio.sistema,
            testo: _testoFallbackStt,
            sottotipoSistema: SottotipoSistema.infoSttFallback,
          );
    }
    await _invia(testo);
  }

  void _scrollAFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messaggiAsync = ref.watch(messaggiProvider(widget.conversazioneId));
    final messaggi = messaggiAsync.valueOrNull ?? const <Messaggio>[];

    if (messaggi.length != _ultimaLunghezzaMessaggi) {
      _ultimaLunghezzaMessaggi = messaggi.length;
      _scrollAFondo();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onSvuota: messaggi.isEmpty ? null : _svuotaChat,
            ),
            Expanded(
              child: messaggi.isEmpty && !_inviando
                  ? _StatoVuoto(
                      abilitato: widget.configurato,
                      onEsempio: _invia,
                    )
                  : _Thread(
                      messaggi: messaggi,
                      inviando: _inviando,
                      scrollController: _scrollController,
                    ),
            ),
            if (!widget.configurato) const _BannerBloccato(),
            _InputBar(
              controller: _controller,
              abilitato: widget.configurato && !_inviando && !_ascoltando,
              microfonoAbilitato: widget.configurato && !_inviando,
              ascoltando: _ascoltando,
              onInvia: _invia,
              onMicrofono: _toggleMicrofono,
            ),
          ],
        ),
      ),
    );
  }
}

/// [onSvuota] `null` disabilita/nasconde il pulsante "Svuota chat" — nessuna
/// Conversazione con Messaggi da cancellare (stato vuoto, §10).
class _Header extends StatelessWidget {
  const _Header({required this.onSvuota});

  final VoidCallback? onSvuota;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cerca',
                  style: AppTypography.headline.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Risponde solo con i dati della tua collezione.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onSvuota != null)
            IconButton(
              onPressed: onSvuota,
              tooltip: 'Svuota chat',
              icon: Icon(Icons.delete_outline, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _StatoVuoto extends StatelessWidget {
  const _StatoVuoto({required this.abilitato, required this.onEsempio});

  final bool abilitato;
  final ValueChanged<String> onEsempio;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentAlpha(0.12),
                borderRadius: AppRadii.lgRadius,
                border: Border.all(color: AppColors.accentAlpha(0.3)),
              ),
              child: const Icon(Icons.search, color: AppColors.accent),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Chiedi qualcosa sulla tua collezione, a voce o scrivendo.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final esempio in _esempiRichiesta)
                  AppChip(
                    label: esempio,
                    selected: false,
                    onTap: abilitato ? () => onEsempio(esempio) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  const _Thread({
    required this.messaggi,
    required this.inviando,
    required this.scrollController,
  });

  final List<Messaggio> messaggi;
  final bool inviando;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final conteggio = messaggi.length + (inviando ? 1 : 0);

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      itemCount: conteggio,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == messaggi.length) return const _BubbleCaricamento();
        return _Bubble(messaggio: messaggi[index]);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.messaggio});

  final Messaggio messaggio;

  @override
  Widget build(BuildContext context) {
    return switch (messaggio.ruolo) {
      RuoloMessaggio.utente => _BubbleUtente(testo: messaggio.testo),
      RuoloMessaggio.assistente => _BubbleAssistente(messaggio: messaggio),
      RuoloMessaggio.sistema => _BubbleSistema(messaggio: messaggio),
    };
  }
}

class _BubbleUtente extends StatelessWidget {
  const _BubbleUtente({required this.testo});

  final String testo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 1,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.accentAlpha(0.14),
          border: Border.all(color: AppColors.accentAlpha(0.3)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.lg),
            topRight: Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(AppRadii.lg),
            bottomRight: Radius.circular(3),
          ),
        ),
        child: Text(
          testo,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _BubbleAssistente extends StatelessWidget {
  const _BubbleAssistente({required this.messaggio});

  final Messaggio messaggio;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.overlayCard,
          border: Border.all(color: AppColors.borderDefault),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.lg),
            topRight: Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(AppRadii.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              messaggio.testo,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            if (messaggio.edizioni.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _EdizioniAttachment(edizioni: messaggio.edizioni),
            ],
          ],
        ),
      ),
    );
  }
}

class _EdizioniAttachment extends StatelessWidget {
  const _EdizioniAttachment({required this.edizioni});

  final List<EdizioneCollezioneIndice> edizioni;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.overlayCardHover,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: AppRadii.mdRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, edizione) in edizioni.indexed) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.borderSubtle),
            _RigaEdizione(edizione: edizione),
          ],
        ],
      ),
    );
  }
}

class _RigaEdizione extends StatelessWidget {
  const _RigaEdizione({required this.edizione});

  final EdizioneCollezioneIndice edizione;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (edizione.serieName != null) edizione.serieName!,
      if (edizione.publisher != null) edizione.publisher!,
      if (edizione.year != null) '${edizione.year}',
    ].join(' · ');

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => context.push('/scheda/${edizione.edizioneId}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 46,
                child: ComicCoverImage(
                  coverImage: null,
                  titolo: edizione.titolo,
                  numero: edizione.issueNumber ?? 0,
                  etichetta: edizione.issueNumberLabel ?? '',
                  compatto: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: edizione.titolo,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        children: [
                          if ((edizione.issueNumberLabel ?? '').isNotEmpty)
                            TextSpan(
                              text: ' ${edizione.issueNumberLabel}',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.monoLabel.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bubble centrata neutra/ambra per i Messaggi di sistema (§24, #124): un
/// avviso informativo (fallback STT) resta neutro, un errore (rete/provider)
/// è ambrato — la CTA "Vai a Impostazioni" compare solo per
/// [SottotipoSistema.erroreProvider], l'unico caso in cui c'è qualcosa da
/// configurare.
class _BubbleSistema extends StatelessWidget {
  const _BubbleSistema({required this.messaggio});

  final Messaggio messaggio;

  @override
  Widget build(BuildContext context) {
    final sottotipo = messaggio.sottotipoSistema;
    final isAvviso = sottotipo != SottotipoSistema.infoSttFallback;
    final colore = isAvviso ? AppColors.amber : AppColors.textSecondary;

    return Align(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 1,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: isAvviso ? AppColors.amberAlpha(0.08) : AppColors.overlayCard,
          border: Border.all(
            color: isAvviso
                ? AppColors.amberStrong.withValues(alpha: 0.4)
                : AppColors.borderDefault,
          ),
          borderRadius: AppRadii.mdRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isAvviso ? Icons.error_outline : Icons.info_outline,
                  size: 15,
                  color: colore,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    messaggio.testo,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (sottotipo == SottotipoSistema.erroreProvider) ...[
              const SizedBox(height: AppSpacing.xs),
              GestureDetector(
                onTap: () => context.go('/impostazioni'),
                child: Text(
                  'Vai a Impostazioni',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.amber,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BubbleCaricamento extends StatefulWidget {
  const _BubbleCaricamento();

  @override
  State<_BubbleCaricamento> createState() => _BubbleCaricamentoState();
}

class _BubbleCaricamentoState extends State<_BubbleCaricamento>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacitaPunto(double t, int indice) {
    final fase = (t - indice * 0.15) % 1.0;
    if (fase < 0.4) return 0.25 + 0.75 * (fase / 0.4);
    return 1 - 0.75 * ((fase - 0.4) / 0.6).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 1,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.overlayCard,
          border: Border.all(color: AppColors.borderDefault),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.lg),
            topRight: Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(AppRadii.lg),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Opacity(
                    opacity: _opacitaPunto(_controller.value, i),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BannerBloccato extends StatelessWidget {
  const _BannerBloccato();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 1,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.amberAlpha(0.08),
          border: Border.all(
            color: AppColors.amberStrong.withValues(alpha: 0.4),
          ),
          borderRadius: AppRadii.mdRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppColors.amber,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _testoBloccato,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            GestureDetector(
              onTap: () => context.go('/impostazioni'),
              child: Text(
                'Vai a Impostazioni',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.amber,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.abilitato,
    required this.microfonoAbilitato,
    required this.ascoltando,
    required this.onInvia,
    required this.onMicrofono,
  });

  final TextEditingController controller;
  final bool abilitato;
  final bool microfonoAbilitato;
  final bool ascoltando;
  final ValueChanged<String> onInvia;
  final VoidCallback onMicrofono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: abilitato ? AppColors.overlayCardHover : AppColors.overlayCard,
          borderRadius: AppRadii.pillRadius,
          border: Border.all(
            color: abilitato
                ? AppColors.accentAlpha(0.4)
                : AppColors.borderDefault,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: abilitato,
                onSubmitted: onInvia,
                textInputAction: TextInputAction.send,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: ascoltando
                      ? 'Ascolto…'
                      : abilitato
                      ? 'Scrivi o chiedi qualcosa…'
                      : 'Configura il Provider per continuare',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textDisabled,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _PulsanteMicrofono(
              abilitato: microfonoAbilitato,
              ascoltando: ascoltando,
              onTap: onMicrofono,
            ),
          ],
        ),
      ),
    );
  }
}

/// Il microfono incorporato nel campo di input (§125): lucchetto quando
/// bloccato (#123), altrimenti avvia/interrompe una sessione
/// [SpeechToTextService] (§10, #138) al tocco.
class _PulsanteMicrofono extends StatelessWidget {
  const _PulsanteMicrofono({
    required this.abilitato,
    required this.ascoltando,
    required this.onTap,
  });

  final bool abilitato;
  final bool ascoltando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: abilitato ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !abilitato
              ? Colors.transparent
              : ascoltando
              ? AppColors.amberStrong
              : AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          !abilitato
              ? Icons.lock_outline
              : ascoltando
              ? Icons.mic
              : Icons.mic_none,
          size: 17,
          color: abilitato ? AppColors.onAccent : AppColors.textDisabled,
        ),
      ),
    );
  }
}
