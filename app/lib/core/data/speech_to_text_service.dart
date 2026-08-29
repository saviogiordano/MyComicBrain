import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Esito di una sessione di ascolto (§10, deciso su
/// [Integrare lo speech-to-text on-device nell'input di Cerca](https://github.com/saviogiordano/MyComicBrain/issues/138)):
/// `testo` è `null` se l'ascolto è stato annullato o non ha prodotto alcun
/// risultato (permesso negato, nessun match, errore del riconoscitore).
/// `fallbackRete` è vero solo quando `testo` non è vuoto **e** siamo su
/// Android con il riconoscimento on-device non disponibile su questo
/// dispositivo (sotto API 31 o senza modello scaricato): il plugin
/// `speech_to_text` in quel caso ricade silenziosamente sul riconoscitore di
/// rete invece di segnalarlo (vedi
/// `docs/research/assistente-speech-to-text.md` §4.2) — sempre `false` su
/// iOS, dove `onDevice: true` fallisce esplicitamente invece di ricadere in
/// rete.
typedef RisultatoAscolto = ({String? testo, bool fallbackRete});

/// Speech-to-text on-device per il microfono di Cerca (§10): STT locale →
/// testo, il Provider AI Testuale non riceve mai audio, solo il transcript
/// prodotto qui (deciso sulla mappa
/// [Ricerca conversazionale e Assistente](https://github.com/saviogiordano/MyComicBrain/issues/118)).
abstract class SpeechToTextService {
  /// Avvia una sessione di ascolto. [onParziale] è invocato ad ogni
  /// risultato intermedio, per riflettere la trascrizione in corso nel
  /// campo di input mentre l'utente parla.
  Future<RisultatoAscolto> ascolta({
    required ValueChanged<String> onParziale,
  });

  /// Interrompe una sessione di ascolto in corso senza restituire un
  /// risultato finale — non fa nulla se non si sta ascoltando.
  Future<void> annulla();

  bool get ascoltando;
}

/// Implementazione su `speech_to_text: 7.4.0` (pinnato esatto, scelto su
/// [Scelta del package Flutter per lo speech-to-text](https://github.com/saviogiordano/MyComicBrain/issues/120)).
///
/// Il pacchetto non espone in Dart una verifica di
/// `SpeechRecognizer.isOnDeviceRecognitionAvailable` lato Android (limite
/// noto, vedi ricerca §4.3): la query passa quindi da un piccolo
/// `MethodChannel` nativo (`MainActivity.kt`) invece che dal plugin.
class PluginSpeechToTextService implements SpeechToTextService {
  PluginSpeechToTextService({stt.SpeechToText? speech})
    : _speech = speech ?? stt.SpeechToText();

  static const _capacitaChannel = MethodChannel('mycomicbrain/stt_capability');

  final stt.SpeechToText _speech;
  bool _pronto = false;
  Completer<String?>? _ascoltoCorrente;

  Future<bool> _assicuraInizializzato() async {
    if (_pronto) return true;
    return _pronto = await _speech.initialize(
      onError: (_) => _completaAscolto(null),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _completaAscolto(null);
        }
      },
    );
  }

  void _completaAscolto(String? valore) {
    final completer = _ascoltoCorrente;
    if (completer != null && !completer.isCompleted) {
      completer.complete(valore);
    }
  }

  /// `true` se, sotto Android, il riconoscimento on-device non è
  /// disponibile su questo dispositivo — sempre `false` su iOS, dove il
  /// vincolo è enforceable direttamente da `onDevice: true` (fallisce
  /// apertamente invece di ricadere in rete).
  Future<bool> _fallbackReteAndroid() async {
    if (!Platform.isAndroid) return false;
    final disponibile =
        await _capacitaChannel.invokeMethod<bool>('onDeviceDisponibile') ??
        false;
    return !disponibile;
  }

  @override
  Future<RisultatoAscolto> ascolta({
    required ValueChanged<String> onParziale,
  }) async {
    if (!await _assicuraInizializzato()) {
      return (testo: null, fallbackRete: false);
    }

    final fallbackRete = await _fallbackReteAndroid();

    final completer = Completer<String?>();
    _ascoltoCorrente = completer;
    await _speech.listen(
      onResult: (result) {
        onParziale(result.recognizedWords);
        if (result.finalResult) _completaAscolto(result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(onDevice: true, cancelOnError: true),
    );

    final testo = await completer.future;
    return (
      testo: testo,
      fallbackRete: fallbackRete && (testo ?? '').trim().isNotEmpty,
    );
  }

  @override
  Future<void> annulla() async {
    await _speech.cancel();
    _completaAscolto(null);
  }

  @override
  bool get ascoltando => _speech.isListening;
}
