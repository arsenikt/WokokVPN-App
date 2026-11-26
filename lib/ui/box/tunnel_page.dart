import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../box/box_controller.dart';
import '../../box/ssh/box_ssh.dart';
import '../../box/tunnel/tunnel_proxy.dart';
import '../../box/tunnel/tunnel_session.dart';
import '../theme.dart';
import 'common.dart';

class TunnelPage extends StatefulWidget {
  const TunnelPage({super.key, required this.box});
  final BoxController box;
  @override
  State<TunnelPage> createState() => _TunnelPageState();
}

class _TunnelPageState extends State<TunnelPage> {
  final _port = TextEditingController(text: '3000');
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();
  String? _server;
  Duration? _ttl = const Duration(hours: 1);
  bool _guests = false;
  bool _ownDomain = false;
  bool _busy = false;
  String? _error;
  final List<String> _log = [];
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.box.tunnel != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final c in [_port, _name, _password, _domain]) {
      c.dispose();
    }
    super.dispose();
  }

  ServerAccess? get _selected {
    final list = widget.box.servers;
    if (list.isEmpty) return null;
    return list.firstWhere((s) => s.id == _server, orElse: () => list.first);
  }

  Future<void> _open() async {
    final server = _selected;
    final port = int.tryParse(_port.text.trim());
    if (server == null || port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Выберите сервер и порт от 1 до 65535');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _log.clear();
    });
    try {
      var name = _name.text.trim().toLowerCase();
      if (name.isEmpty) name = TunnelSession.randomName();
      String? domain;
      final base = _domain.text.trim().toLowerCase();
      if (_ownDomain && base.isNotEmpty) {
        domain = '$name.$base';
        if (!await TunnelSession.domainPointsTo(domain, server.host)) {
          throw BoxException(
              '$domain пока не указывает на сервер. В настройках DNS добавьте запись  *.$base  A  ${server.host}  и подождите несколько минут.');
        }
      }
      await widget.box.openTunnel(
        server,
        TunnelRules(
          localPort: port,
          expiresAt: _ttl == null ? null : DateTime.now().add(_ttl!),
          password: _password.text.isEmpty ? null : _password.text,
          guests: _guests,
        ),
        name: name,
        domain: domain,
        onLine: (l) {
          if (mounted) setState(() => _log.add(l));
        },
      );
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  String _left(DateTime? until) {
    if (until == null) return 'без срока';
    final d = until.difference(DateTime.now());
    if (d.isNegative) return 'истекает';
    String two(int n) => n.toString().padLeft(2, '0');
    final head = d.inDays > 0 ? '${d.inDays} дн ' : '';
    return 'осталось $head${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.box,
        builder: (context, _) {
          final t = widget.box.tunnel;
          return BoxPage(
            title: 'Tunnel',
            children: t == null ? _form() : _live(t),
          );
        },
      );

  List<Widget> _form() {
    final servers = widget.box.servers;
    return [
      const Panel(
        child: Row(children: [
          BoxArt('tunnel', '🛵', size: 72),
          SizedBox(width: 14),
          Expanded(
              child: Muted(
                  'Доставка вашего localhost: публичная HTTPS-ссылка через ваш собственный сервер. Пока ссылка открыта, не закрывайте приложение.')),
        ]),
      ),
      if (widget.box.tunnelEnded != null)
        Panel(child: Text(widget.box.tunnelEnded!, style: const TextStyle(color: Wok.gold))),
      if (servers.isEmpty)
        Panel(
          title: 'Сначала сервер',
          child: FilledButton.icon(
            style: fireButton,
            onPressed: () => addServer(context, widget.box),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить сервер'),
          ),
        )
      else
        Panel(
          title: 'Новый заказ',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              value: _selected!.id,
              decoration: const InputDecoration(labelText: 'Через какой сервер'),
              items: [for (final s in servers) DropdownMenuItem(value: s.id, child: Text(s.name))],
              onChanged: (v) => setState(() => _server = v),
            ),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Локальный порт', prefixText: 'localhost:'),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Имя ссылки (пусто: придумаю блюдо)'),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              for (final (label, d) in const [
                ('1 час', Duration(hours: 1)),
                ('Сутки', Duration(days: 1)),
                ('Неделя', Duration(days: 7)),
                ('Без срока', null),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _ttl == d,
                  onSelected: (_) => setState(() => _ttl = d),
                ),
            ]),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль на ссылку (необязательно)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _guests,
              onChanged: (v) => setState(() => _guests = v),
              title: const Text('Режим гостей'),
              subtitle: const Text('На страницах появится кнопка «Заметка», сообщения придут сюда'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ownDomain,
              onChanged: (v) => setState(() => _ownDomain = v),
              title: const Text('Свой домен'),
              subtitle: const Text('Без него адрес будет вида имя.1-2-3-4.sslip.io'),
            ),
            if (_ownDomain)
              TextField(
                controller: _domain,
                decoration: InputDecoration(
                  labelText: 'Домен, например dev.mysite.com',
                  helperText: 'DNS: *.ваш-домен  A  ${_selected!.host}',
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: fireButton,
              onPressed: _busy ? null : _open,
              icon: const Icon(Icons.delivery_dining_rounded),
              label: Text(_busy ? 'Готовлю…' : 'Открыть доставку'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Wok.chili)),
              ),
            if (_log.isNotEmpty) ...[const SizedBox(height: 10), LogView(_log, height: 120)],
            TextButton.icon(
              onPressed: () => addServer(context, widget.box),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ещё сервер'),
            ),
          ]),
        ),
      const Panel(
        title: 'Одна команда в терминале',
        child: SelectableText(
          'wokok-box login root@ваш-сервер\nwokok-box share 3000 --ttl 1d --guests',
          style: TextStyle(fontFamily: 'monospace'),
        ),
      ),
    ];
  }

  List<Widget> _live(TunnelSession t) {
    final p = t.proxy;
    final r = p.rules;
    return [
      Panel(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Wok.paper, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(data: t.url, size: 190),
          ),
          const SizedBox(height: 12),
          SelectableText(t.url,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Wok.gold)),
          const SizedBox(height: 4),
          Muted('localhost:${r.localPort} · ${_left(r.expiresAt)}'
              '${r.password != null ? ' · под паролем' : ''}${r.guests ? ' · гости' : ''}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              style: fireButton,
              onPressed: () => copy(context, t.url, 'Ссылка скопирована'),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Копировать'),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(t.url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Открыть'),
            ),
            OutlinedButton.icon(
              onPressed: widget.box.closeTunnel,
              icon: const Icon(Icons.close_rounded, color: Wok.chili),
              label: const Text('Закрыть'),
            ),
          ]),
        ]),
      ),
      if (p.notes.isNotEmpty)
        Panel(
          title: 'Заметки гостей (${p.notes.length})',
          child: Column(children: [
            for (final n in p.notes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Text('💬', style: TextStyle(fontSize: 22)),
                title: Text(n.text),
                subtitle: Text('${n.author.isEmpty ? 'Гость' : n.author} · ${n.page}'),
              ),
          ]),
        ),
      Panel(
        title: 'Запросы вживую',
        child: p.requests.isEmpty
            ? const Muted('Пока никто не заходил.')
            : Column(children: [
                for (final q in p.requests.take(60))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _details(q),
                    leading: Text(
                      '${q.status ?? '…'}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: (q.status ?? 0) >= 400 ? Wok.chili : Wok.jade),
                    ),
                    title: Text('${q.method} ${q.uri}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${TimeOfDay.fromDateTime(q.time).format(context)} · ${q.millis ?? '…'} мс${q.replay ? ' · повтор' : ''}'),
                    trailing: IconButton(
                      tooltip: 'Повторить запрос',
                      icon: const Icon(Icons.replay_rounded),
                      onPressed: q.truncated ? null : () => p.replay(q),
                    ),
                  ),
              ]),
      ),
    ];
  }

  void _details(RequestEntry q) {
    final body = utf8.decode(q.body, allowMalformed: true);
    final text = StringBuffer('${q.method} ${q.uri}\n\n');
    q.headers.forEach((k, v) => text.writeln('$k: ${v.join(', ')}'));
    if (body.isNotEmpty) {
      text.write('\n${body.length > 8000 ? '${body.substring(0, 8000)}…' : body}');
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(text.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
        ),
      ),
    );
  }
}
