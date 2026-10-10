package com.example.nestora_pg

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens an installed app (e.g. a UPI app) on its home screen, using
        // the app's own launch intent. A generic MAIN/LAUNCHER intent is not
        // enough: Android only starts implicit intents whose target declares
        // CATEGORY_DEFAULT, which launcher screens usually don't.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pg_management/apps")
            .setMethodCallHandler { call, result ->
                if (call.method != "launch") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val pkg = call.argument<String>("package")
                val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                if (intent == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }
}
