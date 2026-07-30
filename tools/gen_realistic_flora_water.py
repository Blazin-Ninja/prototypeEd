#!/usr/bin/env python3
"""More realistic grass, trees, and water tiles (256px)."""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

TILES = Path("/workspace/assets/tiles")
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
    """Bark trunk + layered canopy clusters with leaf flecks and ground shadow."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rnd = random.Random(200 + variant * 33)
    cx = SIZE // 2 + (variant - 1) * 12

    palettes = [
        ((18, 70, 36), (40, 120, 58), (90, 170, 90), (70, 42, 24)),
        ((14, 60, 42), (34, 110, 70), (80, 165, 110), (60, 36, 20)),
        ((30, 85, 40), (70, 145, 65), (130, 190, 100), (85, 50, 28)),
        ((22, 75, 50), (55, 130, 75), (110, 180, 120), (75, 45, 26)),
    ]
    deep, mid, lit, bark = palettes[variant % 4]

    # ground shadow first
    img = soft_ellipse(img, [cx - 70, 205, cx + 70, 248], (12, 24, 14, 95), 5.0)

    # trunk — tapered with bark ridges
    trunk_pts = [
        (cx - 16, 155),
        (cx - 11, 70),
        (cx + 11, 70),
        (cx + 16, 155),
        (cx + 12, 235),
        (cx - 12, 235),
    ]
    img = soft_poly(img, trunk_pts, rgba(bark), 1.1)
    # trunk lighting
    img = soft_poly(
        img,
        [(cx - 6, 80), (cx - 2, 80), (cx + 2, 220), (cx - 8, 220)],
        rgba(shade(bark, 0.25), 140),
        1.5,
    )
    d = ImageDraw.Draw(img)
    for y in range(85, 230, 14):
        wobble = rnd.randint(-2, 2)
        d.arc([cx - 14 + wobble, y, cx + 14 + wobble, y + 16], 200, 340, fill=(40, 24, 12, 150), width=2)
        # bark pores
        px = cx + rnd.randint(-8, 8)
        d.ellipse([px, y + 4, px + 3, y + 7], fill=(30, 18, 10, 100))

    # root flare
    img = soft_poly(
        img,
        [(cx - 14, 210), (cx - 36, 240), (cx - 8, 235), (cx + 8, 235), (cx + 36, 240), (cx + 14, 210)],
        rgba(shade(bark, -0.1), 220),
        1.2,
    )

    # canopy clusters — many overlapping blobs for organic mass
    clusters = []
    for i in range(16):
        ang = i * (math.pi * 2 / 16) + rnd.random() * 0.4
        dist = 28 + rnd.randint(0, 48)
        bx = cx + int(math.cos(ang) * dist * 0.85)
        by = 70 + int(math.sin(ang) * dist * 0.55) - 20
        r = 38 + rnd.randint(0, 28)
        col = deep if i % 3 == 0 else (mid if i % 3 == 1 else lit)
        clusters.append((bx, by, r, col))
    # center mass
    clusters += [
        (cx - 10, 55, 70, mid),
        (cx + 15, 50, 65, lit),
        (cx, 35, 55, deep),
        (cx - 25, 80, 50, mid),
        (cx + 30, 85, 48, deep),
    ]
    for bx, by, r, col in clusters:
        img = soft_ellipse(img, [bx - r, by - r, bx + r, by + r], rgba(col, 235), 2.4)
        # underside AO on each cluster
        img = soft_ellipse(
            img,
            [bx - int(r * 0.7), by + int(r * 0.15), bx + int(r * 0.7), by + int(r * 0.95)],
            rgba(shade(col, -0.35), 70),
            3.0,
        )
        # highlight cap
        img = soft_ellipse(
            img,
            [bx - int(r * 0.45), by - int(r * 0.75), bx + int(r * 0.15), by - int(r * 0.1)],
            rgba(shade(col, 0.35), 90),
            2.5,
        )

    # individual leaf flecks / sun spots
    d = ImageDraw.Draw(img)
    pix = img.load()
    for _ in range(90):
        x = rnd.randint(cx - 95, cx + 95)
        y = rnd.randint(10, 140)
        if x < 0 or y < 0 or x >= SIZE - 4 or y >= SIZE - 4:
            continue
        if pix[x, y][3] < 40:
            continue
        col = lit if rnd.random() > 0.4 else mid
        d.ellipse([x, y, x + rnd.randint(3, 7), y + rnd.randint(2, 5)], fill=rgba(col, 190))

    # hanging branch hint
    d.line([(cx + 20, 100), (cx + 55, 130)], fill=rgba(bark, 180), width=3)
    img = soft_ellipse(img, [cx + 40, 115, cx + 75, 150], rgba(mid, 200), 1.8)

    return finish(img)


# ─── Water ───────────────────────────────────────────────────────────────────

def make_water(phase: int = 0) -> Image.Image:
    """Depth-graded water with caustics, foam crests, and soft reflections."""
    deep = (8, 42, 72)
    mid = (22, 100, 140)
    shallow = (70, 175, 205)
    foam = (210, 240, 250)
    img = Image.new("RGBA", (SIZE, SIZE))
    pix = img.load()

    for y in range(SIZE):
        for x in range(SIZE):
            # depth gradient (deeper toward bottom-right for variety)
            depth = 0.35 + 0.4 * (y / SIZE) + 0.15 * (x / SIZE)
            # multi-wave field
            w1 = math.sin((x + phase * 9) * 0.055 + y * 0.04)
            w2 = math.cos((y - phase * 4) * 0.07 + x * 0.03)
            w3 = math.sin((x * 0.12 + y * 0.09) + phase * 0.8)
            caustic = fbm(x * 1.6 + phase * 3, y * 1.6, 90 + phase)
            wave = w1 * 0.45 + w2 * 0.3 + w3 * 0.15 + (caustic - 0.5) * 0.5

            base = mix(deep, mid, depth)
            if wave > 0.55:
                col = mix(base, shallow, min(1.0, (wave - 0.55) * 2.2))
            elif wave < -0.45:
                col = mix(base, shade(deep, -0.15), min(1.0, (-wave - 0.45) * 1.8))
            else:
                col = mix(base, shallow, 0.15 + wave * 0.2)

            # specular glitter on wave peaks
            if wave > 0.75 and caustic > 0.6:
                col = mix(col, (255, 255, 255), 0.45)
            pix[x, y] = rgba(col)

    d = ImageDraw.Draw(img)
    # foam crest arcs (animated by phase)
    for i in range(4):
        yy = 45 + i * 48 + (phase % 4) * 5
        alpha = 130 - i * 15
        d.arc([12, yy - 28, SIZE - 12, yy + 36], 200, 340, fill=(*foam, alpha), width=3)
        d.arc([30, yy - 10, SIZE - 30, yy + 40], 210, 330, fill=(255, 255, 255, alpha // 2), width=2)

    # soft shoreline foam flecks
    rnd = random.Random(50 + phase)
    for _ in range(40):
        x = rnd.randint(8, SIZE - 10)
        y = rnd.randint(8, SIZE - 10)
        if rnd.random() > 0.5:
            d.ellipse([x, y, x + 5, y + 2], fill=(230, 245, 255, 100))

    # subsurface green tint patches (weeds / algae)
    for _ in range(6):
        x, y = rnd.randint(20, SIZE - 40), rnd.randint(40, SIZE - 40)
        img = soft_ellipse(img, [x, y, x + 36, y + 20], (30, 120, 90, 45), 4.0)

    # vignette depth
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=(6, 30, 50, 50), width=4)
    img = Image.alpha_composite(img, overlay)
    return finish(img)


def main():
    for i in range(4):
        name = "grass.png" if i == 0 else f"grass_{i}.png"
        make_grass(i).save(TILES / name)
        print("grass", name)
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
