#!/usr/bin/env python3
"""Generate Chimera Bond tile atlas + simple UI chrome (Phase B/A assets)."""
from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path("/workspace/assets")
TILES = ROOT / "tiles"
UI = ROOT / "ui"
TILES.mkdir(parents=True, exist_ok=True)
UI.mkdir(parents=True, exist_ok=True)
SIZE = 48


def new_img(color=(0, 0, 0, 255)) -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), color)


def px(draw: ImageDraw.ImageDraw, x: int, y: int, color, s: int = 1) -> None:
    draw.rectangle([x, y, x + s - 1, y + s - 1], fill=color)


def dither_fill(img: Image.Image, base, speck, dens: float = 0.12) -> None:
    import random

    rnd = random.Random(hash(base) & 0xFFFFFFFF)
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if rnd.random() < dens:
                pix[x, y] = speck


def make_grass() -> Image.Image:
    img = new_img((36, 92, 58, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, SIZE, 4):
        for x in range(0, SIZE, 4):
            c = (42, 110, 68, 255) if (x + y) % 8 == 0 else (30, 78, 50, 255)
            px(d, x, y, c, 2)
    # tufts
    for x, y in [(6, 10), (18, 22), (30, 8), (38, 28), (12, 34), (26, 38)]:
        d.line([(x, y + 4), (x, y)], fill=(70, 150, 85, 255), width=1)
        d.line([(x, y + 4), (x - 2, y + 1)], fill=(55, 130, 75, 220), width=1)
    dither_fill(img, (36, 92, 58), (55, 125, 70, 180), 0.06)
    return img


def make_path() -> Image.Image:
    img = new_img((92, 78, 58, 255))
    d = ImageDraw.Draw(img)
    for y in range(SIZE):
        for x in range(SIZE):
            if (x + y * 3) % 7 == 0:
                px(d, x, y, (110, 95, 70, 255))
            elif (x * 2 + y) % 11 == 0:
                px(d, x, y, (70, 60, 45, 255))
    # edge wear
    d.rectangle([0, 0, SIZE - 1, 1], fill=(70, 60, 48, 180))
    d.rectangle([0, SIZE - 2, SIZE - 1, SIZE - 1], fill=(70, 60, 48, 180))
    return img


def make_wall() -> Image.Image:
    img = new_img((22, 26, 28, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, SIZE, 8):
        offset = 4 if (y // 8) % 2 else 0
        for x in range(-offset, SIZE, 12):
            d.rectangle([x, y, x + 10, y + 6], outline=(40, 46, 50, 255), fill=(28, 32, 36, 255))
    d.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(12, 14, 16, 255))
    return img


def make_rock() -> Image.Image:
    img = new_img((0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # ground hint
    d.ellipse([4, 30, 44, 46], fill=(50, 55, 48, 180))
    d.polygon([(10, 34), (24, 8), (40, 34), (34, 40), (14, 40)], fill=(88, 92, 96, 255))
    d.polygon([(14, 30), (24, 12), (28, 30)], fill=(120, 124, 128, 255))
    d.line([(16, 36), (30, 20)], fill=(60, 64, 68, 255), width=1)
    return img


def make_bridge() -> Image.Image:
    img = new_img((78, 52, 28, 255))
    d = ImageDraw.Draw(img)
    for y in range(4, SIZE, 10):
        d.rectangle([2, y, SIZE - 3, y + 7], fill=(110, 78, 42, 255), outline=(60, 38, 20, 255))
        d.line([(6, y + 3), (SIZE - 6, y + 3)], fill=(140, 100, 55, 160), width=1)
    d.rectangle([0, 0, 2, SIZE - 1], fill=(55, 35, 18, 255))
    d.rectangle([SIZE - 3, 0, SIZE - 1, SIZE - 1], fill=(55, 35, 18, 255))
    return img


def make_water_frame(phase: int) -> Image.Image:
    img = new_img((22, 78, 110, 255))
    d = ImageDraw.Draw(img)
    for y in range(SIZE):
        for x in range(SIZE):
            wave = math.sin((x + phase * 3) * 0.35 + y * 0.2) 
            if wave > 0.35:
                px(d, x, y, (40, 110, 140, 255))
            elif wave < -0.4:
                px(d, x, y, (14, 55, 85, 255))
    # foam line
    yy = 14 + (phase % 3) * 2
    d.line([(4, yy), (44, yy - 2)], fill=(160, 210, 230, 100), width=2)
    return img


def make_lava_frame(phase: int) -> Image.Image:
    img = new_img((150, 40, 12, 255))
    d = ImageDraw.Draw(img)
    for y in range(SIZE):
        for x in range(SIZE):
            n = math.sin((x * 0.4) + phase) * math.cos((y * 0.35) - phase * 0.7)
            if n > 0.4:
                px(d, x, y, (255, 160, 40, 255))
            elif n > 0.0:
                px(d, x, y, (220, 90, 20, 255))
            elif n < -0.45:
                px(d, x, y, (90, 18, 8, 255))
    d.ellipse([16 + phase, 16, 28 + phase, 28], fill=(255, 200, 80, 160))
    return img


def make_void_frame(phase: int) -> Image.Image:
    img = new_img((10, 8, 18, 255))
    d = ImageDraw.Draw(img)
    cx, cy = 24, 24
    r = 10 + phase
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(80, 60, 140, 180))
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(40, 30, 70, 255))
    for a in range(0, 360, 45):
        rad = math.radians(a + phase * 12)
        x2 = cx + int(math.cos(rad) * 18)
        y2 = cy + int(math.sin(rad) * 18)
        d.line([(cx, cy), (x2, y2)], fill=(60, 45, 100, 100), width=1)
    return img


def make_camp() -> Image.Image:
    img = make_path().copy()
    d = ImageDraw.Draw(img)
    # bedroll / fire ring
    d.ellipse([10, 18, 38, 40], outline=(60, 50, 40, 255), fill=(70, 55, 40, 255))
    d.polygon([(24, 10), (18, 26), (30, 26)], fill=(220, 120, 40, 255))
    d.polygon([(24, 6), (20, 18), (28, 18)], fill=(255, 200, 80, 220))
    return img


def make_exit() -> Image.Image:
    img = make_path().copy()
    d = ImageDraw.Draw(img)
    d.ellipse([8, 8, 40, 40], outline=(70, 150, 220, 255), width=3)
    d.ellipse([14, 14, 34, 34], fill=(40, 100, 170, 200))
    d.ellipse([20, 20, 28, 28], fill=(180, 230, 255, 230))
    return img


def make_boss() -> Image.Image:
    img = make_path().copy()
    d = ImageDraw.Draw(img)
    d.rectangle([8, 10, 40, 40], fill=(90, 25, 35, 255), outline=(40, 10, 15, 255))
    d.polygon([(24, 4), (8, 16), (40, 16)], fill=(140, 35, 45, 255))
    d.rectangle([20, 22, 28, 34], fill=(255, 80, 70, 200))
    return img


def make_obelisk() -> Image.Image:
    img = make_path().copy()
    d = ImageDraw.Draw(img)
    d.polygon([(24, 2), (14, 14), (34, 14)], fill=(120, 130, 145, 255))
    d.rectangle([16, 14, 32, 42], fill=(90, 98, 110, 255), outline=(60, 66, 75, 255))
    d.rectangle([21, 20, 27, 34], fill=(90, 210, 255, 200))
    d.ellipse([21, 16, 27, 22], fill=(180, 240, 255, 230))
    return img


def make_empty() -> Image.Image:
    return new_img((6, 8, 10, 255))


def atlas_row(images: list[Image.Image]) -> Image.Image:
    w = SIZE * len(images)
    sheet = Image.new("RGBA", (w, SIZE), (0, 0, 0, 0))
    for i, im in enumerate(images):
        sheet.paste(im, (i * SIZE, 0))
    return sheet


def make_button(w: int, h: int, fill, edge) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=10, fill=fill, outline=edge, width=2)
    d.line([(8, 3), (w - 8, 3)], fill=(255, 255, 255, 40), width=2)
    return img


def make_panel(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=14, fill=(18, 28, 26, 230), outline=(70, 120, 100, 200), width=2)
    d.rounded_rectangle([4, 4, w - 5, h - 5], radius=12, outline=(40, 70, 60, 120), width=1)
    return img


def make_joystick_base() -> Image.Image:
    s = 160
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, s - 5, s - 5], fill=(16, 28, 24, 160), outline=(120, 180, 150, 120), width=3)
    d.ellipse([28, 28, s - 29, s - 29], outline=(80, 120, 100, 80), width=2)
    return img


def make_joystick_knob() -> Image.Image:
    s = 72
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, s - 3, s - 3], fill=(200, 230, 210, 230), outline=(255, 255, 255, 120), width=2)
    d.ellipse([14, 10, 40, 30], fill=(255, 255, 255, 60))
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
        "water_0.png": make_water_frame(0),
        "water_1.png": make_water_frame(1),
        "water_2.png": make_water_frame(2),
        "water_3.png": make_water_frame(3),
        "lava_0.png": make_lava_frame(0),
        "lava_1.png": make_lava_frame(1),
        "lava_2.png": make_lava_frame(2),
        "lava_3.png": make_lava_frame(3),
        "void_0.png": make_void_frame(0),
        "void_1.png": make_void_frame(1),
        "void_2.png": make_void_frame(2),
        "void_3.png": make_void_frame(3),
    }
    for name, im in mapping.items():
        im.save(TILES / name)
        print("wrote", name)

    # Atlas for docs/debug (optional)
    order = [
        mapping["grass.png"],
        mapping["path.png"],
        mapping["wall.png"],
        mapping["rock.png"],
        mapping["bridge.png"],
        mapping["water_0.png"],
        mapping["lava_0.png"],
        mapping["void_0.png"],
        mapping["camp.png"],
        mapping["exit.png"],
        mapping["boss.png"],
        mapping["obelisk.png"],
    ]
    atlas_row(order).save(TILES / "atlas_preview.png")

    make_button(256, 64, (32, 58, 48, 240), (120, 200, 150, 220)).save(UI / "btn_normal.png")
    make_button(256, 64, (48, 90, 70, 250), (180, 240, 190, 230)).save(UI / "btn_hover.png")
    make_button(256, 64, (22, 40, 34, 240), (70, 110, 90, 200)).save(UI / "btn_pressed.png")
    make_button(256, 64, (28, 32, 30, 200), (60, 70, 65, 160)).save(UI / "btn_disabled.png")
    make_panel(512, 512).save(UI / "panel.png")
    make_joystick_base().save(UI / "stick_base.png")
    make_joystick_knob().save(UI / "stick_knob.png")

    # HUD strip background
    hud = Image.new("RGBA", (720, 72), (0, 0, 0, 0))
    d = ImageDraw.Draw(hud)
    d.rounded_rectangle([0, 0, 719, 71], radius=12, fill=(12, 22, 20, 210), outline=(70, 130, 105, 180), width=2)
    hud.save(UI / "hud_strip.png")

    # Soft vignette / boot wash
    boot = Image.new("RGBA", (720, 1280), (0, 0, 0, 0))
    bd = ImageDraw.Draw(boot)
    for y in range(1280):
        t = y / 1279
        # deep teal bottom → moss top
        r = int(8 + t * 10)
        g = int(28 + (1 - t) * 25)
        b = int(24 + t * 18)
        bd.line([(0, y), (719, y)], fill=(r, g, b, 255))
    # soft radial glow center
    for rad in range(280, 40, -8):
        a = max(0, 50 - rad // 8)
        bd.ellipse([360 - rad, 420 - rad, 360 + rad, 420 + rad], outline=(60, 140, 110, a))
    boot.save(UI / "boot_bg.png")
    print("UI chrome written")


if __name__ == "__main__":
    main()
