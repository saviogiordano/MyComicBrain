import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_persistence.dart';

/// L'indice leggero della Collezione (§9, deciso su #112/#113): tutto il
/// catalogo posseduto con i 12 assi di filtro/ordinamento già risolti, mai
/// la cover — quella è la finestra hydratata, vedi
/// [edizioniFinestraCollezioneProvider].
final indiceCollezioneProvider = StreamProvider<List<EdizioneCollezioneIndice>>((
  ref,
) {
  return ref.watch(comicsRepositoryProvider).watchIndiceCollezione();
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

/// Il pre-filtro d'ingresso "aggiunti nel mese corrente" dalla Dashboard
/// (§9, deciso su #91) — a sé rispetto ai 12 assi del pannello Filtri,
/// promosso da stato locale del widget a provider (deciso su #115) perché
/// la finestra dello scroll infinito deve dimensionarsi sull'insieme finale
/// **dopo** questo pre-filtro, non solo dopo `filtriCollezioneProvider`.
class SoloAggiuntiMeseCorrenteNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void imposta({required bool valore}) => state = valore;
}

final soloAggiuntiMeseCorrenteProvider =
    NotifierProvider<SoloAggiuntiMeseCorrenteNotifier, bool>(
      SoloAggiuntiMeseCorrenteNotifier.new,
    );

bool _aggiuntaMeseCorrente(EdizioneCollezioneIndice edizione, DateTime ora) {
  final inizioMese = DateTime(ora.year, ora.month);
  final inizioMeseProssimo = DateTime(ora.year, ora.month + 1);
  return edizione.copiePossedute.any(
    (c) =>
        !c.createdAt.isBefore(inizioMese) &&
        c.createdAt.isBefore(inizioMeseProssimo),
  );
}

/// Le Edizioni visibili nella griglia — filtro (AND fra assi, OR nello
/// stesso asse) + ordinamento + pre-filtro "aggiunti nel mese corrente"
/// applicati all'indice leggero del catalogo posseduto. Base sia del
/// conteggio "X di Y fumetti" sia della finestra caricata (deciso su
/// #115): entrambi devono vedere lo stesso insieme finale.
final Provider<AsyncValue<List<EdizioneCollezioneIndice>>>
edizioniVisibiliProvider = Provider<AsyncValue<List<EdizioneCollezioneIndice>>>((
  ref,
) {
  final stato = ref.watch(filtriCollezioneProvider);
  final soloMeseCorrente = ref.watch(soloAggiuntiMeseCorrenteProvider);
  return ref.watch(indiceCollezioneProvider).whenData((edizioni) {
    var visibili = edizioniVisibili(edizioni, stato);
    if (soloMeseCorrente) {
      final ora = DateTime.now();
      visibili = visibili
          .where((edizione) => _aggiuntaMeseCorrente(edizione, ora))
          .toList();
    }
    return visibili;
  });
});

/// I valori davvero presenti in collezione per un asse (§9, deciso su #85)
/// — usati dal pannello Filtri per proporre solo opzioni realmente
/// selezionabili, mai l'intero enum/range. Sempre sull'intero catalogo
/// posseduto (indice), mai sulla sola finestra caricata né sui risultati
/// già filtrati — altrimenti le opzioni sparirebbero via via che si filtra.
final ProviderFamily<List<String>, AsseCollezione> valoriAsseProvider =
    Provider.family<List<String>, AsseCollezione>((ref, asse) {
      final edizioni =
          ref.watch(indiceCollezioneProvider).valueOrNull ?? const [];
      return valoriAsseInCollezione(edizioni, asse);
    });

/// La dimensione di uno step di caricamento dello scroll infinito della
/// Collezione (§9, deciso su #112): 60 Edizioni per step.
const dimensionePaginaCollezione = 60;

/// Quante Edizioni di [edizioniVisibiliProvider] sono "caricate" (cioè
/// dentro la finestra la cui cover va hydratata) — deciso su #115: un
/// intero, non una lista di id, perché l'indice non è mai paginato lato
/// query (è sempre tutto il catalogo filtrato/ordinato in memoria). La
/// finestra è sempre "i primi N elementi visibili", ricalcolata a ogni
/// rebuild — questo risolve anche la domanda "quali id ri-idratare quando
/// l'indice cambia sotto lo scroll": si ricalcolano i primi N della nuova
/// lista, qualunque essi siano.
///
/// [build] resetta N a [dimensionePaginaCollezione] (pagina 1) ogni volta
/// che cambia [filtriCollezioneProvider] o [soloAggiuntiMeseCorrenteProvider]
/// — il ticket lo richiede esplicitamente perché l'insieme filtrato/
/// ordinato può cambiare completamente. Non guarda invece
/// [indiceCollezioneProvider]/[edizioniVisibiliProvider]: un aggiornamento
/// reattivo del catalogo (es. una scansione in corso) non deve far perdere
/// la posizione di scroll.
class NumeroCaricatiCollezioneNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(filtriCollezioneProvider);
    ref.watch(soloAggiuntiMeseCorrenteProvider);
    return dimensionePaginaCollezione;
  }

  void caricaAltro() => state += dimensionePaginaCollezione;
}

final numeroCaricatiCollezioneProvider =
    NotifierProvider<NumeroCaricatiCollezioneNotifier, int>(
      NumeroCaricatiCollezioneNotifier.new,
    );

/// La cover hydratata (deciso su #113) delle sole Edizioni nella finestra
/// corrente (i primi [numeroCaricatiCollezioneProvider] di
/// [edizioniVisibiliProvider]) — si ri-crea (nuova subscription) ogni volta
/// che la finestra cambia, sia per `caricaAltro()` sia per un cambiamento
/// reattivo a monte.
final hydratazioneCollezioneProvider = StreamProvider<Map<int, String?>>((
  ref,
) {
  final visibili = ref.watch(edizioniVisibiliProvider).valueOrNull ?? const [];
  final n = ref.watch(numeroCaricatiCollezioneProvider);
  final ids = visibili.take(n).map((edizione) => edizione.edizioneId).toList();
  return ref.watch(comicsRepositoryProvider).watchHydratazioneCollezione(ids);
});

/// La finestra caricata della Collezione, pronta per la griglia (§9, deciso
/// su #115): i primi N di [edizioniVisibiliProvider] più lo stato della
/// loro cover da [hydratazioneCollezioneProvider].
///
/// Un errore di hydration (deciso su #115) non fa fallire l'intera griglia
/// — resta un problema solo dell'indice, che qui non è mai coinvolto: le
/// Edizioni restano visibili con la cover "non ancora hydratata"
/// ([EdizioneCollezioneFinestra.coverHydratata] `false`), stesso
/// trattamento di un id la cui hydration non è ancora arrivata (query in
/// corso per una pagina appena caricata).
final Provider<AsyncValue<List<EdizioneCollezioneFinestra>>>
edizioniFinestraCollezioneProvider =
    Provider<AsyncValue<List<EdizioneCollezioneFinestra>>>((ref) {
      final n = ref.watch(numeroCaricatiCollezioneProvider);
      final cover = ref.watch(hydratazioneCollezioneProvider).valueOrNull;
      return ref.watch(edizioniVisibiliProvider).whenData((visibili) {
        return [
          for (final edizione in visibili.take(n))
            EdizioneCollezioneFinestra(
              indice: edizione,
              coverImage: cover?[edizione.edizioneId],
              coverHydratata: cover?.containsKey(edizione.edizioneId) ?? false,
            ),
        ];
      });
    });
