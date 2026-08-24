import 'dart:math' as math;

/// Similarità normalizzata 0-1 fra due stringhe (confronto case/spazi-
/// insensitive), basata sulla distanza di Levenshtein — condivisa fra
/// `MatchingEngine` (punteggio dei Candidati, #52) e `ComicVineHttpClient`
/// (selezione dei volumi ComicVine da interrogare per numero, #60), stesso
/// algoritmo per non farli divergere silenziosamente.
double similaritaTestuale(String a, String b) {
  final x = a.trim().toLowerCase();
  final y = b.trim().toLowerCase();
  if (x == y) return 1;
  if (x.isEmpty || y.isEmpty) return 0;
  final distanza = _levenshtein(x, y);
  final lunghezzaMax = math.max(x.length, y.length);
  return 1 - (distanza / lunghezzaMax);
}

int _levenshtein(String a, String b) {
  var precedente = List<int>.generate(b.length + 1, (j) => j);
  var corrente = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    corrente[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final costo = a[i - 1] == b[j - 1] ? 0 : 1;
      corrente[j] = [
        corrente[j - 1] + 1,
        precedente[j] + 1,
        precedente[j - 1] + costo,
      ].reduce(math.min);
    }
    final scambio = precedente;
    precedente = corrente;
    corrente = scambio;
  }
  return precedente[b.length];
}
