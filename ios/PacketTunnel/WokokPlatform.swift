import Foundation
import Libbox
import Network
import NetworkExtension

/// Platform glue for libbox (sing-box 1.11.x) inside a Network Extension.
/// Modelled on the official sing-box-for-apple implementation.
final class WokokPlatform: NSObject, LibboxPlatformInterfaceProtocol {
    private unowned let tunnel: NEPacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var monitor: NWPathMonitor?

    init(_ tunnel: NEPacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        networkSettings = nil
        monitor?.cancel()
        monitor = nil
    }

    // MARK: TUN

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }

    private func openTun0(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else { throw NSError(domain: "WokokVPN", code: 10, userInfo: [NSLocalizedDescriptionKey: "nil options"]) }
        guard let ret0_ else { throw NSError(domain: "WokokVPN", code: 11, userInfo: [NSLocalizedDescriptionKey: "nil return pointer"]) }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            let dnsServer = try options.getDNSServerAddress()
            let dns = NEDNSSettings(servers: [dnsServer.value])
            dns.matchDomains = [""]
            dns.matchDomainsNoSearch = true
            settings.dnsSettings = dns

            // IPv4
            var v4Address: [String] = []
            var v4Mask: [String] = []
            let v4 = options.getInet4Address()!
            while v4.hasNext() {
                let p = v4.next()!
                v4Address.append(p.address())
                v4Mask.append(p.mask())
            }
            let ipv4 = NEIPv4Settings(addresses: v4Address, subnetMasks: v4Mask)
            var v4Routes: [NEIPv4Route] = []
            var v4Exclude: [NEIPv4Route] = []
            let r4 = options.getInet4RouteAddress()!
            if r4.hasNext() {
                while r4.hasNext() {
                    let p = r4.next()!
                    v4Routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
                }
            } else {
                v4Routes.append(NEIPv4Route.default())
            }
            let e4 = options.getInet4RouteExcludeAddress()!
            while e4.hasNext() {
                let p = e4.next()!
                v4Exclude.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
            }
            // Keep Apple push (APNs) outside the tunnel so notifications keep working.
            if !v4Routes.isEmpty {
                v4Exclude.append(NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"))
            }
            ipv4.includedRoutes = v4Routes
            ipv4.excludedRoutes = v4Exclude
            settings.ipv4Settings = ipv4

            // IPv6
            var v6Address: [String] = []
            var v6Prefix: [NSNumber] = []
            let v6 = options.getInet6Address()!
            while v6.hasNext() {
                let p = v6.next()!
                v6Address.append(p.address())
                v6Prefix.append(NSNumber(value: p.prefix()))
            }
            let ipv6 = NEIPv6Settings(addresses: v6Address, networkPrefixLengths: v6Prefix)
            var v6Routes: [NEIPv6Route] = []
            var v6Exclude: [NEIPv6Route] = []
            let r6 = options.getInet6RouteAddress()!
            if r6.hasNext() {
                while r6.hasNext() {
                    let p = r6.next()!
                    v6Routes.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
                }
            } else {
                v6Routes.append(NEIPv6Route.default())
            }
            let e6 = options.getInet6RouteExcludeAddress()!
            while e6.hasNext() {
                let p = e6.next()!
                v6Exclude.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
            }
            ipv6.includedRoutes = v6Routes
            ipv6.excludedRoutes = v6Exclude
            settings.ipv6Settings = ipv6
        }

        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxy.httpServer = server
            proxy.httpsServer = server
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            settings.proxySettings = proxy
        }

        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)

        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let loopFd = LibboxGetTunnelFileDescriptor()
        if loopFd != -1 {
            ret0_.pointee = loopFd
        } else {
            throw NSError(domain: "WokokVPN", code: 12, userInfo: [NSLocalizedDescriptionKey: "missing tunnel file descriptor"])
        }
    }

    // MARK: Interface control

    func usePlatformAutoDetectInterfaceControl() -> Bool { false }
    func autoDetectInterfaceControl(_ fd: Int32) throws {}

    // MARK: Connection owner (not available on iOS)

    func useProcFS() -> Bool { false }

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                             destinationAddress: String?, destinationPort: Int32,
                             ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "WokokVPN", code: 13, userInfo: [NSLocalizedDescriptionKey: "not implemented"])
    }

    func packageName(byUid uid: Int32, error: NSErrorPointer) -> String { "" }

    func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "WokokVPN", code: 14, userInfo: [NSLocalizedDescriptionKey: "not implemented"])
    }

    func writeLog(_ message: String?) {
        #if DEBUG
        if let message { NSLog("[wokok] %@", message) }
        #endif
    }

    // MARK: Default interface monitor

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onUpdate(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.onUpdate(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func onUpdate(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: NWPath) {
        if path.status == .unsatisfied || path.availableInterfaces.isEmpty {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
        } else {
            let iface = path.availableInterfaces[0]
            listener.updateDefaultInterface(iface.name, interfaceIndex: Int32(iface.index),
                                            isExpensive: path.isExpensive, isConstrained: path.isConstrained)
        }
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        monitor?.cancel()
        monitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let monitor else {
            throw NSError(domain: "WokokVPN", code: 15, userInfo: [NSLocalizedDescriptionKey: "monitor not started"])
        }
        let path = monitor.currentPath
        if path.status == .unsatisfied {
            return InterfaceArray([])
        }
        var result: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let i = LibboxNetworkInterface()
            i.name = it.name
            i.index = Int32(it.index)
            switch it.type {
            case .wifi: i.type = LibboxInterfaceTypeWIFI
            case .cellular: i.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: i.type = LibboxInterfaceTypeEthernet
            default: i.type = LibboxInterfaceTypeOther
            }
            result.append(i)
        }
        return InterfaceArray(result)
    }

    private final class InterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        private var nextValue: LibboxNetworkInterface?

        init(_ array: [LibboxNetworkInterface]) {
            iterator = array.makeIterator()
        }

        func hasNext() -> Bool {
            nextValue = iterator.next()
            return nextValue != nil
        }

        func next() -> LibboxNetworkInterface? { nextValue }
    }

    // MARK: Misc

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }

    func clearDNSCache() {
        guard let networkSettings else { return }
        tunnel.reasserting = true
        tunnel.setTunnelNetworkSettings(nil) { _ in }
        tunnel.setTunnelNetworkSettings(networkSettings) { _ in }
        tunnel.reasserting = false
    }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func send(_ notification: LibboxNotification?) throws {}
}

// MARK: async → sync bridge (libbox calls us synchronously)

private func runBlocking<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    final class Box<V> { var result: Result<V, Error>! }
    let box = Box<T>()
    Task.detached {
        do { box.result = .success(try await block()) } catch { box.result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}
