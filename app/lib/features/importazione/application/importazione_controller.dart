import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/data/supabase/importazione_modalita_locale.dart';
import 'package:mycomicbrain/core/data/supabase/uuid_v4.dart';

/// L'importazione della Modalità locale per il Profilo autenticato (ADR-0005,
/// #173), sostituita da `main.dart` con [ImportazioneModalitaLocale] legata
/// all'utente della sessione.
final importatoreModalitaLocaleProvider = Provider<ImportatoreModalitaLocale>(
  (ref) => throw UnimplementedError(
    'importatoreModalitaLocaleProvider non sostituito',
  ),
);

/// L'id dell'importazione accettata e non ancora finita: persistito sul
/// device, così un nuovo tentativo — anche dopo un riavvio o "Esci e
/// riprova più tardi" — riusa lo stesso id e la RPC non duplica nulla.
const _chiaveImportazioneInCorso = 'account.importazioneInCorso';

sealed class StatoImportazione {
  const StatoImportazione();
}

class RiepilogoInCaricamento extends StatoImportazione {
  const RiepilogoInCaricamento();
}

/// Il prompt: "Abbiamo trovato N fumetti…", oppure la ripresa di
/// un'importazione interrotta ("L'importazione non è finita…").
class PromptImportazione extends StatoImportazione {
  const PromptImportazione(this.riepilogo, {required this.ripresa});

  final RiepilogoModalitaLocale riepilogo;
  final bool ripresa;
}

class ImportazioneInCorso extends StatoImportazione {
  const ImportazioneInCorso(this.avanzamento);

  final AvanzamentoImportazione? avanzamento;
}

/// Importazione (o lettura del riepilogo) fallita: drift è intatto.
class ImportazioneFallita extends StatoImportazione {
  const ImportazioneFallita({this.avanzamento, this.riepilogo});

  /// Fin dove era arrivata, per la barra; `null` se non era partita.
  final AvanzamentoImportazione? avanzamento;

  /// `null` se è fallita la lettura del riepilogo: "Riprova" lo rilegge
  /// invece di importare.
  final RiepilogoModalitaLocale? riepilogo;
}

class ImportazioneCompletata extends StatoImportazione {
  const ImportazioneCompletata(this.esito);

  final EsitoImportazione esito;
}

/// Il flusso del prompt di importazione (variante A del prototipo #170):
/// prompt → avanzamento → fatto, con errore/Riprova, rifiuto ed "Esci e
/// riprova più tardi". La Modalità locale si esaurisce solo quando
/// l'importazione riesce ("Vai alla collezione") o viene rifiutata.
class ImportazioneController extends AutoDisposeNotifier<StatoImportazione> {
  ImportatoreModalitaLocale get _importatore =>
      ref.read(importatoreModalitaLocaleProvider);

  @override
  StatoImportazione build() {
    unawaited(Future.microtask(_caricaRiepilogo));
    return const RiepilogoInCaricamento();
  }

  String? get _idInCorso {
    final id = ref
        .read(accountPreferencesProvider)
        .getString(_chiaveImportazioneInCorso);
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _caricaRiepilogo() async {
    state = const RiepilogoInCaricamento();
    try {
      final riepilogo = await _importatore.riepilogo();
      state = PromptImportazione(riepilogo, ripresa: _idInCorso != null);
    } on Exception {
      state = const ImportazioneFallita();
    }
  }

  Future<void> importa() async {
    final riepilogo = switch (state) {
      PromptImportazione(:final riepilogo) => riepilogo,
      ImportazioneFallita(:final riepilogo?) => riepilogo,
      _ => null,
    };
    if (riepilogo == null) return;
    var importId = _idInCorso;
    if (importId == null) {
      importId = uuidV4();
      await ref
          .read(accountPreferencesProvider)
          .setString(_chiaveImportazioneInCorso, importId);
    }
    state = const ImportazioneInCorso(null);
    AvanzamentoImportazione? ultimo;
    try {
      final esito = await _importatore.importa(
        importId,
        avanzamento: (avanzamento) {
          ultimo = avanzamento;
          state = ImportazioneInCorso(avanzamento);
        },
      );
      state = ImportazioneCompletata(esito);
    } on Exception {
      state = ImportazioneFallita(avanzamento: ultimo, riepilogo: riepilogo);
    }
  }

  Future<void> riprova() async {
    if (state case ImportazioneFallita(riepilogo: null)) {
      return _caricaRiepilogo();
    }
    return importa();
  }

  /// "Vai alla collezione".
  Future<void> continua() => _esaurisci();

  /// Rifiuto confermato due volte: i dati locali si scartano senza
  /// importarli.
  Future<void> rifiuta() async {
    await _importatore.scartaDatiLocali();
    await _esaurisci();
  }

  /// Logout con drift intatto: si torna alla Modalità locale e al prossimo
  /// accesso il prompt riprende con lo stesso id.
  Future<void> esciERiprovaPiuTardi() =>
      ref.read(sessionControllerProvider.notifier).esci();

  Future<void> _esaurisci() async {
    await ref
        .read(accountPreferencesProvider)
        .setString(_chiaveImportazioneInCorso, '');
    await ref
        .read(sessionControllerProvider.notifier)
        .esaurisciModalitaLocale();
  }
}

final AutoDisposeNotifierProvider<ImportazioneController, StatoImportazione>
importazioneControllerProvider =
    NotifierProvider.autoDispose<ImportazioneController, StatoImportazione>(
      ImportazioneController.new,
    );
