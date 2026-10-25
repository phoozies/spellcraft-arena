# Makes assets/ui/studs.png: one classic Roblox stud on a transparent tile.
#
#   python tools/make-stud-texture.py [out.png]
#
# The tile is white highlights and black shadows only, so it lays over any
# panel colour (client/UI/Theme tiles it as an ImageLabel over blue panels and
# buttons, like the studded GUI kits). Upload the PNG to Roblox (Studio MCP
# `upload_image`, or Asset Manager) and put the asset id in Theme.STUD_IMAGE.
# Pure Python (no Pillow needed).

import math
import os
import struct
import sys
import zlib

SIZE = 128
SAMPLES = 3  # supersampling per axis, for smooth edges


def stud_pixel(x, y):
    """RGBA of one sample point of the tile (floats in pixels)."""
    cx = cy = SIZE / 2 - 2
    radius = SIZE * 0.31
    dx, dy = x - cx, y - cy
    d = math.hypot(dx, dy)
    # Soft drop shadow, down and to the right.
    sd = math.hypot(x - (cx + 5), y - (cy + 6))
    shadow = 0.0
    if sd < radius + 3:
        shadow = 0.34 * max(0.0, min(1.0, (radius + 3 - sd) / 4))
    if d <= radius:
        # The stud top: slightly lighter, brighter toward the top-left rim,
        # darker toward the bottom-right rim.
        lean = (-dx - dy) / (radius * 1.4142)  # +1 top-left .. -1 bottom-right
        edge = max(0.0, (d - radius * 0.72) / (radius * 0.28))  # 0 inside .. 1 at the rim
        white = 0.16 + 0.34 * max(0.0, lean) * edge
        black = 0.30 * max(0.0, -lean) * edge
        return (255 if white >= black else 0, 255 if white >= black else 0, 255 if white >= black else 0,
                max(white, black))
    if shadow > 0:
        return (0, 0, 0, shadow)
    return (0, 0, 0, 0.0)


def render():
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            # Average the samples as premultiplied colour.
            r = g = b = a = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    cr, cg, cb, ca = stud_pixel(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES)
                    r += cr * ca
                    g += cg * ca
                    b += cb * ca
                    a += ca
            n = SAMPLES * SAMPLES
            if a > 0:
                row += bytes((round(r / a), round(g / a), round(b / a), round(255 * a / n)))
            else:
                row += bytes((0, 0, 0, 0))
        rows.append(b"\x00" + bytes(row))
    return b"".join(rows)


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path):
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(render(), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "ui", "studs.png")
    write_png(out)
    print(out)
