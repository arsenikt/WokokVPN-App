import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../server_script.dart';

/// Access to one of the user's servers. The password is only needed until a
/// key is issued; after that it is dropped.
class ServerAccess {
  ServerAccess({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    this.user = 'root',
    this.password,
    this.privateKey,
    this.hostKey,
  });

  final String id;
  String name;
  String host;
  int port;
  String user;
  String? password;
  String? privateKey; // OpenSSH PEM
  String? hostKey; // pinned on first connect

  bool get hasKey => privateKey != null && privateKey!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'user': user,
        if (!hasKey && password != null) 'password': password,
        if (privateKey != null) 'privateKey': privateKey,
        if (hostKey != null) 'hostKey': hostKey,
      };

  factory ServerAccess.fromJson(Map<String, dynamic> j) => ServerAccess(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 22,
        user: (j['user'] as String?) ?? 'root',
        password: j['password'] as String?,
        privateKey: j['privateKey'] as String?,
        hostKey: j['hostKey'] as String?,
      );
}

class BoxException implements Exception {
  BoxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Wraps a value for a POSIX shell command line.
String shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

typedef LineSink = void Function(String line);

/// An SSH session to a server running the Wokok Box agent script.
class BoxSsh {
  BoxSsh._(this.client, this.access);

  final SSHClient client;
  final ServerAccess access;
  bool _agentReady = false;

  static const agentPath = '/usr/local/bin/wokok-box';

  static Future<BoxSsh> connect(ServerAccess a) async {
    var mismatch = false;
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(a.host, a.port,
          timeout: const Duration(seconds: 12));
      client = SSHClient(
        socket,
        username: a.user,
        identities: a.hasKey ? SSHKeyPair.fromPem(a.privateKey!) : null,
        onPasswordRequest: a.password == null ? null : () => a.password,
        onVerifyHostKey: (type, fingerprint) {
          final seen = '$type ${base64.encode(fingerprint)}';
          if (a.hostKey == null) {
            a.hostKey = seen; // trust on first use
            return true;
          }
          mismatch = a.hostKey != seen;
          return !mismatch;
        },
      );
      await client.authenticated.timeout(const Duration(seconds: 20));
      return BoxSsh._(client, a);
    } catch (e) {
      await client?.close();
      if (mismatch) {
        throw BoxException(
            'Отпечаток сервера изменился. Если вы переустановили сервер, удалите его и добавьте заново. Иначе кто-то может перехватывать соединение.');
      }
      if (e is SSHAuthError) {
        throw BoxException('Сервер не принял логин, пароль или ключ');
      }
      throw BoxException('Не удалось подключиться к ${a.host}:${a.port} ($e)');
    }
  }

  /// Runs [command], streaming output lines. Returns the exit code.
  Future<int> exec(String command, {List<int>? stdin, LineSink? onLine}) async {
    final s = await client.execute(command);
    Future<void> pump(Stream<Uint8List> src) => src
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((l) => onLine?.call(l));
    final out = pump(s.stdout);
    final err = pump(s.stderr);
    if (stdin != null) s.stdin.add(Uint8List.fromList(stdin));
    await s.stdin.close();
    await Future.wait([out, err]);
    await s.done;
    return s.exitCode ?? -1;
  }

  String _root(String command) =>
      access.user == 'root' ? command : 'sudo -n $command';

  /// Writes [bytes] to [path] on the server.
  Future<void> upload(String path, List<int> bytes) async {
    final errors = <String>[];
    final code = await exec('cat > ${shq(path)}',
        stdin: bytes, onLine: errors.add);
    if (code != 0) {
      throw BoxException('Не удалось загрузить файл: ${errors.join(' ')}');
    }
  }

  /// Installs or refreshes the agent script.
  Future<void> ensureAgent() async {
    if (_agentReady) return;
    final errors = <String>[];
    final code = await exec(
      _root('sh -c ${shq('cat > $agentPath.new && chmod 755 $agentPath.new && mv $agentPath.new $agentPath')}'),
      stdin: utf8.encode(boxServerScript),
      onLine: errors.add,
    );
    if (code != 0) {
      throw BoxException(errors.join(' ').contains('sudo')
          ? 'Нужен root или sudo без пароля'
          : 'Не удалось установить агента: ${errors.join(' ')}');
    }
    _agentReady = true;
  }

  /// Runs an agent command. Human-readable lines go to [onLine]; the last
  /// `@@JSON` line is returned decoded.
  Future<Map<String, dynamic>?> box(
    List<String> args, {
    List<int>? stdin,
    LineSink? onLine,
    Map<String, String> env = const {},
  }) async {
    await ensureAgent();
    Map<String, dynamic>? result;
    String lastError = '';
    final envPrefix = env.isEmpty
        ? ''
        : 'env ${env.entries.map((e) => '${e.key}=${shq(e.value)}').join(' ')} ';
    final code = await exec(
      _root('$envPrefix$agentPath ${args.map(shq).join(' ')}'),
      stdin: stdin,
      onLine: (line) {
        if (line.startsWith('@@JSON ')) {
          result = jsonDecode(line.substring(7)) as Map<String, dynamic>;
        } else {
          if (line.startsWith('! ')) lastError = line.substring(2);
          onLine?.call(line);
        }
      },
    );
    if (code != 0) {
      throw BoxException(
          lastError.isEmpty ? 'Команда на сервере не выполнилась ($code)' : lastError);
    }
    return result;
  }

  /// Switches from password to a key that only this app holds.
  Future<void> issueKey() async {
    final r = await box(['key']);
    final b64 = r?['key'] as String?;
    if (b64 == null) throw BoxException('Сервер не выдал ключ');
    access.privateKey = utf8.decode(base64.decode(b64));
    access.password = null;
  }

  Future<void> close() async => client.close();
}
