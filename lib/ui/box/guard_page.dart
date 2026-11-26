import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../box/box_controller.dart';
import '../../box/device.dart';
import '../../box/guard/analyzer.dart';
import '../../box/guard/lessons.dart';
import '../theme.dart';
import 'common.dart';

class GuardPage extends StatefulWidget {
  const GuardPage(
      {super.key, required this.box, this.initialText, this.scanNow = false, this.onHome});

  /// Set when Guard is the whole screen and needs its own way back.
  final VoidCallback? onHome;
  final BoxController box;
  final String? initialText;
  final bool scanNow;
  @override
  State<GuardPage> createState() => _GuardPageState();
}

class _GuardPageState extends State<GuardPage> {
  final _text = TextEditingController();
  Verdict? _verdict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialText != null) _check(widget.initialText!);
      if (widget.scanNow) _scan();
    });
  }

  @override
  void didUpdateWidget(GuardPage old) {
    super.didUpdateWidget(old);
    if (widget.initialText != null && widget.initialText != old.initialText) {
      _check(widget.initialText!);
    }
  }

  @override
  void dispose() {
    Device.stopSpeaking();
    _text.dispose();
    super.dispose();
  }

  Future<void> _check([String? value]) async {
    if (value != null) _text.text = value;
    if (_text.text.trim().isEmpty) {
      setState(() => _verdict = null);
      return;
    }
    final v = await widget.box.check(_text.text);
    if (mounted) setState(() => _verdict = v);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if ((d?.text ?? '').trim().isEmpty) {
      toast(context, 'Буфер обмена пуст. Сначала скопируйте сообщение.');
      return;
    }
    await _check(d!.text);
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ScanQrPage(), fullscreenDialog: true));
    if (code != null) await _check(code);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.box,
        builder: (context, _) {
          final v = _verdict;
          final s = widget.box.vpn.settings;
          return BoxPage(
            title: 'Guard',
            leading: widget.onHome == null ? null : BackButton(onPressed: widget.onHome),
            children: [
              if (v == null)
                const Panel(
                  child: Row(children: [
                    BoxArt('guard', '🛡️', size: 72),
                    SizedBox(width: 14),
                    Expanded(
                        child: Muted(
                            'Вставьте ссылку или сообщение, отсканируйте QR. Проверка идёт на устройстве, ничего никуда не отправляется.')),
                  ]),
                ),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    controller: _text,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                        hintText: 'Ссылка или текст сообщения', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      style: fireButton,
                      onPressed: _check,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Проверить'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: const Text('Из буфера'),
                    ),
                    if (canScanQr)
                      FilledButton.tonalIcon(
                        onPressed: _scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('QR'),
                      ),
                  ]),
                ]),
              ),
              if (v != null) ...[
                VerdictCard(box: widget.box, verdict: v, original: _text.text),
              ],
              Panel(
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.shield,
                    onChanged: (x) => widget.box.vpn.update((y) => y.shield = x),
                    title: const Text('Щит в VPN'),
                    subtitle: Text(
                        'Сайты, получившие «СТОП», блокируются, пока включён VPN. Сейчас в списке: ${s.shieldDomains.length}'),
                  ),
                  if (s.shieldDomains.isNotEmpty)
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final d in s.shieldDomains)
                        InputChip(
                          label: Text(d),
                          onDeleted: () => widget.box.vpn.update((y) =>
                              y.shieldDomains = y.shieldDomains.where((e) => e != d).toList()),
                        ),
                    ]),
                ]),
              ),
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text('🎓', style: TextStyle(fontSize: 26)),
                  title: const Text('Урок за минуту'),
                  subtitle: Text(
                      'Угадайте, где подвох. Пройдено ${widget.box.lessonsPassed.length} из ${lessons.length}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) => LessonsPage(box: widget.box))),
                ),
              ),
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text('👨‍👩‍👧', style: TextStyle(fontSize: 26)),
                  title: Text(widget.box.helper == null
                      ? 'Кого спрашивать'
                      : 'Спрашиваем: ${widget.box.helper!.name}'),
                  subtitle: Text(widget.box.helper?.phone ?? 'Добавьте близкого человека'),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => editHelper(context, widget.box),
                ),
              ),
            ],
          );
        },
      );
}

class VerdictCard extends StatelessWidget {
  const VerdictCard({super.key, required this.box, required this.verdict, required this.original});
  final BoxController box;
  final Verdict verdict;
  final String original;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final (color, art, emoji) = switch (v.level) {
      Level.stop => (Wok.chili, 'stop', '🔴'),
      Level.careful => (Wok.gold, 'careful', '🟡'),
      Level.ok => (Wok.jade, 'ok', '🟢'),
    };
    return Panel(
      color: Color.alphaBlend(color.withValues(alpha: .18), Wok.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: BoxArt(art, emoji, size: 110)),
        const SizedBox(height: 8),
        Text(v.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 10),
        for (final (i, r) in v.reasons.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i + 1}. ${r.title}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text(r.explain, style: const TextStyle(fontSize: 15, height: 1.35)),
              if (r.fragment.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .3), borderRadius: BorderRadius.circular(8)),
                  child: Text('«${r.fragment}»'),
                ),
            ]),
          ),
        Text(v.advice, style: const TextStyle(fontSize: 16, height: 1.4)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton.icon(
            style: fireButton,
            onPressed: () => askHelper(context, box, v, original),
            icon: const Icon(Icons.family_restroom_rounded),
            label: const Text('Спросить своих'),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              if (!await Device.speak(v.spoken) && context.mounted) {
                toast(context, 'На этом устройстве нет голоса для чтения');
              }
            },
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('Вслух'),
          ),
        ]),
      ]),
    );
  }
}

Future<void> editHelper(BuildContext context, BoxController box) async {
  final name = TextEditingController(text: box.helper?.name ?? '');
  final phone = TextEditingController(text: box.helper?.phone ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Кого спрашивать'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя')),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Телефон с кодом страны', hintText: '+389…'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Сохранить')),
      ],
    ),
  );
  final digits = phone.text.replaceAll(RegExp(r'[^\d+]'), '');
  if (ok == true && digits.length >= 5) {
    await box.setHelper(name.text.isEmpty ? 'Близкий' : name.text, digits);
  }
}

/// Opens WhatsApp or SMS with the suspicious text and the verdict filled in.
/// The person still presses "send" themselves.
Future<void> askHelper(
    BuildContext context, BoxController box, Verdict v, String original) async {
  final clipped = original.length > 700 ? '${original.substring(0, 700)}…' : original;
  final message = 'Посмотри, пожалуйста. Wokok Guard: «${v.title}».\n'
      '${v.reasons.take(3).map((r) => '• ${r.title}').join('\n')}\n\nСообщение:\n$clipped';
  await sendToHelper(context, box, message);
}

Future<void> sendToHelper(BuildContext context, BoxController box, String message) async {
  if (box.helper == null) await editHelper(context, box);
  final h = box.helper;
  if (h == null || !context.mounted) return;
  final how = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (id, icon, label) in [
          ('whatsapp', Icons.chat_rounded, 'WhatsApp: ${h.name}'),
          ('sms', Icons.sms_rounded, 'СМС: ${h.name}'),
          ('telegram', Icons.send_rounded, 'Telegram: выбрать чат'),
          ('copy', Icons.copy_rounded, 'Скопировать текст'),
        ])
          ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(c, id)),
      ]),
    ),
  );
  if (how == null || !context.mounted) return;
  final text = Uri.encodeComponent(message);
  final url = switch (how) {
    'whatsapp' => 'https://wa.me/${h.phone.replaceAll('+', '')}?text=$text',
    'sms' => 'sms:${h.phone}?body=$text',
    // Telegram's share link needs a url field; the text carries the content
    'telegram' => 'https://t.me/share/url?url=%20&text=$text',
    _ => null,
  };
  if (url == null) {
    copy(context, message);
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) copy(context, message, 'Не открылось. Текст скопирован.');
}

class LessonsPage extends StatefulWidget {
  const LessonsPage({super.key, required this.box});
  final BoxController box;
  @override
  State<LessonsPage> createState() => _LessonsPageState();
}

class _LessonsPageState extends State<LessonsPage> {
  late int _i = _firstOpen();
  bool? _answer;

  int _firstOpen() {
    for (var i = 0; i < lessons.length; i++) {
      if (!widget.box.lessonsPassed.contains(i)) return i;
    }
    return 0;
  }

  void _reply(bool scam) {
    setState(() => _answer = scam);
    if (scam == lessons[_i].scam) unawaited(widget.box.passLesson(_i));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.box,
        builder: (context, _) {
          final l = lessons[_i];
          final right = _answer == l.scam;
          final passed = widget.box.lessonsPassed.length;
          return BoxPage(
            title: 'Урок ${_i + 1} из ${lessons.length}',
            children: [
              LinearProgressIndicator(value: passed / lessons.length),
              const SizedBox(height: 14),
              Panel(
                color: Wok.paper,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.from,
                      style: const TextStyle(color: Color(0xFF7A5C40), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(l.text,
                      style: const TextStyle(color: Color(0xFF2A1D14), fontSize: 19, height: 1.4)),
                ]),
              ),
              if (_answer == null)
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Wok.chili, padding: const EdgeInsets.all(20)),
                      onPressed: () => _reply(true),
                      child: const Text('Развод', style: TextStyle(fontSize: 19, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Wok.jade, padding: const EdgeInsets.all(20)),
                      onPressed: () => _reply(false),
                      child: const Text('Нормально', style: TextStyle(fontSize: 19, color: Colors.black)),
                    ),
                  ),
                ])
              else ...[
                Panel(
                  title: right ? '✅ Верно!' : '❌ Не совсем',
                  child: Text(l.why, style: const TextStyle(fontSize: 17, height: 1.4)),
                ),
                FilledButton(
                  style: fireButton,
                  onPressed: () => setState(() {
                    _i = (_i + 1) % lessons.length;
                    _answer = null;
                  }),
                  child: const Text('Дальше'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => sendToHelper(context, widget.box,
                    'Мой прогресс в уроках Wokok Guard: $passed из ${lessons.length} ✔'),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Показать близким мой прогресс'),
              ),
            ],
          );
        },
      );
}
