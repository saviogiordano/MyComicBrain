import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/data/preferences.dart';

/// Avanzamento del Tutorial di inserimento su questo dispositivo (deciso su
/// #241, PRD #242). La chiave assente esiste solo prima di
/// [TutorialInserimentoController.allAvvio].
enum FaseTutorialInserimento {
  /// Il primo momento parte al prossimo ingresso nella Dashboard.
  daMostrare,

  /// Primo momento finito: il secondo aspetta la prima Scansione vera,
  /// senza scadenza.
  inAttesaPrimaScansione,

  visto,
}

class StatoTutorialInserimento {
  const StatoTutorialInserimento({
    required this.fase,
    required this.tappaRiepilogoMostrata,
  });

  final FaseTutorialInserimento fase;
  final bool tappaRiepilogoMostrata;

  bool get mostraPrimoMomento => fase == FaseTutorialInserimento.daMostrare;

  bool get mostraTappaRiepilogo =>
      fase == FaseTutorialInserimento.inAttesaPrimaScansione &&
      !tappaRiepilogoMostrata;

  /// La tappa "Possibile corrispondenza" chiude il tutorial: non aspetta
  /// quella sul Riepilogo, che altrimenti si lascia cadere.
  bool get mostraTappaCorrispondenza =>
      fase == FaseTutorialInserimento.inAttesaPrimaScansione;
}

// Chiavi di dispositivo, come quelle dell'account (ADR-0005): logout ed
// eliminazione dell'account non le azzerano.
const _chiaveFase = 'tutorial.inserimento.fase';
const _chiaveTappaRiepilogo = 'tutorial.inserimento.tappaRiepilogoMostrata';

/// Ogni tappa diventa "vista" appena compare, non quando finisce: saltata o
/// interrotta (app chiusa a metà) conta come vista.
class TutorialInserimentoController extends Notifier<StatoTutorialInserimento> {
  Preferences get _preferences => ref.read(accountPreferencesProvider);

  /// Regola per gli utenti esistenti (#238), da eseguire all'avvio prima
  /// che l'utente possa superare il benvenuto: se `benvenutoSuperato` è già
  /// `true` il dispositivo era in uso e il tutorial non parte. Guarda solo
  /// la chiave assente, quindi gira una volta sola: la riapertura da
  /// Impostazioni scrive "da mostrare" e non la riattiva.
  static Future<void> allAvvio(Preferences preferences) async {
    if (preferences.getString(_chiaveFase) != null) return;
    final giaInUso = benvenutoGiaSuperato(preferences);
    await preferences.setString(
      _chiaveFase,
      (giaInUso
              ? FaseTutorialInserimento.visto
              : FaseTutorialInserimento.daMostrare)
          .name,
    );
  }

  @override
  StatoTutorialInserimento build() {
    final preferences = ref.watch(accountPreferencesProvider);
    // Chiave assente solo se [allAvvio] non è girato (test): nessun
    // tutorial non richiesto.
    final fase =
        FaseTutorialInserimento.values.asNameMap()[preferences.getString(
          _chiaveFase,
        )] ??
        FaseTutorialInserimento.visto;
    return StatoTutorialInserimento(
      fase: fase,
      tappaRiepilogoMostrata:
          preferences.getString(_chiaveTappaRiepilogo) == 'true',
    );
  }

  Future<void> avviaPrimoMomento() =>
      _impostaFase(FaseTutorialInserimento.visto);

  /// Ultimo "Avanti" del primo momento: arma il secondo.
  Future<void> completaPrimoMomento() =>
      _impostaFase(FaseTutorialInserimento.inAttesaPrimaScansione);

  Future<void> avviaTappaRiepilogo() async {
    state = StatoTutorialInserimento(
      fase: state.fase,
      tappaRiepilogoMostrata: true,
    );
    await _preferences.setString(_chiaveTappaRiepilogo, 'true');
  }

  Future<void> avviaTappaCorrispondenza() =>
      _impostaFase(FaseTutorialInserimento.visto);

  /// "Salta" in qualunque punto chiude tutto il tutorial.
  Future<void> salta() => _impostaFase(FaseTutorialInserimento.visto);

  /// Impostazioni → Aiuto → "Come aggiungere un fumetto": riarma entrambi
  /// i momenti.
  Future<void> riapri() async {
    state = const StatoTutorialInserimento(
      fase: FaseTutorialInserimento.daMostrare,
      tappaRiepilogoMostrata: false,
    );
    await _preferences.setString(
      _chiaveFase,
      FaseTutorialInserimento.daMostrare.name,
    );
    await _preferences.setString(_chiaveTappaRiepilogo, 'false');
  }

  Future<void> _impostaFase(FaseTutorialInserimento fase) async {
    state = StatoTutorialInserimento(
      fase: fase,
      tappaRiepilogoMostrata: state.tappaRiepilogoMostrata,
    );
    await _preferences.setString(_chiaveFase, fase.name);
  }
}

final tutorialInserimentoProvider =
    NotifierProvider<TutorialInserimentoController, StatoTutorialInserimento>(
      TutorialInserimentoController.new,
    );
