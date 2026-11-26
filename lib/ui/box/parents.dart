import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../box/box_controller.dart';
import '../../core/vpn_controller.dart';
import '../theme.dart';
import 'common.dart';
import 'guard_page.dart';

/// First launch: who is going to use the box?
class AudiencePage extends StatelessWidget {
  const AudiencePage({super.key, required this.box});
  final BoxController box;

  @override
  Widget build(BuildContext context) => BoxPage(
        title: 'Wokok Box',
        children: [
          const Center(child: BoxArt('hero', '🥡', size: 200)),
          const SizedBox(height: 16),
          const Text('Кто будет пользоваться?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          _choice('me', '🧑', 'Я', 'VPN, Tunnel, Deploy, Spy Check и Guard', Audience.me),
          _choice('parents', '👵', 'Родители',
              'Крупные кнопки: проверить сообщение, позвонить своим', Audience.parents),
          const Center(child: Muted('Это можно изменить в настройках.')),
        ],
      );

  Widget _choice(String art, String emoji, String title, String about, Audience a) => Panel(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: BoxArt(art, emoji, size: 64),
          title: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          subtitle: Text(about),
          onTap: () => box.setAudience(a),
        ),
      );
}

/// The simple mode: a few very large buttons.
class ParentsHome extends StatelessWidget {
  const ParentsHome({super.key, required this.box});
  final BoxController box;

  void _guard(BuildContext context, {bool scan = false}) => Navigator.push(context,
      MaterialPageRoute<void>(builder: (_) => GuardPage(box: box, scanNow: scan)));

  Widget _big(String emoji, String label, Color color, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
          onPressed: onTap,
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 16),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([box, box.vpn]),
        builder: (context, _) {
          final on = box.vpn.state == VpnState.on;
          final h = box.helper;
          return BoxPage(
            title: 'Wokok Box',
            actions: [
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => toast(context, 'Чтобы выйти из простого режима, удерживайте кнопку'),
                onLongPress: () => box.setAudience(Audience.me),
              ),
            ],
            children: [
              const Center(child: BoxArt('parents', '👵', size: 140)),
              const SizedBox(height: 14),
              _big('📋', 'Проверить сообщение или ссылку', Wok.gold, () => _guard(context)),
              if (canScanQr)
                _big('📷', 'Проверить QR-код', Wok.paper, () => _guard(context, scan: true)),
              _big(
                  '📞',
                  h == null ? 'Добавить близкого человека' : 'Позвонить: ${h.name}',
                  Wok.jade, () {
                if (h == null) {
                  editHelper(context, box);
                } else {
                  launchUrl(Uri.parse('tel:${h.phone}'));
                }
              }),
              if (box.vpn.active != null)
                _big(on ? '🔥' : '❄', on ? 'Защита включена' : 'Включить защиту', Wok.fire,
                    box.vpn.toggle),
              _big('🎓', 'Тренировка: найди обман', Wok.paper,
                  () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) => LessonsPage(box: box)))),
            ],
          );
        },
      );
}
