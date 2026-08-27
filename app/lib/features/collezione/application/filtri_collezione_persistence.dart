import 'dart:convert';

import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistenza di filtri/ordinamento della Collezione (§9, comportamento
/// deciso su #85) — un toggle utente "ricorda filtri e ordinamento",
/// attivo di default; se disattivato, filtri e ordinamento si azzerano al
/// riavvio successivo, ma la preferenza "disattivato" resta ricordata (non
/// si riattiva da sola). Chiavi isolate sotto il prefisso `collezione.` per
/// non collidere con future preferenze di altre schermate.
class FiltriCollezionePersistence {
  const FiltriCollezionePersistence(this._prefs);

  final SharedPreferences _prefs;

  static const _chiaveRicorda = 'collezione.ricordaFiltri';
  static const _chiaveStato = 'collezione.filtri';

  bool leggiRicorda() => _prefs.getBool(_chiaveRicorda) ?? true;

  Future<void> scriviRicorda({required bool valore}) =>
      _prefs.setBool(_chiaveRicorda, valore);

  /// `null` se non c'è nulla di persistito, o se il contenuto persistito
  /// non è più decodificabile (es. dopo una migrazione degli assi) — in
  /// entrambi i casi il chiamante ricade sullo stato di default, mai su
  /// un'eccezione. Decodifica difensiva (controlli `is`, mai cast forzati
  /// con `as` sul contenuto esterno) per non dover intercettare `TypeError`.
  FiltriCollezioneState? leggiStato() {
    final grezzo = _prefs.getString(_chiaveStato);
    if (grezzo == null) return null;
    try {
      final json = jsonDecode(grezzo);
      if (json is! Map) return null;
      return _decodifica(json.cast<String, dynamic>());
    } on FormatException {
      return null;
    }
  }

  Future<void> scriviStato(FiltriCollezioneState stato) {
    return _prefs.setString(_chiaveStato, jsonEncode(_codifica(stato)));
  }

  Future<void> cancellaStato() => _prefs.remove(_chiaveStato);

  Map<String, dynamic> _codifica(FiltriCollezioneState stato) => {
    'filtri': {
      for (final entry in stato.filtri.entries)
        if (entry.value.isNotEmpty) entry.key.name: entry.value.toList(),
    },
    'ordinamento': {
      'primario': stato.ordinamento.primario.name,
      'direzionePrimario': stato.ordinamento.direzionePrimario.name,
      'secondario': stato.ordinamento.secondario?.name,
      'direzioneSecondario': stato.ordinamento.direzioneSecondario.name,
    },
  };

  FiltriCollezioneState _decodifica(Map<String, dynamic> json) {
    final filtri = <AsseCollezione, Set<String>>{};
    final filtriJson = json['filtri'];
    if (filtriJson is Map) {
      for (final asse in AsseCollezione.values) {
        final valori = filtriJson[asse.name];
        if (valori is List) filtri[asse] = valori.whereType<String>().toSet();
      }
    }

    final ordJson = json['ordinamento'];
    final ordinamento = ordJson is Map
        ? OrdinamentoCollezione(
            primario:
                _criterioDaNome(ordJson['primario']) ??
                CriterioOrdinamento.titolo,
            direzionePrimario: _direzioneDaNome(ordJson['direzionePrimario']),
            secondario: _criterioDaNome(ordJson['secondario']),
            direzioneSecondario: _direzioneDaNome(
              ordJson['direzioneSecondario'],
            ),
          )
        : const OrdinamentoCollezione();

    return FiltriCollezioneState(filtri: filtri, ordinamento: ordinamento);
  }

  CriterioOrdinamento? _criterioDaNome(Object? nome) {
    if (nome is! String) return null;
    for (final criterio in CriterioOrdinamento.values) {
      if (criterio.name == nome) return criterio;
    }
    return null;
  }

  DirezioneOrdinamento _direzioneDaNome(Object? nome) {
    return nome == DirezioneOrdinamento.decrescente.name
        ? DirezioneOrdinamento.decrescente
        : DirezioneOrdinamento.crescente;
  }
}
