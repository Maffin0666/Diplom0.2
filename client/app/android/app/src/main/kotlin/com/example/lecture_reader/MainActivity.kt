package com.example.lecture_reader

import android.content.Context
import android.content.Intent
import android.app.Activity
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.KeyEvent
import java.io.File
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var captureKeysEnabled = false
    private var cameraChannel: MethodChannel? = null
    private var backupPickerResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4807) return
        val pending = backupPickerResult ?: return
        backupPickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        try {
            val destination = File(cacheDir, "lektoria-import.zip")
            contentResolver.openInputStream(data.data!!).use { input ->
                require(input != null) { "Не удалось открыть выбранный файл" }
                destination.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var copied = 0L
                    while (true) {
                        val length = input.read(buffer)
                        if (length < 0) break
                        copied += length
                        require(copied <= 2L * 1024 * 1024 * 1024) {
                            "Архив слишком большой"
                        }
                        output.write(buffer, 0, length)
                    }
                }
            }
            pending.success(destination.absolutePath)
        } catch (error: Exception) {
            pending.error("BACKUP_PICK_FAILED", error.message, null)
        }
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lektoria/backup")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickArchive") {
                    result.notImplemented()
                } else if (backupPickerResult != null) {
                    result.error("PICKER_BUSY", "Выбор файла уже открыт", null)
                } else {
                    backupPickerResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                    }
                    startActivityForResult(intent, 4807)
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
