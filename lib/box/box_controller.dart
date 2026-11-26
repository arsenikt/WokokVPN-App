import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/vpn_controller.dart';
import 'guard/analyzer.dart';
import 'spy/collectors.dart';
import 'spy/ledger.dart';
import 'spy/trackers.dart';
import 'ssh/box_ssh.dart';
import 'tunnel/tunnel_proxy.dart';
import 'tunnel/tunnel_session.dart';

/// Someone to ask when a message looks suspicious.
class Helper {
  Helper(this.name, this.phone);
  final String name;
  final String phone;
}

enum Audience { unset, me, parents }

/// State of everything in the box that is not the VPN itself.
class BoxController extends ChangeNotifier {
  BoxController(this.vpn, this._prefs, this._secure, {this.spyFile});

  final VpnController vpn;
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final File? spyFile;

  static const _kServers = 'box.servers.v1';

  static Future<BoxController> open(VpnController vpn) async {
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}${Platform.pathSeparator}spy.json');
    } catch (_) {/* tests have no platform paths */}
    final c = BoxController(vpn, await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
        spyFile: file);
    await c.load();
    return c;
  }

  Audience audience = Audience.unset;
  List<ServerAccess> servers = [];
  Helper? helper;
  Set<int> lessonsPassed = {};

  Future<void> load() async {
    audience = Audience.values.asNameMap()[_prefs.getString('box.audience')] ?? Audience.unset;
    final name = _prefs.getString('box.helperName');
    final phone = _prefs.getString('box.helperPhone');
    helper = name == null || phone == null ? null : Helper(name, phone);
    lessonsPassed = {
      for (final s in _prefs.getStringList('box.lessons') ?? const <String>[]) int.parse(s),
    };
    try {
      final raw = await _secure.read(key: _kServers);
      if (raw != null) {
        servers = [
          for (final e in jsonDecode(raw) as List)
            ServerAccess.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
      }
    } catch (_) {/* unreadable storage: start empty */}
    try {
      final f = spyFile;
      if (f != null && await f.exists()) {
        spy.loadJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {
      spy.clear();
    }
    notifyListeners();
    if (_prefs.getBool('box.spyOn') ?? false) startSpy();
  }

  Future<void> setAudience(Audience a) async {
    audience = a;
    await _prefs.setString('box.audience', a.name);
    notifyListeners();
  }

  // ---- servers ------------------------------------------------------------

  Future<void> saveServer(ServerAccess a) async {
    servers = [...servers.where((s) => s.id != a.id), a];
    await _persistServers();
  }

  Future<void> removeServer(String id) async {
    servers = servers.where((s) => s.id != id).toList();
    await _persistServers();
  }

  Future<void> _persistServers() async {
    await _secure.write(
        key: _kServers, value: jsonEncode([for (final s in servers) s.toJson()]));
    notifyListeners();
  }

  /// Connects, remembering the host key on first contact.
  Future<BoxSsh> connect(ServerAccess a) async {
    final firstContact = a.hostKey == null;
    final ssh = await BoxSsh.connect(a);
    if (firstContact && servers.any((s) => s.id == a.id)) await _persistServers();
    return ssh;
  }

  // ---- tunnel -------------------------------------------------------------

  TunnelSession? tunnel;
  String? tunnelEnded;
  StreamSubscription<void>? _tunnelSub;

  Future<void> openTunnel(ServerAccess server, TunnelRules rules,
      {String? name, String? domain, LineSink? onLine}) async {
    await closeTunnel();
    final t = await TunnelSession.open(server, rules,
        name: name, domain: domain, onLine: onLine);
    await _persistServers(); // pinned host key
    tunnel = t;
    tunnelEnded = null;
    _tunnelSub = t.proxy.changes.listen((_) => notifyListeners());
    unawaited(t.done.then((reason) {
      if (tunnel != t) return;
      tunnel = null;
      tunnelEnded = reason;
      _tunnelSub?.cancel();
      notifyListeners();
    }));
    notifyListeners();
  }

  Future<void> closeTunnel() async => tunnel?.close();

  // ---- spy check ----------------------------------------------------------

  final SpyLedger spy = SpyLedger();
  bool spying = false;
  String spySource = '';
  String? spyError;
  Timer? _spyTimer;
  bool _sampling = false;
  int _ticks = 0;
  Collector? _system;

  void startSpy() {
    if (spying) return;
    spying = true;
    unawaited(_prefs.setBool('box.spyOn', true));
    _spyTimer = Timer.periodic(const Duration(seconds: 4), (_) => sampleSpy());
    unawaited(sampleSpy());
    notifyListeners();
  }

  Future<void> stopSpy() async {
    spying = false;
    _spyTimer?.cancel();
    await _prefs.setBool('box.spyOn', false);
    await _saveSpy();
    notifyListeners();
  }

  Collector? _collector() {
    if (vpn.state == VpnState.on) return CoreCollector();
    if (Platform.isWindows) return _system ??= WindowsCollector();
    if (Platform.isMacOS || Platform.isLinux) return _system ??= UnixCollector();
    return null;
  }

  Future<void> sampleSpy() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final c = _collector();
      if (c == null) {
        spySource = '';
        spyError = 'Включите VPN: на телефоне слежку видно через ядро VPN.';
      } else {
        spySource = c.title;
        spy.record(await c.snapshot());
        spyError = null;
        if (++_ticks % 15 == 0) await _saveSpy();
      }
    } catch (e) {
      spyError = 'Не удалось получить список соединений';
    } finally {
      _sampling = false;
    }
    notifyListeners();
  }

  Future<void> _saveSpy() async {
    try {
      await spyFile?.writeAsString(jsonEncode(spy.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> trustApp(String app) async {
    spy.trusted.add(app);
    spy.alerts.removeWhere((a) => a.app == app);
    await _saveSpy();
    notifyListeners();
  }

  /// "Put the lid on": block every tracker an app talks to.
  List<String> trackerDomains(AppStat a) => {
        for (final h in a.trackers) TrackerDb.find(h.host)!.suffix,
      }.toList();

  bool covered(AppStat a) {
    final d = trackerDomains(a);
    return d.isNotEmpty && d.every(vpn.settings.blockedDomains.contains);
  }

  Future<void> block(Iterable<String> domains) => vpn.update((s) => s.blockedDomains =
      {...s.blockedDomains, ...domains}.toList());

  Future<void> unblock(Iterable<String> domains) {
    final gone = domains.toSet();
    return vpn.update((s) => s.blockedDomains =
        s.blockedDomains.where((d) => !gone.contains(d)).toList());
  }

  // ---- guard --------------------------------------------------------------

  /// Checks text and, with the shield on, feeds bad hosts to the VPN.
  Future<Verdict> check(String text) async {
    final v = Guard.check(text);
    if (v.level == Level.stop && vpn.settings.shield) {
      final fresh = v.badHosts.where((h) => !vpn.settings.shieldDomains.contains(h)).toList();
      if (fresh.isNotEmpty) {
        await vpn.update((s) => s.shieldDomains = [...s.shieldDomains, ...fresh]);
      }
    }
    return v;
  }

  Future<void> setHelper(String name, String phone) async {
    helper = Helper(name.trim(), phone.trim());
    await _prefs.setString('box.helperName', helper!.name);
    await _prefs.setString('box.helperPhone', helper!.phone);
    notifyListeners();
  }

  Future<void> passLesson(int i) async {
    lessonsPassed.add(i);
    await _prefs.setStringList('box.lessons', [for (final n in lessonsPassed) '$n']);
    notifyListeners();
  }

  // ---- extinguish ---------------------------------------------------------

  Future<void> extinguish() async {
    await closeTunnel();
    _spyTimer?.cancel();
    spying = false;
    spy.clear();
    try {
      await spyFile?.delete();
    } catch (_) {}
    await vpn.extinguish(); // clears secure storage and preferences
    servers = [];
    helper = null;
    lessonsPassed = {};
    audience = Audience.unset;
    notifyListeners();
  }

  @override
  void dispose() {
    _spyTimer?.cancel();
    _tunnelSub?.cancel();
    super.dispose();
  }
}
