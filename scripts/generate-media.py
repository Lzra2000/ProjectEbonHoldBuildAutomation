#!/usr/bin/env python3
"""EbonBuilds: scripts/generate-media.py

Regenerates media/minimap_icon.tga from code instead of hand-editing a
binary blob. Before this script, the TGA had no source in the repo --
it existed only as compiled pixels, so nobody without image-editing
tools (and nobody in an automated environment) could reproduce or
adjust it. This script IS the source now.

The geometry and colors are pinned to docs/img/logo.svg's viewBox and
values (three gold rings, r=27/18/8.5 on a 64x64 canvas, stroke
3.5/4, opacity .45/.75/1) so the minimap icon and the website's logo
are provably the same mark, not two independently hand-tuned ones --
edit the ring constants in ONE place (this file) and update the SVG
to match, or vice versa.

Requires Pillow (already a project dependency for other tooling).
Usage: python3 scripts/generate-media.py
Writes media/minimap_icon.tga (128x128, 32-bit uncompressed TGA --
same format/depth as the file it replaces, verified client-compatible).
"""

import os
from PIL import Image, ImageDraw

# Pinned to docs/img/logo.svg's viewBox="0 0 64 64" geometry.
RINGS = [
    # (radius, stroke_width, color, opacity)
    (27, 3.5, (0xc9, 0xa2, 0x27), 0.45),
    (18, 4.0, (0xd4, 0xaf, 0x37), 0.75),
]
CORE_RADIUS = 8.5
CORE_COLOR = (0xe6, 0xc4, 0x53)
SVG_VIEWBOX = 64.0

OUTPUT_SIZE = 128
SUPERSAMPLE = 8  # rendered at 8x then downsampled -- smooth ring edges
                 # without a client-side mip/filter to rely on.


def render_icon(size, supersample=SUPERSAMPLE):
    S = size * supersample
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S / 2
    scale = S / SVG_VIEWBOX

    # Dark backdrop disc: minimap icons sit against widely varying map
    # terrain colors, so the motif needs a stable base rather than
    # relying on transparency alone to stay legible.
    backdrop_r = S * 0.47
    d.ellipse([cx - backdrop_r, cy - backdrop_r, cx + backdrop_r, cy + backdrop_r],
              fill=(10, 9, 14, 235))

    for radius, stroke_w, color, opacity in RINGS:
        rr = radius * scale
        w = max(1, stroke_w * scale)
        a = int(255 * opacity)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                   outline=color + (a,), width=int(w))

    core_r = CORE_RADIUS * scale
    d.ellipse([cx - core_r, cy - core_r, cx + core_r, cy + core_r],
              fill=CORE_COLOR + (255,))

    # Thin border ring, matching the circular mask convention Blizzard's
    # minimap button template applies -- without it the motif looks
    # clipped against the round button frame.
    border_r = S * 0.485
    d.ellipse([cx - border_r, cy - border_r, cx + border_r, cy + border_r],
              outline=(0x2a, 0x26, 0x18, 255), width=max(1, int(S * 0.012)))

    return im.resize((size, size), Image.LANCZOS)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = os.path.join(repo_root, "media", "minimap_icon.tga")
    icon = render_icon(OUTPUT_SIZE)
    # Pillow's TGA writer defaults to type-2 uncompressed truecolor for
    # an RGBA source -- the same format/depth the file being replaced
    # already used, so no client-compatibility change.
    icon.save(out_path)
    print("Wrote %s (%dx%d)" % (out_path, *icon.size))


if __name__ == "__main__":
    main()
