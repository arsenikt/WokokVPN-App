import 'dart:convert';

/// One "kitchen" — a server config. Supports VLESS (+Reality) and an optional
/// SSH fallback, the same pair that the Wokok Chrome extension uses.
class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.uuid,
    this.flow = '',
    this.security = 'reality',
    this.sni = '',
    this.publicKey = '',
    this.shortId = '',
    this.fingerprint = 'chrome',
    this.network = 'tcp',
    this.sshUser,
    this.sshPort,
    this.sshPrivateKey,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String uuid;
  final String flow;
  final String security; // reality | tls | none
  final String sni;
  final String publicKey;
  final String shortId;
  final String fingerprint;
  final String network;
  final String? sshUser;
  final int? sshPort;
  final String? sshPrivateKey;

  bool get hasSshFallback =>
      sshUser != null && sshPrivateKey != null && sshPrivateKey!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'uuid': uuid,
        'flow': flow,
        'security': security,
        'sni': sni,
        'publicKey': publicKey,
        'shortId': shortId,
        'fingerprint': fingerprint,
        'network': network,
        'sshUser': sshUser,
        'sshPort': sshPort,
        'sshPrivateKey': sshPrivateKey,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        port: j['port'] as int,
        uuid: j['uuid'] as String,
        flow: (j['flow'] ?? '') as String,
        security: (j['security'] ?? 'reality') as String,
        sni: (j['sni'] ?? '') as String,
        publicKey: (j['publicKey'] ?? '') as String,
        shortId: (j['shortId'] ?? '') as String,
        fingerprint: (j['fingerprint'] ?? 'chrome') as String,
        network: (j['network'] ?? 'tcp') as String,
        sshUser: j['sshUser'] as String?,
        sshPort: j['sshPort'] as int?,
        sshPrivateKey: j['sshPrivateKey'] as String?,
      );

  /// Serialises to the shareable "ticket" (talon) link.
  /// Same wire format the Wokok server and Chrome extension use:
  /// `wokok://` + base64url(JSON). The SSH key travels base64-encoded.
  String toTicket() {
    final j = <String, dynamic>{
      'v': 1,
      'name': name,
      'host': host,
      'port': port,
      'id': uuid,
      'pbk': publicKey,
      'sid': shortId,
      'sni': sni,
      if (hasSshFallback)
        'ssh': {
          'port': sshPort ?? 22,
          'user': sshUser,
          'key': base64.encode(utf8.encode(sshPrivateKey!)),
        },
    };
    return 'wokok://${base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '')}';
  }

  String toVlessLink() {
    final q = <String, String>{
      'type': network,
      'security': security,
      if (flow.isNotEmpty) 'flow': flow,
      if (sni.isNotEmpty) 'sni': sni,
      if (publicKey.isNotEmpty) 'pbk': publicKey,
      if (shortId.isNotEmpty) 'sid': shortId,
      if (fingerprint.isNotEmpty) 'fp': fingerprint,
    };
    return Uri(
      scheme: 'vless',
      userInfo: uuid,
      host: host,
      port: port,
      queryParameters: q,
      fragment: name,
    ).toString();
  }
}

class ProfileParseException implements Exception {
  ProfileParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses `vless://…` links and `wokok://pair?…` tickets.
class ProfileParser {
  static Profile parse(String raw, {String Function()? idGen}) {
    final text = raw.trim();
    final gen = idGen ?? () => DateTime.now().microsecondsSinceEpoch.toString();
    if (text.startsWith('wokok://')) return _parseTicket(text, gen);
    if (text.startsWith('vless://')) return _parseVless(text, gen);
    throw ProfileParseException(
        'Неизвестный формат. Нужна ссылка vless:// или wokok://');
  }

  /// Finds the first supported link inside arbitrary text (clipboard sniffing).
  static String? sniff(String text) {
    final m = RegExp(r'(wokok|vless)://\S+').firstMatch(text);
    return m?.group(0);
  }

  static Profile _parseVless(String text, String Function() gen) {
    final Uri u;
    try {
      u = Uri.parse(text);
    } catch (_) {
      throw ProfileParseException('Ссылка повреждена');
    }
    if (u.userInfo.isEmpty || u.host.isEmpty || !u.hasPort) {
      throw ProfileParseException('В ссылке нет UUID, адреса или порта');
    }
    final q = u.queryParameters;
    final security = q['security'] ?? 'none';
    if (security == 'reality' && (q['pbk'] ?? '').isEmpty) {
      throw ProfileParseException('Для Reality нужен публичный ключ (pbk)');
    }
    final name =
        u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : u.host;
    return Profile(
      id: gen(),
      name: name,
      host: u.host,
      port: u.port,
      uuid: u.userInfo,
      flow: q['flow'] ?? '',
      security: security,
      sni: q['sni'] ?? '',
      publicKey: q['pbk'] ?? '',
      shortId: q['sid'] ?? '',
      fingerprint: q['fp'] ?? 'chrome',
      network: q['type'] ?? 'tcp',
    );
  }

  static Profile _parseTicket(String text, String Function() gen) {
    final Map<String, dynamic> j;
    try {
      final b64 = text.substring('wokok://'.length).replaceAll('/', '').trim();
      j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(b64))))
          as Map<String, dynamic>;
    } catch (_) {
      throw ProfileParseException('Талон повреждён');
    }
    final host = j['host'] as String?;
    final id = j['id'] as String?;
    final pbk = j['pbk'] as String?;
    if (host == null || id == null || pbk == null || host.isEmpty) {
      throw ProfileParseException('В талоне нет данных сервера');
    }
    String? sshUser, sshKey;
    int? sshPort;
    final ssh = j['ssh'];
    if (ssh is Map) {
      try {
        // The server ships the PEM private key base64-encoded.
        sshKey = utf8.decode(base64.decode(base64.normalize(ssh['key'] as String)));
        sshUser = (ssh['user'] ?? 'wokok') as String;
        sshPort = (ssh['port'] as num?)?.toInt() ?? 22;
      } catch (_) {
        sshKey = null; // SSH is optional, never fail the whole import
      }
    }
    return Profile(
      id: gen(),
      name: (j['name'] as String?) ?? host,
      host: host,
      port: (j['port'] as num?)?.toInt() ?? 443,
      uuid: id,
      flow: 'xtls-rprx-vision',
      security: 'reality',
      sni: (j['sni'] as String?) ?? '',
      publicKey: pbk,
      shortId: (j['sid'] as String?) ?? '',
      sshUser: sshKey == null ? null : sshUser,
      sshPort: sshKey == null ? null : sshPort,
      sshPrivateKey: sshKey,
    );
  }
}

