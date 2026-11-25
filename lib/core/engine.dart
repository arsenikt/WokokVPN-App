import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class TrafficSample {
  const TrafficSample(this.up, this.down);
  final int up; // bytes/s
  final int down;
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Abstraction over "something that runs sing-box".
abstract class VpnEngine {
  /// Starts the core with the given JSON config. Throws [EngineException].
  Future<void> start(String configJson);
  Future<void> stop();
  Stream<TrafficSample> get traffic;
  Stream<void> get onUnexpectedExit;

  static VpnEngine forPlatform({int apiPort = 19090}) {
    if (Platform.isAndroid || Platform.isIOS) return MobileEngine(apiPort: apiPort);
    return DesktopEngine(apiPort: apiPort);
  }
}

/// Desktop: runs the bundled `sing-box` binary as a child process.
class DesktopEngine implements VpnEngine {
  DesktopEngine({this.apiPort = 19090});

  final int apiPort;
  Process? _proc;
  HttpClient? _http;
  final _traffic = StreamController<TrafficSample>.broadcast();
  final _exit = StreamController<void>.broadcast();
  bool _stopping = false;

  @override
  Stream<TrafficSample> get traffic => _traffic.stream;
  @override
  Stream<void> get onUnexpectedExit => _exit.stream;

  /// Looks for the core next to the executable (`core/`), then in app support.
  static Future<File?> findCore() async {
    final name = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir${Platform.pathSeparator}core${Platform.pathSeparator}$name',
      '$exeDir${Platform.pathSeparator}$name',
      // macOS app bundle: Contents/MacOS/../Resources/core
      '$exeDir/../Resources/core/$name',
    ];
    final support = await getApplicationSupportDirectory();
    candidates.add('${support.path}${Platform.pathSeparator}core${Platform.pathSeparator}$name');
    for (final c in candidates) {
      final f = File(c);
      if (await f.exists()) return f;
    }
    return null;
  }

  @override
  Future<void> start(String configJson) async {
    await stop();
    final core = await findCore();
    if (core == null) {
      throw EngineException(
          'Ядро sing-box не найдено рядом с приложением (папка core).');
    }
    final dir = await getApplicationSupportDirectory();
    final cfg = File('${dir.path}${Platform.pathSeparator}config.json');
    await cfg.create(recursive: true);
    await cfg.writeAsString(configJson);

    // Validate first so the user gets a readable error instead of a dead process.
    final check = await Process.run(core.path, ['check', '-c', cfg.path]);
    if (check.exitCode != 0) {
      throw EngineException('Конфиг не прошёл проверку: ${check.stderr}'.trim());
    }

    _stopping = false;
    final p = await Process.start(
      core.path,
      ['run', '-c', cfg.path, '-D', dir.path],
      runInShell: false,
    );
    _proc = p;
    final errBuf = StringBuffer();
    p.stderr.transform(utf8.decoder).listen(errBuf.write);
    p.stdout.drain<void>();
    unawaited(p.exitCode.then((code) {
      if (!_stopping && _proc == p) {
        _proc = null;
        _exit.add(null);
      }
    }));

    // Wait until the Clash API answers = core is up.
    final ok = await _waitForApi();
    if (!ok) {
      final err = errBuf.toString().trim();
      await stop();
      throw EngineException(err.isEmpty ? 'Ядро не запустилось' : err);
    }
    _watchTraffic();
  }

  Future<bool> _waitForApi() async {
    for (var i = 0; i < 30; i++) {
      if (_proc == null) return false;
      try {
        final c = HttpClient()..connectionTimeout = const Duration(milliseconds: 400);
        final req = await c.getUrl(Uri.parse('http://127.0.0.1:$apiPort/version'));
        final res = await req.close();
        await res.drain<void>();
        c.close(force: true);
        if (res.statusCode == 200) return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  void _watchTraffic() {
    _http?.close(force: true);
    final c = HttpClient();
    _http = c;
    () async {
      try {
        final req = await c.getUrl(Uri.parse('http://127.0.0.1:$apiPort/traffic'));
        final res = await req.close();
        await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.isEmpty) continue;
          final j = jsonDecode(line) as Map<String, dynamic>;
          _traffic.add(TrafficSample((j['up'] ?? 0) as int, (j['down'] ?? 0) as int));
        }
      } catch (_) {/* closed on stop */}
    }();
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _http?.close(force: true);
    _http = null;
    final p = _proc;
    _proc = null;
    if (p != null) {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    // Core clears the system proxy on exit; belt and braces on Windows.
    if (Platform.isWindows) {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f'
      ]);
    }
  }
}

/// Streams `{"up","down"}` samples from sing-box's Clash API, retrying while
/// the core is still coming up. Ends when the listener cancels.
Stream<TrafficSample> clashTrafficStream(int apiPort) async* {
  final client = HttpClient();
  try {
    var attempts = 0;
    while (attempts < 12) {
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$apiPort/traffic'));
        final res = await req.close();
        attempts = 0;
        await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.isEmpty) continue;
          final j = jsonDecode(line) as Map<String, dynamic>;
          yield TrafficSample((j['up'] ?? 0) as int, (j['down'] ?? 0) as int);
        }
        return;
      } on SocketException {
        attempts++;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  } finally {
    client.close(force: true);
  }
}

/// Android/iOS: talks to the native VpnService / Network Extension via channels.
/// Android: `WokokVpnService` runs sing-box (libbox) in-process.
class MobileEngine implements VpnEngine {
  MobileEngine({this.apiPort = 19090});

  final int apiPort;
  static const _method = MethodChannel('com.wokok.vpn/engine');
  static const _events = EventChannel('com.wokok.vpn/events');

  @override
  Stream<TrafficSample> get traffic => clashTrafficStream(apiPort);

  @override
  Stream<void> get onUnexpectedExit =>
      _events.receiveBroadcastStream().where((e) => e == 'stopped');

  @override
  Future<void> start(String configJson) async {
    try {
      await _method.invokeMethod<void>('start', {'config': configJson});
    } on PlatformException catch (e) {
      throw EngineException(e.message ?? 'Не удалось запустить VPN');
    } on MissingPluginException {
      throw EngineException('Нативное ядро для этой платформы не подключено');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on MissingPluginException {/* nothing running */}
  }
}
