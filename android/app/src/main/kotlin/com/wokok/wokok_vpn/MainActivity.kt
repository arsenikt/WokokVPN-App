package com.wokok.wokok_vpn

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val vpnRequest = 4242
    private var device: MethodChannel? = null
    private var shared: String? = null
    private var tts: TextToSpeech? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // only a fresh start carries a new share; a recreated activity would repeat it
        if (savedInstanceState == null) shared = sharedText(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = sharedText(intent) ?: return
        val channel = device
        if (channel == null) shared = text else channel.invokeMethod("shared", text)
    }

    override fun onDestroy() {
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }

    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND) intent.getStringExtra(Intent.EXTRA_TEXT)?.take(8000)
        else null

    private fun speak(text: String, result: MethodChannel.Result) {
        fun say(engine: TextToSpeech) {
            val cyrillic = text.any { it in 'Ѐ'..'ӿ' }
            if (cyrillic) engine.language = Locale("ru", "RU")
            result.success(engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "guard") == TextToSpeech.SUCCESS)
        }
        val ready = tts
        if (ready != null) {
            say(ready)
            return
        }
        var engine: TextToSpeech? = null
        engine = TextToSpeech(applicationContext) { status ->
            val e = engine
            if (status == TextToSpeech.SUCCESS && e != null) {
                tts = e
                say(e)
            } else {
                result.success(false)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        device = MethodChannel(messenger, "com.wokok.box/device").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> speak(call.argument<String>("text") ?: "", result)
                    "stop" -> {
                        tts?.stop()
                        result.success(null)
                    }
                    "sharedText" -> {
                        result.success(shared)
                        shared = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, "com.wokok.vpn/engine").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    Core.config = call.argument<String>("config")
                    Core.setPending(result)
                    askNotificationPermission()
                    val prepare = VpnService.prepare(this)
                    if (prepare != null) {
                        startActivityForResult(prepare, vpnRequest)
                    } else {
                        startVpn()
                    }
                }
                "stop" -> {
                    startService(
                        Intent(this, WokokVpnService::class.java)
                            .setAction(WokokVpnService.ACTION_STOP)
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "com.wokok.vpn/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = Core.setSink(events)
            override fun onCancel(arguments: Any?) = Core.setSink(null)
        })
    }

    private fun startVpn() {
        val intent = Intent(this, WokokVpnService::class.java).setAction(WokokVpnService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
        else startService(intent)
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4243)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == vpnRequest) {
            if (resultCode == Activity.RESULT_OK) startVpn()
            else Core.fail("Доступ VPN не разрешён")
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
