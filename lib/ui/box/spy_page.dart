import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../box/box_controller.dart';
import '../../box/spy/ledger.dart';
import '../../box/spy/trackers.dart';
import '../../core/vpn_controller.dart';
import '../theme.dart';
import 'common.dart';

Color gradeColor(String g) => switch (g) {
      'A' || 'B' => Wok.jade,
      'C' => Wok.gold,
      'D' => Wok.fire,
      _ => Wok.chili,
    };

class SpyPage extends StatelessWidget {
  const SpyPage({super.key, required this.box});
  final BoxController box;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Spy Check', style: TextStyle(fontWeight: FontWeight.w800)),
            bottom: const TabBar(tabs: [Tab(text: 'Чек'), Tab(text: 'Дозор'), Tab(text: 'Ловушка')]),
          ),
          body: ListenableBuilder(
            listenable: box,
            builder: (context, _) =>
                TabBarView(children: [_receipt(context), _night(context), _trap(context)]),
          ),
        ),
      );

  Widget _list(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );

  Widget _control() => Panel(
        child: Row(children: [
          const BoxArt('spy', '🕵️', size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(box.spying ? 'Слежу за слежкой' : 'Наблюдение выключено',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Muted(box.spyError ??
                  (box.spying
                      ? 'Источник: ${box.spySource}. Всё остаётся на этом устройстве.'
                      : Platform.isIOS
                          ? 'На iPhone видно только адреса: Apple не сообщает, какое приложение их открыло.'
                          : 'Покажу, какие приложения и куда отправляют данные.')),
            ]),
          ),
          Switch(value: box.spying, onChanged: (v) => v ? box.startSpy() : box.stopSpy()),
        ]),
      );

  Widget _receipt(BuildContext context) {
    final apps = box.spy.ranking;
    return _list([
      _control(),
      if (apps.isEmpty)
        const Panel(
            child: Muted('Чек пока пуст. Включите наблюдение и пользуйтесь устройством пару минут.')),
      for (final a in apps)
        Panel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: gradeColor(a.grade),
              child: Text(a.grade,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
            title: Text(a.hook, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              for (final k in TrackerKind.values)
                if (k.isTracker && a.countOf(k) > 0) '${k.title}: ${a.countOf(k)}',
              if (a.upload > 0) 'отправлено ${SpyLedger.formatBytes(a.upload)}',
              if (box.covered(a)) '🥡 накрыто крышкой',
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => ReceiptPage(box: box, app: a.app))),
          ),
        ),
      if (box.vpn.settings.blockedDomains.isNotEmpty)
        Panel(
          title: 'Под крышкой',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Muted(box.vpn.state == VpnState.on
                ? 'Эти адреса сейчас блокируются.'
                : 'Крышка действует, пока включён VPN.'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in box.vpn.settings.blockedDomains)
                InputChip(label: Text(d), onDeleted: () => box.unblock([d])),
            ]),
          ]),
        ),
    ]);
  }

  Widget _night(BuildContext context) {
    final n = box.spy.night();
    String two(int v) => v.toString().padLeft(2, '0');
    return _list([
      _control(),
      Panel(
        title: '🌙 Пока вы спали',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Muted(
              'Ночь с ${two(n.from.day)}.${two(n.from.month)} 23:00 до 07:00. Дозор видит только то время, когда наблюдение включено.'),
          const SizedBox(height: 10),
          Text(
              n.requests == 0 && n.upload == 0
                  ? 'За эту ночь записей нет.'
                  : '${n.requests} ${plural(n.requests, 'соединение', 'соединения', 'соединений')} · ${n.apps.length} ${plural(n.apps.length, 'приложение', 'приложения', 'приложений')} · отправлено ${SpyLedger.formatBytes(n.upload)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          for (final (app, requests, up) in n.apps.take(20))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(app),
              trailing: Text('$requests · ↑ ${SpyLedger.formatBytes(up)}'),
            ),
        ]),
      ),
      ..._alerts(context, AlertKind.newOwner, 'Новые знакомства',
          'Здесь появится сигнал, когда приложение после первых суток впервые свяжется с новым владельцем.'),
    ]);
  }

  Widget _trap(BuildContext context) => _list([
        _control(),
        const Panel(
          title: '🪤 Ловушка утечек',
          child: Muted(
              'Срабатывает, когда приложение за час отправляет намного больше обычного: от 5 МБ ночью и от 20 МБ днём. Объём данных виден, только пока включён VPN.'),
        ),
        ..._alerts(context, AlertKind.leak, 'Поймано', 'Пока никого. Это хорошая новость.'),
      ]);

  List<Widget> _alerts(BuildContext context, AlertKind kind, String title, String empty) {
    final list = box.spy.alerts.where((a) => a.kind == kind).toList();
    return [
      if (list.isEmpty) Panel(title: title, child: Muted(empty)),
      for (final a in list.take(30))
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠ ${a.text}'),
            Muted('${MaterialLocalizations.of(context).formatShortDate(a.time)} ${TimeOfDay.fromDateTime(a.time).format(context)} · ${a.host}'),
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () {
                  final t = TrackerDb.find(a.host);
                  box.block([t?.suffix ?? a.host]);
                  toast(context, 'Накрыто крышкой');
                },
                child: const Text('🥡 Накрыть'),
              ),
              TextButton(onPressed: () => box.trustApp(a.app), child: const Text('Это нормально')),
            ]),
          ]),
        ),
    ];
  }
}

/// The paper receipt of one app; can be saved as a picture and shared.
class ReceiptPage extends StatefulWidget {
  const ReceiptPage({super.key, required this.box, required this.app});
  final BoxController box;
  final String app;
  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final _paper = GlobalKey();

  Future<void> _save() async {
    try {
      final render = _paper.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2.5);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      image.dispose();
      final path = await FilePicker.saveFile(
          fileName: 'wokok-chek.png', type: FileType.image, bytes: png);
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(png);
      if (mounted) toast(context, 'Чек сохранён. Отправьте его друзьям!');
    } catch (_) {
      if (mounted) toast(context, 'Не удалось сохранить картинку');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.box,
        builder: (context, _) {
          final a = widget.box.spy.apps[widget.app];
          if (a == null) {
            return const BoxPage(title: 'Чек', children: [Muted('Записей больше нет.')]);
          }
          final domains = widget.box.trackerDomains(a);
          final covered = widget.box.covered(a);
          return BoxPage(
            title: 'Чек шпиона',
            children: [
              Center(child: RepaintBoundary(key: _paper, child: _Paper(a))),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                if (domains.isNotEmpty)
                  FilledButton.icon(
                    style: fireButton,
                    onPressed: () =>
                        covered ? widget.box.unblock(domains) : widget.box.block(domains),
                    icon: Icon(covered ? Icons.lock_open_rounded : Icons.block_rounded),
                    label: Text(covered ? 'Снять крышку' : 'Накрыть крышкой'),
                  ),
                OutlinedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.image_rounded),
                    label: const Text('Сохранить картинку')),
                OutlinedButton.icon(
                    onPressed: () => copy(context, '${a.hook}. Проверил в Wokok Box.'),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Копировать фразу')),
              ]),
              if (covered && widget.box.vpn.state != VpnState.on)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Muted('Крышка заработает, когда вы включите VPN.'),
                ),
            ],
          );
        },
      );
}

class _Paper extends StatelessWidget {
  const _Paper(this.a);
  final AppStat a;

  static const _ink = Color(0xFF2A1D14);
  static const _style = TextStyle(color: _ink, fontFamily: 'monospace', fontSize: 12.5);

  Widget _row(String l, String r, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(children: [
          Expanded(
              child: Text(l,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bold ? _style.copyWith(fontWeight: FontWeight.w900) : _style)),
          const SizedBox(width: 8),
          Text(r, style: bold ? _style.copyWith(fontWeight: FontWeight.w900) : _style),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final hosts = a.hosts.values.toList()
      ..sort((x, y) {
        final w = (y.tracker?.kind.weight ?? 0) - (x.tracker?.kind.weight ?? 0);
        return w != 0 ? w : y.hits - x.hits;
      });
    final countries = {for (final h in a.trackers) h.tracker!.country};
    const cut = Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('- - - - - - - - - - - - - - - - - - - - - - -',
          maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: _style),
    );
    return Container(
      width: 360,
      color: Wok.paper,
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Center(child: BoxArt('logo', '🥡', size: 54)),
        Text('WOKOK BOX\nЧЕК ШПИОНА',
            textAlign: TextAlign.center, style: _style.copyWith(fontWeight: FontWeight.w900, fontSize: 15)),
        cut,
        Text(a.hook, style: _style.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
        cut,
        for (final h in hosts.take(22))
          _row(h.host, h.tracker == null ? '?' : h.tracker!.kind.title),
        if (hosts.length > 22) _row('…и ещё ${hosts.length - 22}', ''),
        cut,
        for (final h in {for (final h in a.trackers) h.tracker!.owner}.take(8)) _row('Получатель', h),
        if (countries.isNotEmpty) Text('Страны владельцев: ${countries.join(', ')}', style: _style),
        _row('Отправлено', a.upload == 0 ? 'не измерено' : SpyLedger.formatBytes(a.upload)),
        cut,
        _row('ОЦЕНКА ПРИВАТНОСТИ', a.grade, bold: true),
        const SizedBox(height: 6),
        const Text('Проверено на устройстве. Спасибо, что заглянули под крышку.',
            textAlign: TextAlign.center, style: _style),
      ]),
    );
  }
}
