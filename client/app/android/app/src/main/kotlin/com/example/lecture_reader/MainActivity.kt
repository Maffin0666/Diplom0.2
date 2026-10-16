package com.example.lecture_reader

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var captureKeysEnabled = false
    private var cameraChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cameraChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lektoria/camera")
        cameraChannel?.setMethodCallHandler { call, result ->
            if (call.method == "captureKeys") {
                captureKeysEnabled = call.argument<Boolean>("enabled") == true
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lektoria/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method == "tone") {
                    try {
                        val kind = call.argument<String>("kind")
                        val tone = when (kind) {
                            "error" -> ToneGenerator.TONE_PROP_NACK
                            "formula" -> ToneGenerator.TONE_PROP_PROMPT
                            "waiting" -> ToneGenerator.TONE_PROP_BEEP
                            else -> ToneGenerator.TONE_PROP_ACK
                        }
                        val generator = ToneGenerator(AudioManager.STREAM_MUSIC, 28)
                        generator.startTone(tone, if (kind == "error") 180 else 95)
                        Handler(Looper.getMainLooper()).postDelayed({ generator.release() }, 260)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("TONE_FAILED", error.message, null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "vibrate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                            .defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                    }
                    if (!vibrator.hasVibrator()) {
                        result.success(false)
                    } else {
                        val duration = (call.argument<Int>("durationMs") ?: 55).coerceIn(20, 250)
                        val pattern = when (call.argument<String>("kind")) {
                            "shutter" -> longArrayOf(0, 45, 45, 90)
                            "error" -> longArrayOf(0, 140, 65, 140)
                            "boundary" -> longArrayOf(0, 35, 75, 35, 75, 35)
                            "formula" -> longArrayOf(0, 35, 35, 75)
                            else -> longArrayOf(0, duration.toLong())
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            vibrator.vibrate(
                                VibrationEffect.createWaveform(pattern, -1)
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            vibrator.vibrate(pattern, -1)
                        }
                        result.success(true)
                    }
                } catch (error: Exception) {
                    result.error("VIBRATION_FAILED", error.message, null)
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (captureKeysEnabled && (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                    event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                cameraChannel?.invokeMethod("capture", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
