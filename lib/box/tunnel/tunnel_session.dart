import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../ssh/box_ssh.dart';
import 'tunnel_proxy.dart';

/// A live "delivery": SSH reverse forward -> local [TunnelProxy] -> your app,
/// published as HTTPS by Caddy on your server.
class TunnelSession {
  TunnelSession._(this.name, this.proxy, this._ssh, this._forward, this.url);

  final String name;
  final TunnelProxy proxy;
  final BoxSsh _ssh;
  final SSHRemoteForward _forward;
  final String url;

  bool _closed = false;
  Timer? _expiry;
  final _done = Completer<String>();

  /// Completes with a human reason when the tunnel goes away.
  Future<String> get done => _done.future;
  bool get closed => _closed;

  static const _dishes = [
    'noodle', 'dumpling', 'wonton', 'ramen', 'udon', 'tofu', 'ginger', 'sesame',
    'lychee', 'mango', 'basil', 'pepper', 'bamboo', 'lotus', 'miso', 'soba',
  ];

  static String randomName() {
    final r = Random.secure();
    return '${_dishes[r.nextInt(_dishes.length)]}-${1000 + r.nextInt(9000)}';
  }

  static final _nameRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,26}$');

  static Future<TunnelSession> open(
    ServerAccess server,
    TunnelRules rules, {
    String? name,
    String? domain,
    LineSink? onLine,
  }) async {
    final n = (name == null || name.isEmpty) ? randomName() : name.toLowerCase();
    if (!_nameRe.hasMatch(n)) {
      throw BoxException('Имя ссылки: латиница, цифры и дефис, до 27 символов');
    }
    final proxy = TunnelProxy(rules);
    await proxy.start();
    BoxSsh? ssh;
    try {
      onLine?.call('> Подключаюсь к серверу');
      ssh = await BoxSsh.connect(server);
      await ssh.ensureAgent();
      final forward = await ssh.client.forwardRemote(host: '127.0.0.1', port: 0);
      if (forward == null) {
        throw BoxException('Сервер запрещает обратные туннели (AllowTcpForwarding)');
      }
      forward.connections.listen((channel) => _pipe(channel, proxy.port));
      final r = await ssh.box(
        ['tunnel-open', n, '${forward.port}', if (domain != null && domain.isNotEmpty) domain],
        onLine: onLine,
      );
      final url = r?['url'] as String?;
      if (url == null) throw BoxException('Сервер не вернул ссылку');
      final session = TunnelSession._(n, proxy, ssh, forward, url);
      session._watch();
      return session;
    } catch (_) {
      await proxy.stop();
      await ssh?.close();
      rethrow;
    }
  }

  static Future<void> _pipe(SSHForwardChannel channel, int port) async {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      channel.stream.cast<List<int>>().listen(socket.add,
          onDone: () => socket.close(), onError: (_) => socket.destroy());
      socket.listen(channel.sink.add,
          onDone: () => channel.sink.close(), onError: (_) => channel.destroy());
      unawaited(socket.done.catchError((_) => socket));
    } catch (_) {
      channel.destroy();
    }
  }

  void _watch() {
    final until = proxy.rules.expiresAt;
    if (until != null) {
      _expiry = Timer(until.difference(DateTime.now()), () => close('Срок ссылки истёк'));
    }
    _ssh.client.done.then((_) => close('Связь с сервером прервалась'),
        onError: (_) => close('Связь с сервером прервалась'));
  }

  Future<void> close([String reason = 'Ссылка закрыта']) async {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    if (!_ssh.client.isClosed) {
      try {
        await _ssh.box(['tunnel-close', name]).timeout(const Duration(seconds: 15));
        await _ssh.client.cancelForwardRemote(_forward);
      } catch (_) {/* the doctor sweeps dead tunnels later */}
    }
    await _ssh.close();
    await proxy.stop();
    if (!_done.isCompleted) _done.complete(reason);
  }

  /// Checks that `*.domain` already points at the server.
  static Future<bool> domainPointsTo(String domain, String serverHost) async {
    try {
      final a = await InternetAddress.lookup(domain, type: InternetAddressType.IPv4);
      final b = await InternetAddress.lookup(serverHost, type: InternetAddressType.IPv4);
      return a.any((x) => b.any((y) => x.address == y.address));
    } on SocketException {
      return false;
    }
  }
}
