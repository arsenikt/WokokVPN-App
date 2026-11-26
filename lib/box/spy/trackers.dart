/// Offline tracker database: who owns a host and why an app talks to it.
library;

enum TrackerKind { ads, analytics, social, telemetry, broker, cloud, service, unknown }

extension TrackerKindInfo on TrackerKind {
  String get title => switch (this) {
        TrackerKind.ads => 'реклама',
        TrackerKind.analytics => 'аналитика',
        TrackerKind.social => 'соцсети',
        TrackerKind.telemetry => 'телеметрия',
        TrackerKind.broker => 'торговцы данными',
        TrackerKind.cloud => 'облако',
        TrackerKind.service => 'сервис',
        TrackerKind.unknown => 'неизвестно',
      };

  /// Weight in the privacy grade; also decides what the lid covers.
  int get weight => switch (this) {
        TrackerKind.broker => 6,
        TrackerKind.ads => 4,
        TrackerKind.analytics => 3,
        TrackerKind.social => 2,
        TrackerKind.telemetry => 1,
        _ => 0,
      };
  bool get isTracker => weight > 0;
}

class Tracker {
  const Tracker(this.suffix, this.owner, this.kind, this.country);
  final String suffix;
  final String owner;
  final TrackerKind kind;
  final String country; // where the owner is based
}

// suffix|owner|kind|country ; the longest suffix wins.
const _db = '''
doubleclick.net|Google|ads|США
googlesyndication.com|Google|ads|США
googleadservices.com|Google|ads|США
adservice.google.com|Google|ads|США
google-analytics.com|Google|analytics|США
analytics.google.com|Google|analytics|США
googletagmanager.com|Google|analytics|США
app-measurement.com|Google Firebase|analytics|США
firebaselogging.googleapis.com|Google Firebase|telemetry|США
crashlytics.com|Google Firebase|telemetry|США
googleapis.com|Google|service|США
gstatic.com|Google|service|США
google.com|Google|service|США
youtube.com|Google|service|США
googlevideo.com|Google|service|США
1e100.net|Google|cloud|США
facebook.com|Meta|social|США
facebook.net|Meta|social|США
fbcdn.net|Meta|social|США
graph.facebook.com|Meta|analytics|США
instagram.com|Meta|social|США
whatsapp.net|Meta|service|США
an.facebook.com|Meta|ads|США
tiktok.com|ByteDance|social|Китай
tiktokv.com|ByteDance|social|Китай
byteoversea.com|ByteDance|analytics|Китай
ibytedtos.com|ByteDance|cloud|Китай
pangle.io|ByteDance|ads|Китай
pangolin-sdk-toutiao.com|ByteDance|ads|Китай
appsflyer.com|AppsFlyer|analytics|Израиль
appsflyersdk.com|AppsFlyer|analytics|Израиль
adjust.com|Adjust|analytics|Германия
adjust.io|Adjust|analytics|Германия
branch.io|Branch|analytics|США
app.link|Branch|analytics|США
kochava.com|Kochava|broker|США
singular.net|Singular|analytics|США
amplitude.com|Amplitude|analytics|США
mixpanel.com|Mixpanel|analytics|США
segment.io|Twilio Segment|broker|США
segment.com|Twilio Segment|broker|США
braze.com|Braze|analytics|США
onesignal.com|OneSignal|analytics|США
flurry.com|Yahoo Flurry|analytics|США
hotjar.com|Hotjar|analytics|Мальта
clarity.ms|Microsoft Clarity|analytics|США
newrelic.com|New Relic|telemetry|США
nr-data.net|New Relic|telemetry|США
sentry.io|Sentry|telemetry|США
bugsnag.com|Bugsnag|telemetry|США
datadoghq.com|Datadog|telemetry|США
unityads.unity3d.com|Unity Ads|ads|США
unity3d.com|Unity|analytics|США
applovin.com|AppLovin|ads|США
applvn.com|AppLovin|ads|США
ironsrc.com|ironSource|ads|Израиль
supersonicads.com|ironSource|ads|Израиль
vungle.com|Vungle|ads|США
chartboost.com|Chartboost|ads|США
inmobi.com|InMobi|ads|Индия
mintegral.com|Mintegral|ads|Китай
mtgglobals.com|Mintegral|ads|Китай
adcolony.com|AdColony|ads|США
startappservice.com|Start.io|ads|Израиль
mopub.com|MoPub|ads|США
adnxs.com|Microsoft Xandr|ads|США
rubiconproject.com|Magnite|ads|США
pubmatic.com|PubMatic|ads|США
openx.net|OpenX|ads|США
criteo.com|Criteo|ads|Франция
criteo.net|Criteo|ads|Франция
taboola.com|Taboola|ads|Израиль
outbrain.com|Outbrain|ads|США
amazon-adsystem.com|Amazon|ads|США
smartadserver.com|Equativ|ads|Франция
casalemedia.com|Index Exchange|ads|Канада
adsrvr.org|The Trade Desk|ads|США
scorecardresearch.com|Comscore|broker|США
quantserve.com|Quantcast|broker|США
demdex.net|Adobe|broker|США
omtrdc.net|Adobe|analytics|США
bluekai.com|Oracle|broker|США
krxd.net|Salesforce|broker|США
rlcdn.com|LiveRamp|broker|США
agkn.com|Neustar|broker|США
crwdcntrl.net|Lotame|broker|США
exelator.com|Nielsen|broker|США
liadm.com|LiveIntent|broker|США
id5-sync.com|ID5|broker|Великобритания
safegraph.com|SafeGraph|broker|США
cuebiq.com|Cuebiq|broker|США
x-mode.io|Outlogic|broker|США
yandex.ru|Яндекс|service|Россия
yandex.net|Яндекс|service|Россия
mc.yandex.ru|Яндекс Метрика|analytics|Россия
appmetrica.yandex.net|Яндекс AppMetrica|analytics|Россия
yandexadexchange.net|Яндекс|ads|Россия
an.yandex.ru|Яндекс|ads|Россия
vk.com|VK|social|Россия
mycdn.me|VK|cloud|Россия
ad.mail.ru|VK Реклама|ads|Россия
top-fwz1.mail.ru|VK Top.Mail|analytics|Россия
mail.ru|VK|service|Россия
umeng.com|Alibaba Umeng|analytics|Китай
alibaba.com|Alibaba|service|Китай
alicdn.com|Alibaba|cloud|Китай
qq.com|Tencent|service|Китай
bugly.qq.com|Tencent|telemetry|Китай
baidu.com|Baidu|analytics|Китай
miui.com|Xiaomi|telemetry|Китай
xiaomi.com|Xiaomi|telemetry|Китай
heytapmobile.com|OPPO|telemetry|Китай
hicloud.com|Huawei|telemetry|Китай
samsungads.com|Samsung|ads|Южная Корея
samsungcloud.com|Samsung|service|Южная Корея
ads.linkedin.com|LinkedIn|ads|США
linkedin.com|LinkedIn|social|США
ads-twitter.com|X|ads|США
twitter.com|X|social|США
sc-static.net|Snap|ads|США
snapchat.com|Snap|social|США
ads.pinterest.com|Pinterest|ads|США
bat.bing.com|Microsoft Ads|ads|США
events.data.microsoft.com|Microsoft|telemetry|США
vortex.data.microsoft.com|Microsoft|telemetry|США
telemetry.microsoft.com|Microsoft|telemetry|США
microsoft.com|Microsoft|service|США
windows.com|Microsoft|service|США
windowsupdate.com|Microsoft|service|США
live.com|Microsoft|service|США
office.com|Microsoft|service|США
metrics.icloud.com|Apple|telemetry|США
iadsdk.apple.com|Apple|ads|США
apple.com|Apple|service|США
icloud.com|Apple|service|США
adobe.com|Adobe|service|США
telemetry.mozilla.org|Mozilla|telemetry|США
mozilla.com|Mozilla|service|США
steamcommunity.com|Valve|service|США
steampowered.com|Valve|service|США
discord.com|Discord|service|США
discord.gg|Discord|service|США
telegram.org|Telegram|service|ОАЭ
amazonaws.com|Amazon AWS|cloud|США
cloudfront.net|Amazon AWS|cloud|США
akamaiedge.net|Akamai|cloud|США
akamai.net|Akamai|cloud|США
cloudflare.com|Cloudflare|cloud|США
fastly.net|Fastly|cloud|США
azureedge.net|Microsoft Azure|cloud|США
github.com|GitHub|service|США
githubusercontent.com|GitHub|service|США
''';

class TrackerDb {
  TrackerDb._();
  static final Map<String, Tracker> _map = () {
    final m = <String, Tracker>{};
    for (final line in _db.trim().split('\n')) {
      final p = line.split('|');
      m[p[0]] = Tracker(p[0], p[1], TrackerKind.values.byName(p[2]), p[3]);
    }
    return m;
  }();

  static int get size => _map.length;

  /// Longest matching suffix on label boundaries, or null.
  static Tracker? find(String host) {
    var h = host.toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    while (h.contains('.')) {
      final t = _map[h];
      if (t != null) return t;
      h = h.substring(h.indexOf('.') + 1);
    }
    return null;
  }
}
