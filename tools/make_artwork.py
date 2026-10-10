#!/usr/bin/env python3
"""Genera icona dell'app, logo per il README e GIF dimostrativa.

Uso: python3 tools/make_artwork.py
Richiede pycairo e ffmpeg.
"""
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

import cairo

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
LOGO = ROOT / "docs" / "logo.png"
DEMO = ROOT / "docs" / "demo.gif"

NAVY_TOP = (0x12 / 255, 0x30 / 255, 0x5A / 255)
NAVY = (0x0A / 255, 0x1A / 255, 0x33 / 255)
RED = (0xD7 / 255, 0x26 / 255, 0x3D / 255)
ORANGE = (0xFF / 255, 0x95 / 255, 0x00 / 255)
GREEN = (0x34 / 255, 0xC7 / 255, 0x59 / 255)
IMMINENT = (0xFF / 255, 0x3B / 255, 0x30 / 255)
WHITE = (1, 1, 1)
FONT = "Noto Sans"


# MARK: - Logo

def draw_logo(ctx, size):
    """Cartello di divieto (ZTL) con segnaposto e onde "live", su sfondo blu notte."""
    ctx.save()
    ctx.scale(size / 1024, size / 1024)

    gradient = cairo.LinearGradient(0, 0, 0, 1024)
    gradient.add_color_stop_rgb(0, *NAVY_TOP)
    gradient.add_color_stop_rgb(1, *NAVY)
    ctx.set_source(gradient)
    ctx.paint()

    cx, cy = 512, 540

    # Onde "live" ai due lati del cartello.
    ctx.set_source_rgb(*ORANGE)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_width(34)
    for radius in (420, 478):
        for start, end in ((-62, -28), (-152, -118)):
            ctx.new_sub_path()
            ctx.arc(cx, cy, radius, math.radians(start), math.radians(end))
            ctx.stroke()

    # Cartello: bordo rosso e fondo bianco.
    ctx.set_source_rgb(*RED)
    ctx.arc(cx, cy, 360, 0, 2 * math.pi)
    ctx.fill()
    ctx.set_source_rgb(*WHITE)
    ctx.arc(cx, cy, 268, 0, 2 * math.pi)
    ctx.fill()

    # Segnaposto.
    head_y, radius, tip_y = 495, 118, 735
    ctx.set_source_rgb(*NAVY)
    ctx.move_to(cx, tip_y)
    ctx.curve_to(cx - 70, tip_y - 90, cx - radius, head_y + 80, cx - radius, head_y)
    ctx.arc(cx, head_y, radius, math.pi, 2 * math.pi)
    ctx.curve_to(cx + radius, head_y + 80, cx + 70, tip_y - 90, cx, tip_y)
    ctx.close_path()
    ctx.fill()
    ctx.set_source_rgb(*WHITE)
    ctx.arc(cx, head_y, 48, 0, 2 * math.pi)
    ctx.fill()

    ctx.restore()


def rounded_rect(ctx, x, y, w, h, r):
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    ctx.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    ctx.close_path()


def make_icon():
    # Icona senza trasparenza: gli angoli arrotondati li applica iOS.
    surface = cairo.ImageSurface(cairo.FORMAT_RGB24, 1024, 1024)
    draw_logo(cairo.Context(surface), 1024)
    ICON.parent.mkdir(parents=True, exist_ok=True)
    surface.write_to_png(str(ICON))


def make_readme_logo(size=256):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    rounded_rect(ctx, 0, 0, size, size, size * 0.225)
    ctx.clip()
    draw_logo(ctx, size)
    LOGO.parent.mkdir(parents=True, exist_ok=True)
    surface.write_to_png(str(LOGO))


# MARK: - GIF dimostrativa

W, H = 800, 450
GATE = (560, 210)
# Percorso: verso il varco, poi svolta a sinistra 100 m prima per evitarlo.
PATH = [(40, 210), (460, 210), (460, 20)]
METERS_PER_PIXEL = 1.0
FPS = 15


def point_along(distance):
    """Posizione e direzione dopo `distance` pixel lungo PATH."""
    for (x1, y1), (x2, y2) in zip(PATH, PATH[1:]):
        length = math.hypot(x2 - x1, y2 - y1)
        if distance <= length:
            t = distance / length
            return (x1 + (x2 - x1) * t, y1 + (y2 - y1) * t), math.atan2(y2 - y1, x2 - x1)
        distance -= length
    (x1, y1), (x2, y2) = PATH[-2], PATH[-1]
    return (x2, y2), math.atan2(y2 - y1, x2 - x1)


def draw_map(ctx):
    ctx.set_source_rgb(0.13, 0.15, 0.19)
    ctx.paint()

    # Area C: tutto ciò che sta a destra della cerchia.
    ctx.set_source_rgba(*RED, 0.16)
    ctx.rectangle(GATE[0], 0, W - GATE[0], H)
    ctx.fill()

    # Strade secondarie.
    ctx.set_source_rgb(0.24, 0.27, 0.33)
    ctx.set_line_width(10)
    for x in (160, 300, 460, 680):
        ctx.move_to(x, 0)
        ctx.line_to(x, H)
    for y in (80, 210, 340):
        ctx.move_to(0, y)
        ctx.line_to(W, y)
    ctx.stroke()

    # Cerchia dei Bastioni, confine di Area C.
    ctx.set_source_rgb(*RED)
    ctx.set_line_width(4)
    ctx.set_dash([14, 10])
    ctx.move_to(GATE[0], 0)
    ctx.line_to(GATE[0], H)
    ctx.stroke()
    ctx.set_dash([])

    ctx.select_font_face(FONT, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(22)
    ctx.set_source_rgba(*RED, 0.9)
    ctx.move_to(GATE[0] + 24, 50)
    ctx.show_text("AREA C")

    # Varco con telecamera.
    ctx.set_source_rgb(*RED)
    ctx.arc(*GATE, 15, 0, 2 * math.pi)
    ctx.fill()
    ctx.set_source_rgb(*WHITE)
    ctx.arc(*GATE, 6, 0, 2 * math.pi)
    ctx.fill()
    ctx.set_font_size(15)
    ctx.move_to(GATE[0] + 22, GATE[1] - 18)
    ctx.show_text("Porta Tenaglia")


def draw_route(ctx, travelled):
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_source_rgb(0.26, 0.52, 0.96)
    ctx.set_line_width(9)
    (x, y), _ = point_along(travelled)
    ctx.move_to(x, y)
    remaining = travelled
    for (x1, y1), (x2, y2) in zip(PATH, PATH[1:]):
        length = math.hypot(x2 - x1, y2 - y1)
        if remaining < length:
            ctx.line_to(x2, y2)
        remaining -= length
    ctx.stroke()


def draw_vehicle(ctx, position, heading):
    ctx.save()
    ctx.translate(*position)
    ctx.rotate(heading)
    ctx.set_source_rgb(*WHITE)
    ctx.move_to(16, 0)
    ctx.line_to(-11, -12)
    ctx.line_to(-5, 0)
    ctx.line_to(-11, 12)
    ctx.close_path()
    ctx.fill_preserve()
    ctx.set_source_rgb(0.26, 0.52, 0.96)
    ctx.set_line_width(3)
    ctx.stroke()
    ctx.restore()


def draw_shield(ctx, x, y, s, color):
    ctx.set_source_rgb(*color)
    ctx.move_to(x, y - s)
    ctx.curve_to(x + s * 0.6, y - s * 0.75, x + s * 0.85, y - s * 0.8, x + s * 0.85, y - s * 0.8)
    ctx.curve_to(x + s * 0.85, y + s * 0.2, x + s * 0.5, y + s * 0.75, x, y + s)
    ctx.curve_to(x - s * 0.5, y + s * 0.75, x - s * 0.85, y + s * 0.2, x - s * 0.85, y - s * 0.8)
    ctx.curve_to(x - s * 0.85, y - s * 0.8, x - s * 0.6, y - s * 0.75, x, y - s)
    ctx.close_path()
    ctx.fill()
    ctx.set_source_rgb(*WHITE)
    ctx.set_line_width(s * 0.22)
    ctx.move_to(x - s * 0.38, y)
    ctx.line_to(x - s * 0.08, y + s * 0.3)
    ctx.line_to(x + s * 0.42, y - s * 0.3)
    ctx.stroke()


def draw_warning(ctx, x, y, s, imminent):
    ctx.set_source_rgb(*WHITE)
    if imminent:
        ctx.save()
        ctx.translate(x, y)
        for i in range(8):
            angle = math.pi / 8 + i * math.pi / 4
            ctx.line_to(s * math.cos(angle), s * math.sin(angle))
        ctx.close_path()
        ctx.restore()
    else:
        ctx.move_to(x, y - s)
        ctx.line_to(x + s * 1.1, y + s * 0.85)
        ctx.line_to(x - s * 1.1, y + s * 0.85)
        ctx.close_path()
    ctx.fill()
    ctx.set_source_rgb(*(IMMINENT if imminent else ORANGE))
    ctx.select_font_face(FONT, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(s * 1.2)
    mark = "×" if imminent else "!"
    extents = ctx.text_extents(mark)
    ctx.move_to(x - extents.x_advance / 2, y + s * (0.4 if imminent else 0.62))
    ctx.show_text(mark)


def draw_live_activity(ctx, distance):
    """Riquadro come appare su CarPlay sopra la mappa."""
    if distance is None:
        w, h = 74, 56
        x, y = (W - w) / 2, H - h - 22
        ctx.set_source_rgba(0.35, 0.37, 0.42, 0.85)
        rounded_rect(ctx, x, y, w, h, 20)
        ctx.fill()
        draw_shield(ctx, W / 2, y + h / 2, 17, GREEN)
        return

    imminent = distance <= 120
    w, h = 380, 82
    x, y = (W - w) / 2, H - h - 22
    ctx.set_source_rgb(*(IMMINENT if imminent else ORANGE))
    rounded_rect(ctx, x, y, w, h, 24)
    ctx.fill()
    draw_warning(ctx, x + 52, y + h / 2, 22, imminent)

    ctx.set_source_rgb(*WHITE)
    ctx.select_font_face(FONT, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(36)
    ctx.move_to(x + 96, y + 42)
    ctx.show_text(f"{int(round(distance / 10) * 10)} m")
    ctx.set_font_size(17)
    ctx.move_to(x + 98, y + 68)
    ctx.show_text("Area C · Porta Tenaglia")


def gate_distance(position, heading):
    """Metri dal varco se è davanti al veicolo ed entro 400 m, altrimenti None."""
    dx, dy = GATE[0] - position[0], GATE[1] - position[1]
    distance = math.hypot(dx, dy) * METERS_PER_PIXEL
    bearing_gap = abs((math.atan2(dy, dx) - heading + math.pi) % (2 * math.pi) - math.pi)
    if distance > 400 or bearing_gap > math.radians(50):
        return None
    return distance


def make_demo():
    total = sum(math.hypot(x2 - x1, y2 - y1) for (x1, y1), (x2, y2) in zip(PATH, PATH[1:]))
    hold_start, hold_end, moving = FPS, int(FPS * 1.5), FPS * 8
    frames = [0.0] * hold_start + [total * i / (moving - 1) for i in range(moving)] + [total] * hold_end

    with tempfile.TemporaryDirectory() as tmp:
        for index, travelled in enumerate(frames):
            surface = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
            ctx = cairo.Context(surface)
            position, heading = point_along(travelled)
            draw_map(ctx)
            draw_route(ctx, travelled)
            draw_vehicle(ctx, position, heading)
            draw_live_activity(ctx, gate_distance(position, heading))
            surface.write_to_png(f"{tmp}/frame{index:04d}.png")

        DEMO.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            "ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/frame%04d.png",
            "-vf", "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none",
            "-loop", "0", str(DEMO),
        ], check=True)


if __name__ == "__main__":
    if shutil.which("ffmpeg") is None:
        raise SystemExit("ffmpeg non trovato")
    make_icon()
    make_readme_logo()
    make_demo()
    for path in (ICON, LOGO, DEMO):
        print(f"{path.relative_to(ROOT)}: {path.stat().st_size // 1024} KB")
