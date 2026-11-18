package com.example.my_finance_app

import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.example.my_finance_app/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        val uri: Uri = when {
                            toneType.contains("અલાર્મ") || toneType.contains("Alarm") ->
                                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            toneType.contains("નોટિફિકેશન") || toneType.contains("Notification") ->
                                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                            else ->
                                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        }
                        val ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                        ringtone.play()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RINGTONE_ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
