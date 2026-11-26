# Wokok графика: пакет промптов для Gemini

Gemini нельзя вызвать отсюда без вашего API-ключа, поэтому все промпты собраны в одном месте.
Положите результаты в `assets/gemini-raw/` под именами из таблицы и запустите:

```
python tools/import_gemini.py
```

Скрипт нарежет размеры, обновит иконки приложения и трея, положит картинки онбординга и баннер для сайта.

## Общий стиль (вставляйте в начало КАЖДОГО промпта)

> Art style: glossy 3D-rendered neon illustration, a black cast-iron wok on a gas flame with glowing orange
> noodles forming a shield with a Wi-Fi symbol (same character as the attached logo). Palette: charcoal
> #1B1614, fire orange #FF7A1A, gold #FFD23F, chili red #E5341B, cream #F6EAD2. Warm rim light, soft embers,
> subtle depth of field. No text, no watermark, no letters. Clean silhouette, centered subject.

Прикрепите `assets/brand/logo.png` к каждому запросу как референс персонажа.

## Список

| Файл (`assets/gemini-raw/`) | Размер | Промпт (после общего стиля) |
|---|---|---|
| `icon.png` | 1024x1024 | App icon, rounded-square dark glossy background, wok with neon shield rising from the flames, bold and readable at 32px. |
| `wok-cold.png` | 1024x1024 | The same wok, cold and unlit: no flame, dull grey iron, a faint cold-blue shield outline, empty pan. Transparent background. |
| `wok-warming.png` | 1024x1024 | The same wok, heating up: small amber flames, shield half-lit orange, a few noodles lifting. Transparent background. |
| `wok-fire.png` | 1024x1024 | The same wok on full roaring fire, noodles flying, shield blazing gold-orange, embers. Transparent background. |
| `onboard-1.png` | 1200x1200 | Illustration: a QR ticket (cream paper receipt with a QR code) being scanned by a phone, steam and sparks. |
| `onboard-2.png` | 1200x1200 | Illustration: three recipe cards on a chef's counter labelled by icons only: globe, sparkles, checklist. |
| `onboard-3.png` | 1200x1200 | Illustration: a glowing wok with a padlock-shaped shield, an extinguisher-red panic button nearby. |
| `bg-night.png` | 1600x2400 | Vertical wallpaper, dark kitchen at night, soft bokeh flames at the bottom, large empty dark area on top for UI. |
| `banner.png` | 1920x1080 | Wide hero banner: wok on fire on the right, huge empty dark space on the left for a headline. |
| `social.png` | 1280x640 | GitHub social preview: wok centered, minimal dark background, lots of margin. |
| `tray-on.png` | 256x256 | Flat simplified icon: tiny wok with a single bright flame, bold shapes, transparent background, readable at 16px. |
| `tray-off.png` | 256x256 | Flat simplified icon: the same tiny wok, grey, no flame, transparent background, readable at 16px. |

## Советы

- Если Gemini добавил текст на картинку, перегенерируйте с пометкой "absolutely no text".
- Для прозрачного фона попросите "solid pure green background" и удалите зелёный в любом редакторе.
- Держите одного персонажа: всегда прикладывайте референс.

## Wokok Box stickers

Two sheets, cut by `python tools/import_box_art.py` (receive them with `python tools/receiver.py 8777`).

**sheet-a** — square, strict 3x3 grid, large gaps, flat solid #00FF00 background, no shadows, text or frames, no green in the stickers; glossy 3D cartoon, orange/red/cream/charcoal, wok and noodle-box theme:
open takeaway box with five floating compartments · delivery scooter with a box · chef with a wok · detective box with magnifier · box with a shield · wok on fire · globe wrapped in noodles · young person with headphones · grandparents with a phone.

**sheet-b** — same style, 2x2 grid, flat #FF00FF background: robot chef bot · stern box showing STOP with a red alarm · suspicious box with an amber triangle · happy box with thumbs up and a green check.
