#!/usr/bin/env python3
"""Draws the gshare logo and writes the Android launcher icons and the in-app logo.

Needs pycairo and Pillow. Run from anywhere: python3 tool/make_icon.py
The logo is a lowercase "g" whose tail curls into an arrow, on a teal-to-indigo gradient.
"""
import io
import math
import os

import cairo
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
S = 1024  # design canvas = one 108dp adaptive-icon layer; the safe zone is the central 66dp circle

TEAL_LIGHT = (0x2E / 255, 0xD3 / 255, 0xBE / 255)
TEAL = (0x0E / 255, 0x7C / 255, 0x86 / 255)  # app seed colour
INDIGO = (0x1E / 255, 0x2F / 255, 0x8F / 255)
AMBER = (0xFF / 255, 0xC2 / 255, 0x4B / 255)

# Glyph geometry
R = 132        # radius of the bowl
W = 76         # stroke width
DESC = 150     # drop from bowl centre to the tail's curve centre
CX = S / 2
CY = S / 2 - 62
TAIL_END = math.radians(132)  # where the tail stops on its curve (0 = right, clockwise)


def background(ctx):
    g = cairo.LinearGradient(0, 0, S, S)
    g.add_color_stop_rgb(0.0, *TEAL_LIGHT)
    g.add_color_stop_rgb(0.45, *TEAL)
    g.add_color_stop_rgb(1.0, *INDIGO)
    ctx.set_source(g)
    ctx.paint()
    # Soft light from the top left
    hl = cairo.RadialGradient(S * 0.22, S * 0.15, 0, S * 0.22, S * 0.15, S * 0.75)
    hl.add_color_stop_rgba(0, 1, 1, 1, 0.28)
    hl.add_color_stop_rgba(1, 1, 1, 1, 0)
    ctx.set_source(hl)
    ctx.paint()
    # Glow behind the glyph
    glow = cairo.RadialGradient(CX, S / 2, 0, CX, S / 2, S * 0.36)
    glow.add_color_stop_rgba(0, 1, 1, 1, 0.16)
    glow.add_color_stop_rgba(1, 1, 1, 1, 0)
    ctx.set_source(glow)
    ctx.paint()


def glyph_path(ctx):
    """Adds the stroked parts of the "g" to the current path (stroke with butt caps)."""
    ctx.new_sub_path()
    ctx.arc(CX, CY, R, 0, 2 * math.pi)
    # Stem down the right side, then the tail curving left under the bowl into the arrowhead
    ctx.new_sub_path()
    ctx.move_to(CX + R, CY)
    ctx.line_to(CX + R, CY + DESC)
    ctx.arc(CX, CY + DESC, R, 0, TAIL_END)


def arrowhead(ctx):
    """Filled arrowhead at the end of the tail, pointing along it."""
    ex = CX + R * math.cos(TAIL_END)
    ey = CY + DESC + R * math.sin(TAIL_END)
    dx, dy = -math.sin(TAIL_END), math.cos(TAIL_END)  # clockwise tangent
    px, py = -dy, dx
    length, half = W * 1.3, W * 0.95
    back = W * 0.05
    bx, by = ex - dx * back, ey - dy * back
    ctx.move_to(ex + dx * length, ey + dy * length)
    ctx.line_to(bx + px * half, by + py * half)
    ctx.line_to(bx - px * half, by - py * half)
    ctx.close_path()


def spark(ctx):
    """Four-point sparkle off the top right of the bowl."""
    a = math.radians(-45)
    dist = R + W / 2 + 62
    x, y = CX + dist * math.cos(a), CY + dist * math.sin(a)
    big, pinch = 58, 0.16 * 58
    tips = [(0, -1), (1, 0), (0, 1), (-1, 0)]
    ctx.new_sub_path()
    ctx.move_to(x, y - big)
    for (ax, ay), (bx, by) in zip(tips, tips[1:] + tips[:1]):
        # Control point sits in the quadrant between the two tips, close to the centre.
        cx, cy = x + pinch * (ax + bx), y + pinch * (ay + by)
        ctx.curve_to(cx, cy, cx, cy, x + big * bx, y + big * by)
    ctx.close_path()


def glyph(ctx, color=(1, 1, 1), accent=AMBER, shadow=True):
    ctx.set_line_width(W)
    ctx.set_line_cap(cairo.LINE_CAP_BUTT)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    if shadow:
        for i, a in ((10, 0.05), (6, 0.07), (3, 0.08)):
            ctx.save()
            ctx.translate(0, i * 1.6)
            ctx.set_source_rgba(0.02, 0.05, 0.2, a)
            ctx.set_line_width(W + i * 2)
            glyph_path(ctx)
            ctx.stroke()
            arrowhead(ctx)
            ctx.fill()
            ctx.restore()
    ctx.set_source_rgb(*color)
    glyph_path(ctx)
    ctx.stroke()
    arrowhead(ctx)
    ctx.fill()
    ctx.set_source_rgb(*accent)
    spark(ctx)
    ctx.fill()


def render(draw, size=S, clip_round=None):
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, S, S)
    ctx = cairo.Context(surf)
    if clip_round is not None:
        r = clip_round
        ctx.new_sub_path()
        ctx.arc(S - r, r, r, -math.pi / 2, 0)
        ctx.arc(S - r, S - r, r, 0, math.pi / 2)
        ctx.arc(r, S - r, r, math.pi / 2, math.pi)
        ctx.arc(r, r, r, math.pi, 3 * math.pi / 2)
        ctx.close_path()
        ctx.clip()
    draw(ctx)
    buf = io.BytesIO()
    surf.write_to_png(buf)
    img = Image.open(io.BytesIO(buf.getvalue())).convert('RGBA')
    return img if size == S else img.resize((size, size), Image.LANCZOS)


def full(ctx):
    background(ctx)
    glyph(ctx)


def legacy(ctx):
    # Pre-adaptive icons show the whole square, so zoom the glyph in a little.
    background(ctx)
    ctx.translate(S / 2, S / 2)
    ctx.scale(1.3, 1.3)
    ctx.translate(-S / 2, -S / 2)
    glyph(ctx)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def main():
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, scale in densities.items():
        d = os.path.join(RES, f'mipmap-{name}')
        save(render(legacy, int(48 * scale), clip_round=S * 0.22), os.path.join(d, 'ic_launcher.png'))
        layer = int(108 * scale)
        save(render(background, layer), os.path.join(d, 'ic_launcher_background.png'))
        save(render(glyph, layer), os.path.join(d, 'ic_launcher_foreground.png'))
        save(render(lambda c: glyph(c, accent=(1, 1, 1), shadow=False), layer),
             os.path.join(d, 'ic_launcher_monochrome.png'))

    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
            '</adaptive-icon>\n'
        )

    save(render(full, 512, clip_round=S * 0.22), os.path.join(ROOT, 'assets', 'logo.png'))
    print('Icons written to', os.path.normpath(RES), 'and assets/logo.png')


if __name__ == '__main__':
    main()
