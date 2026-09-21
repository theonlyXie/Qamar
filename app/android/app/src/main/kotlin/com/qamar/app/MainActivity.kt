package com.qamar.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodName = "com.qamar.app/quick"
    private val eventName = "com.qamar.app/quick_events"

    private var pendingAction: String? = null
    private var pendingText: String? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        capture(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capture(intent)
        flushToFlutter()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodName)
            .setMethodCallHandler { call, result ->
                if (call.method == "takePending") {
                    result.success(takePending())
                } else {
                    result.notImplemented()
                }
            }
                EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun capture(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val data = intent.data
        when {
            action == "com.qamar.app.QUICK_ASK" -> enqueue("ask", intent.getStringExtra("q"))
            action == "com.qamar.app.QUICK_LOG" -> enqueue("log", intent.getStringExtra("q"))
            // Invitation links: qamar://i/<code> and https://dr-qamar.com/i/<code>.
            data != null && data.scheme == "qamar" && data.host == "i" && data.pathSegments.isNotEmpty() ->
                enqueue("invite", data.pathSegments[0])
            data != null && (data.scheme == "https" || data.scheme == "http") &&
                (data.host == "dr-qamar.com" || data.host == "www.dr-qamar.com") &&
                data.pathSegments.size >= 2 && data.pathSegments[0] == "i" ->
                enqueue("invite", data.pathSegments[1])
            data != null && data.scheme == "com.qamar.app" && data.host == "i" && data.pathSegments.isNotEmpty() ->
                enqueue("invite", data.pathSegments[0])
            data != null && data.scheme == "com.qamar.app" -> {
                val host = data.host ?: ""
                val segs = data.pathSegments
                val kind = when {
                    host == "quick" && segs.isNotEmpty() -> segs[0]
                    host == "ask" || host == "log" || host == "plus" -> host
                    else -> null
                }
                if (kind == "ask" || kind == "log" || kind == "plus") {
                    enqueue(kind, data.getQueryParameter("q") ?: data.getQueryParameter("text"))
                }
            }
        }
    }

    private fun enqueue(action: String, text: String?) {
        pendingAction = action
        pendingText = text?.takeIf { it.isNotBlank() }
    }

    private fun takePending(): Map<String, String>? {
        val action = pendingAction ?: return null
        val text = pendingText
        pendingAction = null
        pendingText = null
        val out = HashMap<String, String>()
        out["action"] = action
        if (text != null) out["text"] = text
        return out
    }

    private fun flushToFlutter() {
        val sink = eventSink ?: return
        val payload = takePending() ?: return
        sink.success(payload)
    }
}
