import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../box/box_controller.dart';
import 'box/box_home.dart';
import 'box/deploy_page.dart';
import 'box/guard_page.dart';
import 'box/spy_page.dart';
import 'box/tunnel_page.dart';
import 'home_page.dart';
import 'recipes_page.dart';
import 'servers_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class _Section {
  const _Section(this.id, this.label, this.icon, this.iconOn);
  final String id;
  final String label;
  final IconData icon;
  final IconData iconOn;
}

const _sections = [
  _Section('box', 'Коробка', Icons.takeout_dining_outlined, Icons.takeout_dining_rounded),
  _Section('vpn', 'VPN', Icons.local_fire_department_outlined, Icons.local_fire_department_rounded),
  _Section('guard', 'Guard', Icons.shield_outlined, Icons.shield_rounded),
  _Section('spy', 'Spy Check', Icons.visibility_outlined, Icons.visibility_rounded),
  _Section('tunnel', 'Tunnel', Icons.delivery_dining_outlined, Icons.delivery_dining_rounded),
  _Section('deploy', 'Deploy', Icons.rocket_launch_outlined, Icons.rocket_launch_rounded),
  _Section('servers', 'Кухни', Icons.dns_outlined, Icons.dns_rounded),
  _Section('recipes', 'Рецепты', Icons.restaurant_menu_outlined, Icons.restaurant_menu_rounded),
  _Section('settings', 'Настройки', Icons.settings_outlined, Icons.settings_rounded),
];

/// Phones show these in the bottom bar; the rest open on top.
const _mobileTabs = ['box', 'vpn', 'guard', 'spy', 'settings'];

/// Adaptive shell: bottom bar on phones (native flavour per OS),
/// sidebar on wide windows (Windows / macOS / tablets).
class Shell extends StatefulWidget {
  const Shell({super.key, required this.box, this.sharedText});
  final BoxController box;

  /// Text shared into the app: opens Guard with it.
  final String? sharedText;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late String _current = widget.sharedText == null ? 'box' : 'guard';
  late final Set<String> _visited = {_current};

  @override
  void didUpdateWidget(Shell old) {
    super.didUpdateWidget(old);
    if (widget.sharedText != null && widget.sharedText != old.sharedText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
        _select('guard');
      });
    }
  }

  void _select(String id) => setState(() {
        _current = id;
        _visited.add(id);
      });

  Widget _page(String id, bool wide) {
    final box = widget.box;
    final vpn = box.vpn;
    return switch (id) {
      'box' => BoxHome(box: box, open: (id) => _open(id, wide)),
      'vpn' => Scaffold(body: HomePage(vpn: vpn, onOpenServers: () => _open('servers', wide))),
      'guard' => GuardPage(box: box, initialText: widget.sharedText),
      'spy' => SpyPage(box: box),
      'tunnel' => TunnelPage(box: box),
      'deploy' => DeployPage(box: box),
      'servers' => ServersPage(vpn: vpn),
      'recipes' => RecipesPage(vpn: vpn),
      _ => SettingsPage(box: box, open: (id) => _open(id, wide)),
    };
  }

  void _open(String id, bool wide) {
    if (wide || _mobileTabs.contains(id)) {
      _select(id);
    } else {
      Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => Material(color: Wok.bg, child: _page(id, wide))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final shown = wide || _mobileTabs.contains(_current) ? _current : 'box';
    _visited.add(shown);
    // Pages are built on first visit and then kept alive.
    final body = IndexedStack(
      index: _sections.indexWhere((s) => s.id == shown),
      children: [
        for (final s in _sections)
          _visited.contains(s.id) ? _page(s.id, wide) : const SizedBox.shrink(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(children: [
          Material(
            color: Wok.bg2,
            child: SizedBox(
              width: 176,
              child: ListView(
                padding: EdgeInsets.fromLTRB(8, Platform.isMacOS ? 32 : 12, 8, 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Image.asset('assets/brand/logo.png', width: 48, height: 48),
                  ),
                  for (final s in _sections)
                    ListTile(
                      dense: true,
                      selected: s.id == shown,
                      selectedColor: Wok.fire,
                      selectedTileColor: Wok.fire.withValues(alpha: .16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: Icon(s.id == shown ? s.iconOn : s.icon),
                      title: Text(s.label),
                      onTap: () => _select(s.id),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: Material(color: Wok.bg, child: body)),
        ]),
      );
    }

    final tabs = [for (final id in _mobileTabs) _sections.firstWhere((s) => s.id == id)];
    final index = _mobileTabs.indexOf(shown);
    // iOS-flavoured tab bar on iPhone, Material 3 bar on Android.
    return Scaffold(
      body: body,
      bottomNavigationBar: Platform.isIOS
          ? CupertinoTabBar(
              currentIndex: index,
              onTap: (i) => _select(_mobileTabs[i]),
              backgroundColor: Wok.bg2,
              activeColor: Wok.fire,
              inactiveColor: Wok.muted,
              items: [
                for (final s in tabs)
                  BottomNavigationBarItem(
                      icon: Icon(s.icon), activeIcon: Icon(s.iconOn), label: s.label),
              ],
            )
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _select(_mobileTabs[i]),
              destinations: [
                for (final s in tabs)
                  NavigationDestination(
                    icon: Icon(s.icon),
                    selectedIcon: Icon(s.iconOn, color: Wok.fire),
                    label: s.label,
                  ),
              ],
            ),
    );
  }
}
