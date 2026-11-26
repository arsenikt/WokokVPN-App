import 'package:flutter/material.dart';

import '../../box/box_controller.dart';
import '../../core/vpn_controller.dart';
import '../theme.dart';
import 'common.dart';

/// The open box: one pulse line and five compartments.
class BoxHome extends StatelessWidget {
  const BoxHome({super.key, required this.box, required this.open});
  final BoxController box;

  /// Opens a compartment by its section id.
  final void Function(String id) open;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([box, box.vpn]),
        builder: (context, _) {
          final vpn = box.vpn;
          final on = vpn.state == VpnState.on;
          final nosy = box.spy.apps.values.where((a) => a.trackers.isNotEmpty).length;
          final leaks = box.spy.alerts.length;
          final blocked = {...vpn.settings.blockedDomains, ...vpn.settings.shieldDomains}.length;
          final t = box.tunnel;
          return BoxPage(
            title: 'Wokok Box',
            children: [
              Panel(
                color: Color.alphaBlend(
                    (on ? Wok.fire : Wok.muted).withValues(alpha: .16), Wok.card),
                child: Column(children: [
                  const BoxArt('hero', '🥡', size: 150),
                  const SizedBox(height: 8),
                  Text(on ? 'Коробка закрыта, вок на огне' : 'Коробка открыта: VPN выключен',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: on ? Wok.gold : Wok.paper)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    _chip(on ? '🔥 защищён' : '❄ без VPN'),
                    _chip(box.spying ? '🕵️ следящих приложений: $nosy' : '🕵️ наблюдение выключено'),
                    if (leaks > 0) _chip('⚠ сигналов: $leaks'),
                    _chip('🥡 заблокировано: $blocked'),
                    _chip('🖥 серверов: ${box.servers.length}'),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: fireButton,
                    onPressed: vpn.active == null ? () => open('vpn') : vpn.toggle,
                    icon: const Icon(Icons.local_fire_department_rounded),
                    label: Text(vpn.state == VpnState.connecting
                        ? 'Разогреваем…'
                        : on
                            ? 'Погасить VPN'
                            : vpn.active == null
                                ? 'Настроить VPN'
                                : 'Разжечь VPN'),
                  ),
                  if (vpn.state == VpnState.error)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(vpn.error ?? '', style: const TextStyle(color: Wok.chili)),
                    ),
                ]),
              ),
              LayoutBuilder(builder: (context, c) {
                final columns = c.maxWidth >= 620 ? 4 : 2;
                final width = (c.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  _tile(width, 'guard', '🛡️', 'Guard', 'Проверить ссылку, QR, сообщение'),
                  _tile(width, 'spy', '🕵️', 'Spy Check', 'Кто за тобой следит'),
                  _tile(width, 'tunnel', '🛵', 'Tunnel',
                      t == null ? 'Показать localhost миру' : 'Открыта: ${t.name}'),
                  _tile(width, 'deploy', '👨‍🍳', 'Deploy', 'VPN, сайт или бот в один клик'),
                ]);
              }),
            ],
          );
        },
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Wok.bg2, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 12.5)),
      );

  Widget _tile(double width, String id, String emoji, String title, String about) => SizedBox(
        width: width,
        height: 176,
        child: Material(
          color: Wok.card,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => open(id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                BoxArt(id, emoji, size: 72),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(about,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Wok.muted, fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
}
