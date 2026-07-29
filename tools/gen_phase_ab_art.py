#!/usr/bin/env python3
"""High-quality Chimera Bond tiles + UI chrome (v0.1.13 graphics pass)."""
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
    img = noise_layer(11, (34, 86, 52), (48, 120, 70), 0.18)
    d = ImageDraw.Draw(img)
    rnd = random.Random(42)
    for _ in range(55):
        x = rnd.randint(2, SIZE - 3)
        y = rnd.randint(4, SIZE - 4)
        h = rnd.randint(3, 7)
        col = (70, 150, 90, 230) if rnd.random() > 0.4 else (28, 70, 42, 230)
        d.line([(x, y), (x - 1, y - h)], fill=col, width=1)
        if rnd.random() > 0.6:
            d.point((x - 1, y - h - 1), fill=(120, 190, 100, 200))
    # soft vignette edge
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(20, 50, 30, 40), width=2)
    return Image.alpha_composite(img, overlay)


def make_path() -> Image.Image:
    img = noise_layer(7, (110, 88, 60), (145, 118, 82), 0.22)
    d = ImageDraw.Draw(img)
    rnd = random.Random(9)
    for _ in range(18):
        x = rnd.randint(4, SIZE - 8)
        y = rnd.randint(4, SIZE - 8)
        d.ellipse([x, y, x + rnd.randint(3, 7), y + rnd.randint(2, 5)], fill=(90, 70, 48, 160))
    d.rectangle([0, 0, SIZE - 1, 2], fill=(80, 62, 42, 90))
    d.rectangle([0, SIZE - 3, SIZE - 1, SIZE - 1], fill=(80, 62, 42, 90))
    return img


def make_wall() -> Image.Image:
    img = noise_layer(3, (28, 32, 36), (48, 54, 60), 0.3)
    d = ImageDraw.Draw(img)
    for row, y in enumerate(range(2, SIZE, 14)):
        off = 7 if row % 2 else 0
        for x in range(-off, SIZE, 16):
            d.rounded_rectangle(
                [x, y, x + 14, y + 11],
                radius=2,
                outline=(18, 20, 22, 255),
                fill=(40, 46, 52, 255),
            )
            d.line([(x + 2, y + 2), (x + 10, y + 2)], fill=(70, 78, 86, 90), width=1)
    return img


def make_rock() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([8, 40, 56, 58], fill=(30, 40, 28, 110))
    d.polygon([(12, 46), (30, 10), (52, 46), (44, 54), (18, 54)], fill=(108, 112, 118, 255))
    d.polygon([(18, 40), (30, 14), (36, 40)], fill=(150, 154, 160, 255))
    d.line([(20, 48), (38, 24)], fill=(70, 74, 80, 255), width=2)
    d.ellipse([34, 28, 42, 34], fill=(170, 174, 180, 180))
    return img


def make_bridge() -> Image.Image:
    img = new_img((70, 44, 24, 255))
    d = ImageDraw.Draw(img)
    for y in range(4, SIZE, 12):
        d.rounded_rectangle([3, y, SIZE - 4, y + 9], radius=2, fill=(128, 86, 48, 255), outline=(60, 36, 18, 255))
        d.line([(8, y + 3), (SIZE - 8, y + 3)], fill=(170, 120, 70, 120), width=1)
        d.line([(10, y + 6), (SIZE - 10, y + 6)], fill=(50, 30, 14, 80), width=1)
    d.rectangle([0, 0, 4, SIZE - 1], fill=(48, 28, 14, 255))
    d.rectangle([SIZE - 5, 0, SIZE - 1, SIZE - 1], fill=(48, 28, 14, 255))
    return img


def make_water(phase: int) -> Image.Image:
    img = new_img((18, 72, 108, 255))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            w = math.sin((x + phase * 4) * 0.22 + y * 0.15) + math.cos((y - phase) * 0.18)
            if w > 0.55:
                pix[x, y] = (70, 150, 185, 255)
            elif w > 0.1:
                pix[x, y] = (36, 105, 145, 255)
            elif w < -0.55:
                pix[x, y] = (10, 48, 78, 255)
    d = ImageDraw.Draw(img)
    yy = 18 + (phase % 4) * 3
    d.arc([6, yy - 8, 58, yy + 10], 200, 340, fill=(190, 230, 245, 110), width=2)
    return img


def make_lava(phase: int) -> Image.Image:
    img = new_img((130, 28, 8, 255))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = math.sin(x * 0.28 + phase * 0.9) * math.cos(y * 0.24 - phase * 0.6)
            if n > 0.45:
                pix[x, y] = (255, 170, 50, 255)
            elif n > 0.05:
                pix[x, y] = (220, 90, 20, 255)
            elif n < -0.5:
                pix[x, y] = (70, 12, 6, 255)
    d = ImageDraw.Draw(img)
    d.ellipse([20 + phase, 18, 36 + phase, 34], fill=(255, 220, 120, 140))
    return img


def make_void(phase: int) -> Image.Image:
    img = new_img((8, 6, 16, 255))
    d = ImageDraw.Draw(img)
    cx = cy = 32
    for i, r in enumerate([26, 18, 10, 4]):
        col = (50 + i * 20, 30 + i * 10, 90 + i * 25, 160 - i * 20)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=2)
    for a in range(0, 360, 30):
        rad = math.radians(a + phase * 10)
        d.line(
            [(cx, cy), (cx + int(math.cos(rad) * 28), cy + int(math.sin(rad) * 28))],
            fill=(70, 50, 120, 70),
            width=1,
        )
    d.ellipse([28, 28, 36, 36], fill=(120, 90, 200, 220))
    return img


def make_camp() -> Image.Image:
    img = make_path()
    d = ImageDraw.Draw(img)
    d.ellipse([14, 28, 50, 54], fill=(70, 52, 34, 255), outline=(40, 28, 18, 255))
    d.polygon([(32, 10), (22, 34), (42, 34)], fill=(230, 110, 40, 255))
    d.polygon([(32, 4), (26, 24), (38, 24)], fill=(255, 210, 90, 230))
    d.ellipse([28, 36, 36, 44], fill=(255, 160, 60, 200))
    return img


def make_exit() -> Image.Image:
    img = make_path()
    d = ImageDraw.Draw(img)
    d.ellipse([10, 10, 54, 54], outline=(80, 170, 230, 255), width=4)
    d.ellipse([18, 18, 46, 46], fill=(30, 90, 150, 210))
    d.ellipse([26, 26, 38, 38], fill=(180, 235, 255, 240))
    d.arc([14, 14, 50, 50], 200, 320, fill=(200, 240, 255, 120), width=2)
    return img


def make_boss() -> Image.Image:
    img = make_path()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([12, 18, 52, 54], radius=4, fill=(110, 28, 38, 255), outline=(50, 10, 16, 255), width=2)
    d.polygon([(32, 4), (10, 22), (54, 22)], fill=(150, 40, 50, 255))
    d.rectangle([28, 28, 36, 46], fill=(255, 90, 80, 220))
    d.ellipse([24, 24, 40, 32], fill=(255, 140, 120, 160))
    return img


def make_obelisk() -> Image.Image:
    base = make_path()
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.paste(base, (0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([16, 46, 48, 58], fill=(40, 50, 40, 100))
    d.polygon([(32, 2), (18, 18), (46, 18)], fill=(150, 160, 175, 255))
    d.rectangle([20, 18, 44, 52], fill=(100, 110, 125, 255), outline=(60, 68, 80, 255), width=2)
    d.rectangle([28, 24, 36, 42], fill=(80, 220, 255, 210))
    d.ellipse([27, 18, 37, 28], fill=(190, 245, 255, 230))
    return img


def make_empty() -> Image.Image:
    return noise_layer(1, (10, 14, 16), (18, 24, 28), 0.4)


def button(w, h, fill, edge) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=14, fill=fill, outline=edge, width=3)
    d.rounded_rectangle([4, 3, w - 5, h // 2], radius=10, fill=(255, 255, 255, 28))
    return img


def panel(w, h) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=18, fill=(14, 26, 24, 235), outline=(90, 170, 140, 210), width=3)
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
        # deep moss → teal night
        col = (
            int(10 + t * 8),
            int(36 + (1 - t) * 28),
            int(28 + t * 22),
            255,
        )
        d.line([(0, y), (w - 1, y)], fill=col)
    # bioluminescent orbs
    for cx, cy, r, a in [
        (360, 420, 220, 45),
        (180, 900, 140, 30),
        (540, 780, 120, 28),
        (360, 200, 90, 35),
    ]:
        for rad in range(r, 10, -10):
            alpha = max(0, a - (r - rad) // 6)
            d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], outline=(70, 180, 140, alpha))
    # ground mist band
    mist = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    md.rectangle([0, 980, w, h], fill=(40, 90, 70, 50))
    mist = mist.filter(ImageFilter.GaussianBlur(28))
    return Image.alpha_composite(img, mist)


def hud_strip() -> Image.Image:
    img = Image.new("RGBA", (720, 84), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, 719, 83], radius=16, fill=(10, 22, 20, 220), outline=(90, 170, 140, 200), width=3)
    d.rounded_rectangle([6, 6, 713, 77], radius=12, outline=(40, 80, 65, 100), width=1)
    d.line([(20, 4), (200, 4)], fill=(160, 230, 190, 60), width=2)
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
