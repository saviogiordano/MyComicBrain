import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';

/// Le Modifiche in sospeso raccontate all'utente (prototipo #201): l'elenco
/// dello sheet e di Impostazioni › Sincronizzazione ("Copia modificata:
/// Dylan Dog 41") e il titolo dell'avviso per le modifiche scartate.
class DescrizioneModifiche {
  DescrizioneModifiche(this._db) : _registro = RegistroModifiche(_db);

  final AppDatabase _db;
  final RegistroModifiche _registro;

  /// Una voce per riga con Modifiche in sospeso, come le conta
  /// [RegistroModifiche.conteggio], nell'ordine della prima scrittura. Le
  /// voci uguali e consecutive (i Candidati di una Scansione, più autori
  /// dello stesso fumetto) si raccolgono in una con "(×N)".
  Future<List<String>> elenco() async {
    final perRiga = <RigaReplicata, TipoVoceRegistro>{};
    for (final voce in await _registro.voci()) {
      final riga = (tabella: voce.tabella, id: voce.riga);
      final prima = perRiga[riga];
      // Aggiunta e poi modificata resta un'aggiunta; un'eliminazione vince
      // su tutto.
      perRiga[riga] = switch ((prima, voce.tipo)) {
        (null, final tipo) => tipo,
        (_, TipoVoceRegistro.eliminazione) => TipoVoceRegistro.eliminazione,
        (final tipo?, _) => tipo,
      };
    }
    final titoli = await this.titoli(perRiga.keys);

    final elenco = <({String testo, int volte})>[];
    for (final MapEntry(key: riga, value: tipo) in perRiga.entries) {
      final testo = _testo(riga.tabella, tipo, titoli[riga]);
      if (elenco.isNotEmpty && elenco.last.testo == testo) {
        elenco.last = (testo: testo, volte: elenco.last.volte + 1);
      } else {
        elenco.add((testo: testo, volte: 1));
      }
    }
    return [
      for (final e in elenco)
        if (e.volte == 1) e.testo else '${e.testo} (×${e.volte})',
    ];
  }

  /// Il nome con cui l'utente riconosce ciascuna delle [righe] ("Dylan Dog
  /// 41" per una Copia o un'Edizione, il nome per un autore). Mancano le
  /// righe che non sono più nella Replica o che non hanno un nome, come le
  /// Scansioni.
  Future<Map<RigaReplicata, String>> titoli(
    Iterable<RigaReplicata> righe,
  ) async {
    final titoli = <RigaReplicata, String>{};
    for (final riga in righe) {
      final sql = _titoloSql[riga.tabella];
      if (sql == null) continue;
      final r = await _db
          .customSelect(sql, variables: [Variable(riga.id)])
          .getSingleOrNull();
      final titolo = r?.read<String?>('titolo');
      if (titolo != null) titoli[riga] = titolo;
    }
    return titoli;
  }

  static String _testo(String tabella, TipoVoceRegistro tipo, String? titolo) {
    final (nome, femminile) = _nomi[tabella] ?? ('Dato', false);
    final participio = switch (tipo) {
      TipoVoceRegistro.inserimento => 'aggiunt',
      TipoVoceRegistro.modifica => 'modificat',
      TipoVoceRegistro.eliminazione => 'eliminat',
    };
    final testo = '$nome $participio${femminile ? 'a' : 'o'}';
    return titolo == null ? testo : '$testo: $titolo';
  }

  /// Come si chiama una riga di ogni tabella replicata, e se il nome è
  /// femminile.
  static const _nomi = {
    'opere': ('Opera', true),
    'serie': ('Serie', true),
    'edizioni': ('Fumetto', false),
    'copie': ('Copia', true),
    'creator': ('Autore', false),
    'comic_creator': ('Autore del fumetto', false),
    'tag': ('Tag', false),
    'edizione_tag': ('Tag del fumetto', false),
    'character': ('Personaggio', false),
    'comic_character': ('Personaggio del fumetto', false),
    'edizione_genere': ('Genere del fumetto', false),
    'valore_stimato': ('Valore stimato', false),
    'scansioni': ('Scansione', true),
    'analisi_copertina': ('Riconoscimento di una Scansione', false),
    'identificazione': ('Identificazione di una Scansione', true),
    'candidati': ('Candidato di una Scansione', false),
  };

  /// Il titolo di un fumetto: l'Opera e il numero, se c'è.
  static const _titoloEdizione =
      "SELECT o.title || coalesce(' ' || e.issue_number_label, '') AS titolo "
      'FROM edizioni e JOIN opere o ON o.id = e.opera_id';

  static const _titoloSql = {
    'opere': 'SELECT title AS titolo FROM opere WHERE id = ?',
    'serie': 'SELECT name AS titolo FROM serie WHERE id = ?',
    'creator': 'SELECT name AS titolo FROM creator WHERE id = ?',
    'tag': 'SELECT name AS titolo FROM tag WHERE id = ?',
    'character': 'SELECT name AS titolo FROM character WHERE id = ?',
    'edizioni': '$_titoloEdizione WHERE e.id = ?',
    'copie':
        '$_titoloEdizione WHERE e.id = (SELECT edizione_id FROM copie '
        'WHERE id = ?)',
    'comic_creator':
        '$_titoloEdizione WHERE e.id = (SELECT edizione_id FROM comic_creator '
        'WHERE id = ?)',
    'edizione_tag':
        '$_titoloEdizione WHERE e.id = (SELECT edizione_id FROM edizione_tag '
        'WHERE id = ?)',
    'comic_character':
        '$_titoloEdizione WHERE e.id = (SELECT edizione_id FROM '
        'comic_character WHERE id = ?)',
    'edizione_genere':
        '$_titoloEdizione WHERE e.id = (SELECT edizione_id FROM '
        'edizione_genere WHERE id = ?)',
    'valore_stimato':
        '$_titoloEdizione WHERE e.id = (SELECT c.edizione_id FROM '
        'valore_stimato v JOIN copie c ON c.id = v.copia_id WHERE v.id = ?)',
  };
}
