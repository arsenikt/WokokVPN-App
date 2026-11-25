package com.wokok.wokok_vpn

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val vpnRequest = 4242

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

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
