#!/usr/bin/env python3
"""Chimera Bond tiles + UI chrome — richer foliage/path pass (v0.1.15)."""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path("/workspace/assets")
TILES = ROOT / "tiles"
UI = ROOT / "ui"
TILES.mkdir(parents=True, exist_ok=True)
UI.mkdir(parents=True, exist_ok=True)
SIZE = 64


def clamp(v: int) -> int:
    return max(0, min(255, v))


def mix(a, b, t: float):
    return tuple(clamp(int(a[i] * (1 - t) + b[i] * t)) for i in range(3)) + (255,)


def new_img(color=(0, 0, 0, 255)) -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), color)


def noise_layer(seed: int, a, b, scale: float = 0.12) -> Image.Image:
    rnd = random.Random(seed)
    img = new_img(a + (255,))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = (
                math.sin(x * scale + seed) * math.cos(y * scale * 1.3)
                + rnd.random() * 0.35
            )
            t = (n + 1.2) / 2.4
            pix[x, y] = mix(a, b, max(0.0, min(1.0, t)))
    return img


def make_grass() -> Image.Image:
    img = noise_layer(11, (40, 98, 58), (62, 140, 82), 0.16)
    d = ImageDraw.Draw(img)
    rnd = random.Random(42)
    for _ in range(80):
        x = rnd.randint(2, SIZE - 3)
        y = rnd.randint(6, SIZE - 3)
        h = rnd.randint(4, 10)
        col = (90, 175, 105, 235) if rnd.random() > 0.35 else (30, 78, 48, 235)
        d.line([(x, y), (x - 1, y - h)], fill=col, width=1)
        if rnd.random() > 0.55:
            d.ellipse([x - 2, y - h - 2, x + 1, y - h + 1], fill=(150, 210, 110, 190))
    # soft flowers
    for _ in range(6):
        fx = rnd.randint(6, SIZE - 8)
        fy = rnd.randint(10, SIZE - 10)
        d.ellipse([fx, fy, fx + 3, fy + 3], fill=(230, 190, 90, 180))
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(24, 60, 34, 50), width=2)
    return Image.alpha_composite(img, overlay)


def make_path() -> Image.Image:
    img = noise_layer(7, (128, 104, 72), (168, 138, 98), 0.2)
    d = ImageDraw.Draw(img)
    rnd = random.Random(9)
    for _ in range(24):
        x = rnd.randint(3, SIZE - 10)
        y = rnd.randint(3, SIZE - 10)
        d.ellipse(
            [x, y, x + rnd.randint(4, 9), y + rnd.randint(3, 6)],
            fill=(95, 74, 50, 170),
        )
    # packed dirt edge
    d.rectangle([0, 0, SIZE - 1, 3], fill=(90, 70, 48, 110))
    d.rectangle([0, SIZE - 4, SIZE - 1, SIZE - 1], fill=(90, 70, 48, 110))
    d.rectangle([0, 0, 3, SIZE - 1], fill=(90, 70, 48, 70))
    d.rectangle([SIZE - 4, 0, SIZE - 1, SIZE - 1], fill=(90, 70, 48, 70))
    # occasional pebble highlight
    for _ in range(5):
        px = rnd.randint(8, SIZE - 10)
        py = rnd.randint(8, SIZE - 10)
        d.ellipse([px, py, px + 3, py + 2], fill=(200, 180, 140, 140))
    return img


def make_wall() -> Image.Image:
    img = noise_layer(3, (34, 38, 44), (58, 64, 72), 0.28)
    d = ImageDraw.Draw(img)
    for row, y in enumerate(range(2, SIZE, 14)):
        off = 7 if row % 2 else 0
        for x in range(-off, SIZE, 16):
            d.rounded_rectangle(
                [x, y, x + 14, y + 11],
                radius=2,
                outline=(22, 24, 28, 255),
                fill=(48, 54, 62, 255),
            )
            d.line([(x + 2, y + 2), (x + 10, y + 2)], fill=(90, 100, 110, 100), width=1)
    return img


def make_rock() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([8, 40, 56, 58], fill=(30, 40, 28, 120))
    d.polygon([(12, 46), (30, 8), (54, 46), (44, 54), (18, 54)], fill=(118, 122, 130, 255))
    d.polygon([(18, 40), (30, 12), (38, 40)], fill=(168, 172, 180, 255))
    d.line([(20, 48), (40, 22)], fill=(70, 74, 80, 255), width=2)
    d.ellipse([34, 26, 44, 34], fill=(190, 194, 200, 190))
    return img


def make_bridge() -> Image.Image:
    img = new_img((78, 50, 28, 255))
    d = ImageDraw.Draw(img)
    for y in range(4, SIZE, 12):
        d.rounded_rectangle(
            [3, y, SIZE - 4, y + 9],
            radius=2,
            fill=(142, 96, 54, 255),
            outline=(60, 36, 18, 255),
        )
        d.line([(8, y + 3), (SIZE - 8, y + 3)], fill=(190, 140, 85, 130), width=1)
        d.line([(10, y + 6), (SIZE - 10, y + 6)], fill=(50, 30, 14, 90), width=1)
    d.rectangle([0, 0, 5, SIZE - 1], fill=(48, 28, 14, 255))
    d.rectangle([SIZE - 6, 0, SIZE - 1, SIZE - 1], fill=(48, 28, 14, 255))
    return img


def make_water(phase: int) -> Image.Image:
    img = new_img((22, 86, 122, 255))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            w = math.sin((x + phase * 4) * 0.22 + y * 0.15) + math.cos((y - phase) * 0.18)
            if w > 0.55:
                pix[x, y] = (86, 170, 205, 255)
            elif w > 0.1:
                pix[x, y] = (42, 118, 158, 255)
            elif w < -0.55:
                pix[x, y] = (12, 54, 86, 255)
    d = ImageDraw.Draw(img)
    yy = 18 + (phase % 4) * 3
    d.arc([6, yy - 8, 58, yy + 10], 200, 340, fill=(210, 240, 250, 130), width=2)
    return img


def make_lava(phase: int) -> Image.Image:
    img = new_img((140, 32, 10, 255))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = math.sin(x * 0.28 + phase * 0.9) * math.cos(y * 0.24 - phase * 0.6)
            if n > 0.45:
                pix[x, y] = (255, 180, 55, 255)
            elif n > 0.05:
                pix[x, y] = (230, 98, 24, 255)
            elif n < -0.5:
                pix[x, y] = (78, 14, 8, 255)
    d = ImageDraw.Draw(img)
    d.ellipse([20 + phase, 18, 36 + phase, 34], fill=(255, 230, 130, 150))
    return img


def make_void(phase: int) -> Image.Image:
    img = new_img((10, 8, 20, 255))
    d = ImageDraw.Draw(img)
    cx = cy = 32
    for i, r in enumerate([26, 18, 10, 4]):
        col = (55 + i * 22, 35 + i * 12, 100 + i * 28, 170 - i * 22)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=2)
    for a in range(0, 360, 30):
        rad = math.radians(a + phase * 10)
        d.line(
            [(cx, cy), (cx + int(math.cos(rad) * 28), cy + int(math.sin(rad) * 28))],
            fill=(80, 55, 130, 80),
            width=1,
        )
    d.ellipse([28, 28, 36, 36], fill=(140, 105, 220, 230))
    return img


def make_camp() -> Image.Image:
    img = make_path()
    d = ImageDraw.Draw(img)
    d.ellipse([12, 30, 52, 56], fill=(70, 52, 34, 255), outline=(40, 28, 18, 255))
    d.polygon([(32, 8), (18, 36), (46, 36)], fill=(235, 120, 42, 255))
    d.polygon([(32, 2), (24, 26), (40, 26)], fill=(255, 220, 100, 235))
    d.ellipse([27, 38, 37, 48], fill=(255, 170, 70, 210))
    # log seats
    d.rounded_rectangle([8, 48, 22, 56], radius=2, fill=(90, 60, 35, 230))
    d.rounded_rectangle([42, 48, 56, 56], radius=2, fill=(90, 60, 35, 230))
    return img


def make_exit() -> Image.Image:
    img = make_path()
    d = ImageDraw.Draw(img)
    d.ellipse([8, 8, 56, 56], outline=(90, 185, 240, 255), width=4)
    d.ellipse([16, 16, 48, 48], fill=(28, 95, 155, 220))
    d.ellipse([24, 24, 40, 40], fill=(190, 240, 255, 245))
    d.arc([12, 12, 52, 52], 200, 320, fill=(210, 245, 255, 140), width=2)
    return img


def make_boss() -> Image.Image:
    img = make_path()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [10, 16, 54, 56], radius=4, fill=(120, 30, 40, 255), outline=(50, 10, 16, 255), width=2
    )
    d.polygon([(32, 2), (8, 22), (56, 22)], fill=(160, 42, 52, 255))
    d.rectangle([27, 28, 37, 48], fill=(255, 95, 85, 230))
    d.ellipse([22, 22, 42, 34], fill=(255, 150, 130, 170))
    return img


def make_obelisk() -> Image.Image:
    base = make_path()
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.paste(base, (0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([14, 46, 50, 60], fill=(40, 50, 40, 110))
    d.polygon([(32, 0), (16, 18), (48, 18)], fill=(165, 175, 190, 255))
    d.rectangle([18, 18, 46, 54], fill=(108, 118, 135, 255), outline=(60, 68, 80, 255), width=2)
    d.rectangle([27, 24, 37, 44], fill=(90, 230, 255, 220))
    d.ellipse([26, 16, 38, 28], fill=(200, 250, 255, 235))
    return img


def make_empty() -> Image.Image:
    """Dense underbrush / canopy — readable dark green, not black void."""
    img = noise_layer(21, (18, 42, 28), (32, 68, 42), 0.22)
    d = ImageDraw.Draw(img)
    rnd = random.Random(77)
    for _ in range(28):
        x = rnd.randint(0, SIZE - 12)
        y = rnd.randint(0, SIZE - 12)
        r = rnd.randint(5, 11)
        col = (24, 58, 36, 210) if rnd.random() > 0.4 else (14, 36, 24, 220)
        d.ellipse([x, y, x + r * 2, y + r * 2], fill=col)
    for _ in range(40):
        x = rnd.randint(2, SIZE - 4)
        y = rnd.randint(2, SIZE - 4)
        d.point((x, y), fill=(70, 120, 80, 160))
    # slight vignette so paths read clearly against brush
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(8, 20, 12, 70), width=3)
    return Image.alpha_composite(img, overlay)


def button(w, h, fill, edge) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=14, fill=fill, outline=edge, width=3)
    d.rounded_rectangle([4, 3, w - 5, h // 2], radius=10, fill=(255, 255, 255, 28))
    return img


def panel(w, h) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [0, 0, w - 1, h - 1], radius=18, fill=(14, 26, 24, 235), outline=(90, 170, 140, 210), width=3
    )
    d.rounded_rectangle([6, 6, w - 7, h - 7], radius=14, outline=(40, 80, 65, 140), width=2)
    return img


def stick_base() -> Image.Image:
    s = 180
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, s - 3, s - 3], fill=(12, 26, 22, 180), outline=(130, 200, 170, 160), width=4)
    d.ellipse([28, 28, s - 29, s - 29], outline=(70, 120, 100, 100), width=3)
    d.ellipse([60, 60, s - 61, s - 61], fill=(20, 40, 34, 60))
    return img


def stick_knob() -> Image.Image:
    s = 84
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, s - 3, s - 3], fill=(190, 230, 210, 235), outline=(255, 255, 255, 150), width=3)
    d.ellipse([16, 12, 48, 36], fill=(255, 255, 255, 70))
    return img


def boot_bg() -> Image.Image:
    w, h = 720, 1280
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        col = (
            int(8 + t * 10),
            int(32 + (1 - t) * 34),
            int(26 + t * 24),
            255,
        )
        d.line([(0, y), (w - 1, y)], fill=col)
    for cx, cy, r, a in [
        (360, 420, 240, 50),
        (160, 920, 150, 34),
        (560, 780, 130, 30),
        (360, 180, 100, 40),
    ]:
        for rad in range(r, 10, -10):
            alpha = max(0, a - (r - rad) // 6)
            d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], outline=(70, 190, 145, alpha))
    mist = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    md.rectangle([0, 960, w, h], fill=(40, 100, 75, 55))
    mist = mist.filter(ImageFilter.GaussianBlur(30))
    return Image.alpha_composite(img, mist)


def hud_strip() -> Image.Image:
    img = Image.new("RGBA", (720, 84), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [0, 0, 719, 83], radius=16, fill=(10, 22, 20, 225), outline=(100, 185, 150, 210), width=3
    )
    d.rounded_rectangle([6, 6, 713, 77], radius=12, outline=(40, 80, 65, 110), width=1)
    d.line([(20, 4), (220, 4)], fill=(170, 240, 200, 70), width=2)
    return img


def main() -> None:
    mapping = {
        "grass.png": make_grass(),
        "path.png": make_path(),
        "wall.png": make_wall(),
        "rock.png": make_rock(),
        "bridge.png": make_bridge(),
        "camp.png": make_camp(),
        "exit.png": make_exit(),
        "boss.png": make_boss(),
        "obelisk.png": make_obelisk(),
        "empty.png": make_empty(),
    }
    for i in range(4):
        mapping[f"water_{i}.png"] = make_water(i)
        mapping[f"lava_{i}.png"] = make_lava(i)
        mapping[f"void_{i}.png"] = make_void(i)
    for name, im in mapping.items():
        im.save(TILES / name)
        print("tile", name)

    button(280, 72, (34, 68, 54, 245), (130, 220, 170, 230)).save(UI / "btn_normal.png")
    button(280, 72, (48, 100, 78, 250), (190, 250, 210, 240)).save(UI / "btn_hover.png")
    button(280, 72, (22, 44, 34, 245), (70, 120, 95, 200)).save(UI / "btn_pressed.png")
    button(280, 72, (30, 34, 32, 200), (70, 80, 75, 150)).save(UI / "btn_disabled.png")
    panel(560, 560).save(UI / "panel.png")
    stick_base().save(UI / "stick_base.png")
    stick_knob().save(UI / "stick_knob.png")
    hud_strip().save(UI / "hud_strip.png")
    boot_bg().save(UI / "boot_bg.png")
    print("ui chrome done")


if __name__ == "__main__":
    main()
