import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../box/box_controller.dart';
import '../core/vpn_controller.dart';
import 'theme.dart';

const siteUrl = 'https://arsenikt.github.io/WokokVPN';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.box, required this.open});
  final BoxController box;
  final void Function(String id) open;
  VpnController get vpn => box.vpn;

  Future<void> _toggleBiometric(BuildContext context, bool on) async {
    final m = ScaffoldMessenger.of(context);
    if (on) {
      final auth = LocalAuthentication();
      try {
        final ok = await auth.isDeviceSupported() &&
            await auth.authenticate(
                localizedReason: 'Подтвердите, чтобы включить защиту входа');
        if (!ok) return;
      } catch (_) {
        m.showSnackBar(const SnackBar(content: Text('Биометрия недоступна на этом устройстве')));
        return;
      }
    }
    await vpn.update((s) => s.biometric = on);
  }

  Future<void> _extinguish(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Wok.bg2,
        icon: const Icon(Icons.local_fire_department_rounded, color: Wok.chili, size: 36),
        title: const Text('Затушить всё?'),
        content: const Text(
            'Будут удалены все серверы, ключи и настройки с этого устройства. Это нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Wok.chili),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Затушить'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await box.extinguish();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Всё затушено')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListenableBuilder(
        listenable: vpn,
        builder: (context, _) {
          final s = vpn.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _group('VPN', [
                ListTile(
                  onTap: () => open('servers'),
                  leading: const Icon(Icons.dns_rounded, color: Wok.fire),
                  title: const Text('Кухни'),
                  subtitle: const Text('Серверы и талоны'),
                ),
                ListTile(
                  onTap: () => open('recipes'),
                  leading: const Icon(Icons.restaurant_menu_rounded, color: Wok.fire),
                  title: const Text('Рецепты'),
                  subtitle: const Text('Что пускать через VPN'),
                ),
              ]),
              _group('Коробка', [
                ListTile(
                  onTap: () => open('tunnel'),
                  leading: const Icon(Icons.delivery_dining_rounded, color: Wok.gold),
                  title: const Text('Tunnel'),
                ),
                ListTile(
                  onTap: () => open('deploy'),
                  leading: const Icon(Icons.rocket_launch_rounded, color: Wok.gold),
                  title: const Text('Deploy'),
                ),
                ListTile(
                  onTap: () => box.setAudience(Audience.parents),
                  leading: const Icon(Icons.elderly_rounded, color: Wok.gold),
                  title: const Text('Простой режим для родителей'),
                  subtitle: const Text('Крупные кнопки. Выход: удерживать значок вверху'),
                ),
              ]),
              _group('Защита', [
                SwitchListTile(
                  value: s.killSwitch,
                  onChanged: (v) => vpn.update((x) => x.killSwitch = v),
                  secondary: const Icon(Icons.shield_rounded, color: Wok.fire),
                  title: const Text('Kill switch'),
                  subtitle: const Text('Блокировать сеть, если VPN оборвался'),
                ),
                SwitchListTile(
                  value: s.biometric,
                  onChanged: (v) => _toggleBiometric(context, v),
                  secondary: const Icon(Icons.fingerprint_rounded, color: Wok.fire),
                  title: const Text('Вход по биометрии'),
                  subtitle: const Text('Face ID, отпечаток или Windows Hello'),
                ),
              ]),
              _group('Соединение', [
                SwitchListTile(
                  value: s.autoSwitch,
                  onChanged: (v) => vpn.update((x) => x.autoSwitch = v),
                  secondary: const Icon(Icons.swap_horiz_rounded, color: Wok.fire),
                  title: const Text('Умный щит (Auto-Switch)'),
                  subtitle: const Text('Сам переключается между Reality и SSH'),
                ),
                if (vpn.isDesktop)
                  SwitchListTile(
                    value: s.fullTunnel,
                    onChanged: (v) => vpn.update((x) => x.fullTunnel = v),
                    secondary: const Icon(Icons.lan_rounded, color: Wok.fire),
                    title: const Text('Весь компьютер (TUN)'),
                    subtitle: const Text('Нужны права администратора. Иначе только системный прокси'),
                  ),
              ]),
              _group('Опасная зона', [
                ListTile(
                  onTap: () => _extinguish(context),
                  leading: const Icon(Icons.local_fire_department_rounded, color: Wok.chili),
                  title: const Text('Тушение', style: TextStyle(color: Wok.chili, fontWeight: FontWeight.w700)),
                  subtitle: const Text('Мгновенно стереть ключи и серверы'),
                ),
              ]),
              _group('О приложении', [
                ListTile(
                  onTap: () => launchUrl(Uri.parse(siteUrl)),
                  leading: const Icon(Icons.public_rounded, color: Wok.gold),
                  title: const Text('Сайт Wokok'),
                  subtitle: const Text('arsenikt.github.io/WokokVPN'),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: Wok.muted),
                  title: Text('Wokok Box 2.0.0'),
                  subtitle: Text('Ядро sing-box · без телеметрии · MIT'),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _group(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(title.toUpperCase(),
                style: const TextStyle(fontSize: 11.5, letterSpacing: 1, color: Wok.muted)),
          ),
          Card(clipBehavior: Clip.antiAlias, child: Column(children: children)),
        ]),
      );
}
