import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../box/box_controller.dart';
import '../../box/ssh/box_ssh.dart';
import '../theme.dart';

bool get canScanQr => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Generated artwork with an emoji stand-in if a file is missing.
class BoxArt extends StatelessWidget {
  const BoxArt(this.name, this.emoji, {super.key, this.size = 56});
  final String name;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/box/$name.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SizedBox(
          width: size,
          height: size,
          child: Center(child: Text(emoji, style: TextStyle(fontSize: size * .62))),
        ),
      );
}

/// Common page frame: title, centred column that stays readable on wide screens.
class BoxPage extends StatelessWidget {
  const BoxPage(
      {super.key, required this.title, required this.children, this.actions, this.leading});
  final Widget? leading;
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: leading,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: actions,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, this.title, required this.child, this.color});
  final String? title;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: color ?? Wok.card,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (title != null) ...[
                Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
              ],
              child,
            ]),
          ),
        ),
      );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Wok.muted, height: 1.4));
}

ButtonStyle get fireButton => FilledButton.styleFrom(
    backgroundColor: Wok.fire,
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14));

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

void copy(BuildContext context, String text, [String what = 'Скопировано']) {
  Clipboard.setData(ClipboardData(text: text));
  toast(context, what);
}

Future<bool> confirm(BuildContext context, String title, String text,
        {String yes = 'Да'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

/// Live output of a server command.
class LogView extends StatelessWidget {
  const LogView(this.lines, {super.key, this.height = 180});
  final List<String> lines;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.all(10),
        decoration:
            BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)),
        child: ListView.builder(
          reverse: true,
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final l = lines[lines.length - 1 - i];
            return SelectableText(
              l,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: l.startsWith('!')
                    ? Wok.chili
                    : l.startsWith('+')
                        ? Wok.jade
                        : Wok.paper,
              ),
            );
          },
        ),
      );
}

/// Dialog that adds a server: connects once, swaps the password for a key.
Future<ServerAccess?> addServer(BuildContext context, BoxController box) =>
    showDialog<ServerAccess>(
        context: context, barrierDismissible: false, builder: (_) => _AddServer(box));

class _AddServer extends StatefulWidget {
  const _AddServer(this.box);
  final BoxController box;
  @override
  State<_AddServer> createState() => _AddServerState();
}

class _AddServerState extends State<_AddServer> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _key = TextEditingController();
  bool _useKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _password, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    if (host.isEmpty || (_useKey ? _key.text.trim().isEmpty : _password.text.isEmpty)) {
      setState(() => _error = 'Нужны адрес и ${_useKey ? 'ключ' : 'пароль'}');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final access = ServerAccess(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? host : _name.text.trim(),
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 22,
      user: _user.text.trim().isEmpty ? 'root' : _user.text.trim(),
      password: _useKey ? null : _password.text,
      privateKey: _useKey ? '${_key.text.trim()}\n' : null,
    );
    BoxSsh? ssh;
    try {
      ssh = await widget.box.connect(access);
      await ssh.ensureAgent();
      if (!access.hasKey) await ssh.issueKey();
      await widget.box.saveServer(access);
      if (mounted) Navigator.pop(context, access);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    } finally {
      await ssh?.close();
    }
  }

  Widget _field(TextEditingController c, String label,
          {bool secret = false, int lines = 1, TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          enabled: !_busy,
          obscureText: secret,
          maxLines: lines,
          keyboardType: type,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Новый сервер'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(_host, 'IP или адрес сервера'),
              _field(_name, 'Название (необязательно)'),
              Row(children: [
                Expanded(flex: 3, child: _field(_user, 'Логин')),
                const SizedBox(width: 8),
                Expanded(child: _field(_port, 'SSH-порт', type: TextInputType.number)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Входить по ключу'),
                value: _useKey,
                onChanged: _busy ? null : (v) => setState(() => _useKey = v),
              ),
              if (_useKey)
                _field(_key, 'Приватный ключ (PEM) без пароля', lines: 4)
              else
                _field(_password, 'Пароль', secret: true),
              if (!_useKey)
                const Muted(
                    'Пароль нужен один раз: приложение получит свой ключ и пароль забудет.'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: Wok.chili)),
                ),
              if (_busy)
                const Padding(
                    padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Подключить')),
        ],
      );
}

/// Full-screen scanner that returns the first QR text it sees.
class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key});
  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Наведите на QR-код')),
        body: MobileScanner(onDetect: (cap) {
          if (_done) return;
          final raw = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          if (raw == null) return;
          _done = true;
          Navigator.of(context).pop(raw);
        }),
      );
}
