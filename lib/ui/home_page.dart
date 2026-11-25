import 'dart:async';

import 'package:flutter/material.dart';

import '../core/vpn_controller.dart';
import 'theme.dart';
import 'wok_button.dart';

String fmtBytes(int b) {
  if (b < 1024) return '$b Б/с';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ/с';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ/с';
}

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.vpn, required this.onOpenServers});
  final VpnController vpn;
  final VoidCallback onOpenServers;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.vpn.state == VpnState.on && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  (String, String, Color) _headline(VpnController v) => switch (v.state) {
        VpnState.on => ('Вок на огне', 'Трафик защищён и летит через ваш сервер', Wok.gold),
        VpnState.connecting => ('Разогреваем…', 'Подключаемся к серверу', Wok.fire),
        VpnState.error => ('Подгорело', v.error ?? 'Не удалось подключиться', Wok.chili),
        VpnState.off => ('Вок остыл', v.active == null ? 'Добавьте сервер, чтобы начать' : 'Нажмите на вок, чтобы разжечь', Wok.paper),
      };

  @override
  Widget build(BuildContext context) {
    final v = widget.vpn;
    final (title, sub, color) = _headline(v);
    final on = v.state == VpnState.on;
    return Stack(
      children: [
        // ambient fire glow at the bottom
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 1.1),
                radius: 1.1,
                colors: [
                  Wok.fire.withValues(alpha: on ? .28 : (v.state == VpnState.connecting ? .12 : 0)),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Wokok',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Wok.paper)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Wok.chili, borderRadius: BorderRadius.circular(5)),
                        child: const Text('VPN',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(child: WokButton(state: v.state, onTap: v.toggle)),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(v.state),
                      children: [
                        Text(title,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
                        const SizedBox(height: 4),
                        Text(sub,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Wok.muted, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (on) _SpeedCard(vpn: v),
                  if (on) const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          label: 'КУХНЯ',
                          value: v.active?.name ?? 'не выбрана',
                          icon: Icons.dns_rounded,
                          onTap: widget.onOpenServers,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoTile(
                          label: on ? 'НА ОГНЕ' : 'РЕЦЕПТ',
                          value: on && v.connectedAt != null
                              ? fmtDuration(DateTime.now().difference(v.connectedAt!))
                              : v.recipeTitle,
                          icon: on ? Icons.timer_rounded : Icons.restaurant_menu_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (v.profiles.isEmpty) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: widget.onOpenServers,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Добавить сервер'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52), backgroundColor: Wok.fire, foregroundColor: Colors.black),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value, required this.icon, this.onTap});
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 14, color: Wok.fire),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(fontSize: 10.5, letterSpacing: .8, color: Wok.muted)),
              ]),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({required this.vpn});
  final VpnController vpn;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _speed(Icons.arrow_downward_rounded, fmtBytes(vpn.traffic.down), Wok.jade),
              _speed(Icons.arrow_upward_rounded, fmtBytes(vpn.traffic.up), Wok.gold),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: CustomPaint(painter: _SparkPainter(vpn.downHistory)),
          ),
        ]),
      ),
    );
  }

  Widget _speed(IconData i, String t, Color c) => Row(children: [
        Icon(i, size: 18, color: c),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ]);
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data);
  final List<int> data;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.fold<int>(1, (m, e) => e > m ? e : m).toDouble();
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - (data[i] / maxV) * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Wok.fire.withValues(alpha: .35), Colors.transparent],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
        path,
        Paint()
          ..color = Wok.fire
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => true;
}
