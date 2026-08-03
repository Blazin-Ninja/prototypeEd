#!/usr/bin/env python3
"""Creature realism pass v3 — organic spline silhouettes (less circle/triangle look).

Resolutions: wild 416px, bosses 512px. Bodies use Catmull-Rom splines, tapered
limbs, curved ears/fins, and per-species accents instead of stacked ellipses.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

_REPO = Path(__file__).resolve().parents[1]
ROOT = _REPO / "assets"
DATA = _REPO / "data"
CREATURES = ROOT / "creatures"
BOSSES = ROOT / "bosses"
CREATURES.mkdir(parents=True, exist_ok=True)
BOSSES.mkdir(parents=True, exist_ok=True)

SIZE = 416
BOSS_SIZE = 512

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


def cubic_bezier(p0, p1, p2, p3, t: float):
    u = 1.0 - t
    return (
        u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
        u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
    )


def sample_bezier(p0, p1, p2, p3, steps: int = 18):
    return [cubic_bezier(p0, p1, p2, p3, i / steps) for i in range(steps + 1)]


def catmull_rom(p0, p1, p2, p3, t: float):
    t2 = t * t
    t3 = t2 * t
    return (
        0.5
        * (
            (2 * p1[0])
            + (-p0[0] + p2[0]) * t
            + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
            + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
        ),
        0.5
        * (
            (2 * p1[1])
            + (-p0[1] + p2[1]) * t
            + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
            + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
        ),
    )


def spline_closed(anchors, steps_per: int = 12):
    n = len(anchors)
    if n < 3:
        return list(anchors)
    pts: list = []
    for i in range(n):
        p0 = anchors[(i - 1) % n]
        p1 = anchors[i]
        p2 = anchors[(i + 1) % n]
        p3 = anchors[(i + 2) % n]
        for j in range(steps_per):
            pts.append(catmull_rom(p0, p1, p2, p3, j / steps_per))
    return pts


def wobble_points(pts, seed: int, amp: float = 2.0):
    rnd = random.Random(seed)
    return [(x + rnd.uniform(-amp, amp), y + rnd.uniform(-amp, amp)) for x, y in pts]


def soft_path_fill(img, pts, color, blur: float = 1.3):
    if len(pts) < 3:
        return img
    layer = new_img(img.size[0])
    d = ImageDraw.Draw(layer)
    d.polygon(pts, fill=color)
    if blur > 0:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img, layer)


def ribbon_along(centerline, half_widths):
    if len(centerline) < 2:
        return []
    left, right = [], []
    for i, (x, y) in enumerate(centerline):
        if i == 0:
            dx = centerline[1][0] - x
            dy = centerline[1][1] - y
        elif i == len(centerline) - 1:
            dx = x - centerline[i - 1][0]
            dy = y - centerline[i - 1][1]
        else:
            dx = centerline[i + 1][0] - centerline[i - 1][0]
            dy = centerline[i + 1][1] - centerline[i - 1][1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = half_widths[min(i, len(half_widths) - 1)]
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + list(reversed(right))


def organic_blob(img, anchors, color, seed: int = 1, blur: float = 1.5, wobble: float = 1.6):
    pts = wobble_points(spline_closed(anchors), seed, wobble)
    return soft_path_fill(img, pts, color, blur)


def organic_ribbon(img, centerline, width_start, width_end, color, seed: int = 1, blur: float = 1.1):
    n = len(centerline)
    if n < 2:
        return img
    ws = [width_start + (width_end - width_start) * (i / max(1, n - 1)) for i in range(n)]
    pts = wobble_points(ribbon_along(centerline, ws), seed, 0.8)
    return soft_path_fill(img, pts, color, blur)


def flame_tendrils(img, cx, cy, sc, accent, seed: int = 1):
    rnd = random.Random(seed)
    for i in range(4):
        ox = cx + rnd.randint(int(-20 * sc), int(40 * sc))
        oy = cy + rnd.randint(int(-30 * sc), int(10 * sc))
        tip = (ox + rnd.randint(int(15 * sc), int(45 * sc)), oy - rnd.randint(int(25 * sc), int(55 * sc)))
        base = (ox, oy)
        ctrl = ((base[0] + tip[0]) / 2 + rnd.uniform(-8 * sc, 8 * sc), base[1] - 12 * sc)
        centerline = sample_bezier(base, ctrl, ctrl, tip, 16)
        img = organic_ribbon(img, centerline, 10 * sc, 2 * sc, rgba(accent, 200), seed + i, 1.4)
        img = organic_ribbon(img, centerline, 6 * sc, 1 * sc, (255, 240, 160, 170), seed + 100 + i, 1.0)
    return img


def electric_arc(img, cx, cy, sc, accent, seed: int = 1):
    rnd = random.Random(seed)
    pts = [(cx, cy)]
    x, y = cx, cy
    for _ in range(5):
        x += rnd.randint(int(8 * sc), int(22 * sc))
        y += rnd.randint(int(-18 * sc), int(10 * sc))
        pts.append((x, y))
    for i in range(len(pts) - 1):
        mid = (
            (pts[i][0] + pts[i + 1][0]) / 2,
            (pts[i][1] + pts[i + 1][1]) / 2 + rnd.uniform(-6 * sc, 6 * sc),
        )
        seg = sample_bezier(pts[i], mid, mid, pts[i + 1], 8)
        img = organic_ribbon(img, seg, 5 * sc, 3 * sc, rgba(accent, 230), seed, 0.6)
    return img


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
            lit = 0.22 + strength * ndot - rim * 0.5
            # dual-lobe specular + fresnel rim light
            spec = (ndot ** 12) * 0.38 + (ndot ** 4) * 0.18
            fresnel = (rim ** 1.4) * 0.22
            col = mix(shade(base, -0.42), shade(base, 0.48), lit)
            col = mix(col, (255, 255, 255), min(0.62, spec))
            col = mix(col, (255, 230, 210), min(0.35, fresnel))
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
    for _ in range(int(s * 0.55)):
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


def subsurface_fringe(img: Image.Image, warm=(210, 90, 70), amount=0.22):
    """Warm rim scatter for skin-like realism along opaque edges."""
    s = img.size[0]
    pix = img.load()
    # copy alpha neighborhood check
    alpha = [[pix[x, y][3] for x in range(s)] for y in range(s)]
    for y in range(1, s - 1):
        for x in range(1, s - 1):
            a = alpha[y][x]
            if a < 30:
                continue
            edge = 0
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                if alpha[y + dy][x + dx] < 20:
                    edge += 1
            if edge == 0:
                continue
            r, g, b, aa = pix[x, y]
            t = min(0.55, amount * edge * 0.35)
            col = mix((r, g, b), warm, t)
            pix[x, y] = (col[0], col[1], col[2], aa)
    return img


def micro_ao(img: Image.Image, strength=0.18):
    """Darken concave/interior pixels slightly using local alpha density."""
    s = img.size[0]
    pix = img.load()
    alpha = [[pix[x, y][3] for x in range(s)] for y in range(s)]
    for y in range(2, s - 2):
        for x in range(2, s - 2):
            a = alpha[y][x]
            if a < 40:
                continue
            dens = 0
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    dens += 1 if alpha[y + dy][x + dx] > 40 else 0
            # dens high in interior; use inverse for crease near edge-inside
            if dens < 18 or dens > 24:
                continue
            r, g, b, aa = pix[x, y]
            col = shade((r, g, b), -strength * (1.0 - dens / 25.0))
            pix[x, y] = (col[0], col[1], col[2], aa)
    return img


def finish(img: Image.Image) -> Image.Image:
    # Soft silhouette fringe + material polish
    soft = img.filter(ImageFilter.GaussianBlur(0.85))
    img = Image.alpha_composite(soft, img)
    subsurface_fringe(img)
    micro_ao(img)
    rgb = img.convert("RGBA")
    detail = rgb.filter(ImageFilter.DETAIL)
    out = Image.blend(rgb, detail, 0.48)
    # gentle unsharp
    blur = out.filter(ImageFilter.GaussianBlur(1.1))
    # manual unsharp: out + (out-blur)*amount — via blend trick
    out = Image.blend(blur, out, 1.35) if False else out
    enhancer = ImageEnhance.Contrast(out)
    out = enhancer.enhance(1.18)
    enhancer = ImageEnhance.Color(out)
    out = enhancer.enhance(1.14)
    enhancer = ImageEnhance.Sharpness(out)
    out = enhancer.enhance(1.35)
    return out


def make_quad(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s)
    c = hex_rgb(base)
    dark, light = shade(c, -0.32), shade(c, 0.28)
    cx, cy = s // 2, int(s * 0.52)
    sc = s / 256.0
    el = elements[0] if elements else "normal"
    accent = ELEMENT_ACCENT.get(el, light)
    glow = el in ("electric", "light", "poison", "shadow", "fire")

    for ox in (-38, -14, 14, 38):
        bx = cx + int(ox * sc)
        leg = sample_bezier(
            (bx, cy + int(8 * sc)),
            (bx + int(4 * sc), cy + int(28 * sc)),
            (bx - int(2 * sc), cy + int(48 * sc)),
            (bx, cy + int(58 * sc)),
            12,
        )
        img = organic_ribbon(img, leg, 11 * sc, 7 * sc, rgba(dark), seed + ox, 1.2)

    if cid in ("pine_wolf", "crystal_wolf", "sand_raptor", "brush_rat", "wire_hound"):
        tail = sample_bezier(
            (cx - int(58 * sc), cy + int(6 * sc)),
            (cx - int(88 * sc), cy - int(10 * sc)),
            (cx - int(100 * sc), cy + int(18 * sc)),
            (cx - int(110 * sc), cy + int(2 * sc)),
            18,
        )
        img = organic_ribbon(img, tail, 16 * sc, 4 * sc, rgba(dark), seed + 7, 1.4)
    elif cid == "ember_pup":
        tail = sample_bezier(
            (cx - int(50 * sc), cy + int(4 * sc)),
            (cx - int(80 * sc), cy - int(28 * sc)),
            (cx - int(70 * sc), cy + int(12 * sc)),
            (cx - int(95 * sc), cy - int(5 * sc)),
            16,
        )
        img = organic_ribbon(img, tail, 14 * sc, 3 * sc, rgba(shade(c, 0.1)), seed + 3, 1.3)

    torso_anchors = [
        (cx - int(74 * sc), cy + int(42 * sc)),
        (cx - int(68 * sc), cy - int(10 * sc)),
        (cx - int(42 * sc), cy - int(32 * sc)),
        (cx + int(8 * sc), cy - int(36 * sc)),
        (cx + int(46 * sc), cy - int(22 * sc)),
        (cx + int(72 * sc), cy + int(8 * sc)),
        (cx + int(64 * sc), cy + int(46 * sc)),
        (cx + int(20 * sc), cy + int(52 * sc)),
        (cx - int(30 * sc), cy + int(50 * sc)),
    ]
    img = organic_blob(img, torso_anchors, rgba(c), seed, 1.6, 1.8)
    radial_shade(img, cx - 8 * sc, cy + 4 * sc, 68 * sc, 42 * sc, c, strength=0.62)
    img = soft_path_fill(
        img,
        spline_closed(
            [
                (cx - int(38 * sc), cy - int(6 * sc)),
                (cx - int(10 * sc), cy - int(18 * sc)),
                (cx + int(22 * sc), cy - int(8 * sc)),
                (cx + int(12 * sc), cy + int(22 * sc)),
                (cx - int(24 * sc), cy + int(18 * sc)),
            ]
        ),
        rgba(light, 75),
        3.2,
    )

    head_anchors = [
        (cx - int(50 * sc), cy - int(8 * sc)),
        (cx - int(46 * sc), cy - int(48 * sc)),
        (cx - int(22 * sc), cy - int(82 * sc)),
        (cx + int(18 * sc), cy - int(86 * sc)),
        (cx + int(44 * sc), cy - int(58 * sc)),
        (cx + int(48 * sc), cy - int(22 * sc)),
        (cx + int(32 * sc), cy - int(4 * sc)),
        (cx - int(10 * sc), cy + int(2 * sc)),
    ]
    img = organic_blob(img, head_anchors, rgba(c), seed + 11, 1.5, 1.5)
    radial_shade(img, cx - 6 * sc, cy - 48 * sc, 46 * sc, 38 * sc, c, strength=0.65)

    for side in (-1, 1):
        base = (cx + int(28 * sc * side), cy - int(62 * sc))
        tip = (cx + int(54 * sc * side), cy - int(108 * sc))
        inner = (cx + int(36 * sc * side), cy - int(76 * sc))
        outer = (cx + int(48 * sc * side), cy - int(104 * sc))
        ear = sample_bezier(base, (cx + int(38 * sc * side), cy - int(96 * sc)), outer, tip, 14)
        ear += sample_bezier(tip, (cx + int(40 * sc * side), cy - int(72 * sc)), inner, base, 14)
        img = soft_path_fill(img, wobble_points(ear, seed + side * 20, 1.0), rgba(dark), 1.0)
        inner_ear = sample_bezier(
            (cx + int(30 * sc * side), cy - int(68 * sc)),
            (cx + int(42 * sc * side), cy - int(94 * sc)),
            (cx + int(38 * sc * side), cy - int(78 * sc)),
            (cx + int(32 * sc * side), cy - int(72 * sc)),
            10,
        )
        img = soft_path_fill(img, inner_ear, rgba(shade(c, 0.12), 170), 0.8)

    img = draw_eyes(img, cx, cy - int(52 * sc), int(18 * sc), int(9 * sc), glow=glow, accent=accent)
    img = soft_path_fill(
        img,
        spline_closed(
            [
                (cx - int(18 * sc), cy - int(28 * sc)),
                (cx + int(24 * sc), cy - int(30 * sc)),
                (cx + int(28 * sc), cy - int(14 * sc)),
                (cx + int(8 * sc), cy - int(6 * sc)),
                (cx - int(12 * sc), cy - int(8 * sc)),
            ]
        ),
        rgba(shade(c, -0.12)),
        1.0,
    )
    d = ImageDraw.Draw(img)
    d.ellipse(
        [cx - int(5 * sc), cy - int(18 * sc), cx + int(10 * sc), cy - int(11 * sc)],
        fill=rgba(shade(c, -0.45)),
    )
    for side in (-1, 1):
        img = soft_path_fill(
            img,
            spline_closed(
                [
                    (cx + int(30 * sc * side), cy - int(42 * sc)),
                    (cx + int(48 * sc * side), cy - int(36 * sc)),
                    (cx + int(44 * sc * side), cy - int(22 * sc)),
                    (cx + int(28 * sc * side), cy - int(26 * sc)),
                ]
            ),
            rgba(accent, 100),
            2.2,
        )
    if "fire" in elements:
        img = flame_tendrils(img, cx + int(40 * sc), cy - int(8 * sc), sc, accent, seed)
    if "electric" in elements:
        img = electric_arc(img, cx + int(32 * sc), cy - int(58 * sc), sc, accent, seed)
    if cid == "thorn_boar":
        for i in range(6):
            bx = cx - int(30 * sc) + i * int(12 * sc)
            bristle = sample_bezier(
                (bx, cy - int(34 * sc)),
                (bx + int(4 * sc), cy - int(52 * sc)),
                (bx - int(2 * sc), cy - int(48 * sc)),
                (bx, cy - int(38 * sc)),
                8,
            )
            img = organic_ribbon(img, bristle, 5 * sc, 2 * sc, rgba(dark), seed + i, 0.7)
    if cid == "frost_hare":
        for side in (-1, 1):
            ear_line = sample_bezier(
                (cx + int(18 * sc * side), cy - int(58 * sc)),
                (cx + int(28 * sc * side), cy - int(110 * sc)),
                (cx + int(22 * sc * side), cy - int(118 * sc)),
                (cx + int(14 * sc * side), cy - int(70 * sc)),
                16,
            )
            img = organic_ribbon(img, ear_line, 9 * sc, 5 * sc, rgba(light), seed + side, 1.0)
    fur_noise(img, c, density=0.028, seed=seed)
    return finish(img)


def make_fish(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.74, 0.34, 0.06)
    c = hex_rgb(base)
    dark, light = shade(c, -0.28), shade(c, 0.32)
    cx, cy = int(s * 0.46), s // 2
    sc = s / 256.0
    body = spline_closed(
        [
            (cx - int(78 * sc), cy - int(6 * sc)),
            (cx - int(70 * sc), cy - int(38 * sc)),
            (cx - int(20 * sc), cy - int(44 * sc)),
            (cx + int(40 * sc), cy - int(28 * sc)),
            (cx + int(58 * sc), cy - int(4 * sc)),
            (cx + int(52 * sc), cy + int(28 * sc)),
            (cx + int(10 * sc), cy + int(42 * sc)),
            (cx - int(40 * sc), cy + int(36 * sc)),
            (cx - int(72 * sc), cy + int(14 * sc)),
        ]
    )
    img = soft_path_fill(img, wobble_points(body, seed, 1.4), rgba(c), 1.8)
    radial_shade(img, cx - 10 * sc, cy, 78 * sc, 40 * sc, c, light_dir=(-0.6, -0.3), strength=0.7)
    img = soft_path_fill(
        img,
        spline_closed(
            [
                (cx - int(48 * sc), cy - int(22 * sc)),
                (cx - int(10 * sc), cy - int(28 * sc)),
                (cx + int(8 * sc), cy - int(12 * sc)),
                (cx - int(18 * sc), cy - int(4 * sc)),
            ]
        ),
        rgba(light, 100),
        3.5,
    )
    tail_upper = sample_bezier(
        (cx + int(52 * sc), cy - int(8 * sc)),
        (cx + int(88 * sc), cy - int(38 * sc)),
        (cx + int(108 * sc), cy - int(18 * sc)),
        (cx + int(112 * sc), cy),
        16,
    )
    tail_lower = sample_bezier(
        (cx + int(112 * sc), cy),
        (cx + int(108 * sc), cy + int(18 * sc)),
        (cx + int(88 * sc), cy + int(38 * sc)),
        (cx + int(52 * sc), cy + int(8 * sc)),
        16,
    )
    img = soft_path_fill(img, tail_upper + list(reversed(tail_lower)), rgba(dark), 1.4)
    dorsal = sample_bezier(
        (cx - int(8 * sc), cy - int(34 * sc)),
        (cx + int(12 * sc), cy - int(62 * sc)),
        (cx + int(28 * sc), cy - int(70 * sc)),
        (cx + int(38 * sc), cy - int(30 * sc)),
        14,
    )
    img = organic_ribbon(img, dorsal, 14 * sc, 4 * sc, rgba(shade(c, 0.05)), seed, 1.2)
    el = elements[0] if elements else "water"
    accent = ELEMENT_ACCENT.get(el, light)
    img = draw_eyes(img, cx - int(36 * sc), cy - int(6 * sc), 0, int(11 * sc), glow=False, accent=accent)
    d = ImageDraw.Draw(img)
    d.ellipse(
        [cx - int(54 * sc), cy + int(4 * sc), cx - int(34 * sc), cy + int(14 * sc)],
        fill=(12, 24, 40, 200),
    )
    scale_flecks(img, accent, seed=seed)
    for i in range(7):
        row = sample_bezier(
            (cx - int(20 * sc) + int(i * 12 * sc), cy - int(8 * sc)),
            (cx - int(14 * sc) + int(i * 12 * sc), cy - int(14 * sc)),
            (cx - int(6 * sc) + int(i * 12 * sc), cy - int(10 * sc)),
            (cx - int(8 * sc) + int(i * 12 * sc), cy + int(4 * sc)),
            6,
        )
        img = organic_ribbon(img, row, 5 * sc, 3 * sc, rgba(light, 70), seed + i, 1.5)
    return finish(img)


def make_plant(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s)
    c = hex_rgb(base)
    dark, light = shade(c, -0.3), shade(c, 0.25)
    cx, cy = s // 2, int(s * 0.58)
    sc = s / 256.0
    pot = spline_closed(
        [
            (cx - int(52 * sc), cy + int(50 * sc)),
            (cx - int(48 * sc), cy - int(4 * sc)),
            (cx - int(28 * sc), cy - int(10 * sc)),
            (cx + int(28 * sc), cy - int(10 * sc)),
            (cx + int(48 * sc), cy - int(4 * sc)),
            (cx + int(52 * sc), cy + int(50 * sc)),
            (cx + int(20 * sc), cy + int(58 * sc)),
            (cx - int(20 * sc), cy + int(58 * sc)),
        ]
    )
    img = soft_path_fill(img, pot, rgba(dark), 1.8)
    radial_shade(img, cx, cy + 24 * sc, 52 * sc, 34 * sc, dark, strength=0.5)
    img = organic_blob(
        img,
        [
            (cx - int(40 * sc), cy + int(44 * sc)),
            (cx - int(36 * sc), cy + int(8 * sc)),
            (cx + int(36 * sc), cy + int(8 * sc)),
            (cx + int(40 * sc), cy + int(44 * sc)),
        ],
        rgba(c),
        seed,
        1.4,
        1.0,
    )
    stem = sample_bezier(
        (cx - int(6 * sc), cy + int(6 * sc)),
        (cx - int(4 * sc), cy - int(30 * sc)),
        (cx + int(4 * sc), cy - int(50 * sc)),
        (cx, cy - int(68 * sc)),
        18,
    )
    img = organic_ribbon(img, stem, 9 * sc, 6 * sc, rgba(shade(c, -0.1)), seed + 2, 1.0)
    for side, tilt in [(-1, -18), (1, 18)]:
        leaf = sample_bezier(
            (cx + int(4 * sc * side), cy - int(50 * sc)),
            (cx + int(58 * sc * side), cy - int(110 * sc)),
            (cx + int(72 * sc * side), cy - int(70 * sc)),
            (cx + int(20 * sc * side), cy - int(42 * sc)),
            20,
        )
        leaf += sample_bezier(
            (cx + int(20 * sc * side), cy - int(42 * sc)),
            (cx + int(48 * sc * side), cy - int(78 * sc)),
            (cx + int(36 * sc * side), cy - int(88 * sc)),
            (cx + int(6 * sc * side), cy - int(54 * sc)),
            16,
        )
        col = rgba(c if side < 0 else light)
        img = soft_path_fill(img, wobble_points(leaf, seed + tilt, 1.4), col, 2.0)
    crown = spline_closed(
        [
            (cx - int(30 * sc), cy - int(132 * sc)),
            (cx - int(8 * sc), cy - int(152 * sc)),
            (cx + int(8 * sc), cy - int(152 * sc)),
            (cx + int(30 * sc), cy - int(132 * sc)),
            (cx + int(16 * sc), cy - int(118 * sc)),
            (cx - int(16 * sc), cy - int(118 * sc)),
        ]
    )
    img = soft_path_fill(img, crown, rgba(shade(c, 0.12)), 2.0)
    radial_shade(img, cx - 20 * sc, cy - 80 * sc, 40 * sc, 40 * sc, c, strength=0.55)
    radial_shade(img, cx + 20 * sc, cy - 80 * sc, 40 * sc, 40 * sc, light, strength=0.55)
    el = elements[0] if elements else "nature"
    accent = ELEMENT_ACCENT.get(el, (230, 190, 90))
    img = draw_eyes(img, cx, cy - int(96 * sc), int(16 * sc), int(7 * sc), accent=accent)
    img = organic_blob(
        img,
        [
            (cx - int(12 * sc), cy - int(148 * sc)),
            (cx - int(8 * sc), cy - int(158 * sc)),
            (cx + int(8 * sc), cy - int(158 * sc)),
            (cx + int(12 * sc), cy - int(148 * sc)),
        ],
        (240, 200, 90, 230),
        seed + 5,
        1.2,
        0.8,
    )
    fur_noise(img, c, density=0.018, seed=seed)
    return finish(img)


def make_bird(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.78)
    c = hex_rgb(base)
    dark, light = shade(c, -0.25), shade(c, 0.3)
    cx, cy = s // 2, int(s * 0.5)
    sc = s / 256.0
    for side in (-1, 1):
        wing_outer = sample_bezier(
            (cx + int(8 * sc * side), cy - int(18 * sc)),
            (cx + int(90 * sc * side), cy - int(8 * sc)),
            (cx + int(118 * sc * side), cy + int(38 * sc)),
            (cx + int(24 * sc * side), cy + int(48 * sc)),
            22,
        )
        wing_inner = sample_bezier(
            (cx + int(24 * sc * side), cy + int(48 * sc)),
            (cx + int(70 * sc * side), cy + int(18 * sc)),
            (cx + int(50 * sc * side), cy - int(4 * sc)),
            (cx + int(12 * sc * side), cy - int(8 * sc)),
            18,
        )
        img = soft_path_fill(img, wing_outer + list(reversed(wing_inner)), rgba(dark, 235), 2.2)
        for i in range(4):
            feather = sample_bezier(
                (cx + int((20 + i * 18) * sc * side), cy + int((8 - i * 4) * sc)),
                (cx + int((50 + i * 16) * sc * side), cy + int((20 - i * 6) * sc)),
                (cx + int((70 + i * 10) * sc * side), cy + int((10 - i * 2) * sc)),
                (cx + int((40 + i * 14) * sc * side), cy + int((28 - i * 5) * sc)),
                10,
            )
            img = organic_ribbon(img, feather, 8 * sc, 2 * sc, rgba(light, 90), seed + i * side, 2.5)
    body = spline_closed(
        [
            (cx - int(40 * sc), cy + int(52 * sc)),
            (cx - int(44 * sc), cy - int(8 * sc)),
            (cx - int(18 * sc), cy - int(28 * sc)),
            (cx + int(18 * sc), cy - int(28 * sc)),
            (cx + int(44 * sc), cy - int(8 * sc)),
            (cx + int(40 * sc), cy + int(52 * sc)),
            (cx, cy + int(58 * sc)),
        ]
    )
    img = soft_path_fill(img, wobble_points(body, seed, 1.2), rgba(c), 1.8)
    radial_shade(img, cx, cy + 18 * sc, 44 * sc, 40 * sc, c, strength=0.6)
    head = organic_blob(
        img,
        [
            (cx - int(36 * sc), cy - int(6 * sc)),
            (cx - int(34 * sc), cy - int(52 * sc)),
            (cx - int(8 * sc), cy - int(78 * sc)),
            (cx + int(22 * sc), cy - int(72 * sc)),
            (cx + int(36 * sc), cy - int(38 * sc)),
            (cx + int(28 * sc), cy - int(8 * sc)),
        ],
        rgba(c),
        seed + 3,
        1.5,
        1.2,
    )
    img = head
    radial_shade(img, cx - 4 * sc, cy - 42 * sc, 38 * sc, 36 * sc, c, strength=0.65)
    beak = sample_bezier(
        (cx - int(4 * sc), cy - int(32 * sc)),
        (cx + int(18 * sc), cy - int(30 * sc)),
        (cx + int(38 * sc), cy - int(24 * sc)),
        (cx + int(4 * sc), cy - int(14 * sc)),
        12,
    )
    beak += sample_bezier(
        (cx + int(4 * sc), cy - int(14 * sc)),
        (cx + int(30 * sc), cy - int(18 * sc)),
        (cx + int(20 * sc), cy - int(22 * sc)),
        (cx - int(4 * sc), cy - int(24 * sc)),
        10,
    )
    img = soft_path_fill(img, beak, (240, 180, 60, 255), 0.8)
    el = elements[0] if elements else "wind"
    accent = ELEMENT_ACCENT.get(el, light)
    img = draw_eyes(img, cx - int(8 * sc), cy - int(48 * sc), int(14 * sc), int(7 * sc), accent=accent)
    crest = sample_bezier(
        (cx - int(10 * sc), cy - int(72 * sc)),
        (cx + int(2 * sc), cy - int(112 * sc)),
        (cx + int(14 * sc), cy - int(108 * sc)),
        (cx + int(20 * sc), cy - int(74 * sc)),
        14,
    )
    img = organic_ribbon(img, crest, 8 * sc, 3 * sc, rgba(accent, 230), seed + 9, 1.0)
    if cid == "spore_bat":
        for side in (-1, 1):
            mem = sample_bezier(
                (cx + int(30 * sc * side), cy - int(20 * sc)),
                (cx + int(70 * sc * side), cy - int(48 * sc)),
                (cx + int(50 * sc * side), cy - int(30 * sc)),
                (cx + int(36 * sc * side), cy - int(18 * sc)),
                12,
            )
            img = organic_ribbon(img, mem, 6 * sc, 2 * sc, rgba(accent, 160), seed + side, 1.2)
    fur_noise(img, c, density=0.024, seed=seed)
    return finish(img)


def make_bug(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s)
    c = hex_rgb(base)
    dark, light = shade(c, -0.28), shade(c, 0.22)
    cx, cy = s // 2, int(s * 0.5)
    sc = s / 256.0
    for ang in (-55, -25, 25, 55):
        rad = math.radians(ang)
        x2 = cx + int(math.cos(rad) * 92 * sc)
        y2 = cy + int(28 * sc + math.sin(rad) * 18 * sc)
        leg = sample_bezier(
            (cx, cy + int(10 * sc)),
            (cx + int(math.cos(rad) * 40 * sc), cy + int(18 * sc)),
            (x2 - int(6 * sc), y2 - int(8 * sc)),
            (x2, y2),
            14,
        )
        img = organic_ribbon(img, leg, 6 * sc, 3 * sc, rgba(dark), seed + ang, 0.7)
    segments = [
        (cx - int(58 * sc), cy + int(44 * sc), 56 * sc, 32 * sc, dark),
        (cx - int(40 * sc), cy + int(4 * sc), 40 * sc, 28 * sc, c),
        (cx - int(34 * sc), cy - int(36 * sc), 34 * sc, 26 * sc, shade(c, 0.05)),
    ]
    for i, (sx, sy, rx, ry, col) in enumerate(segments):
        seg = spline_closed(
            [
                (sx, sy),
                (sx + int(rx * 1.6), sy - int(ry * 0.4)),
                (sx + int(rx * 2.2), sy + int(ry * 0.2)),
                (sx + int(rx * 1.4), sy + int(ry * 1.2)),
                (sx - int(rx * 0.2), sy + int(ry * 1.0)),
            ]
        )
        img = soft_path_fill(img, wobble_points(seg, seed + i * 3, 1.2), rgba(col), 1.5)
        radial_shade(img, sx + rx, sy + ry * 0.4, rx, ry, col, strength=0.5)
    gloss = spline_closed(
        [
            (cx - int(22 * sc), cy - int(34 * sc)),
            (cx - int(6 * sc), cy - int(42 * sc)),
            (cx + int(10 * sc), cy - int(30 * sc)),
            (cx - int(4 * sc), cy - int(18 * sc)),
        ]
    )
    img = soft_path_fill(img, gloss, rgba(light, 110), 2.8)
    el = elements[0] if elements else "poison"
    accent = ELEMENT_ACCENT.get(el, light)
    glow = el in ("poison", "shadow", "electric")
    img = draw_eyes(img, cx, cy - int(24 * sc), int(14 * sc), int(8 * sc), glow=glow, accent=accent)
    for side in (-1, 1):
        mand = sample_bezier(
            (cx + int(20 * sc * side), cy - int(6 * sc)),
            (cx + int(32 * sc * side), cy + int(12 * sc)),
            (cx + int(10 * sc * side), cy + int(16 * sc)),
            (cx + int(4 * sc * side), cy - int(2 * sc)),
            10,
        )
        img = organic_ribbon(img, mand, 5 * sc, 2 * sc, rgba(dark), seed + side, 0.7)
    if cid == "cinder_scorp":
        tail = sample_bezier(
            (cx + int(48 * sc), cy + int(20 * sc)),
            (cx + int(78 * sc), cy - int(10 * sc)),
            (cx + int(98 * sc), cy - int(38 * sc)),
            (cx + int(108 * sc), cy - int(58 * sc)),
            18,
        )
        img = organic_ribbon(img, tail, 10 * sc, 3 * sc, rgba(dark), seed + 20, 1.0)
        img = organic_blob(
            img,
            [
                (cx + int(100 * sc), cy - int(64 * sc)),
                (cx + int(112 * sc), cy - int(72 * sc)),
                (cx + int(116 * sc), cy - int(58 * sc)),
                (cx + int(106 * sc), cy - int(52 * sc)),
            ],
            rgba(accent, 220),
            seed + 21,
            1.0,
            0.6,
        )
    scale_flecks(img, accent, seed=seed)
    return finish(img)


def make_serpent(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.84, 0.36, 0.06)
    c = hex_rgb(base)
    dark, light = shade(c, -0.32), shade(c, 0.24)
    cx = s // 2
    sc = s / 256.0
    coils = [
        sample_bezier(
            (cx - int(78 * sc), int(200 * sc)),
            (cx - int(20 * sc), int(230 * sc)),
            (cx + int(40 * sc), int(210 * sc)),
            (cx + int(70 * sc), int(170 * sc)),
            24,
        ),
        sample_bezier(
            (cx + int(70 * sc), int(170 * sc)),
            (cx + int(30 * sc), int(140 * sc)),
            (cx - int(30 * sc), int(150 * sc)),
            (cx - int(58 * sc), int(120 * sc)),
            24,
        ),
        sample_bezier(
            (cx - int(58 * sc), int(120 * sc)),
            (cx - int(10 * sc), int(100 * sc)),
            (cx + int(36 * sc), int(88 * sc)),
            (cx + int(28 * sc), int(58 * sc)),
            22,
        ),
    ]
    widths = [22 * sc, 18 * sc, 14 * sc]
    for i, coil in enumerate(coils):
        col = dark if i == 0 else (c if i == 1 else shade(c, 0.06))
        img = organic_ribbon(img, coil, widths[i], widths[i] * 0.65, rgba(col), seed + i, 1.6)
    neck = sample_bezier(
        (cx + int(28 * sc), int(58 * sc)),
        (cx + int(18 * sc), int(38 * sc)),
        (cx + int(8 * sc), int(22 * sc)),
        (cx + int(12 * sc), int(8 * sc)),
        18,
    )
    img = organic_ribbon(img, neck, 16 * sc, 12 * sc, rgba(c), seed + 4, 1.4)
    head = organic_blob(
        img,
        [
            (cx - int(38 * sc), int(48 * sc)),
            (cx - int(28 * sc), int(12 * sc)),
            (cx + int(8 * sc), int(4 * sc)),
            (cx + int(44 * sc), int(18 * sc)),
            (cx + int(48 * sc), int(52 * sc)),
            (cx + int(16 * sc), int(68 * sc)),
        ],
        rgba(c),
        seed + 5,
        1.6,
        1.4,
    )
    img = head
    radial_shade(img, cx + 2 * sc, 42 * sc, 46 * sc, 36 * sc, c, strength=0.7)
    img = soft_path_fill(
        img,
        spline_closed(
            [
                (cx - int(20 * sc), int(28 * sc)),
                (cx + int(8 * sc), int(18 * sc)),
                (cx + int(18 * sc), int(34 * sc)),
                (cx - int(4 * sc), int(44 * sc)),
            ]
        ),
        rgba(light, 90),
        2.5,
    )
    el = elements[0] if elements else "poison"
    accent = ELEMENT_ACCENT.get(el, dark)
    glow = el in ("poison", "shadow", "fire")
    img = draw_eyes(img, cx + int(4 * sc), int(40 * sc), int(16 * sc), int(9 * sc), glow=glow, accent=accent)
    fang = sample_bezier(
        (cx + int(18 * sc), int(58 * sc)),
        (cx + int(34 * sc), int(72 * sc)),
        (cx + int(28 * sc), int(78 * sc)),
        (cx + int(14 * sc), int(66 * sc)),
        8,
    )
    img = organic_ribbon(img, fang, 4 * sc, 1 * sc, (220, 60, 80, 230), seed + 6, 0.6)
    for y in (110, 140, 170, 200):
        mark = spline_closed(
            [
                (cx, int((y - 8) * sc)),
                (cx + int(14 * sc), int(y * sc)),
                (cx, int((y + 8) * sc)),
                (cx - int(14 * sc), int(y * sc)),
            ]
        )
        img = soft_path_fill(img, wobble_points(mark, seed + y, 0.6), rgba(accent, 150), 0.8)
    if cid in ("dread_basilisk", "basilisk"):
        hood = sample_bezier(
            (cx - int(48 * sc), int(36 * sc)),
            (cx - int(72 * sc), int(8 * sc)),
            (cx - int(20 * sc), int(2 * sc)),
            (cx + int(8 * sc), int(10 * sc)),
            16,
        )
        hood += sample_bezier(
            (cx + int(8 * sc), int(10 * sc)),
            (cx + int(52 * sc), int(4 * sc)),
            (cx + int(68 * sc), int(28 * sc)),
            (cx + int(44 * sc), int(40 * sc)),
            16,
        )
        img = soft_path_fill(img, hood, rgba(shade(c, -0.15), 200), 1.4)
    scale_flecks(img, accent, seed=seed)
    return finish(img)


def make_bulk(base, elements, boss=False, seed=1, cid="") -> Image.Image:
    s = BOSS_SIZE if boss else SIZE
    img = new_img(s)
    img = ground_shadow(img, s, 0.86, 0.38, 0.08)
    c = hex_rgb(base)
    dark, light = shade(c, -0.3), shade(c, 0.22)
    cx, cy = s // 2, int(s * 0.54)
    sc = s / 256.0
    for side in (-1, 1):
        leg = sample_bezier(
            (cx + int(44 * sc * side), cy + int(30 * sc)),
            (cx + int(58 * sc * side), cy + int(58 * sc)),
            (cx + int(48 * sc * side), cy + int(78 * sc)),
            (cx + int(38 * sc * side), cy + int(88 * sc)),
            14,
        )
        img = organic_ribbon(img, leg, 18 * sc, 12 * sc, rgba(dark), seed + side, 1.6)
    torso = spline_closed(
        [
            (cx - int(88 * sc), cy + int(48 * sc)),
            (cx - int(92 * sc), cy - int(18 * sc)),
            (cx - int(48 * sc), cy - int(44 * sc)),
            (cx + int(20 * sc), cy - int(46 * sc)),
            (cx + int(72 * sc), cy - int(20 * sc)),
            (cx + int(88 * sc), cy + int(28 * sc)),
            (cx + int(60 * sc), cy + int(52 * sc)),
            (cx - int(40 * sc), cy + int(54 * sc)),
        ]
    )
    img = soft_path_fill(img, wobble_points(torso, seed, 1.6), rgba(c), 2.0)
    radial_shade(img, cx - 10 * sc, cy + 4 * sc, 90 * sc, 50 * sc, c, strength=0.62)
    img = soft_path_fill(
        img,
        spline_closed(
            [
                (cx - int(52 * sc), cy - int(22 * sc)),
                (cx - int(12 * sc), cy - int(34 * sc)),
                (cx + int(28 * sc), cy - int(18 * sc)),
                (cx + int(8 * sc), cy + int(18 * sc)),
                (cx - int(28 * sc), cy + int(16 * sc)),
            ]
        ),
        rgba(light, 80),
        3.5,
    )
    for side in (-1, 1):
        arm = sample_bezier(
            (cx + int(70 * sc * side), cy - int(8 * sc)),
            (cx + int(108 * sc * side), cy + int(8 * sc)),
            (cx + int(112 * sc * side), cy + int(38 * sc)),
            (cx + int(78 * sc * side), cy + int(42 * sc)),
            16,
        )
        img = organic_ribbon(img, arm, 20 * sc, 12 * sc, rgba(dark), seed + side * 10, 1.6)
    head = organic_blob(
        img,
        [
            (cx - int(52 * sc), cy - int(18 * sc)),
            (cx - int(48 * sc), cy - int(72 * sc)),
            (cx - int(12 * sc), cy - int(102 * sc)),
            (cx + int(28 * sc), cy - int(96 * sc)),
            (cx + int(52 * sc), cy - int(58 * sc)),
            (cx + int(48 * sc), cy - int(20 * sc)),
        ],
        rgba(c),
        seed + 2,
        1.7,
        1.4,
    )
    img = head
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
        crown = sample_bezier(
            (cx - int(52 * sc), cy - int(88 * sc)),
            (cx - int(18 * sc), cy - int(148 * sc)),
            (cx + int(18 * sc), cy - int(148 * sc)),
            (cx + int(52 * sc), cy - int(88 * sc)),
            18,
        )
        img = organic_ribbon(img, crown, 16 * sc, 6 * sc, rgba(accent, 230), seed + 30, 1.2)
        img = organic_blob(
            img,
            [
                (cx - int(30 * sc), cy - int(158 * sc)),
                (cx - int(10 * sc), cy - int(172 * sc)),
                (cx + int(10 * sc), cy - int(172 * sc)),
                (cx + int(30 * sc), cy - int(158 * sc)),
            ],
            rgba(shade(accent, 0.2), 220),
            seed + 31,
            1.8,
            1.0,
        )
    if cid == "elder_treant":
        for i in range(5):
            bx = cx - int(60 * sc) + i * int(28 * sc)
            branch = sample_bezier(
                (bx, cy - int(40 * sc)),
                (bx + int(18 * sc), cy - int(78 * sc)),
                (bx - int(8 * sc), cy - int(92 * sc)),
                (bx + int(6 * sc), cy - int(118 * sc)),
                16,
            )
            img = organic_ribbon(img, branch, 10 * sc, 3 * sc, rgba(dark), seed + 40 + i, 1.0)
    if cid == "flask_slime":
        drip = sample_bezier(
            (cx - int(30 * sc), cy + int(48 * sc)),
            (cx - int(40 * sc), cy + int(72 * sc)),
            (cx - int(18 * sc), cy + int(78 * sc)),
            (cx - int(8 * sc), cy + int(58 * sc)),
            12,
        )
        img = organic_ribbon(img, drip, 14 * sc, 6 * sc, rgba(shade(c, 0.15), 200), seed + 50, 1.4)
    if cid == "glow_toad":
        for side in (-1, 1):
            spot = organic_blob(
                img,
                [
                    (cx + int(24 * sc * side), cy - int(48 * sc)),
                    (cx + int(34 * sc * side), cy - int(58 * sc)),
                    (cx + int(40 * sc * side), cy - int(46 * sc)),
                    (cx + int(30 * sc * side), cy - int(40 * sc)),
                ],
                rgba(accent, 180),
                seed + side,
                2.0,
                0.8,
            )
            img = spot
    fur_noise(img, c, density=0.02, seed=seed)
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
        img = fn(color, els, boss=boss, seed=1000 + i, cid=cid)
        img.save(CREATURES / f"{cid}.png")
        if boss:
            img.save(BOSSES / f"{cid}.png")
        print("creature", cid, img.size, shape)
    print("DONE", len(data))


if __name__ == "__main__":
    main()
