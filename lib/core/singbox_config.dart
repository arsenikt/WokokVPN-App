import 'dart:convert';

import 'profile.dart';
import 'recipes.dart';

/// How traffic enters the core.
enum CaptureMode {
  /// System-wide TUN device (needs admin on desktop, VpnService on mobile).
  tun,

  /// Local mixed proxy + system proxy setting (desktop, no admin needed).
  systemProxy,
}

class ConfigOptions {
  const ConfigOptions({
    this.recipe = Recipe.smart,
    this.mode = CaptureMode.systemProxy,
    this.killSwitch = true,
    this.autoSwitch = true,
    this.selectedDomains = const [],
    this.proxyPort = 10808,
    this.apiPort = 19090,
  });

  final Recipe recipe;
  final CaptureMode mode;
  final bool killSwitch;
  final bool autoSwitch;
  final List<String> selectedDomains;
  final int proxyPort;
  final int apiPort;
}

/// Builds a sing-box 1.11-style JSON config from a [Profile] and options.
class SingBoxConfig {
  static Map<String, dynamic> build(Profile p, ConfigOptions o) {
    final outbounds = <Map<String, dynamic>>[_vless(p)];
    final useSsh = p.hasSshFallback;
    if (useSsh) outbounds.add(_ssh(p));

    // Auto-Switch: urltest picks the protocol that currently works.
    String proxyTag = 'wokok-vless';
    if (useSsh && o.autoSwitch) {
      outbounds.add({
        'type': 'urltest',
        'tag': 'wokok-auto',
        'outbounds': ['wokok-vless', 'wokok-ssh'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '3m',
        'tolerance': 200,
      });
      proxyTag = 'wokok-auto';
    }
    outbounds.add({'type': 'direct', 'tag': 'direct'});

    final inbounds = <Map<String, dynamic>>[];
    if (o.mode == CaptureMode.tun) {
      inbounds.add({
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        'auto_route': true,
        // strict_route is the kill switch: no traffic outside the tunnel.
        'strict_route': o.killSwitch,
        'stack': 'mixed',
      });
    } else {
      inbounds.add({
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': o.proxyPort,
        'set_system_proxy': true,
      });
    }

    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {'ip_is_private': true, 'outbound': 'direct'},
    ];
    // Never tunnel the tunnel itself.
    rules.add({
      'domain': [p.host],
      'outbound': 'direct',
    });

    String finalOutbound;
    switch (o.recipe) {
      case Recipe.all:
        finalOutbound = proxyTag;
        break;
      case Recipe.smart:
        rules.add({
          'domain_suffix': smartDirectSuffixes,
          'outbound': 'direct',
        });
        finalOutbound = proxyTag;
        break;
      case Recipe.selected:
        if (o.selectedDomains.isNotEmpty) {
          rules.add({
            'domain_suffix': o.selectedDomains,
            'outbound': proxyTag,
          });
        }
        finalOutbound = 'direct';
        break;
    }

    return {
      'log': {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'remote', 'address': 'https://1.1.1.1/dns-query', 'detour': proxyTag},
          {'tag': 'local', 'address': 'local', 'detour': 'direct'},
        ],
        'rules': [
          {'domain': [p.host], 'server': 'local'},
        ],
        'final': 'remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': inbounds,
      'outbounds': outbounds,
      'route': {
        'rules': rules,
        'final': finalOutbound,
        'auto_detect_interface': true,
      },
      'experimental': {
        'clash_api': {'external_controller': '127.0.0.1:${o.apiPort}'},
      },
    };
  }

  static String buildJson(Profile p, ConfigOptions o) =>
      const JsonEncoder.withIndent('  ').convert(build(p, o));

  static Map<String, dynamic> _vless(Profile p) {
    final out = <String, dynamic>{
      'type': 'vless',
      'tag': 'wokok-vless',
      'server': p.host,
      'server_port': p.port,
      'uuid': p.uuid,
      if (p.flow.isNotEmpty) 'flow': p.flow,
      'packet_encoding': 'xudp',
    };
    if (p.security == 'reality' || p.security == 'tls') {
      out['tls'] = {
        'enabled': true,
        'server_name': p.sni.isNotEmpty ? p.sni : p.host,
        'utls': {'enabled': true, 'fingerprint': p.fingerprint},
        if (p.security == 'reality')
          'reality': {
            'enabled': true,
            'public_key': p.publicKey,
            'short_id': p.shortId,
          },
      };
    }
    return out;
  }

  static Map<String, dynamic> _ssh(Profile p) => {
        'type': 'ssh',
        'tag': 'wokok-ssh',
        'server': p.host,
        'server_port': p.sshPort ?? 22,
        'user': p.sshUser,
        'private_key': p.sshPrivateKey,
      };
}
