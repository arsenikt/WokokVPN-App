import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class TunnelRules {
  TunnelRules({
    required this.localPort,
    this.localHost = '127.0.0.1',
    this.expiresAt,
    this.password,
    this.guests = false,
  });

  final int localPort;
  final String localHost;
  DateTime? expiresAt;
  final String? password;
  final bool guests;
}

/// One request seen by the tunnel; enough of it is kept to replay a webhook.
class RequestEntry {
  RequestEntry({
    required this.id,
    required this.time,
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.truncated,
    this.replay = false,
  });

  final int id;
  final DateTime time;
  final String method;
  final Uri uri; // path + query
  final Map<String, List<String>> headers;
  final Uint8List body;
  final bool truncated;
  final bool replay;
  int? status;
  int? millis;
}

class GuestNote {
  GuestNote(this.time, this.page, this.author, this.text);
  final DateTime time;
  final String page;
  final String author;
  final String text;
}

/// The local half of a tunnel: everything that arrives over SSH passes through
/// here, so passwords, lifetime, the live log and guest notes need nothing on
/// the server.
class TunnelProxy {
  TunnelProxy(this.rules);

  final TunnelRules rules;
  static const maxLogged = 200;
  static const maxBody = 256 * 1024;
  static const _cookie = 'wokok_pass';

  final List<RequestEntry> requests = [];
  final List<GuestNote> notes = [];
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = null;
  final String _session = _randomToken();
  int _nextId = 1;
  final List<DateTime> _wrong = [];

  int get port => _server!.port;
  bool get expired =>
      rules.expiresAt != null && DateTime.now().isAfter(rules.expiresAt!);

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.autoCompress = false;
    s.serverHeader = null;
    s.defaultResponseHeaders.clear();
    _server = s;
    s.listen((r) => _handle(r).catchError((Object _) {}));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
    if (!_changes.isClosed) await _changes.close();
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _page(HttpRequest r, int status, String title, String body) async {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('cache-control', 'no-store')
      ..write('<!doctype html><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width,initial-scale=1">'
          '<title>$title</title><body style="background:#1b1614;color:#f6ead2;'
          'font:17px system-ui;display:grid;place-items:center;min-height:90vh;'
          'margin:0;text-align:center"><div><div style="font-size:64px">🥡</div>'
          '<h2>$title</h2>$body</div>');
    await r.response.close();
  }

  Future<void> _handle(HttpRequest r) async {
    if (expired) {
      return _page(r, HttpStatus.gone, 'Срок ссылки истёк',
          '<p>Попросите хозяина выдать новую.</p>');
    }
    if (rules.password != null && rules.password!.isNotEmpty) {
      final ok = r.cookies.any((c) => c.name == _cookie && c.value == _session);
      if (!ok) return _login(r);
    }
    if (rules.guests && r.uri.path == '/__wokok/note' && r.method == 'POST') {
      return _note(r);
    }
    if (WebSocketTransformer.isUpgradeRequest(r)) return _webSocket(r);

    final bytes = BytesBuilder(copy: false);
    var truncated = false;
    final chunks = <List<int>>[];
    await for (final c in r) {
      chunks.add(c);
      if (bytes.length + c.length <= maxBody) {
        bytes.add(c);
      } else {
        truncated = true;
      }
    }
    final headers = <String, List<String>>{};
    r.headers.forEach((k, v) => headers[k] = List.of(v));
    headers[HttpHeaders.cookieHeader] = [
      for (final h in headers[HttpHeaders.cookieHeader] ?? const <String>[])
        h.split(';').where((p) => !p.trim().startsWith('$_cookie=')).join(';'),
    ]..removeWhere((h) => h.trim().isEmpty);

    final entry = RequestEntry(
      id: _nextId++,
      time: DateTime.now(),
      method: r.method,
      uri: r.uri,
      headers: headers,
      body: bytes.takeBytes(),
      truncated: truncated,
    );
    _log(entry);

    final watch = Stopwatch()..start();
    try {
      final res = await _forward(r.method, r.uri, headers, chunks);
      entry
        ..status = res.statusCode
        ..millis = watch.elapsedMilliseconds;
      _changed();
      await _respond(r, res);
    } on SocketException {
      entry
        ..status = HttpStatus.badGateway
        ..millis = watch.elapsedMilliseconds;
      _changed();
      await _page(r, HttpStatus.badGateway, 'Кухня ещё не готовит',
          '<p>На компьютере хозяина никто не отвечает на порту ${rules.localPort}.</p>');
    }
  }

  Future<HttpClientResponse> _forward(String method, Uri uri,
      Map<String, List<String>> headers, List<List<int>> body) async {
    final target = Uri(
      scheme: 'http',
      host: rules.localHost,
      port: rules.localPort,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    );
    final req = await _client.openUrl(method, target);
    req.followRedirects = false;
    final publicHost = headers['host']?.first;
    headers.forEach((k, v) {
      if (const {'host', 'connection', 'content-length', 'transfer-encoding'}.contains(k)) return;
      if (k == 'accept-encoding' && rules.guests) return;
      req.headers.removeAll(k);
      for (final value in v) {
        req.headers.add(k, value);
      }
    });
    // Dev servers reject unknown Host headers; present ourselves as local.
    req.headers.set('host', 'localhost:${rules.localPort}');
    if (publicHost != null) {
      req.headers
        ..set('x-forwarded-host', publicHost)
        ..set('x-forwarded-proto', 'https');
    }
    if (rules.guests) req.headers.set('accept-encoding', 'identity');
    final length = body.fold<int>(0, (n, c) => n + c.length);
    if (length > 0 || const {'POST', 'PUT', 'PATCH'}.contains(method)) {
      req.contentLength = length;
      for (final c in body) {
        req.add(c);
      }
    }
    return req.close();
  }

  Future<void> _respond(HttpRequest r, HttpClientResponse res) async {
    final out = r.response;
    out.statusCode = res.statusCode;
    res.headers.forEach((k, v) {
      if (const {'connection', 'transfer-encoding', 'content-length'}.contains(k)) return;
      out.headers.removeAll(k);
      for (final value in v) {
        out.headers.add(k, value);
      }
    });
    final html = res.headers.contentType?.mimeType == 'text/html';
    final encoded = res.headers.value('content-encoding');
    if (rules.guests && html && (encoded == null || encoded == 'identity') && r.method != 'HEAD') {
      final data = await res.fold<BytesBuilder>(
          BytesBuilder(copy: false), (b, c) => b..add(c));
      final page = injectGuestWidget(data.takeBytes());
      out.contentLength = page.length;
      out.add(page);
    } else {
      if (res.contentLength >= 0) out.contentLength = res.contentLength;
      out.bufferOutput = false; // server-sent events must not stall
      await out.addStream(res);
    }
    await out.close();
  }

  Future<void> _webSocket(HttpRequest r) async {
    try {
      final protocols = r.headers['sec-websocket-protocol']
          ?.expand((v) => v.split(','))
          .map((v) => v.trim())
          .toList();
      final cookie = r.headers.value('cookie');
      final up = await WebSocket.connect(
        'ws://${rules.localHost}:${rules.localPort}${r.uri}',
        protocols: protocols,
        headers: {if (cookie != null) 'cookie': cookie},
      );
      final down = await WebSocketTransformer.upgrade(r,
          protocolSelector: up.protocol == null ? null : (_) => up.protocol!);
      up.listen(down.add, onDone: () => down.close(), onError: (_) => down.close());
      down.listen(up.add, onDone: () => up.close(), onError: (_) => up.close());
    } catch (_) {
      try {
        r.response.statusCode = HttpStatus.badGateway;
        await r.response.close();
      } catch (_) {}
    }
  }

  Future<void> _login(HttpRequest r) async {
    const form = '<form method="post" action="/__wokok/login">'
        '<input type="password" name="p" placeholder="Пароль" autofocus '
        'style="font:inherit;padding:10px;border-radius:10px;border:0"> '
        '<button style="font:inherit;padding:10px 16px;border-radius:10px;border:0;'
        'background:#ff7a1a">Открыть</button></form>';
    if (r.method == 'POST' && r.uri.path == '/__wokok/login') {
      final now = DateTime.now();
      _wrong.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
      if (_wrong.length >= 10) {
        return _page(r, HttpStatus.tooManyRequests, 'Слишком много попыток',
            '<p>Подождите минуту.</p>');
      }
      final body = await _readSmall(r, 4096);
      final given = Uri.splitQueryString(body)['p'] ?? '';
      if (given == rules.password) {
        r.response
          ..statusCode = HttpStatus.seeOther
          ..cookies.add(Cookie(_cookie, _session)
            ..path = '/'
            ..httpOnly = true
            ..secure = true)
          ..headers.set('location', '/');
        return r.response.close();
      }
      _wrong.add(now);
      return _page(r, HttpStatus.unauthorized, 'Неверный пароль', form);
    }
    return _page(r, HttpStatus.unauthorized, 'Закрытая кухня', form);
  }

  Future<String> _readSmall(HttpRequest r, int limit) async {
    final b = BytesBuilder();
    await for (final c in r) {
      if (b.length + c.length > limit) break;
      b.add(c);
    }
    return utf8.decode(b.takeBytes(), allowMalformed: true);
  }

  Future<void> _note(HttpRequest r) async {
    var status = HttpStatus.noContent;
    try {
      final j = jsonDecode(await _readSmall(r, 8192)) as Map<String, dynamic>;
      String clip(Object? v, int n) {
        final s = (v ?? '').toString().trim();
        return s.length > n ? s.substring(0, n) : s;
      }

      final text = clip(j['text'], 600);
      if (text.isEmpty) {
        status = HttpStatus.badRequest;
      } else {
        notes.insert(0, GuestNote(DateTime.now(), clip(j['page'], 200), clip(j['author'], 40), text));
        if (notes.length > 200) notes.removeLast();
        _changed();
      }
    } catch (_) {
      status = HttpStatus.badRequest;
    }
    r.response.statusCode = status;
    await r.response.close();
  }

  void _log(RequestEntry e) {
    requests.insert(0, e);
    if (requests.length > maxLogged) requests.removeLast();
    _changed();
  }

  /// Sends a logged request to the local app again (webhook debugging).
  Future<void> replay(RequestEntry old) async {
    if (old.truncated) {
      throw StateError('Тело запроса слишком большое для повтора');
    }
    final entry = RequestEntry(
      id: _nextId++,
      time: DateTime.now(),
      method: old.method,
      uri: old.uri,
      headers: old.headers,
      body: old.body,
      truncated: false,
      replay: true,
    );
    _log(entry);
    final watch = Stopwatch()..start();
    try {
      final res = await _forward(old.method, old.uri, old.headers, [old.body]);
      await res.drain<void>();
      entry.status = res.statusCode;
    } on SocketException {
      entry.status = HttpStatus.badGateway;
    }
    entry.millis = watch.elapsedMilliseconds;
    _changed();
  }

  static Uint8List injectGuestWidget(Uint8List page) {
    final tag = utf8.encode(_widget);
    // Find the last </body> without decoding the page (it may not be UTF-8).
    const needle = '</body';
    var at = -1;
    for (var i = page.length - needle.length; i >= 0 && at < 0; i--) {
      var hit = true;
      for (var k = 0; k < needle.length; k++) {
        if ((page[i + k] | (k < 2 ? 0 : 0x20)) != needle.codeUnitAt(k)) {
          hit = false;
          break;
        }
      }
      if (hit) at = i;
    }
    if (at < 0) at = page.length;
    return Uint8List.fromList(
        [...page.sublist(0, at), ...tag, ...page.sublist(at)]);
  }

  static const _widget = r'''
<script>(()=>{if(window.__wk)return;window.__wk=1;
const h=document.createElement('div');document.documentElement.appendChild(h);
const r=h.attachShadow({mode:'open'});
r.innerHTML=`<style>*{box-sizing:border-box;font:14px system-ui}
#b{position:fixed;right:16px;bottom:16px;z-index:2147483647;background:#ff7a1a;color:#1b1614;border:0;border-radius:24px;padding:12px 16px;box-shadow:0 4px 18px #0006;cursor:pointer}
#f{position:fixed;right:16px;bottom:72px;z-index:2147483647;width:280px;background:#2e2621;color:#f6ead2;padding:12px;border-radius:14px;display:none;box-shadow:0 8px 30px #0008}
input,textarea{width:100%;margin-bottom:8px;border:0;border-radius:8px;padding:8px;background:#f6ead2;color:#1b1614}
#s{background:#ffd23f;color:#1b1614;border:0;border-radius:8px;padding:8px 14px;cursor:pointer}</style>
<button id="b">💬 Заметка</button><div id="f"><input id="a" maxlength="40" placeholder="Ваше имя">
<textarea id="t" rows="4" maxlength="600" placeholder="Что поправить на этой странице?"></textarea><button id="s">Отправить</button> <span id="m"></span></div>`;
const q=i=>r.getElementById(i);
q('b').onclick=()=>q('f').style.display=q('f').style.display==='block'?'none':'block';
q('s').onclick=async()=>{if(!q('t').value.trim())return;
const x=await fetch('/__wokok/note',{method:'POST',body:JSON.stringify({page:location.pathname,author:q('a').value,text:q('t').value})});
q('m').textContent=x.ok?'Отправлено ✓':'Не вышло';if(x.ok)q('t').value='';};})();</script>
''';
}
