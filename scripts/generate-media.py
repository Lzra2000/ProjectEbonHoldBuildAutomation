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
Writes media/minimap_icon.tga (128x128) and media/vote_icon.tga +
media/vote_icon_off.tga (32x32, filled/outline chevron pair for the
Public Builds vote button) -- all 32-bit uncompressed TGA.
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



# ------------------------------------------------------------------------
# Vote icon: an upward chevron for the Public Builds vote button (issue
# #8's UI shipped with a plain "^" text glyph as a placeholder -- this
# replaces it with a real icon). Two states, matching the on/off pattern
# WoW button textures use: filled gold when the player has voted, dim
# outline otherwise -- clearer at a glance than color alone at 14px.
# ------------------------------------------------------------------------

VOTE_GOLD_FILL  = (0xe6, 0xc4, 0x53)   # matches CORE_COLOR above
VOTE_GOLD_EDGE  = (0xd4, 0xaf, 0x37)   # matches RINGS[1]'s color
VOTE_DIM_EDGE   = (0x9a, 0x84, 0x4a)


def _chevron_points(cx, cy, S):
    w = S * 0.34
    top = cy - S * 0.30
    midY = cy - S * 0.02
    stemW = S * 0.13
    stemBottom = cy + S * 0.32
    return [
        (cx, top),
        (cx + w, midY),
        (cx + stemW, midY),
        (cx + stemW, stemBottom),
        (cx - stemW, stemBottom),
        (cx - stemW, midY),
        (cx - w, midY),
    ]


def render_vote_icon(size, filled, supersample=SUPERSAMPLE):
    S = size * supersample
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S / 2
    points = _chevron_points(cx, cy, S)
    if filled:
        d.polygon(points, fill=VOTE_GOLD_FILL + (255,), outline=VOTE_GOLD_EDGE + (255,),
                   width=max(1, int(S * 0.045)))
    else:
        d.polygon(points, outline=VOTE_DIM_EDGE + (255,), width=max(1, int(S * 0.05)))
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

    vote_size = 32
    for filled, name in ((True, "vote_icon.tga"), (False, "vote_icon_off.tga")):
        vote_path = os.path.join(repo_root, "media", name)
        render_vote_icon(vote_size, filled).save(vote_path)
        print("Wrote %s (%dx%d)" % (vote_path, vote_size, vote_size))


if __name__ == "__main__":
    main()
