import AVFoundation
import Flutter
import NetworkExtension
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var tunnel: TunnelBridge?
  private let voice = AVSpeechSynthesizer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      tunnel = TunnelBridge(messenger: controller.binaryMessenger)
      let device = FlutterMethodChannel(
        name: "com.wokok.box/device", binaryMessenger: controller.binaryMessenger)
      device.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "speak":
          let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
          let utterance = AVSpeechUtterance(string: text)
          if text.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
            utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
          }
          self.voice.stopSpeaking(at: .immediate)
          self.voice.speak(utterance)
          result(true)
        case "stop":
          self.voice.stopSpeaking(at: .immediate)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Dart <-> Packet Tunnel bridge.
///   MethodChannel  com.wokok.vpn/engine   start(config) / stop()
///   EventChannel   com.wokok.vpn/events   "stopped" when the tunnel drops by itself
final class TunnelBridge: NSObject, FlutterStreamHandler {
  private let extensionId: String
  private var sink: FlutterEventSink?
  private var manager: NETunnelProviderManager?
  private var userStopped = false
  private var wasConnected = false
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    extensionId = (Bundle.main.bundleIdentifier ?? "com.wokok.wokokVpn") + ".PacketTunnel"
    super.init()

    let method = FlutterMethodChannel(name: "com.wokok.vpn/engine", binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        guard let config = args?["config"] as? String else {
          result(FlutterError(code: "bad_args", message: "Конфиг не передан", details: nil))
          return
        }
        Task { await self.start(config: config, result: result) }
      case "stop":
        self.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterEventChannel(name: "com.wokok.vpn/events", binaryMessenger: messenger)
      .setStreamHandler(self)

    observer = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: nil, queue: .main
    ) { [weak self] note in
      guard let self, let conn = note.object as? NEVPNConnection else { return }
      if conn.status == .connected { self.wasConnected = true }
      if conn.status == .disconnected, self.wasConnected, !self.userStopped {
        self.wasConnected = false
        self.sink?("stopped")
      }
    }
  }

  // MARK: FlutterStreamHandler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: tunnel
  private func loadManager() async throws -> NETunnelProviderManager {
    let all = try await NETunnelProviderManager.loadAllFromPreferences()
    if let existing = all.first(where: {
      ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionId
    }) {
      return existing
    }
    let m = NETunnelProviderManager()
    let proto = NETunnelProviderProtocol()
    proto.providerBundleIdentifier = extensionId
    proto.serverAddress = "Wokok VPN"
    m.protocolConfiguration = proto
    m.localizedDescription = "Wokok VPN"
    return m
  }

  private func start(config: String, result: @escaping FlutterResult) async {
    var saved = false
    do {
      userStopped = false
      let m = try await loadManager()
      m.isEnabled = true
      try await m.saveToPreferences()
      try await m.loadFromPreferences()
      saved = true
      manager = m
      try m.connection.startVPNTunnel(options: ["config": config as NSString])
      try await waitConnected(m.connection)
      DispatchQueue.main.async { result(nil) }
    } catch {
      // A free Apple ID (AltStore, Sideloadly) cannot sign the Network Extension entitlement.
      let hint = saved ? "" : ". iOS не разрешил создать VPN: нужна подпись с платным Apple Developer"
      let message = error.localizedDescription + hint
      DispatchQueue.main.async {
        result(FlutterError(code: "start_failed", message: message, details: nil))
      }
    }
  }

  private func waitConnected(_ conn: NEVPNConnection) async throws {
    for _ in 0..<100 {  // 25 s
      switch conn.status {
      case .connected:
        return
      case .disconnected, .invalid:
        if #available(iOS 16.0, *) {
          try await conn.fetchLastDisconnectError()
        }
        throw NSError(domain: "WokokVPN", code: 20,
                      userInfo: [NSLocalizedDescriptionKey: "Туннель не запустился"])
      default:
        try await Task.sleep(nanoseconds: 250_000_000)
      }
    }
    throw NSError(domain: "WokokVPN", code: 21,
                  userInfo: [NSLocalizedDescriptionKey: "Время ожидания подключения истекло"])
  }

  private func stop() {
    userStopped = true
    wasConnected = false
    manager?.connection.stopVPNTunnel()
  }
}
