package com.example.god_save_this_shit_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri

class MainActivity : FlutterActivity() {
    private val deepLinkChannelName = "soulbuddy/deep_links"
    private val emailChannelName = "soulbuddy/email"
    private var deepLinkChannel: MethodChannel? = null
    private var pendingLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkChannelName)
        deepLinkChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                result.success(pendingLink ?: intent?.dataString)
                pendingLink = null
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, emailChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "composeEmail") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val subject = call.argument<String>("subject") ?: ""
                val body = call.argument<String>("body") ?: ""
                val intent = Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("mailto:")
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                }
                try {
                    startActivity(intent)
                    result.success(true)
                } catch (error: ActivityNotFoundException) {
                    result.error("NO_EMAIL_APP", "На устройстве нет почтового приложения", null)
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString ?: return
        pendingLink = link
        runOnUiThread { deepLinkChannel?.invokeMethod("onLink", link) }
    }
}
