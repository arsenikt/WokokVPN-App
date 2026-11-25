import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wokok_vpn/core/profile.dart';
import 'package:wokok_vpn/core/recipes.dart';
import 'package:wokok_vpn/core/singbox_config.dart';

const _link =
    'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?type=tcp&security=reality&flow=xtls-rprx-vision&sni=www.microsoft.com&pbk=PUBKEY&sid=ab12&fp=chrome#My%20Wok';

void main() {
  test('parses a vless reality link', () {
    final p = ProfileParser.parse(_link, idGen: () => 'x');
    expect(p.host, '1.2.3.4');
    expect(p.port, 443);
    expect(p.name, 'My Wok');
    expect(p.publicKey, 'PUBKEY');
    expect(p.flow, 'xtls-rprx-vision');
  });

  test('ticket round-trip keeps ssh fallback', () {
    final base = ProfileParser.parse(_link, idGen: () => 'x');
    final withSsh = Profile.fromJson({
      ...base.toJson(),
      'sshUser': 'wokok',
      'sshPort': 5223,
      'sshPrivateKey': 'KEY',
    });
    final back = ProfileParser.parse(withSsh.toTicket(), idGen: () => 'y');
    expect(back.sshUser, 'wokok');
    expect(back.sshPort, 5223);
    expect(back.sshPrivateKey, 'KEY');
    expect(back.uuid, base.uuid);
  });

  test('parses a server-issued wokok:// ticket (JSON + base64 ssh key)', () {
    final json =
        '{"v":1,"name":"Frankfurt · main","host":"79.1.2.3","port":443,"id":"abc","pbk":"PK","sid":"s1","sni":"www.apple.com","ssh":{"port":5223,"user":"wokok","key":"UEVNCktFWQ=="}}';
    final link = 'wokok://${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
    final p = ProfileParser.parse(link, idGen: () => 'z');
    expect(p.name, 'Frankfurt · main');
    expect(p.host, '79.1.2.3');
    expect(p.sshPort, 5223);
    expect(p.sshPrivateKey, 'PEM\nKEY');
    expect(p.flow, 'xtls-rprx-vision');
  });

  test('rejects garbage and reality without key', () {
    expect(() => ProfileParser.parse('hello'), throwsA(isA<ProfileParseException>()));
    expect(
        () => ProfileParser.parse('vless://u@h:1?security=reality'),
        throwsA(isA<ProfileParseException>()));
  });

  test('sniff finds a link inside text', () {
    expect(ProfileParser.sniff('look: $_link thanks'), _link);
    expect(ProfileParser.sniff('nothing'), isNull);
  });

  test('config: smart recipe keeps banks direct, tunnel host never proxied', () {
    final p = ProfileParser.parse(_link, idGen: () => 'x');
    final c = SingBoxConfig.build(p, const ConfigOptions(recipe: Recipe.smart));
    final rules = (c['route']['rules'] as List).cast<Map>();
    expect(rules.any((r) => (r['domain_suffix'] as List?)?.contains('sberbank.ru') ?? false), isTrue);
    expect(rules.any((r) => (r['domain'] as List?)?.contains('1.2.3.4') ?? false), isTrue);
    expect(c['route']['final'], 'wokok-vless');
  });

  test('config: auto-switch urltest only when ssh exists; tun has kill switch', () {
    final base = ProfileParser.parse(_link, idGen: () => 'x');
    final noSsh = SingBoxConfig.build(base, const ConfigOptions());
    expect((noSsh['outbounds'] as List).any((o) => o['type'] == 'urltest'), isFalse);

    final ssh = Profile.fromJson({
      ...base.toJson(),
      'sshUser': 'w',
      'sshPrivateKey': 'K',
    });
    final c = SingBoxConfig.build(
        ssh, const ConfigOptions(mode: CaptureMode.tun, killSwitch: true));
    expect((c['outbounds'] as List).any((o) => o['type'] == 'urltest'), isTrue);
    expect(c['route']['final'], 'wokok-auto');
    expect(c['inbounds'][0]['strict_route'], isTrue);
  });

  test('config: selected recipe goes direct by default', () {
    final p = ProfileParser.parse(_link, idGen: () => 'x');
    final c = SingBoxConfig.build(
        p, const ConfigOptions(recipe: Recipe.selected, selectedDomains: ['youtube.com']));
    expect(c['route']['final'], 'direct');
  });
}
