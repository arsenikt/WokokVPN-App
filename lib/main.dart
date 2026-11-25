import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/vpn_controller.dart';
import 'data/store.dart';
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
        title: 'Wokok VPN',
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
  runApp(WokokApp(vpn: vpn));
}

class WokokApp extends StatefulWidget {
  const WokokApp({super.key, required this.vpn});
  final VpnController vpn;

  @override
  State<WokokApp> createState() => _WokokAppState();
}

class _WokokAppState extends State<WokokApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = widget.vpn.settings.biometric;
    if (_locked) _unlock();
    if (_desktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initTray();
    }
    widget.vpn.addListener(_refreshTray);
    if (widget.vpn.settings.autoConnect) widget.vpn.connect();
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
    final on = widget.vpn.state == VpnState.on;
    try {
      await trayManager
          .setToolTip(on ? 'Wokok VPN: вок на огне' : 'Wokok VPN: вок остыл');
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
      final ok = await auth.authenticate(localizedReason: 'Откройте Wokok VPN');
      if (mounted) setState(() => _locked = !ok);
    } catch (_) {
      if (mounted) setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused && widget.vpn.settings.biometric) {
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
        await widget.vpn.toggle();
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'quit':
        await widget.vpn.disconnect();
        await trayManager.destroy();
        exit(0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.vpn.removeListener(_refreshTray);
    if (_desktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wokok VPN',
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
          : Shell(vpn: widget.vpn),
    );
  }
}
