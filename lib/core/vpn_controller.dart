import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'engine.dart';
import 'profile.dart';
import 'singbox_config.dart';

enum VpnState { off, connecting, on, error }

/// App-wide state: profiles, settings, connection lifecycle.
class VpnController extends ChangeNotifier {
  VpnController(this._store, {VpnEngine? engine})
      : _engine = engine ?? VpnEngine.forPlatform();

  final Store _store;
  final VpnEngine _engine;

  List<Profile> profiles = [];
  Settings settings = Settings();
  VpnState state = VpnState.off;
  String? error;
  DateTime? connectedAt;
  TrafficSample traffic = const TrafficSample(0, 0);
  final List<int> downHistory = List.filled(40, 0, growable: true);
  StreamSubscription<TrafficSample>? _trafficSub;
  StreamSubscription<void>? _exitSub;

  Profile? get active {
    if (profiles.isEmpty) return null;
    return profiles.firstWhere(
      (p) => p.id == settings.activeProfileId,
      orElse: () => profiles.first,
    );
  }

  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> load() async {
    profiles = await _store.loadProfiles();
    settings = _store.loadSettings();
    _exitSub = _engine.onUnexpectedExit.listen((_) {
      // Core died under us: surface it (kill switch keeps the network closed in TUN mode).
      _setError('Соединение оборвалось');
    });
    notifyListeners();
  }

  // ---- profiles -----------------------------------------------------------

  Future<Profile> importLink(String raw) async {
    final p = ProfileParser.parse(raw);
    profiles = [...profiles, p];
    settings.activeProfileId ??= p.id;
    await _persist();
    return p;
  }

  Future<void> selectProfile(String id) async {
    settings.activeProfileId = id;
    await _persist();
    if (state == VpnState.on) await reconnect();
  }

  Future<void> removeProfile(String id) async {
    profiles = profiles.where((p) => p.id != id).toList();
    if (settings.activeProfileId == id) {
      settings.activeProfileId = profiles.isEmpty ? null : profiles.first.id;
    }
    await _persist();
    notifyListeners();
  }

  // ---- settings -----------------------------------------------------------

  Future<void> update(void Function(Settings s) change) async {
    final wasOn = state == VpnState.on;
    change(settings);
    await _persist();
    notifyListeners();
    if (wasOn) await reconnect();
  }

  Future<void> _persist() async {
    await _store.saveProfiles(profiles);
    await _store.saveSettings(settings);
    notifyListeners();
  }

  // ---- connection ---------------------------------------------------------

  Future<void> toggle() async {
    if (state == VpnState.connecting) return;
    if (state == VpnState.on) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    final p = active;
    if (p == null) {
      _setError('Сначала добавьте сервер');
      return;
    }
    state = VpnState.connecting;
    error = null;
    notifyListeners();
    try {
      final cfg = SingBoxConfig.buildJson(
        p,
        ConfigOptions(
          recipe: settings.recipe,
          mode: (!isDesktop || settings.fullTunnel)
              ? CaptureMode.tun
              : CaptureMode.systemProxy,
          killSwitch: settings.killSwitch,
          autoSwitch: settings.autoSwitch,
          selectedDomains: settings.selectedDomains,
        ),
      );
      await _engine.start(cfg);
      state = VpnState.on;
      connectedAt = DateTime.now();
      _trafficSub?.cancel();
      _trafficSub = _engine.traffic.listen((t) {
        traffic = t;
        downHistory
          ..removeAt(0)
          ..add(t.down);
        notifyListeners();
      });
      notifyListeners();
    } on EngineException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('$e');
    }
  }

  Future<void> disconnect() async {
    await _trafficSub?.cancel();
    _trafficSub = null;
    await _engine.stop();
    state = VpnState.off;
    connectedAt = null;
    traffic = const TrafficSample(0, 0);
    downHistory.fillRange(0, downHistory.length, 0);
    notifyListeners();
  }

  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }

  void _setError(String msg) {
    state = VpnState.error;
    error = msg;
    notifyListeners();
  }

  /// "Extinguish": stop, then wipe every profile and secret.
  Future<void> extinguish() async {
    await disconnect();
    await _store.wipeAll();
    profiles = [];
    settings = Settings();
    state = VpnState.off;
    notifyListeners();
  }

  @override
  void dispose() {
    _trafficSub?.cancel();
    _exitSub?.cancel();
    _engine.stop();
    super.dispose();
  }

  // Convenience for the UI.
  String get recipeTitle => settings.recipe.title;
}
