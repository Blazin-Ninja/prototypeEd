#!/usr/bin/env python3
"""More realistic grass, trees, and water tiles (256px)."""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

_REPO = Path(__file__).resolve().parents[1]
TILES = _REPO / "assets" / "tiles"
TILES.mkdir(parents=True, exist_ok=True)
SIZE = 256


def clamp(v: float) -> int:
    return max(0, min(255, int(round(v))))


def mix(a, b, t: float):
    t = max(0.0, min(1.0, t))
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(3))


def shade(c, amt: float):
    if amt >= 0:
        return mix(c, (255, 255, 255), amt)
    return mix(c, (8, 12, 8), -amt)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def fbm(x, y, seed, octaves=5):
    total = amp = norm = 0.0
    amp = 1.0
    freq = 1.0
    for o in range(octaves):
        n = (
            math.sin((x * freq + seed * 1.7 + o * 13.1) * 0.11)
            * math.cos((y * freq - seed * 0.9 + o * 7.3) * 0.13)
            + math.sin((x + y) * freq * 0.07 + seed) * 0.35
        )
        total += n * amp
        norm += amp
        amp *= 0.5
        freq *= 2.05
    return (total / max(norm, 1e-6) + 1.0) * 0.5


def finish(img: Image.Image) -> Image.Image:
    soft = img.filter(ImageFilter.GaussianBlur(0.65))
    out = Image.alpha_composite(soft, img)
    out = Image.blend(out, out.filter(ImageFilter.DETAIL), 0.5)
    out = ImageEnhance.Contrast(out).enhance(1.14)
    out = ImageEnhance.Color(out).enhance(1.12)
    out = ImageEnhance.Sharpness(out).enhance(1.3)
    return out


def soft_ellipse(img, box, col, blur=1.6):
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

def make_grass(variant: int = 0) -> Image.Image:
    """Soil bed + layered blades with lighting, thatch, and tiny flora."""
    soil_a, soil_b = (42, 62, 28), (68, 98, 48)
    blade_dark, blade_mid, blade_lit = (24, 78, 38), (48, 130, 62), (120, 190, 100)
    if variant == 1:
        soil_a, soil_b = (36, 70, 40), (60, 110, 58)
        blade_dark, blade_mid, blade_lit = (20, 70, 48), (40, 125, 75), (110, 195, 130)
    elif variant == 2:
        soil_a, soil_b = (50, 58, 30), (90, 110, 50)
        blade_dark, blade_mid, blade_lit = (40, 85, 35), (80, 145, 55), (160, 205, 110)
    elif variant == 3:
        soil_a, soil_b = (30, 55, 36), (55, 95, 60)
        blade_dark, blade_mid, blade_lit = (18, 60, 40), (36, 110, 70), (95, 170, 115)

    img = Image.new("RGBA", (SIZE, SIZE))
    pix = img.load()
    # soil / thatch bed with soft lighting
    for y in range(SIZE):
        for x in range(SIZE):
            n = fbm(x * 1.1, y * 1.1, 11 + variant * 17)
            n2 = fbm(x * 2.4, y * 2.4, 40 + variant)
            t = n * 0.65 + n2 * 0.35
            col = mix(soil_a, soil_b, t)
            # top-left light
            lit = 0.55 + 0.45 * ((SIZE - x) / SIZE * 0.4 + (SIZE - y) / SIZE * 0.6)
            col = mix(shade(col, -0.2), shade(col, 0.25), lit)
            pix[x, y] = rgba(col)

    d = ImageDraw.Draw(img)
    rnd = random.Random(100 + variant * 77)

    # thatch / dead grass underlayer
    for _ in range(180):
        x = rnd.randint(2, SIZE - 3)
        y = rnd.randint(20, SIZE - 2)
        h = rnd.randint(6, 14)
        lean = rnd.randint(-3, 3)
        d.line([(x, y), (x + lean, y - h)], fill=(90, 78, 40, 120), width=1)

    # primary blades — back row (darker, taller)
    for _ in range(380):
        x = rnd.randint(1, SIZE - 2)
        y = rnd.randint(24, SIZE - 1)
        h = rnd.randint(16, 36)
        lean = rnd.randint(-6, 6)
        # blade with midrib highlight
        d.line([(x, y), (x + lean, y - h)], fill=rgba(blade_dark, 235), width=2)
        d.line([(x, y), (x + lean // 2, y - int(h * 0.7))], fill=rgba(blade_mid, 160), width=1)

    # front blades (brighter)
    for _ in range(420):
        x = rnd.randint(1, SIZE - 2)
        y = rnd.randint(30, SIZE - 1)
        h = rnd.randint(10, 26)
        lean = rnd.randint(-5, 5)
        col = blade_lit if rnd.random() > 0.35 else blade_mid
        d.line([(x, y), (x + lean, y - h)], fill=rgba(col, 240), width=1)
        if rnd.random() > 0.82:
            # dew tip
            d.ellipse(
                [x + lean - 1, y - h - 2, x + lean + 2, y - h + 1],
                fill=(200, 230, 255, 150),
            )

    # clover clusters
    for _ in range(14):
        cx, cy = rnd.randint(16, SIZE - 20), rnd.randint(40, SIZE - 24)
        for _leaf in range(3):
            ang = _leaf * 2.1 + rnd.random()
            lx = cx + int(math.cos(ang) * 4)
            ly = cy + int(math.sin(ang) * 3)
            d.ellipse([lx - 3, ly - 2, lx + 3, ly + 2], fill=(50, 140, 70, 200))

    # wildflowers
    for _ in range(10):
        fx, fy = rnd.randint(14, SIZE - 16), rnd.randint(36, SIZE - 20)
        petal = (235, 200, 80, 210) if rnd.random() > 0.4 else (230, 130, 150, 200)
        for ox, oy in ((0, -2), (2, 0), (0, 2), (-2, 0)):
            d.ellipse([fx + ox, fy + oy, fx + ox + 3, fy + oy + 3], fill=petal)
        d.ellipse([fx, fy, fx + 2, fy + 2], fill=(255, 240, 160, 230))

    # soft contact shadow at tile bottom for depth
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for i in range(18):
        a = int(40 * (1 - i / 18))
        od.rectangle([0, SIZE - 18 + i, SIZE - 1, SIZE - 17 + i], fill=(20, 35, 18, a))
    img = Image.alpha_composite(img, overlay)
    return finish(img)


# ─── Trees ───────────────────────────────────────────────────────────────────

def make_tree(variant: int = 0) -> Image.Image:
    """Full tree kept inside the frame — top padding so canopy is never cropped."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rnd = random.Random(200 + variant * 33)
    cx = SIZE // 2 + (variant - 1) * 8

    palettes = [
        ((18, 70, 36), (40, 120, 58), (90, 170, 90), (70, 42, 24)),
        ((14, 60, 42), (34, 110, 70), (80, 165, 110), (60, 36, 20)),
        ((30, 85, 40), (70, 145, 65), (130, 190, 100), (85, 50, 28)),
        ((22, 75, 50), (55, 130, 75), (110, 180, 120), (75, 45, 26)),
    ]
    deep, mid, lit, bark = palettes[variant % 4]

    # Keep silhouette in ~y=28..248 so soft blur never clips the crown.
    top_pad = 28
    ground_y = 242

    img = soft_ellipse(img, [cx - 55, ground_y - 18, cx + 55, ground_y + 10], (12, 24, 14, 90), 4.0)

    trunk_pts = [
        (cx - 12, 150),
        (cx - 9, 78),
        (cx + 9, 78),
        (cx + 12, 150),
        (cx + 10, ground_y - 4),
        (cx - 10, ground_y - 4),
    ]
    img = soft_poly(img, trunk_pts, rgba(bark), 1.0)
    img = soft_poly(
        img,
        [(cx - 5, 85), (cx - 1, 85), (cx + 2, ground_y - 20), (cx - 6, ground_y - 20)],
        rgba(shade(bark, 0.25), 130),
        1.2,
    )
    d = ImageDraw.Draw(img)
    for y in range(90, ground_y - 15, 14):
        wobble = rnd.randint(-2, 2)
        d.arc([cx - 11 + wobble, y, cx + 11 + wobble, y + 14], 200, 340, fill=(40, 24, 12, 140), width=2)
        px = cx + rnd.randint(-6, 6)
        d.ellipse([px, y + 3, px + 2, y + 6], fill=(30, 18, 10, 100))

    img = soft_poly(
        img,
        [(cx - 10, ground_y - 28), (cx - 28, ground_y), (cx - 4, ground_y - 4),
         (cx + 4, ground_y - 4), (cx + 28, ground_y), (cx + 10, ground_y - 28)],
        rgba(shade(bark, -0.1), 210),
        1.0,
    )

    # Compact canopy centered lower so crown stays below top_pad.
    canopy_cy = 95
    clusters = []
    for i in range(14):
        ang = i * (math.pi * 2 / 14) + rnd.random() * 0.35
        dist = 18 + rnd.randint(0, 34)
        bx = cx + int(math.cos(ang) * dist * 0.9)
        by = canopy_cy + int(math.sin(ang) * dist * 0.5)
        r = 28 + rnd.randint(0, 18)
        col = deep if i % 3 == 0 else (mid if i % 3 == 1 else lit)
        clusters.append((bx, by, r, col))
    clusters += [
        (cx - 6, canopy_cy - 8, 48, mid),
        (cx + 10, canopy_cy - 4, 44, lit),
        (cx, canopy_cy - 18, 40, deep),
        (cx - 18, canopy_cy + 12, 36, mid),
        (cx + 20, canopy_cy + 14, 34, deep),
    ]
    for bx, by, r, col in clusters:
        # Clamp vertically into safe frame
        by = max(top_pad + r // 2, min(by, 150))
        img = soft_ellipse(img, [bx - r, by - r, bx + r, by + r], rgba(col, 235), 2.0)
        img = soft_ellipse(
            img,
            [bx - int(r * 0.65), by + int(r * 0.1), bx + int(r * 0.65), by + int(r * 0.85)],
            rgba(shade(col, -0.35), 65),
            2.5,
        )
        img = soft_ellipse(
            img,
            [bx - int(r * 0.4), by - int(r * 0.7), bx + int(r * 0.12), by - int(r * 0.05)],
            rgba(shade(col, 0.35), 85),
            2.0,
        )

    d = ImageDraw.Draw(img)
    pix = img.load()
    for _ in range(70):
        x = rnd.randint(cx - 70, cx + 70)
        y = rnd.randint(top_pad + 4, 145)
        if x < 2 or y < 2 or x >= SIZE - 4 or y >= SIZE - 4:
            continue
        if pix[x, y][3] < 40:
            continue
        col = lit if rnd.random() > 0.4 else mid
        d.ellipse([x, y, x + rnd.randint(3, 6), y + rnd.randint(2, 4)], fill=rgba(col, 185))

    d.line([(cx + 14, 110), (cx + 40, 130)], fill=rgba(bark, 170), width=2)
    img = soft_ellipse(img, [cx + 28, 118, cx + 54, 146], rgba(mid, 195), 1.5)
    return finish(img)


# ─── Water ───────────────────────────────────────────────────────────────────

def make_water(phase: int = 0) -> Image.Image:
    """Seamless looping water — no borders/vignettes so ponds don't look square."""
    deep = (10, 52, 82)
    mid = (28, 112, 150)
    shallow = (78, 180, 210)
    img = Image.new("RGBA", (SIZE, SIZE))
    pix = img.load()
    # Periods that wrap exactly at SIZE for seamless tiling.
    two_pi = math.pi * 2.0
    phase_shift = phase * 0.55

    for y in range(SIZE):
        for x in range(SIZE):
            u = x / SIZE
            v = y / SIZE
            # seamless waves (integer frequencies)
            w1 = math.sin(two_pi * (2 * u + 1 * v) + phase_shift)
            w2 = math.cos(two_pi * (1 * u - 2 * v) + phase_shift * 1.3)
            w3 = math.sin(two_pi * (3 * u + 2 * v) + phase_shift * 0.7)
            # seamless value noise via wrapped sines
            n = (
                math.sin(two_pi * (3 * u + phase * 0.1)) * math.cos(two_pi * (2 * v + phase * 0.07))
                + 0.5 * math.sin(two_pi * (5 * u - 3 * v) + phase_shift)
            )
            caustic = (n + 1.5) / 3.0
            wave = w1 * 0.4 + w2 * 0.3 + w3 * 0.2 + (caustic - 0.5) * 0.35

            # gentle overall depth — no corner bias (that reads as squares)
            depth = 0.45 + 0.12 * math.sin(two_pi * (u + v) + phase_shift * 0.2)
            base = mix(deep, mid, depth)
            if wave > 0.45:
                col = mix(base, shallow, min(1.0, (wave - 0.45) * 1.6))
            elif wave < -0.4:
                col = mix(base, shade(deep, -0.12), min(1.0, (-wave - 0.4) * 1.4))
            else:
                col = mix(base, shallow, 0.12 + wave * 0.15)
            if wave > 0.72 and caustic > 0.55:
                col = mix(col, (245, 252, 255), 0.28)
            pix[x, y] = rgba(col)

    # Soft highlight ribbons that also wrap (drawn via pixels, not hard arcs)
    for y in range(SIZE):
        for x in range(SIZE):
            u = x / SIZE
            v = y / SIZE
            ribbon = math.sin(two_pi * (1 * u + 3 * v) + phase_shift * 1.1)
            if ribbon > 0.88:
                r, g, b, a = pix[x, y]
                col = mix((r, g, b), (230, 245, 255), 0.22)
                pix[x, y] = rgba(col, a)

    # Light blur only — avoid DETAIL/sharpen that exaggerates tile edges
    soft = img.filter(ImageFilter.GaussianBlur(0.8))
    out = Image.alpha_composite(soft, img)
    out = ImageEnhance.Color(out).enhance(1.06)
    return out


def main():
    for i in range(4):
        name = "tree.png" if i == 0 else f"tree_{i}.png"
        make_tree(i).save(TILES / name)
        print("tree", name)
    for i in range(4):
        name = f"water_{i}.png"
        make_water(i).save(TILES / name)
        print("water", name)
    print("DONE")


if __name__ == "__main__":
    main()
