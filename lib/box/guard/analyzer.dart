/// Guard: explains, on the device and in plain words, why a link, QR code or
/// message looks like a scam. Rules only: nothing is ever sent anywhere.
library;

enum Level { ok, careful, stop }

class Reason {
  const Reason(this.score, this.title, this.explain, [this.fragment = '']);
  final int score;
  final String title;
  final String explain;
  final String fragment; // what to highlight in the original text
}

class Verdict {
  Verdict(this.level, this.reasons, this.badHosts);
  final Level level;
  final List<Reason> reasons;

  /// Hosts the VPN shield may block.
  final List<String> badHosts;

  String get title => switch (level) {
        Level.stop => 'СТОП. Это похоже на развод',
        Level.careful => 'Осторожно',
        Level.ok => 'Похоже, всё нормально',
      };

  String get advice => switch (level) {
        Level.stop =>
          'Не открывайте ссылку, ничего не платите и не называйте коды. Позвоните близким или в банк по номеру с карты.',
        Level.careful =>
          'Не спешите. Проверьте отправителя другим способом: позвоните по знакомому номеру.',
        Level.ok =>
          'Явных признаков обмана не нашёл. Но коды из СМС всё равно никому не называйте.',
      };

  /// Short text for reading aloud.
  String get spoken => [
        title,
        for (final r in reasons.take(3)) r.title,
        advice,
      ].join('. ');
}

/// Brand -> its genuine domains.
const _brands = <String, List<String>>{
  'google': ['google.com', 'google.mk', 'google.ru', 'goo.gl', 'googleapis.com'],
  'apple': ['apple.com', 'icloud.com'],
  'icloud': ['icloud.com', 'apple.com'],
  'microsoft': ['microsoft.com', 'live.com', 'office.com', 'microsoftonline.com'],
  'facebook': ['facebook.com', 'fb.com', 'meta.com'],
  'instagram': ['instagram.com'],
  'whatsapp': ['whatsapp.com', 'whatsapp.net', 'wa.me'],
  'telegram': ['telegram.org', 't.me', 'telegram.me'],
  'netflix': ['netflix.com'],
  'amazon': ['amazon.com', 'amazon.de', 'amazonaws.com', 'amazon.co.uk'],
  'paypal': ['paypal.com', 'paypal.me'],
  'binance': ['binance.com'],
  'steam': ['steampowered.com', 'steamcommunity.com'],
  'dhl': ['dhl.com', 'dhl.de'],
  'sberbank': ['sberbank.ru', 'sber.ru'],
  'sber': ['sber.ru', 'sberbank.ru'],
  'tinkoff': ['tinkoff.ru', 'tbank.ru'],
  'gosuslugi': ['gosuslugi.ru'],
  'vtb': ['vtb.ru'],
  'alfabank': ['alfabank.ru'],
  'avito': ['avito.ru'],
  'ozon': ['ozon.ru'],
  'wildberries': ['wildberries.ru', 'wb.ru'],
  'yandex': ['yandex.ru', 'yandex.com', 'ya.ru', 'yandex.net'],
  'stopanskabanka': ['stb.com.mk'],
  'komercijalna': ['kb.mk'],
  'halkbank': ['halkbank.mk', 'halkbank.com.tr'],
  'sparkasse': ['sparkasse.mk', 'sparkasse.de', 'sparkasse.at'],
  'posta': ['posta.com.mk', 'pochta.ru'],
  'telekom': ['telekom.mk', 'telekom.de'],
};

const _shorteners = {
  'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'cutt.ly', 'is.gd', 'ow.ly', 'rb.gy',
  'clck.ru', 'vk.cc', 'shorturl.at', 'tiny.cc', 'rebrand.ly', 'qr.ae', 't.ly', 'u.to',
};
const _riskyTld = {
  'xyz', 'top', 'click', 'link', 'zip', 'mov', 'tk', 'ml', 'ga', 'cf', 'gq', 'icu',
  'buzz', 'cam', 'rest', 'monster', 'quest', 'sbs', 'cfd', 'work', 'support', 'live', 'shop',
};
const _freeHosts = {
  'github.io', 'netlify.app', 'vercel.app', 'pages.dev', 'workers.dev', 'web.app',
  'firebaseapp.com', 'blogspot.com', 'weebly.com', 'wixsite.com', 'glitch.me',
  'sslip.io', 'nip.io', 'duckdns.org', 'ngrok.io', 'ngrok-free.app', 'trycloudflare.com',
};
const _twoLevel = {
  'com.mk', 'org.mk', 'net.mk', 'edu.mk', 'gov.mk', 'co.uk', 'org.uk', 'com.tr',
  'com.ua', 'com.br', 'com.au', 'co.jp', 'co.il', 'com.cn', 'com.ru',
};

class _Pattern {
  _Pattern(this.score, this.title, this.explain, String re)
      : re = RegExp(re, caseSensitive: false, unicode: true);
  final int score;
  final String title;
  final String explain;
  final RegExp re;
}

// Russian, English and Macedonian in one pass.
final _patterns = <_Pattern>[
  _Pattern(
      3,
      'Торопят и пугают',
      'Мошенники не дают времени подумать. Настоящий банк так не пишет.',
      r'срочно|немедленно|сейчас же|в течение (\d+ )?(час|минут|суток)|иначе|будет заблокирован|заблокирован[аоы]?\b|последн(ее|ий) (предупреждение|шанс)|urgent|immediately|within \d+ (hours?|minutes?)|will be (blocked|suspended|closed)|account (is )?(suspended|locked)|last warning|итно|веднаш|во рок од|ќе биде блокиран|блокирана?та? картичка'),
  _Pattern(
      6,
      'Просят код, пароль или данные карты',
      'Код из СМС и CVV нужны только вору. Сотрудники банка их не спрашивают.',
      r'(назовите|сообщите|отправьте|пришлите|продиктуйте|введите|подтвердите)[^.!?\n]{0,40}(код|парол|cvv|cvc|пин|номер карты|данные карты)|код из (смс|sms)|(send|share|tell|enter|confirm|verify)[^.!?\n]{0,40}(code|password|cvv|pin\b|otp|card (number|details))|verification code|(испратете|кажете|внесете|потврдете)[^.!?\n]{0,40}(код|лозинк|пин|картичка)'),
  _Pattern(
      3,
      'Обещают деньги или выигрыш',
      'Бесплатный приз это приманка: потом попросят «комиссию» или данные карты.',
      r'выиграли|вы победител|приз\b|розыгрыш|вам (положена|начислена|одобрена) (выплата|компенсация|субсидия)|компенсаци[яю]|лотере|you (have )?won|winner|prize|lottery|free (gift|iphone|money)|claim your|освоивте|наградна игра|добитник|бесплатен подарок'),
  _Pattern(
      4,
      'Просят перевести деньги',
      'Перевод незнакомцу почти невозможно вернуть.',
      r'переведите|перевести (деньги|на карту|на счет|на счёт)|скинь (денег|на карту)|займи|одолжи|безопасный сч[её]т|комисси[юя]|предоплат|send (me )?(money|\$|€)|transfer (the )?(money|funds)|gift ?cards?|processing fee|western union|уплатете|префрлете|позајми|провизија'),
  _Pattern(
      4,
      'Притворяются родным человеком',
      '«Это я, новый номер» самый частый обман родителей. Перезвоните на старый номер.',
      r'(мам|пап|бабушк|дедушк)[а-я]*,?\s[^.!?\n]{0,30}(это я|новый номер|телефон (сломал|разбил|потерял))|это (мой )?новый номер|не звони, (просто )?напиши|попал[а]? в (аварию|дтп|полицию)|(hi|hey) (mum|mom|dad)|(this is )?my new number|lost my phone|(мамо|тато)[^.!?\n]{0,40}(јас сум|нов број)|ова е мојот нов број'),
  _Pattern(
      6,
      'Просят установить программу удалённого доступа',
      'Через AnyDesk и подобные программы вор управляет вашим телефоном и банком.',
      r'anydesk|teamviewer|rustdesk|quicksupport|ammyy|удал[её]нн(ый|ого) доступ|remote access|далечински пристап'),
  _Pattern(
      3,
      'Выдают себя за службу',
      'Банк, полиция или почта в сообщении ещё не доказательство. Перезвоните сами.',
      r'служба безопасности|сотрудник (банка|полиции|фсб)|следовател|ваша посылка|таможенн|налогов(ая|ой)|security (department|team)|your (parcel|package|delivery)|customs fee|tax refund|вашата пратка|царинска|банкарска служба'),
  _Pattern(
      3,
      'Обещают лёгкий заработок',
      'Гарантированной прибыли не бывает.',
      r'заработ(ок|ать) от \d+|пассивн(ый|ого) доход|гарантированн(ый|ая) (доход|прибыль)|инвестируйте|удвоим|work from home|guaranteed (profit|returns?)|double your (money|crypto|btc)|заработувачка|гарантиран профит'),
  _Pattern(
      3,
      'Просят секретности',
      'Фраза «никому не говорите» отрезает вас от тех, кто заметил бы обман.',
      r'никому не (говори|сообщай|рассказывай)|это секрет|не клади трубку|do not tell (anyone|anybody)|keep this (secret|between us)|не кажувај никому'),
];

final _urlRe = RegExp(
    r'''((https?://|www\.)[^\s<>"']+|(?<![@\w.-])(?:[a-zа-яё0-9-]+\.)+(?:com|net|org|ru|mk|xyz|top|info|io|me|ly|cc|app|site|online|shop|click|link|live|icu|рф|мкд)(?![\w-])(?:/[^\s<>"']*)?)''',
    caseSensitive: false,
    unicode: true);

class Guard {
  /// Checks free text: a message, a link, or the content of a QR code.
  static Verdict check(String input, {Set<String> trustedHosts = const {}}) {
    final text = input.trim();
    final reasons = <Reason>[];
    final bad = <String>[];
    final lower = text.toLowerCase();

    final special = _special(text);
    if (special != null) {
      reasons.addAll(special);
    } else {
      for (final p in _patterns) {
        final m = p.re.firstMatch(text);
        if (m != null) reasons.add(Reason(p.score, p.title, p.explain, m.group(0)!));
      }
      var hasLink = false;
      for (final m in _urlRe.allMatches(text)) {
        hasLink = true;
        final raw = m.group(0)!.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
        final found = checkUrl(raw, trustedHosts: trustedHosts);
        if (found.$2.isEmpty) continue;
        reasons.addAll(found.$2);
        final score = found.$2.fold(0, (n, r) => n + r.score);
        if (score >= 6 && found.$1 != null) bad.add(found.$1!);
      }
      if (hasLink && reasons.any((r) => r.title == 'Торопят и пугают')) {
        reasons.add(const Reason(2, 'Спешка и ссылка вместе',
            'Классическая схема: напугать и подсунуть страницу для ввода данных.'));
      }
      if (lower.contains('.apk')) {
        reasons.add(const Reason(6, 'Предлагают скачать APK-файл',
            'Приложения из сообщений часто воруют СМС и деньги. Только официальный магазин.', '.apk'));
      }
    }

    reasons.sort((a, b) => b.score.compareTo(a.score));
    final total = reasons.fold(0, (n, r) => n + r.score);
    final level = total >= 6
        ? Level.stop
        : total >= 3
            ? Level.careful
            : Level.ok;
    return Verdict(level, reasons, bad.toSet().toList());
  }

  static List<Reason>? _special(String t) {
    final l = t.toLowerCase();
    if (l.startsWith('wifi:')) {
      final open = l.contains('t:nopass') || !l.contains('t:');
      return [
        Reason(open ? 3 : 1, 'QR подключает к Wi-Fi',
            open ? 'Сеть без пароля: чужой может подсматривать. Включите VPN.' : 'Подключайтесь, только если доверяете хозяину сети.'),
      ];
    }
    if (l.startsWith('smsto:') || l.startsWith('sms:')) {
      return const [Reason(4, 'QR отправляет СМС', 'Так подписывают на платные услуги. Посмотрите номер и текст.')];
    }
    if (l.startsWith('tel:')) {
      return const [Reason(3, 'QR набирает номер', 'Убедитесь, что номер знакомый: бывают платные линии.')];
    }
    if (l.startsWith('otpauth:')) {
      return const [Reason(3, 'QR добавляет коды входа', 'Сканируйте такой код, только если сами сейчас включаете защиту аккаунта.')];
    }
    if (RegExp(r'^(bitcoin|ethereum|litecoin|tron|solana):', caseSensitive: false).hasMatch(t) ||
        RegExp(r'^(0x[a-fA-F0-9]{40}|bc1[a-z0-9]{25,60}|T[1-9A-HJ-NP-Za-km-z]{33})$').hasMatch(t)) {
      return const [Reason(6, 'QR для перевода криптовалюты', 'Такой перевод нельзя отменить. «Оплата по QR» в письме или на столбе почти всегда обман.')];
    }
    if (l.startsWith('javascript:') || l.startsWith('data:')) {
      return const [Reason(8, 'Опасная ссылка со скриптом', 'Она выполняет код вместо открытия сайта.')];
    }
    if (l.startsWith('vless://') || l.startsWith('wokok://')) {
      return const [Reason(3, 'Это настройки VPN', 'Через чужой VPN виден ваш трафик. Берите талоны только у себя или у близких.')];
    }
    return null;
  }

  /// Returns the host and everything suspicious about the link.
  static (String?, List<Reason>) checkUrl(String raw, {Set<String> trustedHosts = const {}}) {
    var s = raw.trim();
    final explicitHttp = s.toLowerCase().startsWith('http://');
    if (!s.contains('://')) s = 'https://$s';
    final m = RegExp(r'^[a-z]+://([^/?#]*)([^]*)$', caseSensitive: false).firstMatch(s);
    if (m == null) return (null, const []);
    var authority = m.group(1)!;
    final rest = m.group(2)!.toLowerCase();
    final out = <Reason>[];
    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      authority = authority.substring(at + 1);
      out.add(Reason(6, 'Обманный знак @ в адресе',
          'Всё до @ ничего не значит. На самом деле откроется $authority.', raw));
    }
    final host = authority.toLowerCase().replaceAll(RegExp(r':\d+$'), '').replaceAll(RegExp(r'\.$'), '');
    if (host.isEmpty) return (null, out);

    final labels = host.split('.');
    var take = 2;
    if (labels.length >= 3 && _twoLevel.contains(labels.sublist(labels.length - 2).join('.'))) take = 3;
    final domain = labels.length <= take ? host : labels.sublist(labels.length - take).join('.');
    final genuine = _brands.values.any((l) => l.contains(domain));
    if (trustedHosts.contains(host) || genuine) {
      if (explicitHttp) {
        out.add(Reason(2, 'Соединение без защиты', 'Адрес начинается с http: данные идут открытым текстом.', raw));
      }
      return (host, out);
    }

    if (RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(host) || host.startsWith('[')) {
      out.add(Reason(5, 'Вместо имени сайта цифры', 'Настоящие банки и магазины не дают ссылки на голый IP-адрес.', host));
    }
    final nonAscii = host.runes.any((r) => r > 127);
    final latin = RegExp(r'[a-z]').hasMatch(labels.first) || RegExp(r'[a-z]').hasMatch(domain.split('.').first);
    final cyr = RegExp(r'\p{Script=Cyrillic}', unicode: true).hasMatch(domain.split('.').first);
    if (host.contains('xn--') || (nonAscii && cyr && latin)) {
      out.add(Reason(6, 'Буквы-двойники в адресе', 'Похожие буквы из другого алфавита подделывают знакомый сайт.', host));
    }

    final plain = _skeleton(domain.split('.').first);
    String? faked;
    for (final e in _brands.entries) {
      final brand = e.key;
      if (e.value.contains(domain)) continue;
      final inName = brand.length >= 5
          ? _skeleton(host).contains(_skeleton(brand))
          : host.split(RegExp(r'[.-]')).contains(brand);
      final typo = brand.length >= 5 &&
          (plain == _skeleton(brand) || _distance(domain.split('.').first, brand) == 1);
      if (inName || typo) {
        faked = brand;
        break;
      }
    }
    if (faked != null) {
      out.add(Reason(7, 'Подделка под «$faked»',
          'Настоящий адрес: ${_brands[faked]!.first}. А это чужой сайт $domain.', host));
    }

    final tld = labels.last;
    if (_riskyTld.contains(tld)) {
      out.add(Reason(3, 'Дешёвая доменная зона .$tld', 'Такие адреса стоят копейки и часто живут один день.', domain));
    }
    if (_shorteners.contains(domain)) {
      out.add(Reason(3, 'Сокращённая ссылка', 'Не видно, куда она ведёт.', host));
    }
    if (_freeHosts.contains(domain)) {
      out.add(Reason(2, 'Бесплатный хостинг', 'Такую страницу может сделать кто угодно за пять минут.', domain));
    }
    if (labels.length >= 5) {
      out.add(Reason(3, 'Слишком длинный адрес', 'Настоящее имя сайта спрятано в конце: $domain.', host));
    }
    if (domain.split('-').length >= 3) {
      out.add(Reason(2, 'Много дефисов в имени', 'Так собирают названия поддельных страниц.', domain));
    }
    if (RegExp(r'(login|signin|verify|secure|confirm|update|bonus|prize|wallet|oplata|vhod)').hasMatch('$host$rest')) {
      out.add(Reason(2, 'Страница входа или оплаты', 'Не вводите пароль и карту, пока не проверили адрес.', raw));
    }
    if (explicitHttp) {
      out.add(Reason(2, 'Соединение без защиты', 'Адрес начинается с http: данные идут открытым текстом.', raw));
    }
    if (rest.contains('.apk') || rest.endsWith('.exe') || rest.endsWith('.scr')) {
      out.add(Reason(5, 'Ссылка качает программу', 'Не устанавливайте программы из сообщений.', raw));
    }
    return (host, out);
  }

  /// Folds look-alike characters: g00gle -> google, paypa1 -> paypal.
  static String _skeleton(String s) {
    const map = {
      '0': 'o', '1': 'l', '3': 'e', '5': 's', '@': 'a',
      'а': 'a', 'е': 'e', 'о': 'o', 'р': 'p', 'с': 'c', 'х': 'x', 'у': 'y', 'і': 'i',
    };
    final b = StringBuffer();
    for (final c in s.split('')) {
      b.write(map[c] ?? c);
    }
    return b.toString().replaceAll('rn', 'm').replaceAll('vv', 'w').replaceAll(RegExp(r'[-.]'), '');
  }

  /// Edit distance where a swap of neighbours counts once.
  static int _distance(String a, String b) {
    if ((a.length - b.length).abs() > 1) return 2;
    final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
        if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] && d[i - 2][j - 2] + 1 < v) {
          v = d[i - 2][j - 2] + 1;
        }
        d[i][j] = v;
      }
    }
    return d[a.length][b.length];
  }
}
