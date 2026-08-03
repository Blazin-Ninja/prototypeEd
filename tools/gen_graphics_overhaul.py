#!/usr/bin/env python3
"""Chimera Bond graphics overhaul — creatures, mutations, arenas, FX, tiles, player."""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

_REPO = Path(__file__).resolve().parents[1]
ROOT = _REPO / "assets"
DATA = _REPO / "data"
CREATURES = ROOT / "creatures"
BOSSES = ROOT / "bosses"
MUTATIONS = ROOT / "mutations"
TILES = ROOT / "tiles"
ARENAS = ROOT / "arenas"
FX = ROOT / "fx"
PLAYER = ROOT / "player"
UI = ROOT / "ui"

for p in (CREATURES, BOSSES, MUTATIONS, TILES, ARENAS, FX, PLAYER, UI):
    p.mkdir(parents=True, exist_ok=True)

SIZE = 128
BOSS_SIZE = 160
TILE = 96


def clamp(v: int) -> int:
    return max(0, min(255, int(v)))


def hex_to_rgb(h: str):
    h = h.lstrip("#")
    if len(h) == 6:
        return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))
    return (180, 180, 180)


def mix(a, b, t: float):
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(3))


def rgba(rgb, a=255):
    return (rgb[0], rgb[1], rgb[2], a)


def new_img(size: int, color=(0, 0, 0, 0)) -> Image.Image:
    return Image.new("RGBA", (size, size), color)


def soft_ellipse(draw, box, fill, outline=None, width=1):
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def shade(base, amount: float):
    if amount >= 0:
        return mix(base, (255, 255, 255), amount)
    return mix(base, (0, 0, 0), -amount)


# ─── Creatures ───────────────────────────────────────────────────────────────

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


def draw_eyes(d: ImageDraw.ImageDraw, cx: int, cy: int, spacing: int, r: int, glow=False):
    for sx in (-spacing, spacing):
        soft_ellipse(d, [cx + sx - r, cy - r, cx + sx + r, cy + r], (20, 18, 22, 255))
        soft_ellipse(
            d,
            [cx + sx - r // 2, cy - r // 2 - 1, cx + sx + r // 3, cy + r // 4],
            (250, 250, 255, 230),
        )
        if glow:
            soft_ellipse(
                d,
                [cx + sx - r - 2, cy - r - 2, cx + sx + r + 2, cy + r + 2],
                (254, 228, 64, 90),
            )


def creature_canvas(boss: bool) -> tuple[Image.Image, ImageDraw.ImageDraw, int]:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    return img, ImageDraw.Draw(img), s


def draw_shadow(d, s, y_frac=0.78, rx=0.28, ry=0.08):
    cx, cy = s // 2, int(s * y_frac)
    soft_ellipse(
        d,
        [cx - int(s * rx), cy - int(s * ry), cx + int(s * rx), cy + int(s * ry)],
        (0, 0, 0, 70),
    )


def make_quad(base, elements, boss=False, name="") -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.28), shade(c, 0.28)
    cx, cy = s // 2, s // 2 + 6
    # legs
    for lx in (-22, -8, 8, 22):
        soft_ellipse(d, [cx + lx - 7, cy + 18, cx + lx + 7, cy + 42], rgba(dark))
    # body
    soft_ellipse(d, [cx - 38, cy - 18, cx + 38, cy + 28], rgba(c))
    soft_ellipse(d, [cx - 28, cy - 12, cx + 18, cy + 12], rgba(light, 160))
    # head
    soft_ellipse(d, [cx - 26, cy - 46, cx + 26, cy - 2], rgba(c))
    soft_ellipse(d, [cx - 18, cy - 42, cx + 10, cy - 18], rgba(light, 150))
    # ears
    d.polygon([(cx - 22, cy - 40), (cx - 34, cy - 62), (cx - 10, cy - 48)], fill=rgba(dark))
    d.polygon([(cx + 22, cy - 40), (cx + 34, cy - 62), (cx + 10, cy - 48)], fill=rgba(dark))
    draw_eyes(d, cx, cy - 28, 10, 5, glow="electric" in elements or "light" in elements)
    # nose
    soft_ellipse(d, [cx - 4, cy - 18, cx + 4, cy - 12], rgba(dark, 220))
    # element cheek marks
    el = elements[0] if elements else "normal"
    accent = ELEMENT_ACCENT.get(el, c)
    soft_ellipse(d, [cx - 30, cy - 22, cx - 18, cy - 12], rgba(accent, 120))
    soft_ellipse(d, [cx + 18, cy - 22, cx + 30, cy - 12], rgba(accent, 120))
    # flame/electric accents for named starters
    if "fire" in elements:
        d.polygon([(cx + 30, cy - 8), (cx + 48, cy - 28), (cx + 40, cy + 4)], fill=(255, 160, 40, 220))
    if "electric" in elements:
        d.polygon([(cx + 28, cy - 36), (cx + 46, cy - 20), (cx + 30, cy - 18)], fill=rgba(accent, 230))
    return img.filter(ImageFilter.SMOOTH_MORE)


def make_fish(base, elements, boss=False) -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s, 0.72)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.25), shade(c, 0.3)
    cx, cy = s // 2 - 4, s // 2
    soft_ellipse(d, [cx - 40, cy - 22, cx + 34, cy + 22], rgba(c))
    soft_ellipse(d, [cx - 30, cy - 14, cx + 10, cy + 6], rgba(light, 150))
    d.polygon([(cx + 30, cy), (cx + 58, cy - 22), (cx + 58, cy + 22)], fill=rgba(dark))
    d.polygon([(cx - 10, cy - 22), (cx + 8, cy - 44), (cx + 18, cy - 18)], fill=rgba(shade(c, 0.1)))
    draw_eyes(d, cx - 18, cy - 4, 0, 6)
    soft_ellipse(d, [cx - 28, cy + 2, cx - 18, cy + 8], (20, 20, 30, 200))  # mouth
    # scales shimmer
    for i in range(5):
        soft_ellipse(
            d,
            [cx - 8 + i * 8, cy - 6, cx - 2 + i * 8, cy],
            rgba(light, 100),
        )
    return img.filter(ImageFilter.SMOOTH)


def make_plant(base, elements, boss=False) -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.3), shade(c, 0.25)
    cx, cy = s // 2, s // 2 + 10
    # pot/body
    soft_ellipse(d, [cx - 28, cy - 6, cx + 28, cy + 34], rgba(dark))
    soft_ellipse(d, [cx - 22, cy, cx + 22, cy + 26], rgba(c))
    # stem
    d.rectangle([cx - 5, cy - 36, cx + 5, cy + 4], fill=rgba(shade(c, -0.15)))
    # leaves / head
    soft_ellipse(d, [cx - 34, cy - 58, cx + 8, cy - 20], rgba(c))
    soft_ellipse(d, [cx - 8, cy - 58, cx + 34, cy - 20], rgba(light))
    soft_ellipse(d, [cx - 16, cy - 70, cx + 16, cy - 40], rgba(shade(c, 0.15)))
    draw_eyes(d, cx, cy - 48, 9, 4)
    # sprout bud
    soft_ellipse(d, [cx - 6, cy - 78, cx + 6, cy - 66], (230, 190, 90, 230))
    return img.filter(ImageFilter.SMOOTH)


def make_bird(base, elements, boss=False) -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s, 0.76)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.22), shade(c, 0.32)
    cx, cy = s // 2, s // 2 + 4
    # wings
    soft_ellipse(d, [cx - 58, cy - 10, cx - 8, cy + 28], rgba(dark, 230))
    soft_ellipse(d, [cx + 8, cy - 10, cx + 58, cy + 28], rgba(dark, 230))
    soft_ellipse(d, [cx - 50, cy - 4, cx - 16, cy + 16], rgba(light, 140))
    soft_ellipse(d, [cx + 16, cy - 4, cx + 50, cy + 16], rgba(light, 140))
    # body + head
    soft_ellipse(d, [cx - 24, cy - 10, cx + 24, cy + 34], rgba(c))
    soft_ellipse(d, [cx - 20, cy - 42, cx + 20, cy - 2], rgba(c))
    soft_ellipse(d, [cx - 12, cy - 36, cx + 8, cy - 16], rgba(light, 160))
    # beak
    d.polygon([(cx - 2, cy - 18), (cx + 18, cy - 14), (cx - 2, cy - 8)], fill=(240, 180, 60, 255))
    draw_eyes(d, cx - 4, cy - 26, 8, 4)
    # crest for wind/poison
    if elements:
        accent = ELEMENT_ACCENT.get(elements[0], light)
        d.polygon([(cx - 6, cy - 40), (cx, cy - 58), (cx + 10, cy - 40)], fill=rgba(accent, 230))
    return img.filter(ImageFilter.SMOOTH)


def make_bug(base, elements, boss=False) -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.25), shade(c, 0.25)
    cx, cy = s // 2, s // 2 + 4
    # legs
    for i, ang in enumerate([-50, -20, 20, 50]):
        rad = math.radians(ang)
        x2 = cx + int(math.cos(rad) * 46)
        y2 = cy + 18 + int(math.sin(rad) * 10)
        d.line([(cx, cy + 8), (x2, y2)], fill=rgba(dark), width=3)
    soft_ellipse(d, [cx - 30, cy - 8, cx + 30, cy + 28], rgba(c))
    soft_ellipse(d, [cx - 18, cy - 28, cx + 18, cy + 4], rgba(shade(c, 0.05)))
    soft_ellipse(d, [cx - 12, cy - 20, cx + 4, cy - 6], rgba(light, 150))
    draw_eyes(d, cx, cy - 14, 8, 4, glow="shadow" in elements or "poison" in elements)
    # mandibles
    d.arc([cx - 16, cy - 8, cx - 2, cy + 10], 20, 160, fill=rgba(dark), width=3)
    d.arc([cx + 2, cy - 8, cx + 16, cy + 10], 20, 160, fill=rgba(dark), width=3)
    return img.filter(ImageFilter.SMOOTH)


def make_serpent(base, elements, boss=False) -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s, 0.8, 0.34, 0.07)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.3), shade(c, 0.25)
    cx = s // 2
    # coiled body
    soft_ellipse(d, [cx - 40, 70, cx + 40, 118], rgba(dark))
    soft_ellipse(d, [cx - 28, 58, cx + 36, 100], rgba(c))
    soft_ellipse(d, [cx - 20, 40, cx + 24, 78], rgba(shade(c, 0.08)))
    # neck + head
    soft_ellipse(d, [cx - 14, 22, cx + 18, 58], rgba(c))
    soft_ellipse(d, [cx - 22, 8, cx + 26, 42], rgba(c))
    soft_ellipse(d, [cx - 14, 12, cx + 10, 30], rgba(light, 150))
    draw_eyes(d, cx + 2, 22, 9, 5, glow="poison" in elements or "shadow" in elements)
    # tongue / fangs hint
    d.polygon([(cx + 8, 34), (cx + 20, 42), (cx + 6, 38)], fill=(220, 60, 80, 230))
    # dorsal pattern
    accent = ELEMENT_ACCENT.get(elements[0] if elements else "nature", dark)
    for y in (55, 70, 85):
        soft_ellipse(d, [cx - 8, y, cx + 8, y + 10], rgba(accent, 140))
    return img.filter(ImageFilter.SMOOTH)


def make_bulk(base, elements, boss=False) -> Image.Image:
    img, d, s = creature_canvas(boss)
    draw_shadow(d, s, 0.82, 0.36)
    c = hex_to_rgb(base) if isinstance(base, str) else base
    dark, light = shade(c, -0.28), shade(c, 0.22)
    cx, cy = s // 2, s // 2 + 8
    # legs
    soft_ellipse(d, [cx - 36, cy + 16, cx - 12, cy + 48], rgba(dark))
    soft_ellipse(d, [cx + 12, cy + 16, cx + 36, cy + 48], rgba(dark))
    # torso
    soft_ellipse(d, [cx - 46, cy - 24, cx + 46, cy + 30], rgba(c))
    soft_ellipse(d, [cx - 30, cy - 18, cx + 18, cy + 10], rgba(light, 140))
    # head
    soft_ellipse(d, [cx - 28, cy - 56, cx + 28, cy - 10], rgba(c))
    draw_eyes(d, cx, cy - 36, 11, 6, glow=boss or "shadow" in elements)
    # arms
    soft_ellipse(d, [cx - 58, cy - 8, cx - 28, cy + 22], rgba(dark))
    soft_ellipse(d, [cx + 28, cy - 8, cx + 58, cy + 22], rgba(dark))
    # boss crown / canopy
    if boss:
        accent = ELEMENT_ACCENT.get(elements[0] if elements else "nature", light)
        d.polygon(
            [(cx - 30, cy - 50), (cx - 10, cy - 78), (cx + 10, cy - 78), (cx + 30, cy - 50)],
            fill=rgba(accent, 230),
        )
        soft_ellipse(d, [cx - 18, cy - 86, cx + 18, cy - 62], rgba(shade(accent, 0.2), 220))
    return img.filter(ImageFilter.SMOOTH_MORE)


SHAPE_FN = {
    "quad": make_quad,
    "fish": make_fish,
    "plant": make_plant,
    "bird": make_bird,
    "bug": make_bug,
    "serpent": make_serpent,
    "bulk": make_bulk,
}


def generate_creatures():
    data = json.loads((DATA / "creatures.json").read_text())["creatures"]
    for c in data:
        cid = c["id"]
        shape = c.get("shape", "quad")
        color = c.get("color", "#888888")
        els = c.get("elements", [])
        boss = bool(c.get("is_boss", False))
        fn = SHAPE_FN.get(shape, make_quad)
        img = fn(color, els, boss=boss, name=cid) if shape == "quad" else fn(color, els, boss=boss)
        # named tweaks
        if cid == "ember_pup":
            d = ImageDraw.Draw(img)
            s = img.size[0]
            cx = s // 2
            d.polygon([(cx + 26, 54), (cx + 48, 30), (cx + 42, 62)], fill=(255, 140, 30, 230))
        path = CREATURES / f"{cid}.png"
        img.save(path)
        if boss:
            img.save(BOSSES / f"{cid}.png")
        print("creature", cid, img.size)


# ─── Mutations ───────────────────────────────────────────────────────────────

def mut_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = new_img(SIZE)
    return img, ImageDraw.Draw(img)


def make_mutation(slot: str, key: str, color: str | None) -> Image.Image:
    img, d = mut_canvas()
    c = hex_to_rgb(color or "#cccccc")
    light, dark = shade(c, 0.3), shade(c, -0.3)
    cx, cy = SIZE // 2, SIZE // 2

    if slot == "horns":
        if "curved" in key or "crest" in key:
            d.pieslice([cx - 42, 8, cx - 6, 56], 200, 340, fill=rgba(c))
            d.pieslice([cx + 6, 8, cx + 42, 56], 200, 340, fill=rgba(c))
            soft_ellipse(d, [cx - 38, 10, cx - 18, 28], rgba(light, 160))
            soft_ellipse(d, [cx + 18, 10, cx + 38, 28], rgba(light, 160))
            if "crest" in key:
                d.polygon([(cx - 8, 18), (cx, 0), (cx + 8, 18)], fill=(255, 214, 10, 240))
        else:
            d.polygon([(cx - 28, 40), (cx - 34, 8), (cx - 16, 36)], fill=rgba(c))
            d.polygon([(cx + 28, 40), (cx + 34, 8), (cx + 16, 36)], fill=rgba(c))
            soft_ellipse(d, [cx - 34, 6, cx - 26, 14], rgba(light))
            soft_ellipse(d, [cx + 26, 6, cx + 34, 14], rgba(light))
    elif slot == "tail":
        if "flame" in key:
            d.polygon([(cx + 20, 70), (cx + 52, 40), (cx + 44, 78), (cx + 58, 90), (cx + 18, 88)], fill=(232, 93, 4, 230))
            d.polygon([(cx + 26, 72), (cx + 44, 50), (cx + 36, 80)], fill=(255, 220, 80, 210))
        else:
            soft_ellipse(d, [cx + 18, 68, cx + 46, 96], rgba(c))
            soft_ellipse(d, [cx + 28, 72, cx + 42, 88], rgba(light, 150))
    elif slot == "claws":
        for dx in (-34, -22, 22, 34):
            d.polygon([(cx + dx - 4, 78), (cx + dx, 98), (cx + dx + 4, 78)], fill=rgba(c))
            d.line([(cx + dx, 78), (cx + dx, 100)], fill=rgba(light), width=2)
    elif slot == "fur":
        soft_ellipse(d, [cx - 44, 30, cx + 44, 96], rgba(c, 90))
        for _ in range(40):
            x = random.Random(key + str(_)).randint(cx - 40, cx + 40)
            y = random.Random(key + str(_ * 3)).randint(36, 92)
            d.line([(x, y), (x - 2, y - 8)], fill=rgba(light, 180), width=1)
        if "canopy" in key:
            soft_ellipse(d, [cx - 36, 8, cx + 36, 48], rgba(dark, 200))
            soft_ellipse(d, [cx - 24, 0, cx + 24, 36], rgba(c, 210))
    elif slot == "scales":
        for row, y in enumerate(range(34, 96, 12)):
            off = 6 if row % 2 else 0
            for x in range(cx - 36 + off, cx + 36, 12):
                soft_ellipse(d, [x, y, x + 10, y + 10], rgba(c, 170))
                soft_ellipse(d, [x + 2, y + 1, x + 6, y + 5], rgba(light, 120))
    elif slot == "feathers":
        for ang, dist in [(-40, 40), (-15, 46), (15, 46), (40, 40)]:
            rad = math.radians(ang - 90)
            x = cx + int(math.cos(rad) * dist)
            y = cy - 20 + int(math.sin(rad) * dist)
            soft_ellipse(d, [x - 8, y - 16, x + 8, y + 8], rgba(c, 210))
            soft_ellipse(d, [x - 4, y - 12, x + 3, y], rgba(light, 160))
    elif slot == "wings":
        soft_ellipse(d, [8, 28, 48, 88], rgba(c, 200))
        soft_ellipse(d, [80, 28, 120, 88], rgba(c, 200))
        soft_ellipse(d, [14, 36, 40, 70], rgba(light, 120))
        soft_ellipse(d, [88, 36, 114, 70], rgba(light, 120))
        d.arc([10, 30, 46, 86], 200, 340, fill=rgba(dark, 180), width=2)
        d.arc([82, 30, 118, 86], 200, 340, fill=rgba(dark, 180), width=2)
    elif slot == "armor":
        if "crystal" in key:
            for pts in [
                [(cx - 8, 24), (cx, 8), (cx + 8, 24), (cx, 36)],
                [(cx - 28, 48), (cx - 18, 28), (cx - 8, 48)],
                [(cx + 28, 48), (cx + 18, 28), (cx + 8, 48)],
            ]:
                d.polygon(pts, fill=rgba(c, 220))
        elif "alien" in key:
            for y in (36, 56, 76):
                d.rounded_rectangle([cx - 30, y, cx + 30, y + 10], radius=3, fill=rgba(c, 180))
        else:
            d.rounded_rectangle([cx - 34, 36, cx + 34, 88], radius=8, outline=rgba(c), width=6)
            soft_ellipse(d, [cx - 16, 44, cx + 16, 68], rgba(light, 100))
    elif slot == "eyes":
        draw_eyes(d, cx, 42, 12, 7, glow=True)
        soft_ellipse(d, [cx - 22, 34, cx - 6, 50], (254, 228, 64, 80))
        soft_ellipse(d, [cx + 6, 34, cx + 22, 50], (254, 228, 64, 80))
    elif slot == "fangs":
        d.polygon([(cx - 14, 54), (cx - 8, 74), (cx - 4, 54)], fill=(248, 249, 250, 240))
        d.polygon([(cx + 14, 54), (cx + 8, 74), (cx + 4, 54)], fill=(248, 249, 250, 240))
        soft_ellipse(d, [cx - 14, 52, cx - 6, 58], rgba(light, 180))
        soft_ellipse(d, [cx + 6, 52, cx + 14, 58], rgba(light, 180))
    elif slot == "body_size":
        soft_ellipse(d, [cx - 50, 28, cx + 50, 108], rgba(c if color else (200, 200, 200), 55))
        soft_ellipse(d, [cx - 40, 36, cx + 40, 100], (255, 255, 255, 35))
    elif slot == "skin_color":
        soft_ellipse(d, [cx - 42, 30, cx + 42, 100], rgba(c, 100))
        soft_ellipse(d, [cx - 28, 40, cx + 20, 80], rgba(light, 70))
    elif slot == "particles":
        rnd = random.Random(key)
        for i in range(18):
            ang = i * TAU / 18 + rnd.random()
            r = 42 + rnd.randint(-6, 10)
            x = cx + int(math.cos(ang) * r)
            y = cy + int(math.sin(ang) * r * 0.85)
            rad = 3 + (i % 3)
            soft_ellipse(d, [x - rad, y - rad, x + rad, y + rad], rgba(c, 200))
        if "burning" in key:
            soft_ellipse(d, [cx - 36, 24, cx + 36, 100], (255, 84, 0, 50))
    else:
        soft_ellipse(d, [cx - 20, cy - 20, cx + 20, cy + 20], rgba(c, 160))
    return img


TAU = math.pi * 2


def generate_mutations():
    data = json.loads((DATA / "mutations.json").read_text())["mutations"]
    for m in data:
        slot = m["slot"]
        key = m.get("sprite_key", m["id"])
        color = m.get("color")
        img = make_mutation(slot, key, color)
        out_dir = MUTATIONS / slot
        out_dir.mkdir(parents=True, exist_ok=True)
        img.save(out_dir / f"{key}.png")
        print("mutation", slot, key)


# ─── Arenas ──────────────────────────────────────────────────────────────────

def make_arena(region_id: str, w=720, h=1280) -> Image.Image:
    palettes = {
        "forest": ((18, 48, 32), (40, 110, 70), (20, 70, 45)),
        "desert": ((70, 42, 22), (196, 140, 80), (230, 180, 110)),
        "frozen_mountains": ((20, 36, 58), (120, 180, 210), (200, 230, 245)),
        "alien_lab": ((24, 10, 40), (70, 30, 110), (140, 80, 200)),
        "meteor_hive": ((30, 8, 28), (80, 20, 60), (160, 50, 90)),
    }
    deep, mid, hi = palettes.get(region_id, palettes["forest"])
    img = Image.new("RGBA", (w, h), deep + (255,))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        col = mix(deep, mid, t * 0.7)
        d.line([(0, y), (w - 1, y)], fill=col + (255,))
    # horizon band
    d.rectangle([0, int(h * 0.28), w, int(h * 0.52)], fill=mid + (40,))
    # ground platform
    d.ellipse([40, int(h * 0.55), w - 40, int(h * 0.78)], fill=hi + (60,))
    d.ellipse([80, int(h * 0.58), w - 80, int(h * 0.74)], fill=mid + (90,))
    # biome props
    rnd = random.Random(region_id)
    if region_id == "forest":
        for _ in range(10):
            x = rnd.randint(20, w - 40)
            y = rnd.randint(int(h * 0.18), int(h * 0.42))
            d.rectangle([x + 8, y + 30, x + 16, y + 70], fill=(70, 45, 25, 180))
            soft_ellipse(d, [x, y, x + 28, y + 40], (30, 90, 50, 180))
    elif region_id == "desert":
        for y in (int(h * 0.4), int(h * 0.48), int(h * 0.56)):
            d.arc([0, y - 40, w, y + 40], 200, 340, fill=(255, 220, 160, 90), width=4)
    elif region_id == "frozen_mountains":
        for pts in [
            [(40, 420), (160, 220), (280, 420)],
            [(220, 440), (360, 180), (520, 440)],
            [(480, 430), (600, 250), (700, 430)],
        ]:
            d.polygon(pts, fill=(180, 210, 230, 120))
    elif region_id in ("alien_lab", "meteor_hive"):
        for i in range(6):
            x = 80 + i * 100
            d.ellipse([x, 180, x + 60, 240], outline=(160, 80, 220, 100), width=3)
            d.line([(x + 30, 240), (x + 30, 420)], fill=(120, 60, 180, 80), width=2)
    mist = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    md.rectangle([0, int(h * 0.7), w, h], fill=(0, 0, 0, 70))
    mist = mist.filter(ImageFilter.GaussianBlur(24))
    return Image.alpha_composite(img, mist)


def generate_arenas():
    for rid in ["forest", "desert", "frozen_mountains", "alien_lab", "meteor_hive"]:
        make_arena(rid).save(ARENAS / f"{rid}.png")
        print("arena", rid)


# ─── FX ──────────────────────────────────────────────────────────────────────

def make_fx_slash() -> Image.Image:
    img = new_img(128)
    d = ImageDraw.Draw(img)
    d.line([(16, 96), (112, 24)], fill=(255, 240, 200, 240), width=10)
    d.line([(20, 104), (108, 32)], fill=(255, 180, 80, 180), width=5)
    d.line([(24, 88), (104, 28)], fill=(255, 255, 255, 200), width=3)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def make_fx_bolt() -> Image.Image:
    img = new_img(96)
    d = ImageDraw.Draw(img)
    soft_ellipse(d, [28, 28, 68, 68], (120, 200, 255, 220))
    soft_ellipse(d, [38, 38, 58, 58], (255, 255, 255, 240))
    for i in range(8):
        ang = i * TAU / 8
        d.line(
            [(48, 48), (48 + int(math.cos(ang) * 40), 48 + int(math.sin(ang) * 40))],
            fill=(160, 220, 255, 160),
            width=2,
        )
    return img


def make_fx_impact() -> Image.Image:
    img = new_img(128)
    d = ImageDraw.Draw(img)
    soft_ellipse(d, [24, 24, 104, 104], (255, 200, 80, 120))
    soft_ellipse(d, [44, 44, 84, 84], (255, 255, 255, 200))
    for i in range(10):
        ang = i * TAU / 10
        d.line(
            [
                (64 + int(math.cos(ang) * 20), 64 + int(math.sin(ang) * 20)),
                (64 + int(math.cos(ang) * 56), 64 + int(math.sin(ang) * 56)),
            ],
            fill=(255, 220, 120, 200),
            width=3,
        )
    return img


def make_fx_miss() -> Image.Image:
    img = new_img(96)
    d = ImageDraw.Draw(img)
    soft_ellipse(d, [16, 20, 80, 76], (200, 210, 220, 100))
    soft_ellipse(d, [28, 28, 68, 64], (230, 235, 240, 80))
    return img.filter(ImageFilter.GaussianBlur(1.2))


def generate_fx():
    make_fx_slash().save(FX / "slash.png")
    make_fx_bolt().save(FX / "bolt.png")
    make_fx_impact().save(FX / "impact.png")
    make_fx_miss().save(FX / "miss.png")
    print("fx done")


# ─── Tiles (depth pass) ──────────────────────────────────────────────────────

def noise_layer(size, seed, a, b, scale=0.14):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size), a + (255,))
    pix = img.load()
    for y in range(size):
        for x in range(size):
            n = math.sin(x * scale + seed) * math.cos(y * scale * 1.3) + rnd.random() * 0.35
            t = (n + 1.2) / 2.4
            pix[x, y] = mix(a, b, max(0.0, min(1.0, t))) + (255,)
    return img


def make_tile_grass(variant=0):
    img = noise_layer(TILE, 11 + variant * 7, (40, 98, 58), (62, 140, 82), 0.15)
    d = ImageDraw.Draw(img)
    rnd = random.Random(42 + variant)
    for _ in range(130):
        x = rnd.randint(2, TILE - 3)
        y = rnd.randint(10, TILE - 3)
        h = rnd.randint(6, 16)
        col = (90, 175, 105, 235) if rnd.random() > 0.35 else (30, 78, 48, 235)
        d.line([(x, y), (x - 1, y - h)], fill=col, width=1)
    # edge darker for autotile feel
    if variant > 0:
        d.rectangle([0, 0, TILE - 1, 4], fill=(24, 60, 34, 80))
        d.rectangle([0, TILE - 5, TILE - 1, TILE - 1], fill=(24, 60, 34, 80))
    return img


def make_tile_path(variant=0):
    img = noise_layer(TILE, 7 + variant, (128, 104, 72), (168, 138, 98), 0.18)
    d = ImageDraw.Draw(img)
    rnd = random.Random(9 + variant)
    for _ in range(34):
        x = rnd.randint(4, TILE - 14)
        y = rnd.randint(4, TILE - 14)
        d.ellipse([x, y, x + rnd.randint(5, 12), y + rnd.randint(3, 8)], fill=(95, 74, 50, 170))
    return img


def make_tile_tree(variant=0):
    img = new_img(TILE)
    d = ImageDraw.Draw(img)
    cx = TILE // 2 + (variant - 1) * 4
    d.rectangle([cx - 5, 58, cx + 5, 90], fill=(78, 48, 28, 255))
    canopies = [
        (cx - 28, 18, cx + 8, 58),
        (cx - 8, 8, cx + 30, 50),
        (cx - 18, 28, cx + 18, 62),
    ]
    cols = [(28, 92, 48, 240), (48, 140, 70, 230), (22, 78, 40, 200)]
    if variant == 1:
        cols = [(20, 70, 40, 240), (36, 110, 55, 230), (16, 60, 32, 200)]
    if variant == 2:
        cols = [(40, 100, 55, 240), (70, 150, 80, 220), (30, 85, 45, 200)]
    for box, col in zip(canopies, cols):
        soft_ellipse(d, list(box), col)
    soft_ellipse(d, [cx - 18, 82, cx + 18, 94], (20, 40, 24, 90))
    return img


def make_tile_dune(variant=0):
    img = noise_layer(TILE, 44 + variant, (196, 154, 96), (230, 190, 130), 0.12)
    d = ImageDraw.Draw(img)
    shift = variant * 8
    d.polygon(
        [(0, 70 - shift), (28, 34), (55, 48), (80, 22), (TILE, 40), (TILE, TILE), (0, TILE)],
        fill=(210, 168, 108, 255),
    )
    d.polygon(
        [(0, 80), (40, 55), (70, 62), (TILE, 48), (TILE, TILE), (0, TILE)],
        fill=(186, 140, 86, 245),
    )
    d.arc([6, 24, TILE - 6, 80], 200, 340, fill=(255, 230, 180, 150), width=3)
    return img


def make_tile_cliff(variant=0):
    img = noise_layer(TILE, 31 + variant, (52, 56, 64), (92, 98, 108), 0.16)
    d = ImageDraw.Draw(img)
    for i, y in enumerate(range(8, TILE, 16)):
        shade_v = 70 + (i % 3) * 18
        d.polygon(
            [(0, y + 12), (20 + (i % 2) * 10, y), (TILE, y + 8), (TILE, y + 18), (0, y + 20)],
            fill=(shade_v, shade_v + 4, shade_v + 10, 210),
        )
    d.polygon([(10, 28), (48, 10), (86, 26), (70, 36), (24, 38)], fill=(150, 156, 168, 230))
    d.line([(12, 30), (80, 22)], fill=(210, 214, 220, 150), width=2)
    d.rectangle([0, TILE - 12, TILE - 1, TILE - 1], fill=(28, 30, 36, 180))
    return img


def make_tile_empty():
    img = noise_layer(TILE, 21, (18, 42, 28), (32, 68, 42), 0.2)
    d = ImageDraw.Draw(img)
    rnd = random.Random(77)
    for _ in range(40):
        x = rnd.randint(0, TILE - 16)
        y = rnd.randint(0, TILE - 16)
        r = rnd.randint(7, 16)
        d.ellipse([x, y, x + r * 2, y + r * 2], fill=(24, 58, 36, 210) if rnd.random() > 0.4 else (14, 36, 24, 220))
    return img


def make_tile_wall():
    return make_tile_cliff(0)


def make_tile_rock():
    img = new_img(TILE)
    d = ImageDraw.Draw(img)
    soft_ellipse(d, [12, 58, 84, 88], (30, 40, 28, 120))
    d.polygon([(16, 70), (46, 12), (84, 70), (68, 84), (28, 84)], fill=(118, 122, 130, 255))
    d.polygon([(28, 60), (46, 18), (58, 60)], fill=(168, 172, 180, 255))
    return img


def make_tile_bridge():
    img = Image.new("RGBA", (TILE, TILE), (78, 50, 28, 255))
    d = ImageDraw.Draw(img)
    for y in range(6, TILE, 16):
        d.rounded_rectangle([5, y, TILE - 6, y + 12], radius=2, fill=(142, 96, 54, 255), outline=(60, 36, 18, 255))
    d.rectangle([0, 0, 7, TILE - 1], fill=(48, 28, 14, 255))
    d.rectangle([TILE - 8, 0, TILE - 1, TILE - 1], fill=(48, 28, 14, 255))
    return img


def make_anim_water(phase):
    img = Image.new("RGBA", (TILE, TILE), (22, 86, 122, 255))
    pix = img.load()
    for y in range(TILE):
        for x in range(TILE):
            w = math.sin((x + phase * 5) * 0.18 + y * 0.12) + math.cos((y - phase) * 0.15)
            if w > 0.55:
                pix[x, y] = (86, 170, 205, 255)
            elif w > 0.1:
                pix[x, y] = (42, 118, 158, 255)
            elif w < -0.55:
                pix[x, y] = (12, 54, 86, 255)
    return img


def make_anim_lava(phase):
    img = Image.new("RGBA", (TILE, TILE), (140, 32, 10, 255))
    pix = img.load()
    for y in range(TILE):
        for x in range(TILE):
            n = math.sin(x * 0.24 + phase * 0.9) * math.cos(y * 0.2 - phase * 0.6)
            if n > 0.45:
                pix[x, y] = (255, 180, 55, 255)
            elif n > 0.05:
                pix[x, y] = (230, 98, 24, 255)
            elif n < -0.5:
                pix[x, y] = (78, 14, 8, 255)
    return img


def make_anim_void(phase):
    img = Image.new("RGBA", (TILE, TILE), (10, 8, 20, 255))
    d = ImageDraw.Draw(img)
    cx = cy = TILE // 2
    for i, r in enumerate([40, 28, 16, 7]):
        col = (55 + i * 22, 35 + i * 12, 100 + i * 28, 170 - i * 22)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=2)
    return img


def make_camp():
    img = make_tile_path(0)
    d = ImageDraw.Draw(img)
    soft_ellipse(d, [18, 48, 78, 86], (70, 52, 34, 255))
    d.polygon([(48, 12), (26, 54), (70, 54)], fill=(235, 120, 42, 255))
    d.polygon([(48, 4), (34, 40), (62, 40)], fill=(255, 220, 100, 235))
    return img


def make_exit():
    img = make_tile_path(0)
    d = ImageDraw.Draw(img)
    d.ellipse([14, 14, 82, 82], outline=(90, 185, 240, 255), width=5)
    soft_ellipse(d, [26, 26, 70, 70], (28, 95, 155, 220))
    soft_ellipse(d, [38, 38, 58, 58], (190, 240, 255, 245))
    return img


def make_boss_tile():
    img = make_tile_path(0)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([16, 26, 80, 84], radius=6, fill=(120, 30, 40, 255), outline=(50, 10, 16, 255), width=2)
    d.polygon([(48, 4), (14, 34), (82, 34)], fill=(160, 42, 52, 255))
    return img


def make_obelisk_tile():
    base = make_tile_path(0)
    img = new_img(TILE)
    img.paste(base, (0, 0))
    d = ImageDraw.Draw(img)
    soft_ellipse(d, [20, 70, 76, 90], (40, 50, 40, 110))
    d.polygon([(48, 2), (22, 28), (74, 28)], fill=(165, 175, 190, 255))
    d.rectangle([26, 28, 70, 80], fill=(108, 118, 135, 255), outline=(60, 68, 80, 255), width=2)
    d.rectangle([40, 36, 56, 64], fill=(90, 230, 255, 220))
    return img


def generate_tiles():
    mapping = {
        "grass.png": make_tile_grass(0),
        "grass_1.png": make_tile_grass(1),
        "grass_2.png": make_tile_grass(2),
        "path.png": make_tile_path(0),
        "path_1.png": make_tile_path(1),
        "wall.png": make_tile_wall(),
        "cliff.png": make_tile_cliff(0),
        "cliff_1.png": make_tile_cliff(1),
        "rock.png": make_tile_rock(),
        "tree.png": make_tile_tree(0),
        "tree_1.png": make_tile_tree(1),
        "tree_2.png": make_tile_tree(2),
        "dune.png": make_tile_dune(0),
        "dune_1.png": make_tile_dune(1),
        "bridge.png": make_tile_bridge(),
        "camp.png": make_camp(),
        "exit.png": make_exit(),
        "boss.png": make_boss_tile(),
        "obelisk.png": make_obelisk_tile(),
        "empty.png": make_tile_empty(),
    }
    for i in range(4):
        mapping[f"water_{i}.png"] = make_anim_water(i)
        mapping[f"lava_{i}.png"] = make_anim_lava(i)
        mapping[f"void_{i}.png"] = make_anim_void(i)
    for name, im in mapping.items():
        im.save(TILES / name)
        print("tile", name, im.size)


# ─── Player walk sheet ───────────────────────────────────────────────────────

def make_player_sheet(frame=96) -> Image.Image:
    cols, rows = 4, 4
    img = Image.new("RGBA", (frame * cols, frame * rows), (0, 0, 0, 0))
    dirs = ["down", "left", "right", "up"]
    for r, direction in enumerate(dirs):
        for c in range(cols):
            cell = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
            d = ImageDraw.Draw(cell)
            cx, cy = frame // 2, frame // 2 + 6
            bob = (0, -2, 0, 2)[c]
            sway = (-3, 0, 3, 0)[c] if direction in ("left", "right") else 0
            # shadow
            soft_ellipse(d, [cx - 16, cy + 28, cx + 16, cy + 38], (0, 0, 0, 60))
            # legs
            leg_gap = 2 + (2 if c % 2 else -2)
            d.rectangle([cx - 10, cy + 8 + bob, cx - 2, cy + 28 + bob + leg_gap], fill=(36, 40, 55, 255))
            d.rectangle([cx + 2, cy + 8 + bob, cx + 10, cy + 28 + bob - leg_gap], fill=(36, 40, 55, 255))
            # boots
            soft_ellipse(d, [cx - 12, cy + 24 + bob, cx - 1, cy + 32 + bob], (50, 35, 25, 255))
            soft_ellipse(d, [cx + 1, cy + 24 + bob, cx + 12, cy + 32 + bob], (50, 35, 25, 255))
            # torso
            d.rounded_rectangle([cx - 14 + sway // 2, cy - 12 + bob, cx + 14 + sway // 2, cy + 12 + bob], radius=4, fill=(45, 110, 120, 255))
            d.rounded_rectangle([cx - 12 + sway // 2, cy - 10 + bob, cx + 12 + sway // 2, cy], radius=3, fill=(70, 150, 155, 120))
            # head
            soft_ellipse(d, [cx - 12, cy - 32 + bob, cx + 12, cy - 8 + bob], (230, 186, 148, 255))
            # hair
            soft_ellipse(d, [cx - 13, cy - 36 + bob, cx + 13, cy - 18 + bob], (42, 28, 20, 255))
            if direction != "up":
                # eyes
                ex = 0 if direction == "down" else (-4 if direction == "left" else 4)
                soft_ellipse(d, [cx - 6 + ex, cy - 24 + bob, cx - 2 + ex, cy - 20 + bob], (20, 18, 22, 255))
                soft_ellipse(d, [cx + 2 + ex, cy - 24 + bob, cx + 6 + ex, cy - 20 + bob], (20, 18, 22, 255))
            # scarf accent
            soft_ellipse(d, [cx - 10, cy - 10 + bob, cx + 10, cy - 2 + bob], (220, 90, 60, 220))
            img.paste(cell, (c * frame, r * frame), cell)
    return img


def generate_player():
    sheet = make_player_sheet(96)
    sheet.save(PLAYER / "human_walk_x2.png")
    # also write 48px downsample for compatibility
    small = sheet.resize((192, 192), Image.Resampling.LANCZOS)
    small.save(PLAYER / "human_walk.png")
    print("player sheet", sheet.size)


def main():
    print("=== creatures ===")
    generate_creatures()
    print("=== mutations ===")
    generate_mutations()
    print("=== arenas ===")
    generate_arenas()
    print("=== fx ===")
    generate_fx()
    print("=== tiles ===")
    generate_tiles()
    print("=== player ===")
    generate_player()
    print("DONE")


if __name__ == "__main__":
    main()
