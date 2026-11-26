/// Pure logic of Deploy: what the server looks like and what a dish will change.
library;

class DeployedApp {
  DeployedApp(this.name, this.type, this.active, this.domain, this.auto, this.docker, this.git);
  final String name;
  final String type; // site | bot | recipe-docker
  final bool active;
  final String domain;
  final bool auto;
  final bool docker;
  final bool git;

  factory DeployedApp.fromJson(Map<String, dynamic> j) => DeployedApp(
        j['name'] as String,
        j['type'] as String,
        j['active'] == true,
        (j['domain'] ?? '') as String,
        j['auto'] == true,
        j['docker'] == true,
        j['git'] == true,
      );
}

class ServerReport {
  ServerReport({
    required this.os,
    required this.ramMb,
    required this.diskMb,
    required this.ip,
    required this.apt,
    required this.port80,
    required this.port443,
    required this.vpn,
    required this.caddy,
    required this.docker,
    required this.apps,
  });

  final String os;
  final int ramMb;
  final int diskMb;
  final String ip;
  final bool apt;
  final String port80;
  final String port443;
  final bool vpn;
  final bool caddy;
  final bool docker;
  final List<DeployedApp> apps;

  factory ServerReport.fromJson(Map<String, dynamic> j) => ServerReport(
        os: j['os'] as String,
        ramMb: (j['ramMb'] as num).toInt(),
        diskMb: (j['diskMb'] as num).toInt(),
        ip: j['ip'] as String,
        apt: j['apt'] == true,
        port80: (j['port80'] ?? '') as String,
        port443: (j['port443'] ?? '') as String,
        vpn: j['vpn'] == true,
        caddy: j['caddy'] == true,
        docker: j['docker'] == true,
        apps: [
          for (final a in (j['apps'] as List? ?? const []))
            DeployedApp.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
      );
}

enum DishKind { vpn, site, bot, recipe }

class Recipe {
  const Recipe(this.id, this.emoji, this.title, this.about,
      {this.docker = false, this.web = false, this.ramMb = 20, this.diskMb = 50});
  final String id;
  final String emoji;
  final String title;
  final String about;
  final bool docker;
  final bool web;
  final int ramMb;
  final int diskMb;
}

/// The recipe showcase. Ids match `box.sh recipe <id>`.
const serverRecipes = <Recipe>[
  Recipe('shield', '🛡️', 'Щит от взлома', 'fail2ban банит тех, кто подбирает пароль к серверу'),
  Recipe('updates', '🔄', 'Самообновление', 'Заплатки безопасности ставятся сами'),
  Recipe('turbo', '⚡', 'Турбо-сеть', 'BBR ускоряет VPN и сайты на плохих линиях', ramMb: 0, diskMb: 0),
  Recipe('swap', '🧊', 'Запас памяти', 'Файл подкачки 1 ГБ для маленьких серверов', ramMb: 0, diskMb: 1024),
  Recipe('monitor', '📈', 'Монитор', 'Uptime Kuma следит, живы ли ваши сайты', docker: true, web: true, ramMb: 220, diskMb: 900),
  Recipe('notes', '📝', 'Свои заметки', 'Memos: личная лента заметок', docker: true, web: true, ramMb: 150, diskMb: 500),
  Recipe('files', '🗂️', 'Свои файлы', 'File Browser: файлы сервера в браузере', docker: true, web: true, ramMb: 80, diskMb: 400),
];

class Dish {
  const Dish(this.kind, {this.name = '', this.docker = false, this.recipe, this.domain = ''});
  final DishKind kind;
  final String name;
  final bool docker;
  final Recipe? recipe;
  final String domain;
}

enum CheckLevel { fine, change, warn, block }

class CheckLine {
  const CheckLine(this.level, this.text);
  final CheckLevel level;
  final String text;
}

/// The "check before the order": everything the dish will touch, up front.
List<CheckLine> planDish(ServerReport s, Dish d) {
  final out = <CheckLine>[];
  void fine(String t) => out.add(CheckLine(CheckLevel.fine, t));
  void change(String t) => out.add(CheckLine(CheckLevel.change, t));
  void warn(String t) => out.add(CheckLine(CheckLevel.warn, t));
  void block(String t) => out.add(CheckLine(CheckLevel.block, t));

  fine('${s.os}, ${s.ramMb} МБ памяти, свободно ${(s.diskMb / 1024).toStringAsFixed(1)} ГБ');
  if (!s.apt) block('Нужен Debian или Ubuntu: на этой системе нет apt');

  final docker = d.docker || (d.recipe?.docker ?? false);
  var ram = d.recipe?.ramMb ?? (d.kind == DishKind.bot ? 90 : 40);
  var disk = d.recipe?.diskMb ?? 150;
  if (docker && !s.docker) {
    change('Установлю Docker (около 400 МБ)');
    ram += 120;
    disk += 400;
  }
  if (s.diskMb < disk + 200) block('Мало места: нужно около ${disk + 200} МБ');
  if (docker && s.ramMb < 700) {
    warn('Для Docker-отсека памяти мало. Выключите Docker или добавьте подкачку (рецепт «Запас памяти»)');
  } else if (s.ramMb < ram + 256) {
    warn('Памяти впритык: поможет рецепт «Запас памяти»');
  }

  final web = d.kind == DishKind.site || (d.recipe?.web ?? false);
  if (d.kind == DishKind.vpn) {
    if (s.vpn) {
      change('VPN уже есть: обновлю и починю, ключи и талоны останутся');
    } else {
      change('Установлю Xray Reality и запасной SSH-пользователь wokok');
    }
    if (s.port443.isEmpty || s.port443 == 'xray') {
      fine('Порт 443 для VPN доступен');
    } else if (s.port443 == 'caddy') {
      change('Сайты и VPN поделят порт 443 по имени сайта');
    } else {
      warn('Порт 443 занят (${s.port443}): VPN встанет на 8443');
    }
  }
  if (web) {
    for (final (port, owner) in [(80, s.port80), (443, s.port443)]) {
      if (owner.isNotEmpty && owner != 'caddy' && owner != 'haproxy' && !(port == 443 && owner == 'xray')) {
        block('Порт $port занят программой $owner');
      }
    }
    if (s.port443 == 'xray') {
      change('Подружу с VPN: HAProxy разведёт их на порту 443, талоны не изменятся');
    }
    if (!s.caddy) change('Установлю Caddy: HTTPS-сертификат появится сам');
    final name = d.recipe?.id ?? d.name;
    final domain = d.domain.isNotEmpty ? d.domain : '$name.${s.ip.replaceAll('.', '-')}.sslip.io';
    change('Адрес: https://$domain');
    fine('Проверьте, что порты 80 и 443 открыты в панели хостинга');
  }
  if (d.kind == DishKind.bot) {
    change('Запущу бота отдельным отсеком wb-${d.name} с автоперезапуском');
    fine('Токен ляжет в файл, который читает только root');
  }
  if (d.kind == DishKind.site || d.kind == DishKind.bot) {
    final exists = s.apps.any((a) => a.name == d.name);
    if (exists) {
      change('Отсек «${d.name}» уже есть: выкачу новую версию, при неудаче верну прежнюю');
    } else {
      fine('Если не запустится, уберу всё созданное');
    }
  }
  return out;
}

final appNameRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,30}$');

/// `owner/repo` or a full https URL -> the source argument of the agent.
String? gitSource(String input) {
  var s = input.trim();
  if (RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(s)) {
    s = 'https://github.com/$s';
  }
  return RegExp(r'^https://[A-Za-z0-9._~/@:%+-]+$').hasMatch(s) ? 'git:$s' : null;
}
