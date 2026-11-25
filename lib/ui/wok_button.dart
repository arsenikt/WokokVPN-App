import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/vpn_controller.dart';
import 'theme.dart';

/// The big "live button": a wok that heats up with the connection state.
/// cold (grey) → heating (amber, shaking) → on fire (flames, tossing noodles).
class WokButton extends StatefulWidget {
  const WokButton({super.key, required this.state, required this.onTap, this.size = 260});

  final VpnState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<WokButton> createState() => _WokButtonState();
}

class _WokButtonState extends State<WokButton> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();
  late final AnimationController _heat = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    _syncHeat();
  }

  @override
  void didUpdateWidget(WokButton old) {
    super.didUpdateWidget(old);
    _syncHeat();
  }

  void _syncHeat() {
    final target = switch (widget.state) {
      VpnState.on => 1.0,
      VpnState.connecting => .45,
      _ => 0.0,
    };
    _heat.animateTo(target, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _loop.dispose();
    _heat.dispose();
    super.dispose();
  }

  String get _label => switch (widget.state) {
        VpnState.on => 'Выключить VPN',
        VpnState.connecting => 'Подключение',
        VpnState.error => 'Ошибка подключения, нажмите чтобы повторить',
        VpnState.off => 'Включить VPN',
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _label,
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: widget.size,
            height: widget.size * .8,
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _heat]),
              builder: (_, __) => CustomPaint(
                painter: _WokPainter(
                  t: _loop.value,
                  heat: _heat.value,
                  busy: widget.state == VpnState.connecting,
                  error: widget.state == VpnState.error,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WokPainter extends CustomPainter {
  _WokPainter({required this.t, required this.heat, required this.busy, required this.error});

  final double t, heat;
  final bool busy, error;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 220;
    canvas.save();
    canvas.scale(s);
    final w = 220.0;

    // glow behind
    if (heat > 0) {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          Wok.fire.withValues(alpha: .35 * heat),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: Offset(w / 2, 150), radius: 120));
      canvas.drawCircle(Offset(w / 2, 150), 120, glow);
    }

    // flames
    if (heat > .05) {
      for (var i = 0; i < 3; i++) {
        final cx = 70.0 + i * 32;
        final flick = math.sin((t * 2 * math.pi * 3) + i * 1.3);
        final h = (34 + i % 2 * 14 + flick * 6) * heat;
        final path = Path()
          ..moveTo(cx - 14, 168)
          ..quadraticBezierTo(cx - 16, 168 - h * .6, cx + flick * 3, 168 - h)
          ..quadraticBezierTo(cx + 16, 168 - h * .6, cx + 14, 168)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Wok.gold, Wok.fire, Color(0x00E5341B)],
            ).createShader(Rect.fromLTWH(cx - 16, 168 - h, 32, h)),
        );
      }
    }

    // pan tilt (toss when on, shake when busy)
    double angle = 0;
    double lift = 0;
    if (busy) {
      angle = math.sin(t * 2 * math.pi * 8) * .035;
    } else if (heat > .9) {
      final k = (t * 2) % 2.0;
      if (k > 1.2 && k < 1.6) {
        final u = (k - 1.2) / .4;
        angle = -.1 * math.sin(u * math.pi);
        lift = -6 * math.sin(u * math.pi);
      }
    }
    canvas.save();
    canvas.translate(102, 90 + lift);
    canvas.rotate(angle);
    canvas.translate(-102, -90);

    // handle
    canvas.save();
    canvas.translate(178, 63);
    canvas.rotate(-14 * math.pi / 180);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, -5, 44, 10), const Radius.circular(5)),
        Paint()..color = const Color(0xFF2A2421));
    canvas.restore();

    // bowl
    final bowl = Path()
      ..moveTo(18, 70)
      ..arcToPoint(const Offset(186, 70), radius: const Radius.elliptical(84, 62), clockwise: false)
      ..close();
    canvas.drawPath(
      bowl,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.1, -.6),
          radius: 1.0,
          colors: [Color(0xFF4A423D), Color(0xFF151211)],
        ).createShader(const Rect.fromLTWH(18, 70, 168, 62)),
    );
    final rim = Color.lerp(const Color(0xFF5A4A40), error ? Wok.chili : Wok.fire, heat + (error ? .8 : 0))!;
    canvas.drawOval(const Rect.fromLTWH(16, 59, 172, 22), Paint()..color = rim);
    canvas.drawOval(
        const Rect.fromLTWH(26, 63, 152, 14),
        Paint()..color = Color.lerp(const Color(0xFF3A302A), const Color(0xFFC8641E), heat)!);
    canvas.restore();

    // noodles & veggies flying when on fire
    if (heat > .6) {
      final a = ((heat - .6) / .4).clamp(0.0, 1.0);
      final k = (t * 2) % 2.0;
      final fly = (k > 1.2 && k < 2.0) ? math.sin((k - 1.2) / .8 * math.pi) : 0.0;
      final dy = -46 * fly;
      final noodle = Paint()
        ..color = Wok.gold.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final p1 = Path()
        ..moveTo(70, 56 + dy)
        ..quadraticBezierTo(82, 30 + dy, 96, 50 + dy)
        ..quadraticBezierTo(106, 64 + dy, 118, 42 + dy);
      canvas.drawPath(p1, noodle);
      final p2 = Path()
        ..moveTo(104, 50 + dy * 1.1)
        ..quadraticBezierTo(118, 20 + dy * 1.1, 134, 46 + dy * 1.1);
      canvas.drawPath(p2, noodle);
      canvas.drawCircle(Offset(88, 38 + dy * 1.2), 5, Paint()..color = Wok.jade.withValues(alpha: a));
      canvas.drawCircle(Offset(128, 30 + dy * 1.3), 5, Paint()..color = Wok.chili.withValues(alpha: a));
      canvas.drawCircle(Offset(112, 24 + dy * 1.15), 4, Paint()..color = Wok.jade.withValues(alpha: a));
    }

    // stove
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(40, 160, 124, 6), const Radius.circular(3)),
        Paint()..color = const Color(0xFF2A2421));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WokPainter o) => o.t != t || o.heat != heat || o.busy != busy || o.error != error;
}
