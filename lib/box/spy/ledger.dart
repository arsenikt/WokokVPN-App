/// Spy Check memory: receipt, night watch and leak trap. Pure Dart, kept only
/// on the device.
library;

import 'trackers.dart';

/// One observed connection. [id] is stable while the connection lives, so byte
/// counters can be turned into deltas.
class Observation {
  const Observation({
    required this.id,
    required this.app,
    required this.host,
    this.upload = 0,
    this.download = 0,
  });
  final String id;
  final String app;
  final String host;
  final int upload;
  final int download;
}

class HostStat {
  HostStat(this.host, this.first, this.last, [this.hits = 0, this.up = 0]);
  final String host;
  final DateTime first;
  DateTime last;
  int hits;
  int up;

  Tracker? get tracker => TrackerDb.find(host);
}

class HourStat {
  HourStat([this.hits = 0, this.up = 0]);
  int hits;
  int up;
}

class AppStat {
  AppStat(this.app, this.since);
  final String app;
  final DateTime since;
  final Map<String, HostStat> hosts = {};
  final Map<int, HourStat> hours = {}; // hours since epoch

  Iterable<HostStat> get trackers =>
      hosts.values.where((h) => h.tracker?.kind.isTracker ?? false);
  int get upload => hosts.values.fold(0, (n, h) => n + h.up);
  DateTime get lastSeen => hosts.values
      .fold(since, (t, h) => h.last.isAfter(t) ? h.last : t);

  int countOf(TrackerKind k) =>
      hosts.values.where((h) => h.tracker?.kind == k).length;

  /// 0 is silent, 100 is a walking billboard.
  int get score {
    var s = 0;
    for (final h in trackers) {
      s += h.tracker!.kind.weight * 3;
    }
    final unknownIp = hosts.keys.where(isBareIp).length;
    s += unknownIp > 10 ? 10 : unknownIp;
    return s > 100 ? 100 : s;
  }

  String get grade {
    final s = score;
    if (s == 0) return 'A';
    if (s <= 9) return 'B';
    if (s <= 24) return 'C';
    if (s <= 45) return 'D';
    if (s <= 70) return 'E';
    return 'F';
  }

  /// The punchline: "flashlight.exe стучится на 14 серверов".
  String get hook {
    final n = hosts.length;
    final t = trackers.length;
    final base = '$app стучится на $n ${plural(n, 'сервер', 'сервера', 'серверов')}';
    return t == 0 ? base : '$base, из них $t ${plural(t, 'следящий', 'следящих', 'следящих')}';
  }
}

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

bool isBareIp(String h) =>
    RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(h) || h.contains(':');

enum AlertKind { newOwner, leak }

class SpyAlert {
  SpyAlert(this.kind, this.app, this.text, this.time, [this.host = '']);
  final AlertKind kind;
  final String app;
  final String text;
  final DateTime time;
  final String host;

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'a': app,
        't': text,
        'w': time.millisecondsSinceEpoch,
        'h': host,
      };
  factory SpyAlert.fromJson(Map<String, dynamic> j) => SpyAlert(
        AlertKind.values.byName(j['k'] as String),
        j['a'] as String,
        j['t'] as String,
        DateTime.fromMillisecondsSinceEpoch(j['w'] as int),
        (j['h'] ?? '') as String,
      );
}

class NightReport {
  NightReport(this.from, this.to, this.requests, this.upload, this.apps);
  final DateTime from;
  final DateTime to;
  final int requests;
  final int upload;
  final List<(String, int, int)> apps; // app, requests, bytes up
}

class SpyLedger {
  final Map<String, AppStat> apps = {};
  final List<SpyAlert> alerts = [];

  /// Apps the user said are fine to be chatty.
  final Set<String> trusted = {};
  final Map<String, int> _lastUp = {};

  static const keepDays = 7;
  static const leakFloor = 5 * 1024 * 1024;
  static const learning = Duration(hours: 24);

  static int hourKey(DateTime t) => t.millisecondsSinceEpoch ~/ 3600000;

  static String formatBytes(int b) {
    if (b < 1024) return '$b Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
    return '${(b / 1048576).toStringAsFixed(1)} МБ';
  }

  /// Takes one snapshot of live connections. Returns alerts raised by it.
  List<SpyAlert> record(Iterable<Observation> snapshot, [DateTime? at]) {
    final now = at ?? DateTime.now();
    final fresh = <SpyAlert>[];
    final alive = <String>{};
    for (final o in snapshot) {
      if (o.host.isEmpty || o.app.isEmpty) continue;
      alive.add(o.id);
      final isNew = !_lastUp.containsKey(o.id);
      final delta = o.upload - (_lastUp[o.id] ?? 0);
      _lastUp[o.id] = o.upload;
      final up = delta > 0 ? delta : 0;

      final app = apps.putIfAbsent(o.app, () => AppStat(o.app, now));
      var host = app.hosts[o.host];
      if (host == null) {
        final t = TrackerDb.find(o.host);
        final known = app.hosts.values.any((h) => h.tracker?.owner == t?.owner);
        if (t != null && !known && now.difference(app.since) > learning && !trusted.contains(o.app)) {
          fresh.add(SpyAlert(AlertKind.newOwner, o.app,
              '${o.app} впервые связался с ${t.owner} (${t.kind.title}, ${t.country})', now, o.host));
        }
        host = app.hosts[o.host] = HostStat(o.host, now, now);
      }
      host
        ..last = now
        ..up += up;
      final hour = app.hours.putIfAbsent(hourKey(now), HourStat.new);
      if (isNew) {
        host.hits++;
        hour.hits++;
      }
      final before = hour.up;
      hour.up += up;
      final limit = leakLimit(app, now);
      if (before <= limit && hour.up > limit && !trusted.contains(o.app)) {
        final usual = _usual(app, now);
        fresh.add(SpyAlert(
            AlertKind.leak,
            o.app,
            '${o.app} отправил ${formatBytes(hour.up)} за час'
            '${isNight(now) ? ' ночью' : ''} (обычно ${formatBytes(usual)})',
            now,
            o.host));
      }
    }
    _lastUp.removeWhere((id, _) => !alive.contains(id));
    alerts.insertAll(0, fresh);
    if (alerts.length > 100) alerts.removeRange(100, alerts.length);
    _prune(now);
    return fresh;
  }

  static bool isNight(DateTime t) => t.hour >= 23 || t.hour < 7;

  int _usual(AppStat a, DateTime now) {
    final current = hourKey(now);
    final past = [
      for (final e in a.hours.entries)
        if (e.key != current) e.value.up,
    ];
    if (past.isEmpty) return 0;
    return past.reduce((x, y) => x + y) ~/ past.length;
  }

  /// Bytes per hour above which sending looks abnormal for this app.
  int leakLimit(AppStat a, DateTime now) {
    final floor = isNight(now) ? leakFloor : leakFloor * 4;
    final usual = _usual(a, now) * 3;
    return usual > floor ? usual : floor;
  }

  /// What happened during the most recent 23:00–07:00 window.
  NightReport night([DateTime? at]) {
    final now = at ?? DateTime.now();
    var start = DateTime(now.year, now.month, now.day, 23);
    if (now.hour < 23) start = start.subtract(const Duration(days: 1));
    final end = start.add(const Duration(hours: 8));
    final from = hourKey(start), to = hourKey(end);
    var requests = 0, upload = 0;
    final rows = <(String, int, int)>[];
    for (final a in apps.values) {
      var r = 0, u = 0;
      for (final e in a.hours.entries) {
        if (e.key >= from && e.key < to) {
          r += e.value.hits;
          u += e.value.up;
        }
      }
      if (r > 0 || u > 0) rows.add((a.app, r, u));
      requests += r;
      upload += u;
    }
    rows.sort((a, b) => b.$3 != a.$3 ? b.$3.compareTo(a.$3) : b.$2.compareTo(a.$2));
    return NightReport(start, end, requests, upload, rows);
  }

  /// Apps, nosiest first.
  List<AppStat> get ranking => apps.values.toList()
    ..sort((a, b) => b.score != a.score
        ? b.score.compareTo(a.score)
        : b.hosts.length.compareTo(a.hosts.length));

  void _prune(DateTime now) {
    final oldest = hourKey(now) - keepDays * 24;
    final cut = now.subtract(const Duration(days: keepDays));
    for (final a in apps.values) {
      a.hours.removeWhere((k, _) => k < oldest);
      a.hosts.removeWhere((_, h) => h.last.isBefore(cut));
    }
    apps.removeWhere((_, a) => a.hosts.isEmpty);
  }

  void clear() {
    apps.clear();
    alerts.clear();
    trusted.clear();
    _lastUp.clear();
  }

  Map<String, dynamic> toJson() => {
        'apps': [
          for (final a in apps.values)
            {
              'a': a.app,
              's': a.since.millisecondsSinceEpoch,
              'h': [
                for (final h in a.hosts.values)
                  [h.host, h.first.millisecondsSinceEpoch, h.last.millisecondsSinceEpoch, h.hits, h.up],
              ],
              'r': [
                for (final e in a.hours.entries) [e.key, e.value.hits, e.value.up],
              ],
            },
        ],
        'alerts': [for (final a in alerts) a.toJson()],
        'trusted': trusted.toList(),
      };

  void loadJson(Map<String, dynamic> j) {
    clear();
    DateTime at(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms as int);
    for (final raw in (j['apps'] as List? ?? const [])) {
      final m = raw as Map;
      final a = AppStat(m['a'] as String, at(m['s']));
      for (final h in m['h'] as List) {
        final r = h as List;
        a.hosts[r[0] as String] =
            HostStat(r[0] as String, at(r[1]), at(r[2]), r[3] as int, r[4] as int);
      }
      for (final h in m['r'] as List) {
        final r = h as List;
        a.hours[r[0] as int] = HourStat(r[1] as int, r[2] as int);
      }
      apps[a.app] = a;
    }
    for (final a in (j['alerts'] as List? ?? const [])) {
      alerts.add(SpyAlert.fromJson(Map<String, dynamic>.from(a as Map)));
    }
    trusted.addAll([for (final t in (j['trusted'] as List? ?? const [])) t as String]);
  }
}
