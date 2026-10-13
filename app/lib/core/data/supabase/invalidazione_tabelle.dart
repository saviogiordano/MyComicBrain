import 'dart:async';

/// Le tabelle di ADR-0004 su cui scrive `SupabaseComicsRepository`, con il
/// nome Postgres.
enum TabellaSupabase {
  opere('opere'),
  serie('serie'),
  edizioni('edizioni'),
  copie('copie'),
  creator('creator'),
  comicCreator('comic_creator'),
  tag('tag'),
  edizioneTag('edizione_tag'),
  character('character'),
  comicCharacter('comic_character'),
  edizioneGenere('edizione_genere'),
  valoreStimato('valore_stimato'),
  scansioni('scansioni'),
  analisiCopertina('analisi_copertina'),
  identificazione('identificazione'),
  candidati('candidati'),
  conversazione('conversazione'),
  messaggio('messaggio');

  const TabellaSupabase(this.nome);

  final String nome;
}

/// Reattività dei `watch*` sull'adapter Supabase (ADR-0007): ogni scrittura
/// dell'adapter [segnala] le tabelle toccate e gli stream di [osserva] che
/// le leggono si rileggono. Riproduce la semantica di drift ("vedo subito
/// le mie scritture") senza Supabase Realtime: le modifiche fatte da un
/// altro device si vedono alla riapertura.
class InvalidazioneTabelle {
  final _segnali = StreamController<Set<TabellaSupabase>>.broadcast(
    sync: true,
  );

  void segnala(Set<TabellaSupabase> tabelle) {
    if (!_segnali.isClosed) _segnali.add(tabelle);
  }

  /// Emette [leggi] all'ascolto e lo rilegge a ogni segnale su una delle
  /// [tabelle]. Segnali arrivati durante una lettura ne provocano una sola
  /// in più alla fine, così l'ultimo valore emesso è sempre successivo
  /// all'ultima scrittura. Un errore di lettura arriva sullo stream, che
  /// resta aperto.
  Stream<T> osserva<T>(
    Set<TabellaSupabase> tabelle,
    Future<T> Function() leggi,
  ) {
    late final StreamController<T> uscita;
    StreamSubscription<Set<TabellaSupabase>>? sottoscrizione;
    var inLettura = false;
    var daRileggere = false;

    Future<void> rileggi() async {
      if (inLettura) {
        daRileggere = true;
        return;
      }
      inLettura = true;
      do {
        daRileggere = false;
        try {
          final valore = await leggi();
          if (!uscita.isClosed) uscita.add(valore);
        } on Object catch (errore, stack) {
          if (!uscita.isClosed) uscita.addError(errore, stack);
        }
      } while (daRileggere && !uscita.isClosed);
      inLettura = false;
    }

    uscita = StreamController<T>(
      onListen: () {
        sottoscrizione = _segnali.stream
            .where((toccate) => toccate.any(tabelle.contains))
            .listen((_) => unawaited(rileggi()));
        unawaited(rileggi());
      },
      onCancel: () => sottoscrizione?.cancel(),
    );
    return uscita.stream;
  }

  Future<void> chiudi() => _segnali.close();
}
