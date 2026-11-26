// wokok-box: your own ngrok, plus Guard in the terminal.
//   dart compile exe bin/wokok_box.dart -o wokok-box
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wokok_vpn/box/guard/analyzer.dart';
import 'package:wokok_vpn/box/ssh/box_ssh.dart';
import 'package:wokok_vpn/box/tunnel/tunnel_proxy.dart';
import 'package:wokok_vpn/box/tunnel/tunnel_session.dart';

const usage = '''
Wokok Box

  wokok-box login [user@]host [--ssh-port 22] [--key файл]
      один раз: сохранить сервер (пароль не хранится, выдаётся ключ)
  wokok-box share <порт> [--name имя] [--ttl 1h|1d|forever] [--password слово]
                         [--guests] [--domain dev.example.com]
      публичная HTTPS-ссылка на ваш localhost
  wokok-box check "ссылка или сообщение"
      проверить на мошенничество (на этом компьютере)
''';

File get configFile {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  return File('$home${Platform.pathSeparator}.wokok-box.json');
}

Never fail(String message) {
  stderr.writeln('✖ $message');
  exit(1);
}

/// `--flag value` and bare flags.
(List<String>, Map<String, String>) parseArgs(List<String> args) {
  final rest = <String>[];
  final opts = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      rest.add(a);
    } else if (a == '--guests') {
      opts['guests'] = '1';
    } else if (i + 1 < args.length) {
      opts[a.substring(2)] = args[++i];
    } else {
      fail('Нет значения у $a');
    }
  }
  return (rest, opts);
}

Duration? parseTtl(String s) {
  if (s == 'forever') return null;
  final m = RegExp(r'^(\d+)([mhd])$').firstMatch(s);
  if (m == null) fail('Срок: 30m, 1h, 1d или forever');
  final n = int.parse(m.group(1)!);
  return switch (m.group(2)) {
    'm' => Duration(minutes: n),
    'h' => Duration(hours: n),
    _ => Duration(days: n),
  };
}

void save(ServerAccess a) {
  configFile.writeAsStringSync(jsonEncode(a.toJson()));
  if (!Platform.isWindows) Process.runSync('chmod', ['600', configFile.path]);
}

String readSecret(String prompt) {
  stdout.write(prompt);
  final tty = stdin.hasTerminal;
  if (tty) stdin.echoMode = false;
  final line = stdin.readLineSync() ?? '';
  if (tty) {
    stdin.echoMode = true;
    stdout.writeln();
  }
  return line;
}

Future<void> login(List<String> rest, Map<String, String> o) async {
  if (rest.isEmpty) fail('Укажите сервер: wokok-box login root@1.2.3.4');
  final parts = rest.first.split('@');
  final access = ServerAccess(
    id: 'cli',
    name: parts.last,
    host: parts.last,
    user: parts.length > 1 ? parts.first : 'root',
    port: int.tryParse(o['ssh-port'] ?? '') ?? 22,
  );
  if (o['key'] != null) {
    access.privateKey = File(o['key']!).readAsStringSync();
  } else {
    access.password = readSecret('Пароль ${access.user}@${access.host}: ');
  }
  final ssh = await BoxSsh.connect(access);
  if (!access.hasKey) await ssh.issueKey();
  await ssh.ensureAgent();
  await ssh.close();
  save(access);
  stdout.writeln('✔ Сервер сохранён. Теперь: wokok-box share 3000');
}

Future<void> share(List<String> rest, Map<String, String> o) async {
  final port = int.tryParse(rest.isEmpty ? '' : rest.first);
  if (port == null || port < 1 || port > 65535) fail('Укажите порт: wokok-box share 3000');
  if (!configFile.existsSync()) fail('Сначала: wokok-box login root@ваш-сервер');
  final access = ServerAccess.fromJson(
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>);
  final ttl = parseTtl(o['ttl'] ?? '1h');
  var name = o['name'] ?? TunnelSession.randomName();
  String? domain;
  if (o['domain'] != null) {
    domain = '$name.${o['domain']}';
    if (!await TunnelSession.domainPointsTo(domain, access.host)) {
      fail('$domain не указывает на сервер. Добавьте DNS-запись: *.${o['domain']} A <IP сервера>');
    }
  }
  final session = await TunnelSession.open(
    access,
    TunnelRules(
      localPort: port,
      expiresAt: ttl == null ? null : DateTime.now().add(ttl),
      password: o['password'],
      guests: o.containsKey('guests'),
    ),
    name: name,
    domain: domain,
    onLine: stdout.writeln,
  );
  save(access); // keeps the pinned host key
  stdout.writeln('\n✔ ${session.url}  →  localhost:$port');
  stdout.writeln('  ${ttl == null ? 'без срока' : 'живёт ${o['ttl'] ?? '1h'}'}'
      '${o['password'] != null ? ' · под паролем' : ''}'
      '${o.containsKey('guests') ? ' · гости могут оставлять заметки' : ''}');
  stdout.writeln('  Ctrl+C — закрыть\n');

  var seenId = 0;
  var seenNotes = 0;
  final printed = <int>{};
  session.proxy.changes.listen((_) {
    for (final r in session.proxy.requests.reversed) {
      if (r.status == null || printed.contains(r.id)) continue;
      printed.add(r.id);
      seenId = r.id;
      stdout.writeln('  ${r.method.padRight(6)} ${r.status}  ${r.millis} мс  ${r.uri}');
    }
    while (seenNotes < session.proxy.notes.length) {
      final n = session.proxy.notes[session.proxy.notes.length - 1 - seenNotes++];
      stdout.writeln('  💬 ${n.author.isEmpty ? 'Гость' : n.author} (${n.page}): ${n.text}');
    }
    if (printed.length > 1000) printed.removeWhere((id) => id < seenId - 500);
  });
  final sigint = ProcessSignal.sigint.watch().listen((_) => session.close());
  stdout.writeln(await session.done);
  await sigint.cancel();
  exit(0);
}

Future<void> main(List<String> args) async {
  final (rest, opts) = parseArgs(args.skip(1).toList());
  try {
    switch (args.isEmpty ? '' : args.first) {
      case 'login':
        await login(rest, opts);
      case 'share':
        await share(rest, opts);
      case 'check':
        if (rest.isEmpty) fail('Что проверить?');
        final v = Guard.check(rest.join(' '));
        stdout.writeln('${switch (v.level) { Level.stop => '🔴', Level.careful => '🟡', Level.ok => '🟢' }} ${v.title}');
        for (final r in v.reasons) {
          stdout.writeln('  • ${r.title}: ${r.explain}');
        }
        stdout.writeln(v.advice);
        exit(v.level == Level.stop ? 2 : 0);
      default:
        stdout.write(usage);
    }
  } on BoxException catch (e) {
    fail(e.message);
  }
}
