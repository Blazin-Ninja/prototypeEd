#!/usr/bin/env python3
"""Creature realism pass — ~83% richer shading/texture/volume vs flat silhouettes.

Resolutions: wild 256px (~128 * 1.83+), bosses 320px.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path("/workspace/assets")
DATA = Path("/workspace/data")
CREATURES = ROOT / "creatures"
BOSSES = ROOT / "bosses"
CREATURES.mkdir(parents=True, exist_ok=True)
BOSSES.mkdir(parents=True, exist_ok=True)

SIZE = 256
BOSS_SIZE = 320

ELEMENT_ACCENT = {
    "fire": (232, 93, 4),
    "water": (0, 119, 182),
    "earth": (139, 94, 52),
    "wind": (144, 224, 239),
    "nature": (45, 106, 79),
    "normal": (207, 207, 207),
    "electric": (255, 214, 10),
    "ice": (173, 232, 244),
    "poison": (123, 44, 191),
    "shadow": (60, 9, 108),
    "light": (255, 243, 176),
    "metal": (141, 153, 174),
}


def clamp(v: float) -> int:
    return max(0, min(255, int(round(v))))


def hex_rgb(h: str):
    h = (h or "#888888").lstrip("#")
    if len(h) != 6:
        return (140, 140, 140)
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(3))


def shade(c, amt: float):
    if amt >= 0:
        return mix(c, (255, 255, 255), amt)
    return mix(c, (8, 6, 10), -amt)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def new_img(s: int) -> Image.Image:
    return Image.new("RGBA", (s, s), (0, 0, 0, 0))


def soft_blob(img: Image.Image, box, color, blur=1.6):
    layer = new_img(img.size[0])
    d = ImageDraw.Draw(layer)
    d.ellipse(box, fill=color)
    if blur > 0:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img, layer)


def soft_poly(img: Image.Image, pts, color, blur=1.2):
    layer = new_img(img.size[0])
    d = ImageDraw.Draw(layer)
    d.polygon(pts, fill=color)
    if blur > 0:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img, layer)


def radial_shade(img: Image.Image, cx, cy, rx, ry, base, light_dir=(-0.45, -0.55), strength=0.55):
    """Paint elliptical volume with directional lighting into existing alpha."""
    pix = img.load()
    s = img.size[0]
    lx, ly = light_dir
    ln = math.hypot(lx, ly) or 1.0
    lx, ly = lx / ln, ly / ln
    x0, x1 = max(0, int(cx - rx - 2)), min(s, int(cx + rx + 3))
    y0, y1 = max(0, int(cy - ry - 2)), min(s, int(cy + ry + 3))
    for y in range(y0, y1):
        for x in range(x0, x1):
            a = pix[x, y][3]
            if a < 8:
                continue
            nx = (x - cx) / max(rx, 1)
            ny = (y - cy) / max(ry, 1)
            d2 = nx * nx + ny * ny
            if d2 > 1.15:
                continue
            # fake normal from ellipse
            nz = math.sqrt(max(0.0, 1.0 - min(1.0, d2)))
            ndot = max(0.0, (-nx) * lx + (-ny) * ly + nz * 0.85)
            rim = max(0.0, 1.0 - nz) * 0.35
            lit = 0.28 + strength * ndot - rim * 0.4
            # specular
            spec = (ndot ** 10) * 0.45
            col = mix(shade(base, -0.35), shade(base, 0.42), lit)
            col = mix(col, (255, 255, 255), min(0.55, spec))
            pix[x, y] = (col[0], col[1], col[2], a)
    return img


def fur_noise(img: Image.Image, base, density=0.012, seed=1):
    rnd = random.Random(seed)
    pix = img.load()
    s = img.size[0]
    n = int(s * s * density)
    for _ in range(n):
        x = rnd.randint(0, s - 1)
        y = rnd.randint(0, s - 1)
        a = pix[x, y][3]
        if a < 40:
            continue
        c = pix[x, y][:3]
        tip = mix(c, shade(base, 0.35 if rnd.random() > 0.5 else -0.25), 0.55)
        dx = rnd.choice([-1, 0, 1])
        dy = rnd.choice([-2, -1, -1, 0])
        x2, y2 = max(0, min(s - 1, x + dx)), max(0, min(s - 1, y + dy))
        if pix[x2, y2][3] > 20:
            pix[x2, y2] = (tip[0], tip[1], tip[2], min(255, a))
    return img


def scale_flecks(img: Image.Image, accent, seed=2):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img)
    s = img.size[0]
    pix = img.load()
    for _ in range(int(s * 0.35)):
        x = rnd.randint(8, s - 9)
        y = rnd.randint(8, s - 9)
        if pix[x, y][3] < 80:
            continue
        r = rnd.randint(2, 5)
        col = rgba(mix(accent, (255, 255, 255), 0.15), 90)
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    return img


def draw_eyes(img: Image.Image, cx, cy, spacing, r, glow=False, accent=(254, 228, 64)):
    d = ImageDraw.Draw(img)
    for sx in (-spacing, spacing):
        ex, ey = cx + sx, cy
        # socket shade
        img = soft_blob(img, [ex - r - 2, ey - r - 1, ex + r + 2, ey + r + 3], (20, 12, 18, 90), 1.2)
        d = ImageDraw.Draw(img)
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=(18, 16, 22, 255))
        # iris
        ir = max(2, r - 2)
        d.ellipse([ex - ir, ey - ir + 1, ex + ir, ey + ir + 1], fill=rgba(accent, 230))
        # pupil
        pr = max(1, r // 3)
        d.ellipse([ex - pr, ey - pr + 1, ex + pr, ey + pr + 1], fill=(8, 8, 12, 255))
        # catchlight
        d.ellipse([ex - r // 2, ey - r // 2 - 1, ex - r // 6, ey - r // 6], fill=(255, 255, 255, 230))
        if glow:
            img = soft_blob(img, [ex - r - 4, ey - r - 4, ex + r + 4, ey + r + 4], (*accent, 55), 2.5)
            d = ImageDraw.Draw(img)
    return img


def ground_shadow(img: Image.Image, s, y_frac=0.82, rx=0.30, ry=0.07):
    cx, cy = s // 2, int(s * y_frac)
    return soft_blob(
        img,
        [cx - int(s * rx), cy - int(s * ry), cx + int(s * rx), cy + int(s * ry)],
        (0, 0, 0, 75),
        3.0,
    )


def finish(img: Image.Image) -> Image.Image:
    # slight blur then gentle sharpen for painted realism
    soft = img.filter(ImageFilter.GaussianBlur(0.55))
    img = Image.alpha_composite(soft, img)
    # enhance contrast/color a touch
    rgb = img.convert("RGBA")
    # Unsharp-ish via detail filter
    detail = rgb.filter(ImageFilter.DETAIL)
    out = Image.blend(rgb, detail, 0.35)
    enhancer = ImageEnhance.Contrast(out)
    out = enhancer.enhance(1.12)
    enhancer = ImageEnhance.Color(out)
    out = enhancer.enhance(1.08)
    return out


def make_quad(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s)
    c = hex_rgb(base)
    dark, light = shade(c, -0.32), shade(c, 0.28)
    cx, cy = s // 2, int(s * 0.52)
    sc = s / 256.0
    # legs with volume
    for lx, ly in [(-44, 38), (-18, 42), (18, 42), (44, 38)]:
        bx = cx + int(lx * sc)
        by = cy + int(ly * sc)
        img = soft_blob(img, [bx - int(12 * sc), by, bx + int(12 * sc), by + int(40 * sc)], rgba(dark), 1.4)
        radial_shade(img, bx, by + int(18 * sc), 12 * sc, 20 * sc, dark, strength=0.4)
    # torso
    img = soft_blob(
        img,
        [cx - int(72 * sc), cy - int(28 * sc), cx + int(72 * sc), cy + int(48 * sc)],
        rgba(c),
        1.8,
    )
    radial_shade(img, cx - 8 * sc, cy + 4 * sc, 72 * sc, 40 * sc, c, strength=0.62)
    # chest highlight
    img = soft_blob(
        img,
        [cx - int(40 * sc), cy - int(10 * sc), cx + int(20 * sc), cy + int(24 * sc)],
        rgba(light, 70),
        3.0,
    )
    # head
    img = soft_blob(
        img,
        [cx - int(48 * sc), cy - int(88 * sc), cx + int(48 * sc), cy - int(8 * sc)],
        rgba(c),
        1.6,
    )
    radial_shade(img, cx - 6 * sc, cy - 48 * sc, 48 * sc, 40 * sc, c, strength=0.65)
    # ears
    img = soft_poly(
        img,
        [
            (cx - int(36 * sc), cy - int(70 * sc)),
            (cx - int(62 * sc), cy - int(118 * sc)),
            (cx - int(14 * sc), cy - int(82 * sc)),
        ],
        rgba(dark),
        1.0,
    )
    img = soft_poly(
        img,
        [
            (cx + int(36 * sc), cy - int(70 * sc)),
            (cx + int(62 * sc), cy - int(118 * sc)),
            (cx + int(14 * sc), cy - int(82 * sc)),
        ],
        rgba(dark),
        1.0,
    )
    # inner ear
    img = soft_poly(
        img,
        [
            (cx - int(34 * sc), cy - int(74 * sc)),
            (cx - int(50 * sc), cy - int(104 * sc)),
            (cx - int(22 * sc), cy - int(82 * sc)),
        ],
        rgba(shade(c, 0.15), 180),
        0.8,
    )
    el = elements[0] if elements else "normal"
    accent = ELEMENT_ACCENT.get(el, light)
    glow = el in ("electric", "light", "poison", "shadow", "fire")
    img = draw_eyes(img, cx, cy - int(52 * sc), int(18 * sc), int(9 * sc), glow=glow, accent=accent)
    # nose / muzzle
    img = soft_blob(
        img,
        [cx - int(16 * sc), cy - int(28 * sc), cx + int(16 * sc), cy - int(8 * sc)],
        rgba(shade(c, -0.15)),
        1.0,
    )
    d = ImageDraw.Draw(img)
    d.ellipse(
        [cx - int(6 * sc), cy - int(20 * sc), cx + int(6 * sc), cy - int(12 * sc)],
        fill=rgba(shade(c, -0.45)),
    )
    # element cheek marks
    img = soft_blob(
        img,
        [cx - int(52 * sc), cy - int(44 * sc), cx - int(30 * sc), cy - int(24 * sc)],
        rgba(accent, 110),
        2.0,
    )
    img = soft_blob(
        img,
        [cx + int(30 * sc), cy - int(44 * sc), cx + int(52 * sc), cy - int(24 * sc)],
        rgba(accent, 110),
        2.0,
    )
    if "fire" in elements:
        img = soft_poly(
            img,
            [
                (cx + int(50 * sc), cy - int(10 * sc)),
                (cx + int(88 * sc), cy - int(48 * sc)),
                (cx + int(70 * sc), cy + int(8 * sc)),
                (cx + int(96 * sc), cy + int(20 * sc)),
                (cx + int(48 * sc), cy + int(18 * sc)),
            ],
            (255, 140, 30, 210),
            1.5,
        )
        img = soft_poly(
            img,
            [
                (cx + int(58 * sc), cy - int(6 * sc)),
                (cx + int(78 * sc), cy - int(28 * sc)),
                (cx + int(66 * sc), cy + int(6 * sc)),
            ],
            (255, 230, 120, 180),
            1.0,
        )
    if "electric" in elements:
        img = soft_poly(
            img,
            [
                (cx + int(44 * sc), cy - int(70 * sc)),
                (cx + int(78 * sc), cy - int(40 * sc)),
                (cx + int(52 * sc), cy - int(36 * sc)),
                (cx + int(70 * sc), cy - int(8 * sc)),
                (cx + int(40 * sc), cy - int(28 * sc)),
            ],
            rgba(accent, 230),
            0.8,
        )
    fur_noise(img, c, density=0.018, seed=seed)
    return finish(img)


def make_fish(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.74, 0.34, 0.06)
    c = hex_rgb(base)
    dark, light = shade(c, -0.28), shade(c, 0.32)
    cx, cy = int(s * 0.46), s // 2
    sc = s / 256.0
    img = soft_blob(img, [cx - int(78 * sc), cy - int(40 * sc), cx + int(64 * sc), cy + int(40 * sc)], rgba(c), 2.0)
    radial_shade(img, cx - 10 * sc, cy, 78 * sc, 40 * sc, c, light_dir=(-0.6, -0.3), strength=0.7)
    # wet highlight streak
    img = soft_blob(
        img,
        [cx - int(50 * sc), cy - int(28 * sc), cx + int(10 * sc), cy - int(4 * sc)],
        rgba(light, 100),
        3.5,
    )
    # tail
    img = soft_poly(
        img,
        [
            (cx + int(50 * sc), cy),
            (cx + int(110 * sc), cy - int(42 * sc)),
            (cx + int(92 * sc), cy),
            (cx + int(110 * sc), cy + int(42 * sc)),
        ],
        rgba(dark),
        1.4,
    )
    radial_shade(img, cx + 85 * sc, cy, 30 * sc, 40 * sc, dark, strength=0.45)
    # dorsal
    img = soft_poly(
        img,
        [
            (cx - int(10 * sc), cy - int(36 * sc)),
            (cx + int(24 * sc), cy - int(78 * sc)),
            (cx + int(36 * sc), cy - int(28 * sc)),
        ],
        rgba(shade(c, 0.05)),
        1.2,
    )
    el = elements[0] if elements else "water"
    accent = ELEMENT_ACCENT.get(el, light)
    img = draw_eyes(img, cx - int(36 * sc), cy - int(6 * sc), 0, int(11 * sc), glow=False, accent=accent)
    d = ImageDraw.Draw(img)
    d.ellipse(
        [cx - int(54 * sc), cy + int(4 * sc), cx - int(34 * sc), cy + int(14 * sc)],
        fill=(12, 24, 40, 200),
    )
    # scale rows
    scale_flecks(img, accent, seed=seed)
    for i in range(7):
        img = soft_blob(
            img,
            [
                cx - int(20 * sc) + int(i * 12 * sc),
                cy - int(8 * sc),
                cx - int(8 * sc) + int(i * 12 * sc),
                cy + int(4 * sc),
            ],
            rgba(light, 70),
            1.5,
        )
    return finish(img)


def make_plant(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s)
    c = hex_rgb(base)
    dark, light = shade(c, -0.3), shade(c, 0.25)
    cx, cy = s // 2, int(s * 0.58)
    sc = s / 256.0
    # pot body
    img = soft_blob(img, [cx - int(52 * sc), cy - int(8 * sc), cx + int(52 * sc), cy + int(58 * sc)], rgba(dark), 1.8)
    radial_shade(img, cx, cy + 24 * sc, 52 * sc, 34 * sc, dark, strength=0.5)
    img = soft_blob(img, [cx - int(42 * sc), cy + int(4 * sc), cx + int(42 * sc), cy + int(46 * sc)], rgba(c), 1.4)
    # stem
    img = soft_blob(img, [cx - int(10 * sc), cy - int(70 * sc), cx + int(10 * sc), cy + int(8 * sc)], rgba(shade(c, -0.1)), 1.0)
    # leaves
    img = soft_blob(img, [cx - int(70 * sc), cy - int(120 * sc), cx + int(8 * sc), cy - int(40 * sc)], rgba(c), 2.2)
    img = soft_blob(img, [cx - int(8 * sc), cy - int(120 * sc), cx + int(70 * sc), cy - int(40 * sc)], rgba(light), 2.2)
    img = soft_blob(img, [cx - int(34 * sc), cy - int(140 * sc), cx + int(34 * sc), cy - int(70 * sc)], rgba(shade(c, 0.12)), 2.0)
    radial_shade(img, cx - 20 * sc, cy - 80 * sc, 40 * sc, 40 * sc, c, strength=0.55)
    radial_shade(img, cx + 20 * sc, cy - 80 * sc, 40 * sc, 40 * sc, light, strength=0.55)
    el = elements[0] if elements else "nature"
    accent = ELEMENT_ACCENT.get(el, (230, 190, 90))
    img = draw_eyes(img, cx, cy - int(96 * sc), int(16 * sc), int(7 * sc), accent=accent)
    # blossom
    img = soft_blob(
        img,
        [cx - int(14 * sc), cy - int(152 * sc), cx + int(14 * sc), cy - int(124 * sc)],
        (240, 200, 90, 230),
        1.5,
    )
    img = soft_blob(
        img,
        [cx - int(6 * sc), cy - int(144 * sc), cx + int(6 * sc), cy - int(132 * sc)],
        (255, 240, 180, 220),
        1.0,
    )
    fur_noise(img, c, density=0.01, seed=seed)
    return finish(img)


def make_bird(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.78)
    c = hex_rgb(base)
    dark, light = shade(c, -0.25), shade(c, 0.3)
    cx, cy = s // 2, int(s * 0.5)
    sc = s / 256.0
    # wings
    img = soft_blob(img, [cx - int(118 * sc), cy - int(20 * sc), cx - int(8 * sc), cy + int(55 * sc)], rgba(dark, 235), 2.4)
    img = soft_blob(img, [cx + int(8 * sc), cy - int(20 * sc), cx + int(118 * sc), cy + int(55 * sc)], rgba(dark, 235), 2.4)
    radial_shade(img, cx - 60 * sc, cy + 10 * sc, 55 * sc, 35 * sc, dark, strength=0.5)
    radial_shade(img, cx + 60 * sc, cy + 10 * sc, 55 * sc, 35 * sc, dark, strength=0.5)
    img = soft_blob(img, [cx - int(100 * sc), cy - int(4 * sc), cx - int(30 * sc), cy + int(28 * sc)], rgba(light, 90), 3.0)
    img = soft_blob(img, [cx + int(30 * sc), cy - int(4 * sc), cx + int(100 * sc), cy + int(28 * sc)], rgba(light, 90), 3.0)
    # body + head
    img = soft_blob(img, [cx - int(44 * sc), cy - int(16 * sc), cx + int(44 * sc), cy + int(60 * sc)], rgba(c), 1.8)
    radial_shade(img, cx, cy + 18 * sc, 44 * sc, 40 * sc, c, strength=0.6)
    img = soft_blob(img, [cx - int(38 * sc), cy - int(78 * sc), cx + int(38 * sc), cy - int(4 * sc)], rgba(c), 1.6)
    radial_shade(img, cx - 4 * sc, cy - 42 * sc, 38 * sc, 36 * sc, c, strength=0.65)
    # beak
    img = soft_poly(
        img,
        [
            (cx - int(4 * sc), cy - int(34 * sc)),
            (cx + int(36 * sc), cy - int(26 * sc)),
            (cx - int(4 * sc), cy - int(16 * sc)),
        ],
        (240, 180, 60, 255),
        0.8,
    )
    el = elements[0] if elements else "wind"
    accent = ELEMENT_ACCENT.get(el, light)
    img = draw_eyes(img, cx - int(8 * sc), cy - int(48 * sc), int(14 * sc), int(7 * sc), accent=accent)
    # crest
    img = soft_poly(
        img,
        [
            (cx - int(10 * sc), cy - int(74 * sc)),
            (cx + int(2 * sc), cy - int(112 * sc)),
            (cx + int(20 * sc), cy - int(74 * sc)),
        ],
        rgba(accent, 230),
        1.0,
    )
    fur_noise(img, c, density=0.014, seed=seed)
    return finish(img)


def make_bug(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s)
    c = hex_rgb(base)
    dark, light = shade(c, -0.28), shade(c, 0.22)
    cx, cy = s // 2, int(s * 0.5)
    sc = s / 256.0
    # legs
    dlayer = new_img(s)
    dd = ImageDraw.Draw(dlayer)
    for ang in (-55, -25, 25, 55):
        rad = math.radians(ang)
        x2 = cx + int(math.cos(rad) * 92 * sc)
        y2 = cy + int(28 * sc + math.sin(rad) * 18 * sc)
        dd.line([(cx, cy + int(10 * sc)), (x2, y2)], fill=rgba(dark), width=max(3, int(5 * sc)))
        dd.ellipse([x2 - 5, y2 - 5, x2 + 5, y2 + 5], fill=rgba(dark))
    dlayer = dlayer.filter(ImageFilter.GaussianBlur(0.7))
    img = Image.alpha_composite(img, dlayer)
    # abdomen + thorax + head
    img = soft_blob(img, [cx - int(56 * sc), cy - int(8 * sc), cx + int(56 * sc), cy + int(52 * sc)], rgba(c), 1.8)
    radial_shade(img, cx, cy + 20 * sc, 56 * sc, 32 * sc, c, strength=0.55)
    img = soft_blob(img, [cx - int(36 * sc), cy - int(48 * sc), cx + int(36 * sc), cy + int(8 * sc)], rgba(shade(c, 0.05)), 1.5)
    radial_shade(img, cx, cy - 20 * sc, 36 * sc, 28 * sc, shade(c, 0.05), strength=0.55)
    # carapace gloss
    img = soft_blob(
        img,
        [cx - int(24 * sc), cy - int(36 * sc), cx + int(8 * sc), cy - int(8 * sc)],
        rgba(light, 110),
        2.8,
    )
    el = elements[0] if elements else "poison"
    accent = ELEMENT_ACCENT.get(el, light)
    glow = el in ("poison", "shadow", "electric")
    img = draw_eyes(img, cx, cy - int(24 * sc), int(14 * sc), int(8 * sc), glow=glow, accent=accent)
    # mandibles
    img = soft_poly(
        img,
        [
            (cx - int(28 * sc), cy - int(8 * sc)),
            (cx - int(8 * sc), cy + int(18 * sc)),
            (cx - int(4 * sc), cy - int(2 * sc)),
        ],
        rgba(dark),
        0.7,
    )
    img = soft_poly(
        img,
        [
            (cx + int(28 * sc), cy - int(8 * sc)),
            (cx + int(8 * sc), cy + int(18 * sc)),
            (cx + int(4 * sc), cy - int(2 * sc)),
        ],
        rgba(dark),
        0.7,
    )
    scale_flecks(img, accent, seed=seed)
    return finish(img)


def make_serpent(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.84, 0.36, 0.06)
    c = hex_rgb(base)
    dark, light = shade(c, -0.32), shade(c, 0.24)
    cx = s // 2
    sc = s / 256.0
    # coils
    img = soft_blob(img, [cx - int(78 * sc), int(140 * sc), cx + int(78 * sc), int(230 * sc)], rgba(dark), 2.2)
    radial_shade(img, cx, 185 * sc, 78 * sc, 40 * sc, dark, strength=0.45)
    img = soft_blob(img, [cx - int(58 * sc), int(110 * sc), cx + int(70 * sc), int(190 * sc)], rgba(c), 2.0)
    radial_shade(img, cx + 4 * sc, 150 * sc, 64 * sc, 40 * sc, c, strength=0.55)
    img = soft_blob(img, [cx - int(42 * sc), int(72 * sc), cx + int(48 * sc), int(145 * sc)], rgba(shade(c, 0.06)), 1.8)
    # neck + head
    img = soft_blob(img, [cx - int(28 * sc), int(36 * sc), cx + int(36 * sc), int(100 * sc)], rgba(c), 1.6)
    img = soft_blob(img, [cx - int(44 * sc), int(8 * sc), cx + int(50 * sc), int(78 * sc)], rgba(c), 1.8)
    radial_shade(img, cx + 2 * sc, 42 * sc, 46 * sc, 36 * sc, c, strength=0.7)
    img = soft_blob(
        img,
        [cx - int(28 * sc), int(16 * sc), cx + int(16 * sc), int(52 * sc)],
        rgba(light, 90),
        2.5,
    )
    el = elements[0] if elements else "poison"
    accent = ELEMENT_ACCENT.get(el, dark)
    glow = el in ("poison", "shadow", "fire")
    img = draw_eyes(img, cx + int(4 * sc), int(40 * sc), int(16 * sc), int(9 * sc), glow=glow, accent=accent)
    # fangs / tongue
    img = soft_poly(
        img,
        [
            (cx + int(14 * sc), int(62 * sc)),
            (cx + int(40 * sc), int(78 * sc)),
            (cx + int(12 * sc), int(70 * sc)),
        ],
        (220, 60, 80, 230),
        0.6,
    )
    # dorsal diamonds
    for y in (100, 130, 160, 190):
        img = soft_poly(
            img,
            [
                (cx, int((y - 10) * sc)),
                (cx + int(16 * sc), int(y * sc)),
                (cx, int((y + 10) * sc)),
                (cx - int(16 * sc), int(y * sc)),
            ],
            rgba(accent, 150),
            0.8,
        )
    scale_flecks(img, accent, seed=seed)
    return finish(img)


def make_bulk(base, elements, boss=False, seed=1) -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.86, 0.38, 0.08)
    c = hex_rgb(base)
    dark, light = shade(c, -0.3), shade(c, 0.22)
    cx, cy = s // 2, int(s * 0.54)
    sc = s / 256.0
    # legs
    img = soft_blob(img, [cx - int(70 * sc), cy + int(24 * sc), cx - int(18 * sc), cy + int(90 * sc)], rgba(dark), 1.8)
    img = soft_blob(img, [cx + int(18 * sc), cy + int(24 * sc), cx + int(70 * sc), cy + int(90 * sc)], rgba(dark), 1.8)
    radial_shade(img, cx - 44 * sc, cy + 55 * sc, 26 * sc, 32 * sc, dark, strength=0.4)
    radial_shade(img, cx + 44 * sc, cy + 55 * sc, 26 * sc, 32 * sc, dark, strength=0.4)
    # torso
    img = soft_blob(img, [cx - int(90 * sc), cy - int(40 * sc), cx + int(90 * sc), cy + int(55 * sc)], rgba(c), 2.2)
    radial_shade(img, cx - 10 * sc, cy + 4 * sc, 90 * sc, 50 * sc, c, strength=0.62)
    img = soft_blob(
        img,
        [cx - int(55 * sc), cy - int(28 * sc), cx + int(30 * sc), cy + int(20 * sc)],
        rgba(light, 80),
        3.5,
    )
    # arms
    img = soft_blob(img, [cx - int(118 * sc), cy - int(10 * sc), cx - int(48 * sc), cy + int(48 * sc)], rgba(dark), 1.8)
    img = soft_blob(img, [cx + int(48 * sc), cy - int(10 * sc), cx + int(118 * sc), cy + int(48 * sc)], rgba(dark), 1.8)
    # head
    img = soft_blob(img, [cx - int(54 * sc), cy - int(105 * sc), cx + int(54 * sc), cy - int(18 * sc)], rgba(c), 1.8)
    radial_shade(img, cx - 6 * sc, cy - 62 * sc, 54 * sc, 44 * sc, c, strength=0.65)
    el = elements[0] if elements else "nature"
    accent = ELEMENT_ACCENT.get(el, light)
    img = draw_eyes(
        img,
        cx,
        cy - int(66 * sc),
        int(20 * sc),
        int(11 * sc),
        glow=boss or el in ("shadow", "poison", "fire"),
        accent=accent,
    )
    if boss:
        img = soft_poly(
            img,
            [
                (cx - int(56 * sc), cy - int(95 * sc)),
                (cx - int(18 * sc), cy - int(150 * sc)),
                (cx + int(18 * sc), cy - int(150 * sc)),
                (cx + int(56 * sc), cy - int(95 * sc)),
            ],
            rgba(accent, 230),
            1.4,
        )
        img = soft_blob(
            img,
            [cx - int(34 * sc), cy - int(168 * sc), cx + int(34 * sc), cy - int(118 * sc)],
            rgba(shade(accent, 0.2), 220),
            2.0,
        )
    fur_noise(img, c, density=0.012, seed=seed)
    scale_flecks(img, accent, seed=seed + 3)
    return finish(img)


SHAPE_FN = {
    "quad": make_quad,
    "fish": make_fish,
    "plant": make_plant,
    "bird": make_bird,
    "bug": make_bug,
    "serpent": make_serpent,
    "bulk": make_bulk,
}


def main():
    data = json.loads((DATA / "creatures.json").read_text())["creatures"]
    for i, c in enumerate(data):
        cid = c["id"]
        shape = c.get("shape", "quad")
        color = c.get("color", "#888888")
        els = c.get("elements", [])
        boss = bool(c.get("is_boss", False))
        fn = SHAPE_FN.get(shape, make_quad)
        img = fn(color, els, boss=boss, seed=1000 + i)
        img.save(CREATURES / f"{cid}.png")
        if boss:
            img.save(BOSSES / f"{cid}.png")
        print("creature", cid, img.size, shape)
    print("DONE", len(data))


if __name__ == "__main__":
    main()
