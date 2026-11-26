import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../box/box_controller.dart';
import '../../box/deploy/deploy.dart';
import '../../box/deploy/folder_upload.dart';
import '../../box/ssh/box_ssh.dart';
import '../theme.dart';
import 'common.dart';

class DeployPage extends StatelessWidget {
  const DeployPage({super.key, required this.box});
  final BoxController box;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: box,
        builder: (context, _) => BoxPage(
          title: 'Deploy',
          children: [
            const Panel(
              child: Row(children: [
                BoxArt('deploy', '👨‍🍳', size: 72),
                SizedBox(width: 14),
                Expanded(
                    child: Muted(
                        'Ваш сервер без терминала. Каждое блюдо живёт в своём отсеке, а перед заказом вы видите чек: что изменится.')),
              ]),
            ),
            for (final s in box.servers)
              Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dns_rounded, color: Wok.fire),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${s.user}@${s.host}:${s.port}'),
                  trailing: IconButton(
                    tooltip: 'Забыть сервер',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirm(context, 'Забыть «${s.name}»?',
                          'Ключ удалится из приложения. На самом сервере ничего не изменится.',
                          yes: 'Забыть')) {
                        await box.removeServer(s.id);
                      }
                    },
                  ),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) => ServerPage(box: box, server: s))),
                ),
              ),
            FilledButton.icon(
              style: fireButton,
              onPressed: () => addServer(context, box),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить сервер'),
            ),
          ],
        ),
      );
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key, required this.box, required this.server});
  final BoxController box;
  final ServerAccess server;
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  BoxSsh? _ssh;
  ServerReport? _report;
  bool _busy = false;
  String? _error;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _ssh?.close();
    super.dispose();
  }

  Future<BoxSsh> _session() async {
    final s = _ssh;
    if (s != null && !s.client.isClosed) return s;
    return _ssh = await widget.box.connect(widget.server);
  }

  void _line(String l) {
    if (!mounted) return;
    setState(() {
      _log.add(l);
      if (_log.length > 400) _log.removeAt(0);
    });
  }

  /// Runs one server job with the busy flag and error reporting.
  Future<void> _job(Future<void> Function(BoxSsh ssh) work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ssh = await _session();
      await work(ssh);
      final j = await ssh.box(['check']);
      if (j != null) _report = ServerReport.fromJson(j);
    } catch (e) {
      _error = '$e';
      _line('! $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refresh() => _job((_) async {});

  void _done(Map<String, dynamic>? r) {
    final url = r?['url'] as String?;
    if (url != null) _line('+ Готово: $url');
  }

  /// The check before the order; returns true to cook.
  Future<bool> _approve(String title, Dish dish) async {
    final lines = planDish(_report!, dish);
    final blocked = lines.any((l) => l.level == CheckLevel.block);
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Чек: $title'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(
                          switch (l.level) {
                            CheckLevel.fine => Icons.check_circle_rounded,
                            CheckLevel.change => Icons.add_circle_rounded,
                            CheckLevel.warn => Icons.warning_rounded,
                            CheckLevel.block => Icons.block_rounded,
                          },
                          size: 18,
                          color: switch (l.level) {
                            CheckLevel.fine => Wok.jade,
                            CheckLevel.change => Wok.gold,
                            CheckLevel.warn => Wok.fire,
                            CheckLevel.block => Wok.chili,
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l.text)),
                      ]),
                    ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отменить')),
              FilledButton(
                  onPressed: blocked ? null : () => Navigator.pop(c, true),
                  child: const Text('Приготовить')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _vpn() async {
    if (!await _approve('VPN', const Dish(DishKind.vpn))) return;
    await _job((ssh) async {
      final r = await ssh.box(['vpn'], onLine: _line);
      final ticket = r?['ticket'] as String?;
      if (ticket == null) return;
      final vpn = widget.box.vpn;
      if (vpn.profiles.any((p) => p.host == widget.server.host)) {
        _line('+ VPN готов. Профиль этого сервера уже есть в «Кухнях»');
      } else {
        final p = await vpn.importLink(ticket);
        _line('+ VPN готов, профиль «${p.name}» добавлен в «Кухни»');
      }
    });
  }

  Future<void> _app(DishKind kind) async {
    final order = await showDialog<_Order>(
        context: context, builder: (_) => _OrderDialog(kind: kind));
    if (order == null || !mounted) return;
    final dish = Dish(kind, name: order.name, docker: order.docker, domain: order.domain);
    if (!await _approve(kind == DishKind.site ? 'сайт' : 'бот', dish)) return;
    await _job((ssh) async {
      final source = order.git ??
          (order.zip != null
              ? await FolderUpload.zip(ssh, order.zip!)
              : await FolderUpload.folder(ssh, order.folder!, onLine: _line));
      final r = await ssh.box(
        [
          kind == DishKind.site ? 'site' : 'bot',
          order.name,
          source,
          if (kind == DishKind.site && order.domain.isNotEmpty) order.domain,
        ],
        env: {'WB_DOCKER': order.docker ? '1' : '0'},
        stdin: kind == DishKind.bot ? utf8.encode('${order.env.trim()}\n') : null,
        onLine: _line,
      );
      _done(r);
      if (order.auto && order.git != null) {
        await ssh.box(['autoupdate', order.name, 'on'], onLine: _line);
      }
    });
  }

  Future<void> _recipe(Recipe r) async {
    if (!await _approve(r.title, Dish(DishKind.recipe, recipe: r))) return;
    await _job((ssh) async => _done(await ssh.box(['recipe', r.id], onLine: _line)));
  }

  Future<void> _command(List<String> args) =>
      _job((ssh) async => _done(await ssh.box(args, onLine: _line)));

  Widget _menuCard(String art, String emoji, String title, String about, VoidCallback onTap) =>
      SizedBox(
        width: 230,
        child: Material(
          color: Wok.bg2,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _busy || _report == null ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                BoxArt(art, emoji, size: 48),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(about, style: const TextStyle(color: Wok.muted, fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return BoxPage(
      title: widget.server.name,
      actions: [
        IconButton(
            tooltip: 'Обновить',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded)),
      ],
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Panel(child: Text(_error!, style: const TextStyle(color: Wok.chili))),
        if (r != null)
          Panel(
            child: Row(children: [
              Expanded(
                child: Muted(
                    '${r.os}\n${r.ramMb} МБ памяти · свободно ${(r.diskMb / 1024).toStringAsFixed(1)} ГБ\nVPN: ${r.vpn ? 'стоит' : 'нет'} · Docker: ${r.docker ? 'есть' : 'нет'}'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _command(['doctor']),
                icon: const Icon(Icons.medical_services_rounded),
                label: const Text('Доктор'),
              ),
            ]),
          ),
        Panel(
          title: 'Меню',
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            _menuCard('vpn', '🔥', 'VPN', 'Reality + запасной SSH, талон сам добавится', _vpn),
            _menuCard('site', '🌐', 'Сайт', 'Папка, ZIP или GitHub, сразу с HTTPS', () => _app(DishKind.site)),
            _menuCard('bot', '🤖', 'Telegram-бот', 'Python или Node.js, перезапуск сам', () => _app(DishKind.bot)),
          ]),
        ),
        if (r != null && r.apps.isNotEmpty)
          Panel(
            title: 'Отсеки',
            child: Column(children: [for (final a in r.apps) _appTile(a)]),
          ),
        Panel(
          title: 'Витрина рецептов',
          child: Column(children: [
            for (final x in serverRecipes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(x.emoji, style: const TextStyle(fontSize: 24)),
                title: Text(x.title),
                subtitle: Text('${x.about}${x.docker ? ' · Docker' : ''}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _busy || r == null ? null : () => _recipe(x),
              ),
          ]),
        ),
        if (_log.isNotEmpty) Panel(title: 'Что происходит на кухне', child: LogView(_log, height: 240)),
      ],
    );
  }

  Widget _appTile(DeployedApp a) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.circle, size: 14, color: a.active ? Wok.jade : Wok.chili),
        title: Text(a.name),
        subtitle: Text([
          a.type == 'bot' ? 'бот' : a.type == 'site' ? 'сайт' : 'рецепт',
          if (a.docker) 'Docker',
          if (a.auto) 'автообновление',
          if (a.domain.isNotEmpty) a.domain,
        ].join(' · ')),
        onTap: a.domain.isEmpty
            ? null
            : () => launchUrl(Uri.parse('https://${a.domain}'),
                mode: LaunchMode.externalApplication),
        trailing: PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (v) async {
            switch (v) {
              case 'logs':
                await _command(['logs', a.name]);
              case 'update':
                await _command(['update', a.name]);
              case 'auto':
                await _command(['autoupdate', a.name, a.auto ? 'off' : 'on']);
              case 'rollback':
                await _command(['rollback', a.name]);
              case 'remove':
                if (await confirm(context, 'Удалить отсек «${a.name}»?',
                    'Программа, её файлы и настройки на сервере будут стёрты безвозвратно.',
                    yes: 'Удалить')) {
                  await _command(['remove', a.name]);
                }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'logs', child: Text('Журнал')),
            if (a.git) const PopupMenuItem(value: 'update', child: Text('Обновить сейчас')),
            if (a.git)
              PopupMenuItem(
                  value: 'auto',
                  child: Text(a.auto ? 'Выключить автообновление' : 'Включить автообновление')),
            if (a.type != 'recipe-docker')
              const PopupMenuItem(value: 'rollback', child: Text('Откатить версию')),
            const PopupMenuItem(value: 'remove', child: Text('Удалить')),
          ],
        ),
      );
}

class _Order {
  String name = '';
  String domain = '';
  String env = '';
  String? git;
  Directory? folder;
  File? zip;
  bool docker = false;
  bool auto = false;
}

enum _Source { git, folder, zip }

class _OrderDialog extends StatefulWidget {
  const _OrderDialog({required this.kind});
  final DishKind kind;
  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  final _name = TextEditingController();
  final _repo = TextEditingController();
  final _domain = TextEditingController();
  final _token = TextEditingController();
  final _extra = TextEditingController();
  _Source _source = _Source.git;
  final _order = _Order();
  String? _error;

  bool get _bot => widget.kind == DishKind.bot;
  // folder access by path works on computers; phones use GitHub or ZIP
  bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void dispose() {
    for (final c in [_name, _repo, _domain, _token, _extra]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    if (_source == _Source.folder) {
      final path = await FilePicker.getDirectoryPath();
      if (path != null) setState(() => _order.folder = Directory(path));
    } else {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
      final path = r?.files.single.path;
      if (path != null) setState(() => _order.zip = File(path));
    }
  }

  void _submit() {
    final name = _name.text.trim().toLowerCase();
    String? error;
    if (!appNameRe.hasMatch(name)) error = 'Имя: латиница, цифры и дефис';
    if (_source == _Source.git && gitSource(_repo.text) == null) {
      error ??= 'Укажите репозиторий: хозяин/название или https://…';
    }
    if (_source == _Source.folder && _order.folder == null) error ??= 'Выберите папку';
    if (_source == _Source.zip && _order.zip == null) error ??= 'Выберите ZIP';
    final domain = _domain.text.trim().toLowerCase();
    if (domain.isNotEmpty && !RegExp(r'^([a-z0-9-]+\.)+[a-z]{2,24}$').hasMatch(domain)) {
      error ??= 'Неверный домен';
    }
    if (_bot && _token.text.contains(RegExp(r'\s'))) error ??= 'В токене не должно быть пробелов';
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _order
      ..name = name
      ..domain = domain
      ..git = _source == _Source.git ? gitSource(_repo.text) : null
      ..folder = _source == _Source.folder ? _order.folder : null
      ..zip = _source == _Source.zip ? _order.zip : null
      ..env = [
        if (_token.text.isNotEmpty) 'BOT_TOKEN=${_token.text}\nTELEGRAM_BOT_TOKEN=${_token.text}',
        _extra.text,
      ].join('\n');
    Navigator.pop(context, _order);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_bot ? 'Telegram-бот' : 'Сайт'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Название отсека, например shop')),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final (v, label) in [
                  (_Source.git, 'GitHub'),
                  if (_desktop) (_Source.folder, 'Папка'),
                  (_Source.zip, 'ZIP'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _source == v,
                    onSelected: (_) => setState(() => _source = v),
                  ),
              ]),
              if (_source == _Source.git)
                TextField(
                    controller: _repo,
                    decoration: const InputDecoration(
                        labelText: 'Репозиторий (открытый)', hintText: 'owner/repo'))
              else
                TextButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(_source == _Source.folder
                      ? _order.folder?.path ?? 'Выбрать папку'
                      : _order.zip?.path ?? 'Выбрать ZIP'),
                ),
              if (_bot) ...[
                TextField(
                  controller: _token,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Токен от BotFather',
                      helperText: 'Бот прочитает его из BOT_TOKEN'),
                ),
                TextField(
                  controller: _extra,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Другие переменные (КЛЮЧ=значение)'),
                ),
              ] else
                TextField(
                  controller: _domain,
                  decoration: const InputDecoration(
                      labelText: 'Свой домен (необязательно)',
                      helperText: 'Его запись A должна указывать на сервер'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _order.docker,
                onChanged: (v) => setState(() => _order.docker = v),
                title: const Text('Docker-отсек'),
                subtitle: const Text('Полная изоляция, нужно от 1 ГБ памяти'),
              ),
              if (_source == _Source.git)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _order.auto,
                  onChanged: (v) => setState(() => _order.auto = v),
                  title: const Text('Автообновление'),
                  subtitle: const Text('Новый коммит выкатится сам, а сломанный откатится'),
                ),
              if (_error != null) Text(_error!, style: const TextStyle(color: Wok.chili)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: _submit, child: const Text('К чеку')),
        ],
      );
}
