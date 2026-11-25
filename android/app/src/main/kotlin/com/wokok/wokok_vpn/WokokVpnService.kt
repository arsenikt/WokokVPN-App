package com.wokok.wokok_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.LinkProperties
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.Process
import android.util.Log
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification as LibboxNotification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface as JavaNetworkInterface
import io.nekohasekai.libbox.NetworkInterface as BoxNetworkInterface

/**
 * Runs sing-box (libbox) inside an Android VpnService.
 * The Dart side hands us a ready JSON config; we only provide the platform glue.
 */
class WokokVpnService : VpnService(), PlatformInterface {

    companion object {
        const val ACTION_START = "com.wokok.vpn.START"
        const val ACTION_STOP = "com.wokok.vpn.STOP"
        private const val CHANNEL = "wokok_vpn"
        private const val NOTIFICATION_ID = 7
        private const val TAG = "WokokVPN"
    }

    private var box: BoxService? = null
    private var stoppingByUser = false
    private var monitorCallback: ConnectivityManager.NetworkCallback? = null

    private val connectivity by lazy { getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stoppingByUser = true
            shutdown()
            return START_NOT_STICKY
        }
        val config = Core.config
        if (config == null) {
            Core.fail("Конфиг не передан")
            stopSelf()
            return START_NOT_STICKY
        }
        showForeground()
        Thread {
            try {
                val options = SetupOptions()
                options.basePath = filesDir.path
                options.workingPath = getExternalFilesDir(null)?.path ?: filesDir.path
                options.tempPath = cacheDir.path
                Libbox.setup(options)
                val service = Libbox.newService(config, this)
                service.start()
                box = service
                Core.service = this
                Core.complete()
            } catch (e: Throwable) {
                Log.e(TAG, "start failed", e)
                Core.fail(e.message ?: e.toString())
                shutdown()
            }
        }.start()
        return START_NOT_STICKY
    }

    private fun showForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val n = builder
            .setContentTitle("Wokok VPN")
            .setContentText("Вок на огне: трафик защищён")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun shutdown() {
        try {
            box?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "close failed", e)
        }
        box = null
        monitorCallback?.let {
            try { connectivity.unregisterNetworkCallback(it) } catch (_: Throwable) {}
        }
        monitorCallback = null
        Core.service = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
        if (!stoppingByUser) Core.emit("stopped")
        stoppingByUser = false
    }

    override fun onRevoke() {
        // User turned the VPN off from system settings.
        shutdown()
    }

    override fun onDestroy() {
        if (box != null) shutdown()
        super.onDestroy()
    }

    // ---- PlatformInterface ------------------------------------------------

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing VPN permission")
        val builder = Builder()
            .setSession("Wokok VPN")
            .setMtu(options.getMTU())

        val v4 = options.getInet4Address()
        while (v4.hasNext()) {
            val p = v4.next()
            builder.addAddress(p.address(), p.prefix())
        }
        val v6 = options.getInet6Address()
        while (v6.hasNext()) {
            val p = v6.next()
            builder.addAddress(p.address(), p.prefix())
        }

        if (options.getAutoRoute()) {
            builder.addDnsServer(options.getDNSServerAddress().getValue())

            val r4 = options.getInet4RouteAddress()
            if (r4.hasNext()) {
                while (r4.hasNext()) { val p = r4.next(); builder.addRoute(p.address(), p.prefix()) }
            } else if (options.getInet4Address().hasNext()) {
                builder.addRoute("0.0.0.0", 0)
            }
            val r6 = options.getInet6RouteAddress()
            if (r6.hasNext()) {
                while (r6.hasNext()) { val p = r6.next(); builder.addRoute(p.address(), p.prefix()) }
            } else if (options.getInet6Address().hasNext()) {
                builder.addRoute("::", 0)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val e4 = options.getInet4RouteExcludeAddress()
                while (e4.hasNext()) {
                    val p = e4.next()
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(p.address()), p.prefix()))
                }
                val e6 = options.getInet6RouteExcludeAddress()
                while (e6.hasNext()) {
                    val p = e6.next()
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(p.address()), p.prefix()))
                }
            }

            val include = options.getIncludePackage()
            if (include.hasNext()) {
                while (include.hasNext()) {
                    try { builder.addAllowedApplication(include.next()) } catch (_: Exception) {}
                }
            } else {
                val exclude = options.getExcludePackage()
                while (exclude.hasNext()) {
                    try { builder.addDisallowedApplication(exclude.next()) } catch (_: Exception) {}
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val pfd = builder.establish() ?: error("android: the VPN service was revoked")
        return pfd.detachFd()
    }

    override fun writeLog(message: String) {
        Log.i(TAG, message)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): Int {
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        return uid
    }

    override fun packageNameByUid(uid: Int): String =
        packageManager.getPackagesForUid(uid)?.firstOrNull()
            ?: error("android: package not found")

    override fun uidByPackageName(packageName: String): Int =
        packageManager.getPackageUid(packageName, 0)

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                val name = lp.interfaceName ?: return
                val index = try {
                    JavaNetworkInterface.getByName(name)?.index ?: return
                } catch (_: Exception) {
                    return
                }
                listener.updateDefaultInterface(name, index, false, false)
            }

            override fun onLost(network: Network) {
                listener.updateDefaultInterface("", -1, false, false)
            }
        }
        monitorCallback = callback
        connectivity.registerDefaultNetworkCallback(callback)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        monitorCallback?.let {
            try { connectivity.unregisterNetworkCallback(it) } catch (_: Throwable) {}
        }
        monitorCallback = null
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val result = ArrayList<BoxNetworkInterface>()
        val all = JavaNetworkInterface.getNetworkInterfaces() ?: return IteratorOf(result)
        for (ni in all) {
            try {
                val box = BoxNetworkInterface()
                box.name = ni.name
                box.index = ni.index
                box.mtu = ni.mtu
                var flags = 0
                if (ni.isUp) flags = flags or 1
                if (ni.isLoopback) flags = flags or 4
                if (ni.isPointToPoint) flags = flags or 8
                if (ni.supportsMulticast()) flags = flags or 16
                box.flags = flags
                box.addresses = StringList(
                    ni.interfaceAddresses.map {
                        val host = it.address.hostAddress?.substringBefore('%') ?: ""
                        "$host/${it.networkPrefixLength}"
                    }
                )
                box.type = when {
                    ni.name.startsWith("wlan") -> Libbox.InterfaceTypeWIFI
                    ni.name.startsWith("rmnet") || ni.name.startsWith("ccmni") ->
                        Libbox.InterfaceTypeCellular
                    ni.name.startsWith("eth") -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                box.dnsServer = StringList(emptyList())
                box.metered = box.type == Libbox.InterfaceTypeCellular
                result.add(box)
            } catch (_: Exception) {
            }
        }
        return IteratorOf(result)
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun sendNotification(notification: LibboxNotification) {}

    // ---- small iterator helpers (gomobile interfaces) ---------------------

    private class StringList(private val items: List<String>) : StringIterator {
        private var i = 0
        override fun len(): Int = items.size
        override fun hasNext(): Boolean = i < items.size
        override fun next(): String = items[i++]
    }

    private class IteratorOf(private val items: List<BoxNetworkInterface>) : NetworkInterfaceIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): BoxNetworkInterface = items[i++]
    }
}
