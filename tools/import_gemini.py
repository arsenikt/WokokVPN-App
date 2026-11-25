"""Cut Gemini renders from assets/gemini-raw/ into every size the app and site need.

Usage: python tools/import_gemini.py      (requires Pillow)
Missing files are skipped, so you can add images one by one.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "gemini-raw"
BRAND = ROOT / "assets" / "brand"


def load(name):
    p = RAW / name
    if not p.exists():
        print(f"skip  {name} (not found)")
        return None
    return Image.open(p).convert("RGBA")


def save(im, path, size=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if size:
        im = im.resize(size, Image.LANCZOS)
    im.save(path)
    print(f"write {path.relative_to(ROOT)}")


def main():
    BRAND.mkdir(parents=True, exist_ok=True)

    if (im := load("icon.png")):
        save(im, BRAND / "logo.png", (1024, 1024))
        im.resize((64, 64), Image.LANCZOS).save(BRAND / "tray.png")
        im.save(BRAND / "tray.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)])
        print("now run: dart run flutter_launcher_icons")

    for name in ("tray-on", "tray-off"):
        if (im := load(f"{name}.png")):
            save(im, BRAND / f"{name}.png", (64, 64))
            im.save(BRAND / f"{name}.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48)])

    for name in ("wok-cold", "wok-warming", "wok-fire"):
        if (im := load(f"{name}.png")):
            save(im, BRAND / f"{name}.png", (768, 768))

    for i in (1, 2, 3):
        if (im := load(f"onboard-{i}.png")):
            save(im, BRAND / f"onboard-{i}.png", (900, 900))

    if (im := load("bg-night.png")):
        save(im.convert("RGB"), BRAND / "bg-night.jpg", (1200, 1800))

    if (im := load("banner.png")):
        save(im.convert("RGB"), BRAND / "banner.jpg", (1600, 900))

    if (im := load("social.png")):
        save(im.convert("RGB"), ROOT / "docs" / "social.png", (1280, 640))


if __name__ == "__main__":
    main()
