import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_persistence.dart';

final collezioneEdizioniProvider = StreamProvider<List<EdizioneCollezione>>((
  ref,
) {
  return ref.watch(comicsRepositoryProvider).watchCollezione();
});

final filtriCollezionePersistenceProvider =
    Provider<FiltriCollezionePersistence>((ref) {
      return FiltriCollezionePersistence(ref.watch(sharedPreferencesProvider));
    });

/// Il toggle "ricorda filtri e ordinamento" (§9, deciso su #85) — persistito
/// a sé, indipendentemente dal fatto che sia acceso o spento: è la
/// preferenza stessa (non lo stato dei filtri) a dover sopravvivere sempre
/// al riavvio.
class RicordaFiltriNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(filtriCollezionePersistenceProvider).leggiRicorda();

  Future<void> imposta({required bool valore}) async {
    state = valore;
    await ref
        .read(filtriCollezionePersistenceProvider)
        .scriviRicorda(valore: valore);
  }
}

final ricordaFiltriProvider = NotifierProvider<RicordaFiltriNotifier, bool>(
  RicordaFiltriNotifier.new,
);

/// Filtri + ordinamento della Collezione (§9) — idratati dalla persistenza
/// solo se [ricordaFiltriProvider] è attivo (deciso su #85: se l'utente lo
/// disattiva, filtri e ordinamento ripartono vuoti al riavvio successivo).
class FiltriCollezioneNotifier extends Notifier<FiltriCollezioneState> {
  @override
  FiltriCollezioneState build() {
    if (!ref.watch(ricordaFiltriProvider)) return const FiltriCollezioneState();
    return ref.watch(filtriCollezionePersistenceProvider).leggiStato() ??
        const FiltriCollezioneState();
  }

  void toggleValore(AsseCollezione asse, String valore) =>
      _aggiorna(state.toggleValore(asse, valore));

  void azzeraAsse(AsseCollezione asse) => _aggiorna(state.azzeraAsse(asse));

  void azzeraTutti() => _aggiorna(state.azzeraTutti());

  void impostaOrdinamento(OrdinamentoCollezione ordinamento) =>
      _aggiorna(state.conOrdinamento(ordinamento));

  void _aggiorna(FiltriCollezioneState nuovoStato) {
    state = nuovoStato;
    if (ref.read(ricordaFiltriProvider)) {
      unawaited(
        ref.read(filtriCollezionePersistenceProvider).scriviStato(nuovoStato),
      );
    }
  }
}

final filtriCollezioneProvider =
    NotifierProvider<FiltriCollezioneNotifier, FiltriCollezioneState>(
      FiltriCollezioneNotifier.new,
    );

/// Le Edizioni visibili nella griglia — filtro (AND fra assi, OR nello
/// stesso asse) + ordinamento applicati al catalogo posseduto.
final Provider<AsyncValue<List<EdizioneCollezione>>> edizioniVisibiliProvider =
    Provider<AsyncValue<List<EdizioneCollezione>>>((ref) {
      final stato = ref.watch(filtriCollezioneProvider);
      return ref
          .watch(collezioneEdizioniProvider)
          .whenData((edizioni) => edizioniVisibili(edizioni, stato));
    });

/// I valori davvero presenti in collezione per un asse (§9, deciso su #85)
/// — usati dal pannello Filtri per proporre solo opzioni realmente
/// selezionabili, mai l'intero enum/range.
final ProviderFamily<List<String>, AsseCollezione> valoriAsseProvider =
    Provider.family<List<String>, AsseCollezione>((ref, asse) {
      final edizioni =
          ref.watch(collezioneEdizioniProvider).valueOrNull ?? const [];
      return valoriAsseInCollezione(edizioni, asse);
    });
