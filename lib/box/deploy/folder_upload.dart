import 'dart:convert';
import 'dart:io';

import '../ssh/box_ssh.dart';

/// Copies a project folder (or a ZIP) to a temporary place on the server and
/// returns the source argument for the agent.
class FolderUpload {
  static const _skip = {'node_modules', '.git', '.venv', 'venv', '__pycache__', '.dart_tool'};
  static const maxBytes = 80 * 1024 * 1024;
  static const maxFiles = 3000;

  static String _tmp() => '/tmp/wokok-up-${DateTime.now().microsecondsSinceEpoch}';

  static List<(File, String)> collect(Directory root) {
    final out = <(File, String)>[];
    var size = 0;
    void walk(Directory d, String rel) {
      for (final e in d.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        final path = rel.isEmpty ? name : '$rel/$name';
        if (e is Directory) {
          if (!_skip.contains(name)) walk(e, path);
        } else if (e is File) {
          // secrets stay on the computer; tokens are entered separately
          if (name == '.env') continue;
          size += e.lengthSync();
          out.add((e, path));
          if (size > maxBytes || out.length > maxFiles) {
            throw BoxException('Папка слишком большая. Для крупных проектов используйте GitHub.');
          }
        }
      }
    }

    walk(root, '');
    if (out.isEmpty) throw BoxException('Папка пуста');
    return out;
  }

  static Future<String> folder(BoxSsh ssh, Directory root, {LineSink? onLine}) async {
    final files = collect(root);
    final dst = _tmp();
    final dirs = <String>{dst};
    for (final (_, rel) in files) {
      final i = rel.lastIndexOf('/');
      if (i > 0) dirs.add('$dst/${rel.substring(0, i)}');
    }
    final code = await ssh.exec('xargs -0 mkdir -p',
        stdin: [
          for (final d in dirs) ...[...utf8.encode(d), 0],
        ]);
    if (code != 0) throw BoxException('Не удалось создать папки на сервере');
    var n = 0;
    for (final (file, rel) in files) {
      await ssh.upload('$dst/$rel', await file.readAsBytes());
      if (++n % 25 == 0 || n == files.length) {
        onLine?.call('> Загружено $n из ${files.length}');
      }
    }
    return 'dir:$dst';
  }

  static Future<String> zip(BoxSsh ssh, File file) async {
    if (await file.length() > maxBytes) throw BoxException('Архив больше 80 МБ');
    final dst = '${_tmp()}.zip';
    await ssh.upload(dst, await file.readAsBytes());
    return 'zip:$dst';
  }
}

