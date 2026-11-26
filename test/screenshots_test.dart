// Renders README screenshots. Skipped in normal runs.
//   SHOTS=1 SHOTS_OUT=docs/img SHOTS_FLUTTER=<flutter sdk root> flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wokok_vpn/box/box_controller.dart';
import 'package:wokok_vpn/core/engine.dart';
import 'package:wokok_vpn/core/profile.dart';
import 'package:wokok_vpn/core/recipes.dart';
import 'package:wokok_vpn/core/vpn_controller.dart';
import 'package:wokok_vpn/data/store.dart';
import 'package:wokok_vpn/ui/shell.dart';
import 'package:wokok_vpn/ui/theme.dart';

Future<void> _font(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await l.load();
}

void main() {
  final run = Platform.environment['SHOTS'] == '1';
  final out = Platform.environment['SHOTS_OUT'] ?? 'docs/img';
  final sdk = Platform.environment['SHOTS_FLUTTER'] ?? '';

  Future<VpnController> makeVpn({required bool on}) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    final vpn = VpnController(await Store.open());
    final p = Profile(
      id: '1',
      name: 'Frankfurt',
      host: '203.0.113.7',
      port: 443,
      uuid: 'x',
      publicKey: 'k',
      sshUser: 'wokok',
      sshPrivateKey: 'k',
    );
    final p2 = Profile(id: '2', name: 'Helsinki', host: '203.0.113.9', port: 443, uuid: 'y', publicKey: 'k');
    vpn.profiles = [p, p2];
    vpn.settings.activeProfileId = '1';
    vpn.settings.recipe = Recipe.smart;
    if (on) {
      vpn.state = VpnState.on;
      vpn.connectedAt = DateTime.now().subtract(const Duration(minutes: 42, seconds: 17));
      vpn.traffic = const TrafficSample(86 * 1024, 2400 * 1024);
      final wave = [4, 6, 9, 7, 12, 18, 14, 22, 30, 26, 19, 24, 33, 41, 36, 28, 31, 44, 52, 47, 38, 42, 55, 61, 49, 44, 51, 58, 66, 59, 47, 52, 60, 71, 64, 55, 49, 57, 63, 68];
      for (var i = 0; i < wave.length; i++) {
        vpn.downHistory[i] = wave[i] * 40000;
      }
    }
    return vpn;
  }

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required Size size,
    required bool on,
    String? tab,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    final vpn = (await tester.runAsync(() => makeVpn(on: on)))!;
    final box = (await tester.runAsync(() async => BoxController(
        vpn, await SharedPreferences.getInstance(), const FlutterSecureStorage())))!;
    box.audience = Audience.me;
    final key = GlobalKey();
    final base = wokTheme();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Segoe')),
        home: Shell(box: box),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    if (on && tab == null) {
      await tester.tap(find.text('VPN').first);
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (tab != null) {
      await tester.tap(find.text(tab).first);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    // let the wok finish heating up and sit mid-toss for a nice frame
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 1480));
    final boundary = tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!;
    });
    await tester.runAsync(() async {
      await Directory(out).create(recursive: true);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  setUpAll(() async {
    if (!run) return;
    await _font('Segoe', r'C:\Windows\Fonts\segoeui.ttf');
    await _font('MaterialIcons', '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  });

  testWidgets('shots', (tester) async {
    await shot(tester, name: 'desktop-home', size: const Size(980, 640), on: true);
    await shot(tester, name: 'desktop-recipes', size: const Size(980, 640), on: true, tab: 'Рецепты');
    await shot(tester, name: 'phone-home', size: const Size(390, 800), on: true);
    await shot(tester, name: 'phone-off', size: const Size(390, 800), on: false);
    await shot(tester, name: 'desktop-box', size: const Size(980, 720), on: false, tab: 'Коробка');
    await shot(tester, name: 'phone-box', size: const Size(390, 800), on: false, tab: 'Коробка');
    await shot(tester, name: 'phone-guard', size: const Size(390, 800), on: false, tab: 'Guard');
    await shot(tester, name: 'desktop-servers', size: const Size(980, 640), on: true, tab: 'Кухни');
    await shot(tester, name: 'phone-settings', size: const Size(390, 800), on: true, tab: 'Настройки');
  }, skip: !run);
}
