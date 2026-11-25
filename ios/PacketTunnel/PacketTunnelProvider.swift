import Foundation
import Libbox
import NetworkExtension

/// Runs sing-box (libbox) inside an iOS Packet Tunnel extension.
/// The Flutter app passes the ready JSON config in the start options,
/// so no secrets are written to shared storage.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var service: LibboxBoxService?
    private var platform: WokokPlatform?

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let config = (options?["config"] as? NSString) as String?, !config.isEmpty else {
            throw NSError(domain: "WokokVPN", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Конфиг не передан"])
        }

        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("wokok", isDirectory: true)
        let work = base.appendingPathComponent("work", isDirectory: true)
        let temp = base.appendingPathComponent("tmp", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)

        let setup = LibboxSetupOptions()
        setup.basePath = base.path
        setup.workingPath = work.path
        setup.tempPath = temp.path
        var error: NSError?
        LibboxSetup(setup, &error)
        if let error { throw error }

        // Packet Tunnel extensions are killed above ~50 MB: let libbox keep itself small.
        LibboxSetMemoryLimit(true)

        let platform = WokokPlatform(self)
        self.platform = platform
        var serviceError: NSError?
        guard let service = LibboxNewService(config, platform, &serviceError) else {
            throw serviceError ?? NSError(domain: "WokokVPN", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "Не удалось создать сервис"])
        }
        try service.start()
        self.service = service
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        if let service {
            try? service.close()
        }
        service = nil
        platform?.reset()
        platform = nil
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        messageData
    }

    override func sleep() async {
        service?.pause()
    }

    override func wake() {
        service?.wake()
    }
}
