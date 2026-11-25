import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/vpn_controller.dart';
import 'home_page.dart';
import 'recipes_page.dart';
import 'servers_page.dart';
import 'settings_page.dart';
import 'theme.dart';

/// Adaptive shell: bottom bar on phones (native flavour per OS),
/// sidebar rail on wide windows (Windows / macOS / tablets).
class Shell extends StatefulWidget {
  const Shell({super.key, required this.vpn});
  final VpnController vpn;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _labels = ['Огонь', 'Кухни', 'Рецепты', 'Настройки'];
  static const _icons = [
    Icons.local_fire_department_outlined,
    Icons.dns_outlined,
    Icons.restaurant_menu_outlined,
    Icons.settings_outlined,
  ];
  static const _iconsOn = [
    Icons.local_fire_department_rounded,
    Icons.dns_rounded,
    Icons.restaurant_menu_rounded,
    Icons.settings_rounded,
  ];

  late final _pages = <Widget>[
    HomePage(vpn: widget.vpn, onOpenServers: () => setState(() => _index = 1)),
    ServersPage(vpn: widget.vpn),
    RecipesPage(vpn: widget.vpn),
    SettingsPage(vpn: widget.vpn),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = IndexedStack(index: _index, children: _pages);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: EdgeInsets.only(top: Platform.isMacOS ? 28 : 12, bottom: 12),
              child: Image.asset('assets/brand/logo.png', width: 44, height: 44),
            ),
            destinations: [
              for (var i = 0; i < 4; i++)
                NavigationRailDestination(
                  icon: Icon(_icons[i]),
                  selectedIcon: Icon(_iconsOn[i], color: Wok.fire),
                  label: Text(_labels[i]),
                ),
            ],
          ),
          Expanded(child: body),
        ]),
      );
    }

    // iOS-flavoured tab bar on iPhone, Material 3 bar on Android.
    final cupertino = Platform.isIOS;
    return Scaffold(
      body: body,
      bottomNavigationBar: cupertino
          ? CupertinoTabBar(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              backgroundColor: Wok.bg2,
              activeColor: Wok.fire,
              inactiveColor: Wok.muted,
              items: [
                for (var i = 0; i < 4; i++)
                  BottomNavigationBarItem(
                    icon: Icon(_icons[i]),
                    activeIcon: Icon(_iconsOn[i]),
                    label: _labels[i],
                  ),
              ],
            )
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationDestination(
                    icon: Icon(_icons[i]),
                    selectedIcon: Icon(_iconsOn[i], color: Wok.fire),
                    label: _labels[i],
                  ),
              ],
            ),
    );
  }
}
