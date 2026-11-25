import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/profile.dart';
import '../core/vpn_controller.dart';
import 'theme.dart';

bool get _canScan => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class ServersPage extends StatelessWidget {
  const ServersPage({super.key, required this.vpn});
  final VpnController vpn;

  Future<void> _import(BuildContext context, String raw) async {
    final m = ScaffoldMessenger.of(context);
    try {
      final link = ProfileParser.sniff(raw) ?? raw;
      final p = await vpn.importLink(link);
      m.showSnackBar(SnackBar(content: Text('Добавлено: ${p.name}')));
    } on ProfileParseException catch (e) {
      m.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _paste(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text ?? '';
    if (ProfileParser.sniff(text) == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('В буфере нет ссылки vless:// или wokok://')));
      return;
    }
    await _import(context, text);
  }

  Future<void> _file(BuildContext context) async {
    final r = await FilePicker.pickFiles(type: FileType.any, withData: true);
    final bytes = r?.files.single.bytes;
    if (bytes == null || !context.mounted) return;
    await _import(context, String.fromCharCodes(bytes));
  }

  Future<void> _scan(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _ScanPage(), fullscreenDialog: true));
    if (code != null && context.mounted) await _import(context, code);
  }

  void _showTicket(BuildContext context, Profile p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Wok.bg2,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Талон', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Отсканируйте на другом устройстве Wokok',
              style: TextStyle(color: Wok.muted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Wok.paper, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(
              data: p.toTicket(),
              size: 240,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
              eyeStyle: const QrEyeStyle(color: Color(0xFF2A1D14), eyeShape: QrEyeShape.square),
              dataModuleStyle:
                  const QrDataModuleStyle(color: Color(0xFF2A1D14), dataModuleShape: QrDataModuleShape.square),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: p.toTicket()));
              Navigator.pop(context);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Копировать ссылку'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Кухни', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListenableBuilder(
        listenable: vpn,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_canScan)
                FilledButton.icon(
                  onPressed: () => _scan(context),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Сканировать QR'),
                  style: FilledButton.styleFrom(backgroundColor: Wok.fire, foregroundColor: Colors.black),
                ),
              FilledButton.tonalIcon(
                onPressed: () => _paste(context),
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Из буфера'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _file(context),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Из файла'),
              ),
            ]),
            const SizedBox(height: 16),
            if (vpn.profiles.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                      'Пока пусто. Откройте расширение Wokok в Chrome или панель сервера, покажите QR-талон и отсканируйте его здесь.',
                      style: TextStyle(color: Wok.muted, height: 1.4)),
                ),
              ),
            for (final p in vpn.profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: Wok.chili, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.delete_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) => vpn.removeProfile(p.id),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      onTap: () => vpn.selectProfile(p.id),
                      leading: Icon(
                        vpn.active?.id == p.id ? Icons.local_fire_department_rounded : Icons.dns_rounded,
                        color: vpn.active?.id == p.id ? Wok.fire : Wok.muted,
                      ),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${p.host}:${p.port} · ${p.security == 'reality' ? 'VLESS Reality' : 'VLESS'}${p.hasSshFallback ? ' + SSH' : ''}',
                          style: const TextStyle(color: Wok.muted, fontSize: 12.5)),
                      trailing: IconButton(
                        tooltip: 'Показать талон',
                        icon: const Icon(Icons.qr_code_2_rounded),
                        onPressed: () => _showTicket(context, p),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Наведите на QR-талон')),
      body: Stack(children: [
        MobileScanner(onDetect: (cap) {
          if (_done) return;
          final raw = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          if (raw != null && ProfileParser.sniff(raw) != null) {
            _done = true;
            Navigator.of(context).pop(raw);
          }
        }),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Wok.fire, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ]),
    );
  }
}
