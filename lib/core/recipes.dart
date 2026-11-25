/// "Recipes" — routing presets.
enum Recipe {
  all('Всё в вок', 'Весь трафик идёт через VPN'),
  smart('Умный', 'Банки и госсайты напрямую, остальное через VPN'),
  selected('Только выбранное', 'Через VPN только ваш список сайтов');

  const Recipe(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Domains that stay direct in Smart mode (RU banks / government / local).
const smartDirectSuffixes = <String>[
  'gosuslugi.ru', 'nalog.ru', 'mos.ru', 'sberbank.ru', 'sber.ru',
  'sberbank.com', 'tinkoff.ru', 'tbank.ru', 'vtb.ru', 'alfabank.ru',
  'raiffeisen.ru', 'gazprombank.ru', 'yandex.ru', 'ya.ru', 'vk.com',
  'mail.ru', 'ozon.ru', 'wildberries.ru', 'avito.ru', 'rzd.ru', 'cbr.ru',
];
