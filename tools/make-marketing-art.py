# Makes the store art in assets/marketing/: two 512x512 icons and three
# 1920x1080 thumbnails, all in the classic blocky Roblox style (flat colours,
# thick black outlines, bevelled bricks, studded baseplates, blocky characters).
#
#   python tools/make-marketing-art.py [out_dir]
#
# Needs Pillow (pip install pillow). Everything is drawn from rectangles and
# polygons, so the output is deterministic: edit a scene below and re-run.

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

OUTLINE = (20, 20, 28)
SKIN = (245, 205, 48)
GOLD = (255, 205, 40)
FONT_PATHS = ("C:/Windows/Fonts/ariblk.ttf", "C:/Windows/Fonts/impact.ttf", "C:/Windows/Fonts/arialbd.ttf")


def shade(color, f):
    """Lighten (f > 0) or darken (f < 0) a colour."""
    if f >= 0:
        return tuple(min(255, round(c + (255 - c) * f)) for c in color)
    return tuple(max(0, round(c * (1 + f))) for c in color)


def font(size):
    for path in FONT_PATHS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


class Canvas:
    def __init__(self, w, h, unit):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
        self.d = ImageDraw.Draw(self.img)
        self.w, self.h = w, h
        self.u = unit  # one "stud" in pixels: every size scales from this
        self.ow = max(2, round(unit * 0.08))  # outline width

    def block(self, x0, y0, x1, y1, color, bevel=True, ow=None):
        """A bevelled brick: black outline, lighter top, darker bottom."""
        ow = ow or self.ow
        x0, y0, x1, y1 = round(x0), round(y0), round(x1), round(y1)
        self.d.rectangle([x0, y0, x1, y1], fill=OUTLINE)
        self.d.rectangle([x0 + ow, y0 + ow, x1 - ow, y1 - ow], fill=color)
        if bevel and y1 - y0 > ow * 5:
            band = max(2, round((y1 - y0) * 0.14))
            self.d.rectangle([x0 + ow, y0 + ow, x1 - ow, y0 + ow + band], fill=shade(color, 0.28))
            self.d.rectangle([x0 + ow, y1 - ow - band, x1 - ow, y1 - ow], fill=shade(color, -0.22))

    def poly(self, pts, color):
        self.d.polygon(pts, fill=color, outline=OUTLINE, width=self.ow)

    def studs_row(self, x0, x1, y, size, color, count=None):
        """A row of round-ish studs seen from the front."""
        n = count or max(1, int((x1 - x0) // (size * 1.7)))
        gap = (x1 - x0) / n
        for i in range(n):
            cx = x0 + gap * (i + 0.5)
            self.d.ellipse([cx - size, y - size * 0.55, cx + size, y + size * 0.55], fill=OUTLINE)
            self.d.ellipse([cx - size + self.ow, y - size * 0.55 + self.ow, cx + size - self.ow, y + size * 0.55 - self.ow],
                           fill=shade(color, 0.18))

    def sparkle(self, cx, cy, r, color=(255, 255, 255)):
        pts = []
        for i in range(8):
            a = i * math.pi / 4
            rr = r if i % 2 == 0 else r * 0.28
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        self.d.polygon(pts, fill=color)

    def text(self, x, y, s, size, fill=GOLD, anchor="mm", stroke=None):
        f = font(size)
        stroke = stroke or max(3, size // 9)
        self.d.text((x + size * 0.04, y + size * 0.06), s, font=f, fill=(0, 0, 0, 120), anchor=anchor, stroke_width=stroke,
                    stroke_fill=(0, 0, 0, 120))
        self.d.text((x, y), s, font=f, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=OUTLINE)

    def save(self, path):
        self.img.convert("RGB").save(path, optimize=True)
        print(path)


# ---- Scenery ---------------------------------------------------------------


def sky(c, top, bottom, bands=9):
    for i in range(bands):
        t = i / (bands - 1)
        col = tuple(round(top[k] + (bottom[k] - top[k]) * t) for k in range(3))
        c.d.rectangle([0, c.h * i / bands, c.w, c.h * (i + 1) / bands + 1], fill=col)


def cloud(c, x, y, s, color=(255, 255, 255)):
    """A blocky cloud: a few stacked white bricks, no outline."""
    for dx, dy, w, h in ((0, 0.5, 3.0, 0.9), (0.5, 0, 1.6, 0.9), (1.4, -0.4, 1.2, 0.9)):
        c.d.rectangle([x + dx * s, y + dy * s, x + (dx + w) * s, y + (dy + h) * s], fill=color)
        c.d.rectangle([x + dx * s, y + (dy + h - 0.22) * s, x + (dx + w) * s, y + (dy + h) * s], fill=shade(color, -0.1))


def stars(c, n, seed, region, size):
    rng = random.Random(seed)
    for _ in range(n):
        x = rng.uniform(region[0], region[2])
        y = rng.uniform(region[1], region[3])
        s = size * rng.uniform(0.5, 1.2)
        c.d.rectangle([x, y, x + s, y + s], fill=rng.choice([(255, 255, 255), (255, 240, 160), (200, 220, 255)]))


def baseplate(c, y, color=(88, 190, 84)):
    """The classic grassy studded baseplate across the bottom."""
    c.d.rectangle([0, y, c.w, c.h], fill=OUTLINE)
    c.d.rectangle([0, y + c.ow, c.w, y + c.u * 2.4], fill=color)
    face = y + c.u * 2.4
    c.d.rectangle([0, face, c.w, c.h], fill=shade((120, 84, 52), -0.05))
    c.d.rectangle([0, face, c.w, face + c.ow], fill=OUTLINE)
    # Dirt side bricks.
    bx = 0
    row = 0
    while face + row * c.u * 1.6 < c.h:
        y0 = face + row * c.u * 1.6
        off = (c.u * 1.6) if row % 2 else 0
        x = -off
        while x < c.w:
            c.d.rectangle([x, y0, x + c.u * 3.2, y0 + c.u * 1.6], outline=shade((120, 84, 52), -0.4), width=max(1, c.ow // 2))
            x += c.u * 3.2
        row += 1
    # Studs on the grass.
    for r, off in enumerate((0.0, 0.5)):
        yy = y + c.u * (0.75 + r * 0.9)
        x = c.u * (0.9 + off * 1.8)
        while x < c.w:
            c.d.ellipse([x - c.u * 0.62, yy - c.u * 0.28, x + c.u * 0.62, yy + c.u * 0.28], fill=OUTLINE)
            c.d.ellipse([x - c.u * 0.5, yy - c.u * 0.2, x + c.u * 0.5, yy + c.u * 0.2], fill=shade(color, 0.22))
            x += c.u * 1.8


# ---- Characters ------------------------------------------------------------


def wizard(c, cx, base, u, robe, trim, hat, facing=1, cast=True, hat_band=GOLD, angry=True):
    """A blocky Roblox wizard. facing = +1 (looks right) or -1; cast = front arm out."""
    ow = c.ow
    # Legs
    c.block(cx - u, base - 2 * u, cx, base, shade(robe, -0.35))
    c.block(cx, base - 2 * u, cx + u, base, shade(robe, -0.35))
    # Back arm (down), torso, front arm.
    back = -facing
    bx0, bx1 = (cx + u, cx + 2 * u) if back > 0 else (cx - 2 * u, cx - u)
    c.block(bx0, base - 4 * u, bx1, base - 2 * u, robe)
    c.block(bx0, base - 2.3 * u, bx1, base - 2 * u, SKIN, bevel=False)
    c.block(cx - u, base - 4 * u, cx + u, base - 2 * u, robe)
    c.d.rectangle([cx - u + ow, base - 2.55 * u, cx + u - ow, base - 2.25 * u], fill=trim)  # belt
    c.d.rectangle([cx - u * 0.15, base - 4 * u + ow, cx + u * 0.15, base - 2 * u - ow], fill=trim)  # trim stripe
    if cast:
        fx0, fx1 = (cx + u, cx + 3.2 * u) if facing > 0 else (cx - 3.2 * u, cx - u)
        c.block(fx0, base - 4 * u, fx1, base - 3 * u, robe)
        hx0, hx1 = (fx1 - 0.2 * u, fx1 + 0.7 * u) if facing > 0 else (fx0 - 0.7 * u, fx0 + 0.2 * u)
        c.block(hx0, base - 4 * u, hx1, base - 3 * u, SKIN, bevel=False)
    else:
        fx0, fx1 = (cx + u, cx + 2 * u) if facing > 0 else (cx - 2 * u, cx - u)
        c.block(fx0, base - 4 * u, fx1, base - 2 * u, robe)
        c.block(fx0, base - 2.3 * u, fx1, base - 2 * u, SKIN, bevel=False)
    # Head
    hy1 = base - 4 * u - 0.02 * u
    hy0 = hy1 - 1.2 * u
    c.block(cx - 0.7 * u, hy0, cx + 0.7 * u, hy1, SKIN)
    ex = 0.28 * u * facing
    for sx in (-0.26, 0.26):
        px = cx + sx * u + ex * 0.6
        c.d.rectangle([px - 0.09 * u, hy0 + 0.35 * u, px + 0.09 * u, hy0 + 0.62 * u], fill=OUTLINE)
    if angry:
        for sx in (-0.26, 0.26):
            px = cx + sx * u + ex * 0.6
            c.d.line([px - 0.2 * u, hy0 + 0.25 * u + sx * 0.3 * u * facing, px + 0.2 * u, hy0 + 0.25 * u - sx * 0.3 * u * facing],
                     fill=OUTLINE, width=ow)
        c.d.arc([cx - 0.3 * u + ex, hy0 + 0.62 * u, cx + 0.3 * u + ex, hy0 + 1.0 * u], 200, 340, fill=OUTLINE, width=ow)
    else:
        c.d.arc([cx - 0.32 * u + ex, hy0 + 0.45 * u, cx + 0.32 * u + ex, hy0 + 0.95 * u], 20, 160, fill=OUTLINE, width=ow)
    # Pointy hat: wide brim, then four narrowing bricks, tip flopped to the back.
    c.block(cx - 1.25 * u, hy0 - 0.3 * u, cx + 1.25 * u, hy0 + 0.1 * u, hat)
    c.block(cx - 0.8 * u, hy0 - 0.95 * u, cx + 0.8 * u, hy0 - 0.3 * u, hat)
    c.d.rectangle([cx - 0.8 * u + ow, hy0 - 0.58 * u, cx + 0.8 * u - ow, hy0 - 0.38 * u], fill=hat_band)
    c.block(cx - 0.55 * u, hy0 - 1.5 * u, cx + 0.55 * u, hy0 - 0.95 * u, hat)
    tip = back * 0.15 * u
    c.block(cx - 0.35 * u + tip, hy0 - 2.0 * u, cx + 0.35 * u + tip, hy0 - 1.5 * u, hat)
    c.block(cx - 0.18 * u + tip * 2.2, hy0 - 2.4 * u, cx + 0.18 * u + tip * 2.2, hy0 - 2.0 * u, hat)


# ---- Spell effects -----------------------------------------------------------


def blocky_ball(c, cx, cy, r, colors):
    """A spell orb made of nested spinning squares (outermost first)."""
    for i, col in enumerate(colors):
        rr = r * (1 - i * 0.2)
        a = math.pi / 4 * (i % 2)
        pts = [(cx + math.cos(a + k * math.pi / 2 + math.pi / 4) * rr * 1.4, cy + math.sin(a + k * math.pi / 2 + math.pi / 4) * rr * 1.4)
               for k in range(4)]
        if i == 0:
            c.poly(pts, col)
        else:
            c.d.polygon(pts, fill=col)


def fireball(c, cx, cy, r, trail=0):
    """trail = -1 or +1: a tail of cube flames behind the ball."""
    if trail:
        for i in range(1, 6):
            s = r * (0.9 - i * 0.13)
            x = cx - trail * (r * 0.9 + i * r * 0.6)
            y = cy + math.sin(i * 1.7) * r * 0.35
            col = [(255, 200, 40), (255, 150, 30), (240, 90, 30), (220, 60, 30), (200, 50, 40)][i - 1]
            c.block(x - s, y - s, x + s, y + s, col, bevel=False)
    blocky_ball(c, cx, cy, r, [(235, 70, 30), (255, 140, 30), (255, 205, 50), (255, 245, 170)])


def waterball(c, cx, cy, r, trail=0):
    if trail:
        for i in range(1, 6):
            s = r * (0.9 - i * 0.13)
            x = cx - trail * (r * 0.9 + i * r * 0.6)
            y = cy + math.sin(i * 1.7) * r * 0.35
            col = [(120, 200, 255), (80, 170, 250), (60, 140, 235), (50, 110, 220), (40, 90, 200)][i - 1]
            c.block(x - s, y - s, x + s, y + s, col, bevel=False)
    blocky_ball(c, cx, cy, r, [(40, 110, 220), (70, 160, 250), (130, 210, 255), (225, 245, 255)])


def rock(c, cx, cy, r):
    c.block(cx - r, cy - r * 0.8, cx + r, cy + r * 0.8, (150, 150, 158))
    c.block(cx - r * 0.55, cy - r * 1.35, cx + r * 0.5, cy - r * 0.7, (175, 175, 182))
    c.block(cx + r * 0.1, cy + r * 0.2, cx + r * 0.95, cy + r * 0.7, (120, 120, 130), bevel=False)


def glyph(c, kind, cx, cy, r, color=(255, 255, 255), glow=(120, 200, 255)):
    """A hand-drawn spell shape: a glowing stroke with a dotted trail of blocks."""
    if kind == "circle":
        pts = [(cx + math.cos(a / 40 * math.tau) * r, cy + math.sin(a / 40 * math.tau) * r) for a in range(41)]
    elif kind == "star":
        order = [0, 2, 4, 1, 3, 0]
        pts = [(cx + math.cos(-math.pi / 2 + k * math.tau / 5) * r, cy + math.sin(-math.pi / 2 + k * math.tau / 5) * r)
               for k in order]
    elif kind == "triangle":
        pts = [(cx, cy - r), (cx + r * 0.95, cy + r * 0.7), (cx - r * 0.95, cy + r * 0.7), (cx, cy - r)]
    else:  # square
        pts = [(cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + r), (cx - r, cy + r), (cx - r, cy - r)]
    w = max(4, round(c.u * 0.32))
    for width, col in ((w * 3, tuple(round(g * 0.5 + 40) for g in glow)), (w * 2, glow), (w, color)):
        c.d.line(pts, fill=col, width=width, joint="curve")
    for p in (pts[0], pts[-1]):
        c.d.ellipse([p[0] - w * 1.2, p[1] - w * 1.2, p[0] + w * 1.2, p[1] + w * 1.2], fill=color)


def coin(c, cx, cy, r):
    c.d.ellipse([cx - r, cy - r * 0.6, cx + r, cy + r * 0.6], fill=OUTLINE)
    c.d.ellipse([cx - r + c.ow, cy - r * 0.6 + c.ow, cx + r - c.ow, cy + r * 0.6 - c.ow], fill=GOLD)
    c.d.ellipse([cx - r * 0.6, cy - r * 0.32, cx + r * 0.6, cy + r * 0.32], outline=shade(GOLD, -0.3), width=max(1, c.ow // 2))


def chest(c, x, base, w, color, is_open=True):
    """A blocky treasure chest (x = left edge, base = bottom). Returns the mouth centre."""
    h = w * 0.55
    body_top = base - h
    c.block(x, body_top, x + w, base, color)
    c.d.rectangle([x + w * 0.45, body_top, x + w * 0.55, base], fill=GOLD, outline=OUTLINE, width=max(1, c.ow // 2))
    for sx in (0.1, 0.8):
        c.d.rectangle([x + w * sx, body_top + c.ow, x + w * (sx + 0.08), base - c.ow], fill=shade(color, -0.3))
    c.block(x + w * 0.42, body_top + h * 0.08, x + w * 0.58, body_top + h * 0.4, GOLD)
    if is_open:
        lid_h = h * 0.55
        c.poly([(x - w * 0.02, body_top), (x + w * 1.02, body_top), (x + w * 0.92, body_top - lid_h), (x + w * 0.08, body_top - lid_h)],
               shade(color, -0.25))
        c.d.rectangle([x + w * 0.12, body_top - lid_h + c.ow, x + w * 0.88, body_top - c.ow * 2], fill=shade(color, -0.45))
    else:
        lid_h = h * 0.45
        c.block(x - w * 0.02, body_top - lid_h, x + w * 1.02, body_top + c.ow, shade(color, 0.12))
        c.block(x + w * 0.44, body_top - lid_h * 0.5, x + w * 0.56, body_top + h * 0.2, GOLD)
    return x + w / 2, body_top


def beam(c, cx, top, bottom, spread, color):
    """A soft light cone rising from a chest (alpha-blended)."""
    layer = Image.new("RGBA", c.img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.polygon([(cx - spread * 0.3, bottom), (cx + spread * 0.3, bottom), (cx + spread, top), (cx - spread, top)], fill=color + (70,))
    c.img.alpha_composite(layer)
    c.d = ImageDraw.Draw(c.img)


# ---- Scenes ------------------------------------------------------------------


def icon_a(path):
    """Wizard casting a fireball through a drawn circle."""
    c = Canvas(512, 512, 14)
    sky(c, (92, 60, 190), (222, 120, 190))
    stars(c, 26, 3, (0, 0, 512, 260), 5)
    cloud(c, 20, 70, 26, (255, 214, 235))
    cloud(c, 360, 40, 22, (255, 214, 235))
    baseplate(c, 410)
    glyph(c, "circle", 330, 232, 96, glow=(255, 190, 80))
    fireball(c, 330, 232, 52, trail=0)
    wizard(c, 150, 408, 26, (60, 100, 220), GOLD, (50, 70, 180), facing=1)
    for x, y, r in ((420, 120, 14), (250, 100, 10), (440, 330, 11), (60, 200, 9)):
        c.sparkle(x, y, r)
    c.save(path)


def icon_b(path):
    """An open spell chest bursting with a drawn star."""
    c = Canvas(512, 512, 14)
    sky(c, (40, 150, 235), (150, 215, 255))
    cloud(c, 30, 60, 26)
    cloud(c, 330, 110, 22)
    baseplate(c, 420)
    beam(c, 256, 40, 330, 190, (255, 240, 150))
    chest(c, 126, 410, 260, (150, 80, 220))
    glyph(c, "star", 256, 190, 86, glow=(255, 220, 90))
    for x, y, r in ((90, 150, 14), (430, 200, 12), (400, 70, 10), (130, 60, 9)):
        c.sparkle(x, y, r)
    for x, y in ((90, 440), (420, 450), (330, 470)):
        coin(c, x, y, 20)
    c.save(path)


def title(c, cx, cy, size):
    c.text(cx, cy, "SPELLCRAFT", size)
    c.text(cx, cy + size * 0.95, "ARENA", round(size * 1.05), fill=(255, 150, 60))


def thumb_keyart(path):
    c = Canvas(1920, 1080, 52)
    sky(c, (92, 60, 190), (240, 140, 170), bands=11)
    stars(c, 40, 7, (0, 0, 1920, 420), 8)
    for x, y, s in ((60, 120, 70), (1580, 90, 80), (1380, 330, 50), (-10, 420, 60)):
        cloud(c, x, y, s, (255, 214, 235))
    # Floating islands.
    for x, y, w in ((140, 560, 190), (1640, 520, 170)):
        c.block(x, y, x + w, y + 36, (88, 190, 84))
        c.block(x + w * 0.15, y + 36, x + w * 0.85, y + 120, (120, 84, 52))
        c.block(x + w * 0.35, y + 120, x + w * 0.65, y + 170, (95, 66, 40))
    baseplate(c, 840)
    c.d.rectangle([0, 0, 0, 0])
    title(c, 960, 150, 190)
    wizard(c, 440, 836, 58, (60, 100, 220), GOLD, (50, 70, 180), facing=1)
    wizard(c, 1480, 836, 58, (60, 160, 90), (200, 140, 60), (110, 70, 40), facing=-1, hat_band=(240, 90, 80))
    glyph(c, "star", 960, 560, 150, glow=(255, 220, 90))
    fireball(c, 780, 560, 70, trail=0)
    rock(c, 1150, 580, 70)
    for x, y, r in ((960, 330, 22), (700, 380, 16), (1250, 400, 18), (880, 760, 14), (1090, 740, 16)):
        c.sparkle(x, y, r)
    c.save(path)


def thumb_action(path):
    c = Canvas(1920, 1080, 52)
    sky(c, (50, 120, 220), (170, 220, 255), bands=11)
    for x, y, s in ((100, 100, 80), (1500, 140, 90), (800, 60, 60)):
        cloud(c, x, y, s)
    baseplate(c, 860)
    wizard(c, 300, 856, 62, (225, 80, 50), GOLD, (170, 40, 30), facing=1, hat_band=(255, 220, 90))
    wizard(c, 1620, 856, 62, (50, 120, 230), (210, 240, 255), (30, 80, 190), facing=-1, hat_band=(210, 240, 255))
    fireball(c, 760, 560, 100, trail=-1)
    waterball(c, 1160, 560, 100, trail=1)
    # The clash in the middle.
    for a in range(0, 360, 45):
        r = 150 + (a // 45 % 2) * 40
        x, y = 960 + math.cos(math.radians(a)) * r, 560 + math.sin(math.radians(a)) * r
        c.sparkle(x, y, 30 if a % 90 == 0 else 20, (255, 255, 200))
    c.sparkle(960, 560, 90, (255, 255, 255))
    glyph(c, "triangle", 330, 300, 90, glow=(255, 150, 70))
    glyph(c, "circle", 1590, 300, 90, glow=(100, 190, 255))
    c.text(960, 130, "DRAW YOUR SPELL!", 130)
    c.save(path)


def thumb_crates(path):
    c = Canvas(1920, 1080, 52)
    sky(c, (40, 150, 235), (170, 225, 255), bands=11)
    for x, y, s in ((60, 120, 80), (1500, 100, 90), (900, 220, 60)):
        cloud(c, x, y, s)
    baseplate(c, 800)
    colors = [(170, 175, 185), (80, 190, 90), (70, 150, 240), (150, 80, 220), (255, 190, 40)]
    names = ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
    shapes = ["circle", "triangle", "square", "star", "star"]
    for i, (col, name, shp) in enumerate(zip(colors, names, shapes)):
        x = 90 + i * 360
        cx, top = chest(c, x, 790, 280, col)
        beam(c, cx, 250, top, 150, shade(col, 0.4))
        glyph(c, shp, cx, top - 150, 62, glow=shade(col, 0.45))
        c.text(cx, 900, name, 46, fill=shade(col, 0.35))
    for x, y in ((120, 830), (520, 960), (1000, 950), (1500, 970), (1800, 840)):
        coin(c, x, y, 34)
    c.text(960, 120, "SPELL CRATES", 150)
    c.save(path)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "marketing")
    os.makedirs(out, exist_ok=True)
    icon_a(os.path.join(out, "icon-512-a.png"))
    icon_b(os.path.join(out, "icon-512-b.png"))
    thumb_keyart(os.path.join(out, "thumbnail-1-keyart-1920x1080.png"))
    thumb_action(os.path.join(out, "thumbnail-2-action-1920x1080.png"))
    thumb_crates(os.path.join(out, "thumbnail-3-crates-1920x1080.png"))
