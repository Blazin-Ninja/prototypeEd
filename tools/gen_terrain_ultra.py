#!/usr/bin/env python3
"""Ultra terrain pass — dramatically richer overworld tiles (256px, many variants).

Targets a large visual leap vs the old 96px flat tiles: multi-octave noise,
directional lighting, micro-detail, and biome-specific props.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

TILES = Path("/workspace/assets/tiles")
TILES.mkdir(parents=True, exist_ok=True)
SIZE = 256  # was 96 — ~2.7× linear / ~7× pixels, plus quality leap


def clamp(v: float) -> int:
    return max(0, min(255, int(round(v))))


def mix(a, b, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(3))


def shade(c, amt: float):
    if amt >= 0:
        return mix(c, (255, 255, 255), amt)
    return mix(c, (6, 8, 10), -amt)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def fbm(x, y, seed, octaves=5):
    total = 0.0
    amp = 1.0
    freq = 1.0
    norm = 0.0
    for o in range(octaves):
        # value-noise-ish via sines
        n = (
            math.sin((x * freq + seed * 1.7 + o * 13.1) * 0.11)
            * math.cos((y * freq - seed * 0.9 + o * 7.3) * 0.13)
            + math.sin((x + y) * freq * 0.07 + seed)
            * 0.35
        )
        total += n * amp
        norm += amp
        amp *= 0.5
        freq *= 2.05
    return (total / max(norm, 1e-6) + 1.0) * 0.5


def noise_base(a, b, seed=1, scale=1.0, light=(-0.55, -0.65)):
    img = Image.new("RGBA", (SIZE, SIZE))
    pix = img.load()
    lx, ly = light
    ln = math.hypot(lx, ly) or 1.0
    lx, ly = lx / ln, ly / ln
    for y in range(SIZE):
        for x in range(SIZE):
            n = fbm(x * scale, y * scale, seed)
            n2 = fbm(x * scale * 2.3 + 40, y * scale * 2.3, seed + 9)
            # fake slope for lighting
            nx = fbm((x + 1) * scale, y * scale, seed) - fbm((x - 1) * scale, y * scale, seed)
            ny = fbm(x * scale, (y + 1) * scale, seed) - fbm(x * scale, (y - 1) * scale, seed)
            ndot = max(0.0, (-nx) * lx * 4 + (-ny) * ly * 4 + 0.65)
            t = n * 0.7 + n2 * 0.3
            col = mix(a, b, t)
            col = mix(shade(col, -0.28), shade(col, 0.32), 0.35 + 0.65 * ndot)
            pix[x, y] = rgba(col)
    return img


def finish(img: Image.Image) -> Image.Image:
    soft = img.filter(ImageFilter.GaussianBlur(0.7))
    out = Image.alpha_composite(soft, img)
    out = Image.blend(out, out.filter(ImageFilter.DETAIL), 0.45)
    out = ImageEnhance.Contrast(out).enhance(1.16)
    out = ImageEnhance.Color(out).enhance(1.1)
    out = ImageEnhance.Sharpness(out).enhance(1.28)
    return out


def soft_ellipse(img, box, col, blur=1.5):
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=col)
    if blur > 0:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img, layer)


def soft_poly(img, pts, col, blur=1.0):
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=col)
    if blur > 0:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img, layer)


# ─── Grass ───────────────────────────────────────────────────────────────────

def make_grass(variant=0):
    deep = (28, 78, 42)
    mid = (52, 128, 68)
    hi = (92, 178, 98)
    if variant == 1:
        deep, mid, hi = (24, 70, 48), (48, 120, 78), (110, 190, 120)
    if variant == 2:
        deep, mid, hi = (36, 70, 38), (70, 130, 60), (150, 200, 110)
    if variant == 3:
        deep, mid, hi = (22, 60, 40), (40, 110, 70), (80, 160, 100)
    img = noise_base(deep, mid, seed=11 + variant * 17, scale=1.15)
    d = ImageDraw.Draw(img)
    rnd = random.Random(42 + variant * 91)
    # dense blades
    for _ in range(520):
        x = rnd.randint(2, SIZE - 3)
        y = rnd.randint(18, SIZE - 2)
        h = rnd.randint(10, 28)
        lean = rnd.randint(-4, 4)
        col = hi if rnd.random() > 0.4 else deep
        width = 1 if rnd.random() > 0.25 else 2
        d.line([(x, y), (x + lean, y - h)], fill=rgba(col, 230), width=width)
        if rnd.random() > 0.7:
            d.ellipse([x + lean - 2, y - h - 2, x + lean + 2, y - h + 2], fill=(170, 220, 120, 180))
    # clover / flowers
    for _ in range(18):
        fx, fy = rnd.randint(12, SIZE - 14), rnd.randint(20, SIZE - 16)
        petal = (230, 190, 90, 200) if rnd.random() > 0.45 else (220, 120, 150, 190)
        d.ellipse([fx, fy, fx + 5, fy + 5], fill=petal)
    # soft vignette edge for tiling
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(18, 48, 28, 40), width=3)
    img = Image.alpha_composite(img, overlay)
    return finish(img)


# ─── Path ────────────────────────────────────────────────────────────────────

def make_path(variant=0):
    a, b = (110, 86, 58), (168, 136, 96)
    if variant:
        a, b = (96, 74, 50), (180, 148, 108)
    img = noise_base(a, b, seed=7 + variant * 11, scale=1.35, light=(-0.4, -0.7))
    d = ImageDraw.Draw(img)
    rnd = random.Random(9 + variant)
    # packed dirt patches + pebbles
    for _ in range(70):
        x, y = rnd.randint(6, SIZE - 20), rnd.randint(6, SIZE - 18)
        w, h = rnd.randint(8, 22), rnd.randint(5, 14)
        d.ellipse([x, y, x + w, y + h], fill=(78, 58, 38, 150))
    for _ in range(40):
        x, y = rnd.randint(10, SIZE - 12), rnd.randint(10, SIZE - 12)
        d.ellipse([x, y, x + 4, y + 3], fill=(210, 190, 150, 160))
        d.ellipse([x + 1, y, x + 3, y + 1], fill=(240, 230, 200, 120))
    # wheel / wear ruts
    for yy in (SIZE // 3, 2 * SIZE // 3):
        d.arc([20, yy - 30, SIZE - 20, yy + 30], 200, 340, fill=(70, 52, 34, 90), width=3)
    # border dust
    d.rectangle([0, 0, SIZE - 1, 6], fill=(90, 70, 48, 90))
    d.rectangle([0, SIZE - 7, SIZE - 1, SIZE - 1], fill=(90, 70, 48, 90))
    return finish(img)


# ─── Cliff / wall ────────────────────────────────────────────────────────────

def make_cliff(variant=0):
    a, b = (48, 52, 60), (108, 114, 126)
    if variant == 1:
        a, b = (56, 60, 70), (130, 136, 150)
    if variant == 2:
        a, b = (40, 48, 58), (90, 100, 120)
    img = noise_base(a, b, seed=31 + variant * 13, scale=0.9, light=(-0.3, -0.85))
    d = ImageDraw.Draw(img)
    # strata shelves
    for i, y in enumerate(range(16, SIZE, 28)):
        shade_v = 70 + (i % 4) * 16
        pts = [
            (0, y + 18),
            (40 + (i % 3) * 18, y - 4),
            (SIZE, y + 12),
            (SIZE, y + 26),
            (0, y + 28),
        ]
        d.polygon(pts, fill=(shade_v, shade_v + 6, shade_v + 14, 200))
        d.line([(8, y + 2), (SIZE - 8, y + 8)], fill=(210, 215, 225, 110), width=2)
    # ledges
    img = soft_poly(
        img,
        [(20, 70), (110, 28), (200, 64), (160, 92), (50, 96)],
        (150, 156, 170, 220),
        1.4,
    )
    img = soft_poly(
        img,
        [(30, 150), (130, 110), (230, 148), (180, 180), (60, 184)],
        (100, 108, 120, 210),
        1.4,
    )
    # cracks + AO base
    d = ImageDraw.Draw(img)
    d.line([(90, 20), (70, 220)], fill=(30, 32, 38, 180), width=3)
    d.line([(170, 40), (190, 230)], fill=(30, 32, 38, 140), width=2)
    d.rectangle([0, SIZE - 28, SIZE - 1, SIZE - 1], fill=(18, 20, 26, 160))
    # moss tufts
    rnd = random.Random(50 + variant)
    for _ in range(12):
        x, y = rnd.randint(20, SIZE - 30), rnd.randint(40, SIZE - 40)
        d.ellipse([x, y, x + 14, y + 8], fill=(40, 90, 50, 120))
    return finish(img)


def make_wall(variant=0):
    return make_cliff(variant)


# ─── Rock ────────────────────────────────────────────────────────────────────

def make_rock(variant=0):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img = soft_ellipse(img, [30, 150, 220, 230], (20, 30, 22, 110), 4.0)
    body = [(40, 180), (100, 40), (190, 55), (230, 170), (180, 220), (60, 220)]
    if variant:
        body = [(50, 190), (80, 60), (160, 30), (230, 140), (200, 220), (70, 230)]
    img = soft_poly(img, body, (118, 124, 134, 255), 1.2)
    img = soft_poly(img, [(90, 150), (120, 55), (150, 140)], (180, 186, 196, 230), 1.0)
    # mineral sparkle
    d = ImageDraw.Draw(img)
    rnd = random.Random(3 + variant)
    for _ in range(10):
        x, y = rnd.randint(90, 180), rnd.randint(80, 160)
        d.ellipse([x, y, x + 4, y + 3], fill=(220, 225, 235, 180))
    d.line([(80, 180), (150, 70)], fill=(60, 64, 72, 200), width=3)
    return finish(img)


# ─── Trees ───────────────────────────────────────────────────────────────────

def make_tree(variant=0):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cx = SIZE // 2 + (variant - 1) * 10
    # trunk with bark bands
    img = soft_poly(
        img,
        [(cx - 14, 150), (cx - 10, 70), (cx + 10, 70), (cx + 14, 150), (cx + 8, 230), (cx - 8, 230)],
        (92, 58, 32, 255),
        1.0,
    )
    d = ImageDraw.Draw(img)
    for y in range(90, 220, 16):
        d.arc([cx - 12, y, cx + 12, y + 14], 200, 340, fill=(60, 36, 20, 140), width=2)
    palettes = [
        [(22, 78, 40), (48, 130, 62), (18, 60, 32)],
        [(18, 70, 48), (40, 120, 70), (14, 50, 36)],
        [(40, 100, 50), (80, 160, 70), (30, 80, 40)],
        [(28, 90, 55), (70, 150, 80), (20, 70, 45)],
    ]
    deep, mid, hi = palettes[variant % len(palettes)]
    canopies = [
        (cx - 90, 20, cx + 20, 130, deep),
        (cx - 30, 0, cx + 95, 120, mid),
        (cx - 55, 40, cx + 55, 150, hi),
        (cx - 70, 60, cx + 10, 150, deep),
        (cx - 5, 50, cx + 75, 145, mid),
    ]
    for x0, y0, x1, y1, col in canopies:
        img = soft_ellipse(img, [x0, y0, x1, y1], rgba(col, 235), 2.2)
    # leaf sparkles
    rnd = random.Random(5 + variant)
    d = ImageDraw.Draw(img)
    for _ in range(35):
        x, y = rnd.randint(cx - 70, cx + 70), rnd.randint(20, 130)
        d.ellipse([x, y, x + 5, y + 5], fill=(150, 220, 120, 170))
    img = soft_ellipse(img, [cx - 50, 210, cx + 50, 245], (15, 30, 18, 90), 3.0)
    return finish(img)


# ─── Dunes ───────────────────────────────────────────────────────────────────

def make_dune(variant=0):
    a, b = (186, 140, 86), (236, 198, 132)
    if variant:
        a, b = (170, 120, 70), (245, 210, 150)
    img = noise_base(a, b, seed=44 + variant * 8, scale=0.85, light=(-0.7, -0.25))
    d = ImageDraw.Draw(img)
    shift = variant * 18
    img = soft_poly(
        img,
        [(0, 160 - shift), (70, 70), (140, 110), (200, 40), (SIZE, 90), (SIZE, SIZE), (0, SIZE)],
        (214, 170, 108, 255),
        1.8,
    )
    img = soft_poly(
        img,
        [(0, 190), (90, 130), (170, 150), (SIZE, 110), (SIZE, SIZE), (0, SIZE)],
        (178, 128, 78, 245),
        1.8,
    )
    d = ImageDraw.Draw(img)
    for y in (130, 155, 180, 205, 225):
        d.arc([10, y - 35, SIZE - 10, y + 35], 200, 340, fill=(255, 230, 180, 100), width=2)
    # wind sparkle
    rnd = random.Random(12 + variant)
    for _ in range(25):
        x, y = rnd.randint(20, SIZE - 20), rnd.randint(80, SIZE - 20)
        d.point((x, y), fill=(255, 245, 210, 180))
    return finish(img)


# ─── Hazards / anim ──────────────────────────────────────────────────────────

def make_water(phase: int):
    img = Image.new("RGBA", (SIZE, SIZE), (18, 78, 118, 255))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            w = (
                math.sin((x + phase * 7) * 0.09 + y * 0.07)
                + math.cos((y - phase * 3) * 0.11)
                + fbm(x * 0.8, y * 0.8, 90 + phase) * 0.8
            )
            if w > 1.0:
                pix[x, y] = (110, 200, 230, 255)
            elif w > 0.25:
                pix[x, y] = (50, 140, 180, 255)
            elif w < -0.8:
                pix[x, y] = (10, 48, 78, 255)
            else:
                pix[x, y] = (24, 100, 140, 255)
    d = ImageDraw.Draw(img)
    yy = 70 + (phase % 4) * 12
    d.arc([20, yy - 30, SIZE - 20, yy + 40], 200, 340, fill=(210, 245, 255, 140), width=3)
    d.arc([40, yy + 30, SIZE - 40, yy + 90], 200, 340, fill=(180, 230, 250, 90), width=2)
    return finish(img)


def make_lava(phase: int):
    img = Image.new("RGBA", (SIZE, SIZE), (120, 24, 8, 255))
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = math.sin(x * 0.12 + phase * 0.9) * math.cos(y * 0.1 - phase * 0.55)
            n += fbm(x, y, 70 + phase) * 0.6
            if n > 0.85:
                pix[x, y] = (255, 220, 90, 255)
            elif n > 0.25:
                pix[x, y] = (240, 110, 30, 255)
            elif n < -0.6:
                pix[x, y] = (60, 10, 6, 255)
            else:
                pix[x, y] = (180, 40, 12, 255)
    d = ImageDraw.Draw(img)
    d.ellipse([70 + phase * 3, 60, 130 + phase * 3, 120], fill=(255, 240, 150, 140))
    return finish(img)


def make_void(phase: int):
    img = Image.new("RGBA", (SIZE, SIZE), (8, 6, 18, 255))
    d = ImageDraw.Draw(img)
    cx = cy = SIZE // 2
    for i, r in enumerate([110, 85, 60, 35, 16]):
        col = (50 + i * 25, 30 + i * 14, 110 + i * 28, 170 - i * 20)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=3)
    for a in range(0, 360, 18):
        rad = math.radians(a + phase * 12)
        d.line(
            [(cx, cy), (cx + int(math.cos(rad) * 118), cy + int(math.sin(rad) * 118))],
            fill=(90, 60, 150, 70),
            width=2,
        )
    d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=(160, 120, 240, 230))
    return finish(img)


# ─── Special markers ─────────────────────────────────────────────────────────

def make_bridge():
    img = Image.new("RGBA", (SIZE, SIZE), (70, 44, 24, 255))
    d = ImageDraw.Draw(img)
    for y in range(10, SIZE, 28):
        d.rounded_rectangle(
            [10, y, SIZE - 11, y + 20],
            radius=4,
            fill=(150, 100, 56, 255),
            outline=(50, 28, 14, 255),
            width=2,
        )
        d.line([(20, y + 6), (SIZE - 20, y + 6)], fill=(200, 150, 90, 140), width=2)
        d.line([(24, y + 14), (SIZE - 24, y + 14)], fill=(40, 24, 12, 100), width=2)
    d.rectangle([0, 0, 14, SIZE - 1], fill=(42, 24, 12, 255))
    d.rectangle([SIZE - 15, 0, SIZE - 1, SIZE - 1], fill=(42, 24, 12, 255))
    return finish(img)


def make_empty():
    img = noise_base((14, 36, 24), (34, 72, 44), seed=21, scale=1.4)
    d = ImageDraw.Draw(img)
    rnd = random.Random(77)
    for _ in range(80):
        x, y = rnd.randint(0, SIZE - 28), rnd.randint(0, SIZE - 28)
        r = rnd.randint(10, 26)
        col = (20, 52, 32, 210) if rnd.random() > 0.4 else (10, 30, 20, 220)
        d.ellipse([x, y, x + r * 2, y + r * 2], fill=col)
    # twig litter
    for _ in range(30):
        x, y = rnd.randint(10, SIZE - 10), rnd.randint(10, SIZE - 10)
        d.line([(x, y), (x + rnd.randint(-8, 8), y + rnd.randint(-6, 6))], fill=(60, 40, 25, 140), width=1)
    return finish(img)


def make_camp():
    img = make_path(0)
    d = ImageDraw.Draw(img)
    d.ellipse([50, 120, 206, 220], fill=(70, 50, 32, 255), outline=(40, 28, 18, 255), width=3)
    d.polygon([(128, 30), (70, 140), (186, 140)], fill=(235, 120, 42, 255))
    d.polygon([(128, 10), (95, 110), (161, 110)], fill=(255, 220, 100, 235))
    d.ellipse([110, 150, 146, 186], fill=(255, 170, 70, 210))
    d.rounded_rectangle([40, 190, 90, 220], radius=4, fill=(90, 60, 35, 230))
    d.rounded_rectangle([166, 190, 216, 220], radius=4, fill=(90, 60, 35, 230))
    return finish(img)


def make_exit():
    img = make_path(0)
    d = ImageDraw.Draw(img)
    d.ellipse([36, 36, 220, 220], outline=(90, 185, 240, 255), width=8)
    d.ellipse([64, 64, 192, 192], fill=(28, 95, 155, 220))
    d.ellipse([96, 96, 160, 160], fill=(190, 240, 255, 245))
    d.arc([48, 48, 208, 208], 200, 320, fill=(210, 245, 255, 150), width=3)
    return finish(img)


def make_boss_tile():
    img = make_path(0)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([40, 70, 216, 220], radius=10, fill=(120, 30, 40, 255), outline=(50, 10, 16, 255), width=3)
    d.polygon([(128, 10), (30, 85), (226, 85)], fill=(160, 42, 52, 255))
    d.rectangle([112, 110, 144, 180], fill=(255, 95, 85, 230))
    d.ellipse([90, 90, 166, 130], fill=(255, 150, 130, 160))
    return finish(img)


def make_obelisk():
    base = make_path(0)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.paste(base, (0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([60, 190, 196, 240], fill=(40, 50, 40, 110))
    d.polygon([(128, 8), (70, 70), (186, 70)], fill=(165, 175, 190, 255))
    d.rectangle([78, 70, 178, 210], fill=(108, 118, 135, 255), outline=(60, 68, 80, 255), width=3)
    d.rectangle([112, 90, 144, 170], fill=(90, 230, 255, 220))
    d.ellipse([108, 60, 148, 100], fill=(200, 250, 255, 235))
    return finish(img)


def main():
    mapping = {}
    for i in range(4):
        mapping[f"grass{'' if i == 0 else f'_{i}'}.png"] = make_grass(i)
    for i in range(3):
        mapping[f"path{'' if i == 0 else f'_{i}'}.png"] = make_path(i)
    for i in range(3):
        mapping[f"cliff{'' if i == 0 else f'_{i}'}.png"] = make_cliff(i)
    mapping["wall.png"] = make_wall(0)
    for i in range(2):
        mapping[f"rock{'' if i == 0 else f'_{i}'}.png"] = make_rock(i)
    for i in range(4):
        mapping[f"tree{'' if i == 0 else f'_{i}'}.png"] = make_tree(i)
    for i in range(3):
        mapping[f"dune{'' if i == 0 else f'_{i}'}.png"] = make_dune(i)
    mapping["bridge.png"] = make_bridge()
    mapping["empty.png"] = make_empty()
    mapping["camp.png"] = make_camp()
    mapping["exit.png"] = make_exit()
    mapping["boss.png"] = make_boss_tile()
    mapping["obelisk.png"] = make_obelisk()
    for i in range(4):
        mapping[f"water_{i}.png"] = make_water(i)
        mapping[f"lava_{i}.png"] = make_lava(i)
        mapping[f"void_{i}.png"] = make_void(i)
    for name, im in mapping.items():
        im.save(TILES / name)
        print("tile", name, im.size)
    print("DONE", len(mapping))


if __name__ == "__main__":
    main()
