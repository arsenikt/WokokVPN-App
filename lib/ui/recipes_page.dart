import 'package:flutter/material.dart';

import '../core/recipes.dart';
import '../core/vpn_controller.dart';
import 'theme.dart';

class RecipesPage extends StatelessWidget {
  const RecipesPage({super.key, required this.vpn});
  final VpnController vpn;

  static const _icons = {
    Recipe.all: Icons.public_rounded,
    Recipe.smart: Icons.auto_awesome_rounded,
    Recipe.selected: Icons.checklist_rounded,
  };

  Future<void> _editDomains(BuildContext context) async {
    final c = TextEditingController(text: vpn.settings.selectedDomains.join('\n'));
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Wok.bg2,
        title: const Text('Сайты через VPN'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: c,
            maxLines: 8,
            decoration: const InputDecoration(
                hintText: 'Один домен на строку\nпример: youtube.com', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (res == null) return;
    final list = res
        .split(RegExp(r'[\s,;]+'))
        .map((e) => e.trim().toLowerCase().replaceAll(RegExp(r'^https?://|/.*$'), ''))
        .where((e) => e.contains('.'))
        .toSet()
        .toList();
    await vpn.update((s) => s.selectedDomains = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Рецепты', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListenableBuilder(
        listenable: vpn,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12, left: 4),
              child: Text('Что готовим: какой трафик отправлять через VPN',
                  style: TextStyle(color: Wok.muted)),
            ),
            for (final r in Recipe.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                        color: vpn.settings.recipe == r ? Wok.fire : Colors.transparent, width: 1.6),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onTap: () => vpn.update((s) => s.recipe = r),
                    leading: CircleAvatar(
                      backgroundColor: Wok.fire.withValues(alpha: .16),
                      child: Icon(_icons[r], color: Wok.fire),
                    ),
                    title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r.subtitle, style: const TextStyle(color: Wok.muted)),
                    trailing: vpn.settings.recipe == r
                        ? const Icon(Icons.check_circle_rounded, color: Wok.fire)
                        : null,
                  ),
                ),
              ),
            if (vpn.settings.recipe == Recipe.selected)
              Card(
                child: ListTile(
                  onTap: () => _editDomains(context),
                  leading: const Icon(Icons.edit_rounded, color: Wok.gold),
                  title: const Text('Список сайтов'),
                  subtitle: Text('${vpn.settings.selectedDomains.length} доменов'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
