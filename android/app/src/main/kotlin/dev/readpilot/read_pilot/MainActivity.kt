package dev.readpilot.read_pilot

import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    companion object {
        private const val READ_ALOUD_CHANNEL = "dev.readpilot.read_pilot/read_aloud"
        private const val MAX_READ_ALOUD_CHARACTERS = 8000
    }

    private var channel: MethodChannel? = null
    private var textToSpeech: TextToSpeech? = null
    private var ready = false
    private var pendingSpeak: Pair<String, MethodChannel.Result>? = null
    private var activeUtteranceId: String? = null
    private var utteranceSequence = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, READ_ALOUD_CHANNEL)
        channel?.setMethodCallHandler(::handleReadAloudCall)
    }

    private fun handleReadAloudCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                if (text.isEmpty() || text.length > MAX_READ_ALOUD_CHARACTERS) {
                    result.error("invalid_text", "朗读文本无效或超过安全上限。", null)
                    return
                }
                startSpeak(text, result)
            }
            "stop" -> {
                pendingSpeak = null
                activeUtteranceId = null
                textToSpeech?.stop()
                result.success(null)
                notifyDart("cancelled")
            }
            else -> result.notImplemented()
        }
    }

    private fun startSpeak(text: String, result: MethodChannel.Result) {
        val engine = textToSpeech
        if (engine == null) {
            pendingSpeak = text to result
            textToSpeech = TextToSpeech(this, this)
            return
        }
        if (!ready) {
            pendingSpeak = text to result
            return
        }
        speakWithEngine(engine, text, result)
    }

    override fun onInit(status: Int) {
        val engine = textToSpeech ?: return
        if (status != TextToSpeech.SUCCESS) {
            failPending("unavailable", "设备未提供可用的本机朗读服务。")
            return
        }
        val language = engine.setLanguage(Locale.SIMPLIFIED_CHINESE)
        if (language == TextToSpeech.LANG_MISSING_DATA || language == TextToSpeech.LANG_NOT_SUPPORTED) {
            failPending("language_unavailable", "设备未安装可用的中文本机语音。")
            return
        }
        engine.setSpeechRate(0.45f)
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = Unit

            override fun onDone(utteranceId: String?) {
                if (utteranceId == activeUtteranceId) {
                    activeUtteranceId = null
                    notifyDart("completed")
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                onError(utteranceId, TextToSpeech.ERROR)
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                if (utteranceId == activeUtteranceId) {
                    activeUtteranceId = null
                    notifyDart("error")
                }
            }
        })
        ready = true
        pendingSpeak?.let { (text, result) ->
            pendingSpeak = null
            speakWithEngine(engine, text, result)
        }
    }

    private fun speakWithEngine(
        engine: TextToSpeech,
        text: String,
        result: MethodChannel.Result,
    ) {
        utteranceSequence += 1
        val utteranceId = "read-pilot-$utteranceSequence"
        activeUtteranceId = utteranceId
        val status = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        if (status == TextToSpeech.SUCCESS) {
            result.success(null)
        } else {
            activeUtteranceId = null
            result.error("speak_failed", "设备无法开始本机朗读。", null)
        }
    }

    private fun failPending(code: String, message: String) {
        pendingSpeak?.second?.error(code, message, null)
        pendingSpeak = null
        activeUtteranceId = null
        ready = false
        textToSpeech?.shutdown()
        textToSpeech = null
    }

    private fun notifyDart(method: String) {
        runOnUiThread {
            channel?.invokeMethod(method, null)
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }
}
