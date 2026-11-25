package com.wokok.wokok_vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Shared state between the Flutter activity and the VPN service. */
object Core {
    @Volatile var config: String? = null
    @Volatile var service: WokokVpnService? = null

    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null

    fun setPending(r: MethodChannel.Result) { pending = r }

    fun complete() = main.post {
        pending?.success(null)
        pending = null
    }

    fun fail(message: String) = main.post {
        pending?.error("start_failed", message, null)
        pending = null
    }

    fun setSink(s: EventChannel.EventSink?) { sink = s }

    fun emit(event: String) = main.post { sink?.success(event) }
}
