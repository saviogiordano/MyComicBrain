package com.saviogiordano.mycomicbrain.mycomicbrain

import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canale nativo minimo per il fallback STT Android (#138): il plugin
 * `speech_to_text` non espone in Dart una verifica di
 * `SpeechRecognizer.isOnDeviceRecognitionAvailable` — sotto API 31 o senza
 * modello scaricato ricade silenziosamente sul riconoscitore di rete senza
 * segnalarlo (vedi docs/research/assistente-speech-to-text.md §4.2/§4.3).
 */
class MainActivity : FlutterActivity() {
    private val sttCapabilityChannel = "mycomicbrain/stt_capability"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sttCapabilityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "onDeviceDisponibile" -> result.success(onDeviceDisponibile())
                    else -> result.notImplemented()
                }
            }
    }

    private fun onDeviceDisponibile(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return SpeechRecognizer.isOnDeviceRecognitionAvailable(applicationContext)
    }
}
