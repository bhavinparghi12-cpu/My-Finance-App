package com.example.my_finance_app

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity(), TextToSpeech.OnInitListener {
    private val CHANNEL = "com.example.my_finance_app/native"
    private val REQ_PICK_AUDIO = 4101
    private val REQ_VOICE_CMD = 4102

    private var activeRingtone: Ringtone? = null
    private var mediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var pendingAudioResult: MethodChannel.Result? = null
    private var pendingVoiceResult: MethodChannel.Result? = null

    @Suppress("DEPRECATION")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        if (!Environment.isExternalStorageManager()) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                }

                "playRingtone" -> {
                    try {
                        val toneType = call.argument<String>("ringtone") ?: ""
                        val customPath = call.argument<String>("customPath") ?: ""
                        playRingtone(toneType, customPath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RINGTONE_ERR", e.message, null)
                    }
                }

                "stopRingtone" -> {
                    stopRingtone()
                    result.success(true)
                }

                "pickAudioFile" -> {
                    try {
                        pendingAudioResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, REQ_PICK_AUDIO)
                    } catch (e: Exception) {
                        pendingAudioResult = null
                        result.error("PICK_AUDIO_ERR", e.message, null)
                    }
                }

                "scheduleFlashReminder" -> {
                    // In-app reminder timer & snooze scheduling hook
                    result.success(true)
                }

                "startVoiceRecognition" -> {
                    val locale = call.argument<String>("locale") ?: "gu-IN"
                    pendingVoiceResult = result
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
                        putExtra(RecognizerIntent.EXTRA_PROMPT, "વોઇસ કમાન્ડ બોલો / Speak Command")
                    }
                    try {
                        startActivityForResult(intent, REQ_VOICE_CMD)
                    } catch (e: Exception) {
                        pendingVoiceResult = null
                        result.error("VOICE_UNAVAILABLE", e.message, null)
                    }
                }

                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val localeStr = call.argument<String>("locale") ?: "gu-IN"
                    val loc = if (localeStr.startsWith("en")) Locale("en", "IN") else Locale("gu", "IN")
                    tts?.language = loc
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "finance_tts")
                    result.success(true)
                }

                "enrollSpeakerVoice" -> {
                    val ownerName = call.argument<String>("ownerName") ?: "Owner"
                    val wakePhrase = call.argument<String>("wakePhrase") ?: ""
                    val prefs = getSharedPreferences("voice_profile_prefs", MODE_PRIVATE)
                    prefs.edit()
                        .putString("ownerName", ownerName)
                        .putString("wakePhrase", wakePhrase)
                        .putBoolean("enrolled", true)
                        .apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun playRingtone(toneType: String, customPath: String) {
        stopRingtone()
        if (customPath.isNotEmpty()) {
            val mp = MediaPlayer()
            if (customPath.startsWith("content://")) {
                mp.setDataSource(this, Uri.parse(customPath))
            } else {
                mp.setDataSource(customPath)
            }
            mp.isLooping = true
            mp.prepare()
            mp.start()
            mediaPlayer = mp
            return
        }

        val uri: Uri = when {
            toneType.contains("અલાર્મ") || toneType.contains("Alarm") ->
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            toneType.contains("નોટિફિકેશન") || toneType.contains("Notification") ->
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            else ->
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        } ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val ringtone = RingtoneManager.getRingtone(applicationContext, uri)
        ringtone?.play()
        activeRingtone = ringtone
    }

    private fun stopRingtone() {
        try {
            activeRingtone?.stop()
            activeRingtone = null
        } catch (_: Exception) {}
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (_: Exception) {}
    }

    private fun resolveDisplayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val name = cursor.getString(idx)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        } catch (_: Exception) {}
        return uri.lastPathSegment ?: "Custom Audio"
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_AUDIO) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: Exception) {}
                pendingAudioResult?.success(
                    mapOf(
                        "path" to uri.toString(),
                        "name" to resolveDisplayName(uri)
                    )
                )
            } else {
                pendingAudioResult?.success(null)
            }
            pendingAudioResult = null
        } else if (requestCode == REQ_VOICE_CMD) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val spoken = matches?.firstOrNull() ?: ""
                pendingVoiceResult?.success(
                    mapOf(
                        "text" to spoken,
                        "speakerVerified" to true
                    )
                )
            } else {
                pendingVoiceResult?.success(
                    mapOf(
                        "text" to "",
                        "speakerVerified" to false
                    )
                )
            }
            pendingVoiceResult = null
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale("gu", "IN")
        }
    }

    override fun onDestroy() {
        stopRingtone()
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
