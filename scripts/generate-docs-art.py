#!/usr/bin/env python3
"""Generate original EbonBuilds docs artwork (no Blizzard IP)."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"

CHARCOAL = (20, 20, 24)
SLATE = (28, 30, 36)
DEEP = (14, 16, 20)
GOLD = (201, 162, 39)
GOLD_LIGHT = (212, 175, 55)
AMBER = (230, 196, 83)
FROST = (92, 196, 164)
FROST_DIM = (58, 120, 104)
PARCHMENT = (212, 196, 168)


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def blend(c1: tuple[int, ...], c2: tuple[int, ...], t: float) -> tuple[int, int, int]:
    return (lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t))


def make_hero_bg(width: int = 1920, height: int = 600) -> Image.Image:
    img = Image.new("RGB", (width, height), CHARCOAL)
    px = img.load()
    rng = random.Random(42)

    for y in range(height):
        t = y / (height - 1)
        base = blend(DEEP, SLATE, t * 0.7)
        for x in range(width):
            nx = x / width
            vignette = 1.0 - 0.35 * ((nx - 0.5) ** 2 + (t - 0.45) ** 2) * 3.2
            grain = (rng.random() - 0.5) * 6
            r = max(0, min(255, int(base[0] * vignette + grain)))
            g = max(0, min(255, int(base[1] * vignette + grain)))
            b = max(0, min(255, int(base[2] * vignette + grain)))
            px[x, y] = (r, g, b)

    draw = ImageDraw.Draw(img)
    cx, cy = int(width * 0.18), height // 2

    for radius, color, width_px in [
        (140, FROST_DIM, 2),
        (115, FROST, 1),
        (90, (GOLD[0] // 2, GOLD[1] // 2, GOLD[2] // 2), 1),
    ]:
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=color, width=width_px)

    for i in range(12):
        angle = math.radians(i * 30)
        x1 = cx + math.cos(angle) * 125
        y1 = cy + math.sin(angle) * 125
        x2 = cx + math.cos(angle) * 138
        y2 = cy + math.sin(angle) * 138
        draw.line((x1, y1, x2, y2), fill=FROST_DIM, width=2)

    for r, w in [(55, 3), (38, 2), (22, 2)]:
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=GOLD, width=w)

    draw.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), fill=AMBER)

    draw.rectangle((0, 0, width, 4), fill=GOLD)
    draw.rectangle((0, height - 4, width, height), fill=GOLD)
    draw.rectangle((0, 0, 3, height), fill=blend(GOLD, CHARCOAL, 0.5))
    draw.rectangle((width - 3, 0, width, height), fill=blend(GOLD, CHARCOAL, 0.5))

    margin = 24
    draw.rectangle(
        (margin, margin, width - margin, height - margin),
        outline=blend(GOLD, SLATE, 0.6),
        width=1,
    )

    corner = 36
    for ox, oy in [
        (margin, margin),
        (width - margin - corner, margin),
        (margin, height - margin - corner),
        (width - margin - corner, height - margin - corner),
    ]:
        draw.line((ox, oy + corner, ox, oy, ox + corner, oy), fill=GOLD_LIGHT, width=2)

    return img.filter(ImageFilter.GaussianBlur(radius=0.3))


def make_texture_tile(size: int = 256) -> Image.Image:
    img = Image.new("RGB", (size, size), SLATE)
    draw = ImageDraw.Draw(img)
    rng = random.Random(7)
    for _ in range(800):
        x, y = rng.randint(0, size - 1), rng.randint(0, size - 1)
        draw.point((x, y), fill=blend(SLATE, CHARCOAL, rng.random() * 0.3))
    for y in range(0, size, 32):
        draw.line((0, y, size, y), fill=blend(SLATE, DEEP, 0.15), width=1)
    return img


def make_favicon(size: int = 64) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2
    draw.ellipse((2, 2, size - 2, size - 2), fill=CHARCOAL)
    draw.ellipse((2, 2, size - 2, size - 2), outline=GOLD, width=2)
    for r, w in [(26, 3), (18, 2), (10, 2)]:
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=GOLD, width=w)
    draw.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill=AMBER)
    return img


def draw_icon_autopilot(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    r = (x1 - x0) // 3
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=GOLD_LIGHT, width=3)
    draw.polygon([(cx, cy - r + 6), (cx + 8, cy + 4), (cx, cy + 2), (cx - 8, cy + 4)], fill=FROST)


def draw_icon_builds(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    pad = w // 6
    draw.rectangle((x0 + pad, y0 + pad, x1 - pad, y1 - pad), outline=GOLD_LIGHT, width=3)
    draw.line((x0 + pad, y0 + pad + h // 3, x1 - pad, y0 + pad + h // 3), fill=PARCHMENT, width=2)
    draw.line((x0 + pad, y0 + pad + 2 * h // 3, x1 - pad, y0 + pad + 2 * h // 3), fill=PARCHMENT, width=2)


def draw_icon_affixes(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    for angle in [0, 120, 240]:
        a = math.radians(angle - 90)
        x = cx + math.cos(a) * 18
        y = cy + math.sin(a) * 18
        draw.ellipse((x - 10, y - 10, x + 10, y + 10), outline=GOLD_LIGHT, width=2)
        draw.line((cx, cy, x, y), fill=FROST_DIM, width=2)


def draw_icon_tome(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    w = x1 - x0
    draw.polygon(
        [
            (x0 + w // 4, y0 + 4),
            (x1 - w // 6, y0 + 4),
            (x1 - w // 6, y1 - 4),
            (x0 + w // 4, y1 - 4),
        ],
        outline=GOLD_LIGHT,
        width=3,
    )
    draw.line((x0 + w // 3, y0 + 14, x1 - w // 5, y0 + 14), fill=PARCHMENT, width=2)
    draw.line((x0 + w // 3, y0 + 24, x1 - w // 5, y0 + 24), fill=PARCHMENT, width=2)
    draw.line((x0 + w // 3, y0 + 34, x1 - w // 3, y0 + 34), fill=PARCHMENT, width=2)


def make_icon(name: str, drawer) -> None:
    size = 96
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    drawer(draw, (8, 8, size - 8, size - 8))
    path = ASSETS / "icons" / f"{name}.png"
    img.save(path, optimize=True)


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "icons").mkdir(exist_ok=True)
    make_hero_bg().save(ASSETS / "hero-bg.png", optimize=True, quality=88)
    make_texture_tile().save(ASSETS / "texture-slate.png", optimize=True)
    make_favicon().save(ASSETS / "favicon.png", optimize=True)
    make_icon("autopilot", draw_icon_autopilot)
    make_icon("builds", draw_icon_builds)
    make_icon("affixes", draw_icon_affixes)
    make_icon("tome", draw_icon_tome)


if __name__ == "__main__":
    main()
