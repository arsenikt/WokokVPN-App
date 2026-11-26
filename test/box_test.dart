import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wokok_vpn/box/deploy/deploy.dart';
import 'package:wokok_vpn/box/guard/analyzer.dart';
import 'package:wokok_vpn/box/guard/lessons.dart';
import 'package:wokok_vpn/box/server_script.dart';
import 'package:wokok_vpn/box/spy/collectors.dart';
import 'package:wokok_vpn/box/spy/ledger.dart';
import 'package:wokok_vpn/box/spy/trackers.dart';
import 'package:wokok_vpn/box/tunnel/tunnel_proxy.dart';
import 'package:wokok_vpn/core/profile.dart';
import 'package:wokok_vpn/core/singbox_config.dart';

void main() {
  group('Guard', () {
    test('stops typical scams in three languages', () {
      for (final s in [
        'Ваша карта будет заблокирована в течение 1 часа. http://sber-secure.top/login',
        'Назовите код из СМС, чтобы отменить операцию',
        'Мам, это я, это мой новый номер. Срочно переведи деньги',
        'Your account is suspended. Verify your password at https://paypa1.com/signin',
        'Итно потврдете ја лозинката, картичката ќе биде блокирана',
        'https://google.com@evil.example.xyz/',
        'http://g00gle.com',
      ]) {
        expect(Guard.check(s).level, Level.stop, reason: s);
      }
    });

    test('leaves ordinary text and real sites alone', () {
      for (final s in [
        'Пап, буду поздно, не жди с ужином',
        'https://www.google.com/search?q=wok',
        'https://www.sberbank.ru/',
        'Напиши мне на ivan@example.com',
        'https://github.com/arsenikt/WokokVPN',
      ]) {
        expect(Guard.check(s).level, Level.ok, reason: s);
      }
    });

    test('collects hosts for the VPN shield and reads QR kinds', () {
      expect(Guard.check('http://sberbank-bonus.top/prize').badHosts, ['sberbank-bonus.top']);
      expect(Guard.check('0x0aA2d41976f087763a354d598D32c21E1983CbFD').level, Level.stop);
      expect(Guard.check('WIFI:T:nopass;S:free;;').level, Level.careful);
    });

    test('agrees with its own lessons', () {
      for (final l in lessons) {
        final level = Guard.check(l.text).level;
        expect(level != Level.ok, l.scam, reason: l.text);
      }
    });
  });

  group('Spy Check', () {
    test('matches trackers by suffix only', () {
      expect(TrackerDb.find('stats.g.doubleclick.net')?.owner, 'Google');
      expect(TrackerDb.find('mc.yandex.ru')?.kind, TrackerKind.analytics);
      expect(TrackerDb.find('notdoubleclick.net'), isNull);
    });

    test('grades, counts bytes once and springs the trap', () {
      final l = SpyLedger();
      final night = DateTime(2026, 11, 26, 2);
      Observation o(int up) =>
          Observation(id: '1', app: 'flashlight', host: 'x.applovin.com', upload: up);
      expect(l.record([o(1000)], night), isEmpty);
      final alerts = l.record([o(7 * 1024 * 1024)], night.add(const Duration(seconds: 4)));
      expect(alerts.single.kind, AlertKind.leak);
      expect(l.record([o(7 * 1024 * 1024)], night.add(const Duration(seconds: 8))), isEmpty);
      final a = l.apps['flashlight']!;
      expect(a.upload, 7 * 1024 * 1024);
      expect(a.grade, isNot('A'));
      expect(l.night(DateTime(2026, 11, 26, 9)).upload, 7 * 1024 * 1024);
      final copy = SpyLedger()..loadJson(jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>);
      expect(copy.apps['flashlight']!.upload, a.upload);
      expect(copy.alerts, hasLength(1));
    });

    test('parses system and core connection lists', () {
      final rows = WindowsCollector.parseNetstat('''
  TCP    192.168.1.5:50000    142.250.1.1:443    ESTABLISHED    42
  TCP    127.0.0.1:50001      127.0.0.1:80       ESTABLISHED    42
  TCP    0.0.0.0:135          0.0.0.0:0          LISTENING      4
''');
      expect(rows.single.$2, '142.250.1.1');
      expect(WindowsCollector.parseTasklist('"chrome.exe","42","Console","1","10 K"')[42], 'chrome.exe');
      expect(UnixCollector.parseLsof('p1\ncSafari\nn10.0.0.2:5000->17.0.0.1:443\n').single.$1, 'Safari');
      final core = CoreCollector.parse({
        'connections': [
          {
            'id': 'a',
            'upload': 5,
            'metadata': {'host': 'a.example', 'processPath': r'C:\x\app.exe (me)'},
          }
        ]
      });
      expect(core.single.app, 'app.exe');
    });

    test('the lid becomes a reject rule', () {
      final p = Profile(id: '1', name: 'n', host: 'h.example', port: 443, uuid: 'u', publicKey: 'k');
      final c = SingBoxConfig.build(p, const ConfigOptions(blockedDomains: ['applovin.com']));
      final rules = (c['route'] as Map)['rules'] as List;
      expect(rules.any((r) => (r as Map)['action'] == 'reject'), isTrue);
    });
  });

  group('Deploy', () {
    ServerReport report({String p443 = '', int ram = 1024}) => ServerReport.fromJson({
          'os': 'Ubuntu 24.04', 'ramMb': ram, 'diskMb': 20000, 'ip': '1.2.3.4', 'apt': true,
          'port80': '', 'port443': p443, 'vpn': p443 == 'xray', 'apps': <Object>[],
        });

    test('the check explains sharing 443 with the VPN', () {
      final lines = planDish(report(p443: 'xray'), const Dish(DishKind.site, name: 'shop'));
      expect(lines.any((l) => l.level == CheckLevel.block), isFalse);
      expect(lines.any((l) => l.text.contains('shop.1-2-3-4.sslip.io')), isTrue);
      expect(lines.any((l) => l.text.contains('HAProxy')), isTrue);
    });

    test('a foreign web server blocks the order', () {
      final lines = planDish(report(p443: 'nginx'), const Dish(DishKind.site, name: 'shop'));
      expect(lines.any((l) => l.level == CheckLevel.block), isTrue);
    });

    test('accepts repositories, rejects shell tricks', () {
      expect(gitSource('me/bot'), 'git:https://github.com/me/bot');
      expect(gitSource('https://x.example/a;rm -rf /'), isNull);
    });

    test('embedded agent is in sync with server/box.sh', () {
      final src = File('server/box.sh').readAsStringSync().replaceAll('\r\n', '\n');
      expect(boxServerScript.replaceAll('\r\n', '\n'), src,
          reason: 'run: python tools/embed_server.py');
    });
  });

  group('Tunnel proxy', () {
    late HttpServer app;
    final seen = <String>[];

    setUp(() async {
      seen.clear();
      app = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      app.listen((r) async {
        seen.add('${r.method} ${r.uri} ${await utf8.decoder.bind(r).join()}');
        r.response.headers.contentType = ContentType.html;
        r.response.write('<html><body>привет</body></html>');
        await r.response.close();
      });
    });
    tearDown(() => app.close(force: true));

    Future<(int, String, HttpClientResponse)> call(TunnelProxy p, String method, String path,
        {String body = '', Cookie? cookie}) async {
      final c = HttpClient();
      final req = await c.open(method, '127.0.0.1', p.port, path);
      req.followRedirects = false;
      if (cookie != null) req.cookies.add(cookie);
      req.add(utf8.encode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      c.close();
      return (res.statusCode, text, res);
    }

    test('forwards, logs, replays and takes guest notes', () async {
      final p = TunnelProxy(TunnelRules(localPort: app.port, guests: true));
      await p.start();
      final r = await call(p, 'POST', '/hook?a=1', body: 'data');
      expect(r.$1, 200);
      expect(r.$2, contains('привет'));
      expect(r.$2, contains('__wokok/note'));
      expect(r.$2.indexOf('<script>'), lessThan(r.$2.indexOf('</body>')));
      await p.replay(p.requests.single);
      expect(seen, ['POST /hook?a=1 data', 'POST /hook?a=1 data']);
      final n = await call(p, 'POST', '/__wokok/note',
          body: jsonEncode({'page': '/', 'author': 'A', 'text': 'кнопка уехала'}));
      expect(n.$1, 204);
      expect(p.notes.single.text, 'кнопка уехала');
      await p.stop();
    });

    test('guards with a password and expires', () async {
      final p = TunnelProxy(TunnelRules(localPort: app.port, password: 'лапша'));
      await p.start();
      expect((await call(p, 'GET', '/')).$1, 401);
      expect(seen, isEmpty);
      final login = await call(p, 'POST', '/__wokok/login',
          body: 'p=${Uri.encodeQueryComponent('лапша')}');
      expect(login.$1, 303);
      final cookie = login.$3.cookies.single;
      expect((await call(p, 'GET', '/', cookie: Cookie(cookie.name, cookie.value))).$1, 200);
      p.rules.expiresAt = DateTime.now().subtract(const Duration(seconds: 1));
      expect((await call(p, 'GET', '/')).$1, 410);
      await p.stop();
    });
  });
}
