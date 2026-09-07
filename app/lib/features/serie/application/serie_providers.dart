import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';

/// Le due viste dei "numeri posseduti" nel dettaglio Serie (§11): solo il
/// numero (default, com'era prima) o la cover con il numero sotto.
enum VistaNumeriSerie { numero, cover }

class VistaNumeriSerieNotifier extends Notifier<VistaNumeriSerie> {
  @override
  VistaNumeriSerie build() => VistaNumeriSerie.numero;

  void imposta(VistaNumeriSerie valore) => state = valore;
}

final vistaNumeriSerieProvider =
    NotifierProvider<VistaNumeriSerieNotifier, VistaNumeriSerie>(
      VistaNumeriSerieNotifier.new,
    );

/// Le Edizioni possedute di una Serie — usate dalla vista "cover" del
/// dettaglio Serie per risolvere la copertina di ciascun numero posseduto.
final FutureProviderFamily<List<EdizioneCatalogo>, int>
edizioniPosseduteDiSerieProvider =
    FutureProvider.family<List<EdizioneCatalogo>, int>((ref, serieId) {
      return ref
          .watch(comicsRepositoryProvider)
          .edizioniPosseduteDiSerie(serieId);
    });
