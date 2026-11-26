import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'box/box_controller.dart';
import 'box/device.dart';
import 'core/vpn_controller.dart';
import 'data/store.dart';
import 'ui/box/guard_page.dart';
import 'ui/box/parents.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(980, 680),
        minimumSize: Size(380, 600),
        center: true,
        title: 'Wokok Box',
        titleBarStyle: TitleBarStyle.normal,
        backgroundColor: Wok.bg,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(true);
  }
  final vpn = VpnController(await Store.open());
  await vpn.load();
  runApp(WokokApp(box: await BoxController.open(vpn)));
}

class WokokApp extends StatefulWidget {
  const WokokApp({super.key, required this.box});
  final BoxController box;

  @override
  State<WokokApp> createState() => _WokokAppState();
}

class _WokokAppState extends State<WokokApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  bool _locked = false;
  String? _shared;
  VpnController get _vpn => widget.box.vpn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = _vpn.settings.biometric;
    if (_locked) _unlock();
    if (_desktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initTray();
    }
    _vpn.addListener(_refreshTray);
    if (_vpn.settings.autoConnect) _vpn.connect();
    Device.listenShared((text) => setState(() => _shared = text));
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(Platform.isWindows
          ? 'assets/brand/tray.ico'
          : 'assets/brand/tray.png');
      await _refreshTray();
    } catch (_) {/* tray is a nicety, never fatal */}
  }

  Future<void> _refreshTray() async {
    if (!_desktop) return;
    final on = _vpn.state == VpnState.on;
    try {
      await trayManager
          .setToolTip(on ? 'Wokok Box: вок на огне' : 'Wokok Box: вок остыл');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'toggle', label: on ? 'Погасить' : 'Разжечь'),
        MenuItem.separator(),
        MenuItem(key: 'show', label: 'Открыть Wokok'),
        MenuItem(key: 'quit', label: 'Выход'),
      ]));
    } catch (_) {}
  }

  Future<void> _unlock() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        if (mounted) setState(() => _locked = false);
        return;
      }
      final ok = await auth.authenticate(localizedReason: 'Откройте Wokok Box');
      if (mounted) setState(() => _locked = !ok);
    } catch (_) {
      if (mounted) setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused && _vpn.settings.biometric) {
      setState(() => _locked = true);
    }
    if (s == AppLifecycleState.resumed && _locked) _unlock();
  }

  // Closing the window hides it to the tray; the VPN keeps running.
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => windowManager.show();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'toggle':
        await _vpn.toggle();
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'quit':
        await widget.box.closeTunnel();
        await _vpn.disconnect();
        await trayManager.destroy();
        exit(0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vpn.removeListener(_refreshTray);
    if (_desktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wokok Box',
      debugShowCheckedModeBanner: false,
      theme: wokTheme(),
      home: _locked
          ? Scaffold(
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/brand/logo.png', width: 96),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _unlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Разблокировать'),
                  ),
                ]),
              ),
            )
          : ListenableBuilder(
              listenable: widget.box,
              builder: (context, _) => switch (widget.box.audience) {
                Audience.unset => AudiencePage(box: widget.box),
                Audience.parents when _shared == null => ParentsHome(box: widget.box),
                Audience.parents => GuardPage(
                    box: widget.box,
                    initialText: _shared,
                    onHome: () => setState(() => _shared = null),
                  ),
                Audience.me => Shell(box: widget.box, sharedText: _shared),
              },
            ),
    );
  }
}
