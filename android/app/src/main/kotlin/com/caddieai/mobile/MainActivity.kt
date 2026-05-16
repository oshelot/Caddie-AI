package com.caddieai.mobile

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val AUTH_CHANNEL = "caddieai/auth"
    private val LINK_CHANNEL = "caddieai/deeplink"
    private var linkEventSink: EventChannel.EventSink? = null
    private var pendingLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method channel: launch URL in browser
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchUrl" -> {
                        val url = call.arguments as? String
                        if (url != null) {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            startActivity(intent)
                            result.success(null)
                        } else {
                            result.error("INVALID_URL", "URL was null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Event channel: stream deep link callbacks
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LINK_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    linkEventSink = events
                    // Send any pending link that arrived before listener was set
                    pendingLink?.let {
                        events?.success(it)
                        pendingLink = null
                    }
                }
                override fun onCancel(arguments: Any?) {
                    linkEventSink = null
                }
            })

        // Check if the activity was launched with a deep link
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data?.toString() ?: return
        if (uri.startsWith("caddieai://callback")) {
            if (linkEventSink != null) {
                linkEventSink?.success(uri)
            } else {
                pendingLink = uri
            }
        }
    }
}
