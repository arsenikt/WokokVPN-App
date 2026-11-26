/// Where connections come from: the VPN core (all platforms, with byte counts)
/// or the operating system (Windows / macOS / Linux, no VPN needed).
library;

import 'dart:convert';
import 'dart:io';

import 'ledger.dart';

abstract class Collector {
  String get title;
  Future<List<Observation>> snapshot();
}

/// sing-box Clash API: `GET /connections`.
class CoreCollector implements Collector {
  CoreCollector({this.apiPort = 19090});
  final int apiPort;

  @override
  String get title => 'через ядро VPN';

  @override
  Future<List<Observation>> snapshot() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:$apiPort/connections'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      return parse(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      c.close(force: true);
    }
  }

  static List<Observation> parse(Map<String, dynamic> j) {
    final out = <Observation>[];
    for (final raw in (j['connections'] as List? ?? const [])) {
      final m = raw as Map;
      final meta = (m['metadata'] as Map?) ?? const {};
      var host = (meta['host'] ?? '').toString();
      if (host.isEmpty) host = (meta['destinationIP'] ?? '').toString();
      if (host.isEmpty || isLocal(host)) continue;
      out.add(Observation(
        id: m['id'].toString(),
        app: appName((meta['processPath'] ?? '').toString()),
        host: host,
        upload: (m['upload'] as num?)?.toInt() ?? 0,
        download: (m['download'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  /// `C:\a\b\app.exe (user)` or an Android package name -> short name.
  static String appName(String path) {
    var p = path.replaceAll(RegExp(r'\s*\([^()]*\)$'), '').trim();
    if (p.isEmpty) return 'Неизвестное приложение';
    p = p.split(RegExp(r'[\\/]')).last;
    return p;
  }
}

bool isLocal(String ip) {
  if (ip == 'localhost' || ip == '::1' || ip == '::' || ip == '*') return true;
  if (ip.startsWith('127.') || ip.startsWith('10.') || ip.startsWith('192.168.') || ip.startsWith('169.254.') || ip.startsWith('0.')) return true;
  if (ip.startsWith('fe80:') || ip.startsWith('fd')  && ip.contains(':')) return true;
  final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
  if (m != null) {
    final n = int.parse(m.group(1)!);
    if (n >= 16 && n <= 31) return true;
  }
  final first = int.tryParse(ip.split('.').first);
  return first != null && first >= 224 && ip.split('.').length == 4;
}

/// Windows: netstat for sockets, tasklist for names, the DNS cache for hosts.
class WindowsCollector implements Collector {
  Map<int, String> _names = {};
  Map<String, String> _dns = {};
  DateTime _dnsAt = DateTime(0);

  @override
  String get title => 'через Windows';

  @override
  Future<List<Observation>> snapshot() async {
    final net = await Process.run('netstat', ['-ano'], stdoutEncoding: latin1);
    final rows = parseNetstat(net.stdout as String);
    if (rows.any((r) => !_names.containsKey(r.$1))) {
      final t = await Process.run('tasklist', ['/fo', 'csv', '/nh'], stdoutEncoding: latin1);
      _names = parseTasklist(t.stdout as String);
    }
    if (DateTime.now().difference(_dnsAt) > const Duration(seconds: 20)) {
      _dnsAt = DateTime.now();
      final d = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Get-DnsClientCache | Where-Object { $_.Type -eq 1 -or $_.Type -eq 28 } | ForEach-Object { "$($_.Data)|$($_.Entry)" }',
      ], stdoutEncoding: latin1);
      // keep older names: the cache expires faster than connections do
      _dns = {..._dns, ...parseDns(d.stdout as String)};
    }
    return [
      for (final (pid, remote, local) in rows)
        if (_names[pid] != null)
          Observation(id: '$pid/$local/$remote', app: _names[pid]!, host: _dns[remote] ?? remote),
    ];
  }

  /// (pid, remote ip, local endpoint) of established TCP connections.
  static List<(int, String, String)> parseNetstat(String text) {
    final out = <(int, String, String)>[];
    for (final line in const LineSplitter().convert(text)) {
      final p = line.trim().split(RegExp(r'\s+'));
      if (p.length != 5 || p[0] != 'TCP') continue;
      // the state column is localised, so recognise it by the remote end
      final colon = p[2].lastIndexOf(':');
      if (colon < 0 || p[2].substring(colon + 1) == '0') continue;
      final ip = p[2].substring(0, colon).replaceAll('[', '').replaceAll(']', '');
      final pid = int.tryParse(p[4]);
      if (pid == null || pid == 0 || isLocal(ip)) continue;
      out.add((pid, ip, p[1]));
    }
    return out;
  }

  static Map<int, String> parseTasklist(String csv) => {
        for (final m in RegExp(r'^"([^"]*)","(\d+)"', multiLine: true).allMatches(csv))
          int.parse(m.group(2)!): m.group(1)!,
      };

  static Map<String, String> parseDns(String text) {
    final out = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final p = line.trim().split('|');
      if (p.length == 2 && p[0].isNotEmpty) out[p[0]] = p[1];
    }
    return out;
  }
}

/// macOS / Linux: lsof.
class UnixCollector implements Collector {
  final Map<String, String> _reverse = {};

  @override
  String get title => 'через систему';

  @override
  Future<List<Observation>> snapshot() async {
    final r = await Process.run('lsof', ['-nP', '-iTCP', '-sTCP:ESTABLISHED', '-F', 'pcn']);
    final rows = parseLsof(r.stdout as String);
    // a few reverse lookups per pass keep it light
    var budget = 8;
    for (final (_, _, ip) in rows) {
      if (budget == 0) break;
      if (_reverse.containsKey(ip)) continue;
      budget--;
      try {
        final a = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 700));
        _reverse[ip] = a.host;
      } catch (_) {
        _reverse[ip] = ip;
      }
    }
    return [
      for (final (app, endpoint, ip) in rows)
        Observation(id: '$app/$endpoint', app: app, host: _reverse[ip] ?? ip),
    ];
  }

  static List<(String, String, String)> parseLsof(String text) {
    final out = <(String, String, String)>[];
    var app = '';
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      final v = line.substring(1);
      if (line[0] == 'c') app = v.replaceAll(r'\x20', ' ');
      if (line[0] == 'n' && v.contains('->')) {
        final remote = v.split('->').last;
        final ip = remote
            .substring(0, remote.lastIndexOf(':'))
            .replaceAll('[', '')
            .replaceAll(']', '');
        if (!isLocal(ip)) out.add((app, v, ip));
      }
    }
    return out;
  }
}
