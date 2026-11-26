"""Cut the Wokok Box sticker sheets (Gemini renders) into transparent icons.

Usage: python tools/import_box_art.py      (requires Pillow)
Reads assets/gemini-raw/sheet-a.* (3x3 on green) and sheet-b.* (2x2 on
magenta), writes assets/box/<name>.png.
"""
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "gemini-raw"
OUT = ROOT / "assets" / "box"
SHEETS = {
    "sheet-a": (3, ["hero", "tunnel", "deploy", "spy", "guard", "vpn", "site", "me", "parents"]),
    "sheet-b": (2, ["bot", "stop", "careful", "ok"]),
}
SIZE = 384


def key_out(im):
    """Makes the background transparent, flooding in from the border only."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    kr, kg, kb = px[2, 2][:3]

    def near(x, y):
        r, g, b = px[x, y][:3]
        return abs(r - kr) + abs(g - kg) + abs(b - kb) < 170

    seen = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.extend(((x, 0), (x, h - 1)))
    for y in range(h):
        queue.extend(((0, y), (w - 1, y)))
    mask = Image.new("L", (w, h), 255)
    m = mask.load()
    while queue:
        x, y = queue.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not near(x, y):
            continue
        m[x, y] = 0
        if x > 0:
            queue.append((x - 1, y))
        if x < w - 1:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y < h - 1:
            queue.append((x, y + 1))
    # pockets of key colour fully enclosed by the art
    pure_green = kg > 180 and kr < 120
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            if near(x, y) or (pure_green and g > 170 and g - r > 70 and g - b > 90):
                m[x, y] = 0
    # shave one pixel of colour fringe, then soften the edge
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    im.putalpha(mask)
    return im


def components(alpha):
    """Boxes of connected opaque blobs, found on a reduced copy for speed."""
    scale = 4
    small = alpha.resize((alpha.width // scale, alpha.height // scale))
    w, h = small.size
    px = small.load()
    seen = set()
    found = []
    for sy in range(h):
        for sx in range(w):
            if px[sx, sy] < 128 or (sx, sy) in seen:
                continue
            stack = [(sx, sy)]
            seen.add((sx, sy))
            cells = []
            while stack:
                x, y = stack.pop()
                cells.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny] >= 128:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if len(cells) > 20:
                found.append(cells)
    return scale, found


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for sheet, (n, names) in SHEETS.items():
        files = list(RAW.glob(sheet + ".*"))
        if not files:
            print(f"skip  {sheet} (not found)")
            continue
        im = key_out(Image.open(files[0]))
        alpha = im.getchannel("A")
        scale, blobs = components(alpha)
        cw, ch = im.width / n, im.height / n
        # each blob belongs to the grid cell holding its centre
        cells = {}
        for blob in blobs:
            cx = sum(x for x, _ in blob) / len(blob) * scale
            cy = sum(y for _, y in blob) / len(blob) * scale
            cells.setdefault(min(int(cy // ch), n - 1) * n + min(int(cx // cw), n - 1), []).extend(blob)
        for i, name in enumerate(names):
            if i not in cells:
                print(f"miss  {name}")
                continue
            own = Image.new("L", (im.width // scale, im.height // scale), 0)
            for x, y in cells[i]:
                own.putpixel((x, y), 255)
            own = own.filter(ImageFilter.MaxFilter(5)).resize(im.size, Image.BILINEAR)
            part = im.copy()
            part.putalpha(Image.composite(alpha, Image.new("L", im.size, 0), own.point(lambda v: 255 if v > 40 else 0)))
            part = part.crop(part.getchannel("A").getbbox())
            side = int(max(part.size) * 1.04)
            square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            square.paste(part, ((side - part.width) // 2, (side - part.height) // 2))
            square.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png", optimize=True)
            print(f"write assets/box/{name}.png")
    # the box itself is the logo on the receipt
    if (OUT / "hero.png").exists():
        (OUT / "logo.png").write_bytes((OUT / "hero.png").read_bytes())
        make_icon()


def make_icon():
    """App and tray icon: the open box on a dark rounded tile."""
    from PIL import ImageDraw

    brand = ROOT / "assets" / "brand"
    big = 1024
    tile = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, big - 1, big - 1), 224, fill=(38, 32, 28, 255))
    art = Image.open(OUT / "hero.png").convert("RGBA")
    art = art.resize((920, 920), Image.LANCZOS)
    tile.alpha_composite(art, ((big - art.width) // 2, (big - art.height) // 2))
    tile.save(brand / "logo.png", optimize=True)
    tile.resize((64, 64), Image.LANCZOS).save(brand / "tray.png")
    tile.save(brand / "tray.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)])
    print("write assets/brand/logo.png, tray (now: dart run flutter_launcher_icons)")


if __name__ == "__main__":
    main()
