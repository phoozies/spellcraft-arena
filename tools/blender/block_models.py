# The blocky, classic-Roblox models: one spec, two outputs.
#
#   python tools/blender/block_models.py --luau .          writes src/shared/Models/BlockModels.luau
#   blender --background --python tools/blender/block_models.py -- .
#                                                          builds every model in Blender, exports
#                                                          assets/models/blocks/<Name>.fbx and the
#                                                          scene assets/models/source/BlockModels.blend
#
# The spec below is the source of truth. The generated BlockModels.luau lets
# the game build every model from plain Parts (ModelKit), so these models work
# in any place without importing meshes; the FBX/blend files are the Blender
# source for artists (and for uploading meshes later).
#
# Coordinates are Roblox studs, y up, forward = -Z, the model's origin is its
# pivot. `base=True` models stand on y = 0 (trees, statue, chest); the rest are
# centered on the origin. Every part is a block unless `shape` says otherwise
# (Ball, Cylinder: its length runs along X like a Roblox cylinder). Rotation
# `rot=(rx, ry, rz)` is in degrees, applied in Roblox's YXZ order.
#
# Part names are a contract: tests/Models.spec.luau, prepare tools, and the
# tinting code in the hub (Crate_Trim, Crate_Gem) look parts up by name.

import math
import os
import random
import sys

STUD = 28.0  # cm per stud in the Blender scene (1 Blender unit = 1 cm)


def rgb(r, g, b):
    return (r, g, b)


def P(name, pos, size, color, mat="SmoothPlastic", t=0.0, rot=None, shape="Block", collide=None):
    return {
        "name": name,
        "pos": pos,
        "size": size,
        "color": color,
        "mat": mat,
        "t": t,
        "rot": rot,
        "shape": shape,
        "collide": collide,
    }


def lerp(a, b, f):
    return tuple(round(a[i] + (b[i] - a[i]) * f) for i in range(3))


MODELS = {}


def model(name, parts, vfx=False, solid=False, base=False, note=""):
    MODELS[name] = {"parts": parts, "vfx": vfx, "solid": solid, "base": base, "note": note}


# ---------------------------------------------------------------- spells
def crescent(core, glow, flame):
    """A fast blade of power: a shallow arc of blocks, bulging forward (-Z)."""
    parts = [
        P("Slash_Core", (0, 0, -0.6), (2.4, 0.5, 0.9), core, "Neon"),
        P("Slash_Mid", (1.9, 0, -0.35), (2.2, 0.5, 0.8), flame, "Neon", rot=(0, -18, 0)),
        P("Slash_Mid", (-1.9, 0, -0.35), (2.2, 0.5, 0.8), flame, "Neon", rot=(0, 18, 0)),
        P("Slash_Tip", (2.9, 0, 0.25), (1.8, 0.4, 0.7), flame, "Neon", rot=(0, -38, 0)),
        P("Slash_Tip", (-2.9, 0, 0.25), (1.8, 0.4, 0.7), flame, "Neon", rot=(0, 38, 0)),
        P("Slash_Glow", (0, 0, -0.3), (6.4, 0.8, 1.8), glow, "Neon", t=0.6),
    ]
    return parts


model("FireSlash", crescent(rgb(255, 240, 170), rgb(255, 120, 40), rgb(255, 150, 50)), vfx=True,
      note="Fire Slash bolt")
model("WaterSlice", crescent(rgb(235, 250, 255), rgb(60, 150, 255), rgb(90, 190, 255)), vfx=True,
      note="Water Slice bolt")

model("FireBoost", [
    P("Flame_Base", (0, -1.0, 0), (2.0, 0.7, 2.0), rgb(255, 80, 30), "Neon"),
    P("Flame_Low", (0, -0.2, 0), (1.6, 0.9, 1.6), rgb(255, 120, 40), "Neon", rot=(0, 45, 0)),
    P("Flame_Mid", (0, 0.7, 0), (1.1, 0.9, 1.1), rgb(255, 180, 60), "Neon"),
    P("Flame_Top", (0, 1.5, 0), (0.6, 0.8, 0.6), rgb(255, 240, 150), "Neon", rot=(0, 45, 0)),
    P("Flame_Lick", (0.85, 0.2, 0), (0.45, 1.1, 0.45), rgb(255, 130, 40), "Neon"),
    P("Flame_Lick", (-0.85, 0.0, 0), (0.45, 0.9, 0.45), rgb(255, 130, 40), "Neon"),
    P("Flame_Lick", (0, 0.1, 0.85), (0.45, 0.8, 0.45), rgb(255, 100, 30), "Neon"),
], vfx=True, note="Fire Boost pop-up over the caster's head")

model("WaterBody", [
    P("Drop_Base", (0, -1.0, 0), (2.0, 0.8, 2.0), rgb(40, 130, 240), "Glass", t=0.15),
    P("Drop_Low", (0, -0.2, 0), (1.6, 0.8, 1.6), rgb(64, 164, 255), "Glass", t=0.15),
    P("Drop_Mid", (0, 0.6, 0), (1.1, 0.8, 1.1), rgb(110, 195, 255), "Glass", t=0.1),
    P("Drop_Top", (0, 1.3, 0), (0.55, 0.7, 0.55), rgb(170, 225, 255), "Glass", t=0.1),
    P("Drop_Shine", (-0.5, -0.2, -0.85), (0.4, 0.9, 0.2), rgb(255, 255, 255), "Neon", t=0.2),
], vfx=True, note="Water Body pop-up over the caster's head")

model("AirBoost", [
    P("Wing_Core", (0, 0, 0), (0.9, 0.9, 0.9), rgb(120, 220, 200), "Neon"),
    P("Wing_Feather", (1.0, 0.1, 0), (1.0, 0.25, 1.7), rgb(235, 250, 255), "Neon", rot=(0, 0, 10)),
    P("Wing_Feather", (1.9, 0.3, 0), (0.9, 0.25, 1.35), rgb(215, 240, 255), "Neon", rot=(0, 0, 18)),
    P("Wing_Feather", (2.7, 0.55, 0), (0.8, 0.25, 0.95), rgb(190, 230, 250), "Neon", rot=(0, 0, 26)),
    P("Wing_Feather", (-1.0, 0.1, 0), (1.0, 0.25, 1.7), rgb(235, 250, 255), "Neon", rot=(0, 0, -10)),
    P("Wing_Feather", (-1.9, 0.3, 0), (0.9, 0.25, 1.35), rgb(215, 240, 255), "Neon", rot=(0, 0, -18)),
    P("Wing_Feather", (-2.7, 0.55, 0), (0.8, 0.25, 0.95), rgb(190, 230, 250), "Neon", rot=(0, 0, -26)),
], vfx=True, note="Air Boost winged emblem over the caster's head")

model("AirShield", [
    P("Shield_Plate", (0, 0, 0), (2.6, 3.2, 0.4), rgb(150, 220, 215), "SmoothPlastic", t=0.1),
    P("Shield_Rim", (0, 1.7, 0), (3.0, 0.4, 0.55), rgb(235, 250, 255), "Neon"),
    P("Shield_Rim", (0, -1.7, 0), (3.0, 0.4, 0.55), rgb(235, 250, 255), "Neon"),
    P("Shield_Rim", (1.4, 0, 0), (0.4, 3.2, 0.55), rgb(235, 250, 255), "Neon"),
    P("Shield_Rim", (-1.4, 0, 0), (0.4, 3.2, 0.55), rgb(235, 250, 255), "Neon"),
    P("Shield_Boss", (0, 0, -0.35), (1.1, 1.1, 0.4), rgb(255, 255, 255), "Neon", rot=(0, 0, 45)),
    P("Shield_Swirl", (0.7, 0.9, -0.25), (0.7, 0.18, 0.2), rgb(120, 220, 230), "Neon"),
    P("Shield_Swirl", (-0.7, -0.9, -0.25), (0.7, 0.18, 0.2), rgb(120, 220, 230), "Neon"),
], vfx=True, note="Air Shield kite shield over the caster's head")


def column(name, height, width, c0, c1, mats, spin, glow=None, twist=15):
    """A tall stack of rotating blocks, standing on y = 0."""
    parts = []
    layers = 7
    step = height / layers
    for i in range(layers):
        f = i / (layers - 1)
        w = width * (1.0 - 0.45 * f)
        parts.append(
            P(f"{name}_Layer", (0, step * (i + 0.5), 0), (w, step, w), lerp(c0, c1, f),
              mats, t=0.12, rot=(0, spin * (i % 2) + twist * i, 0))
        )
    parts.append(P(f"{name}_Core", (0, height / 2, 0), (width * 0.3, height, width * 0.3), (255, 255, 255),
                   "Neon", t=0.2))
    if glow:
        parts.append(P(f"{name}_Base", (0, 0.3, 0), (width * 1.6, 0.6, width * 1.6), glow, "Neon", t=0.35,
                       rot=(0, 45, 0)))
    return parts


model("FirePillar", column("Fire", 14, 4.0, (255, 70, 30), (255, 230, 120), "Neon", 45,
                           glow=(255, 110, 30)), vfx=True, base=True,
      note="Fire Pillar column that erupts at the aim point")
model("WaterNebula", column("Nebula", 16, 5.0, (40, 110, 240), (170, 230, 255), "Neon", 45,
                            glow=(70, 160, 255), twist=25) + [
    P("Nebula_Star", (2.6, 5.0, 0), (0.5, 0.5, 0.5), (255, 255, 255), "Neon"),
    P("Nebula_Star", (-2.2, 9.0, 1.2), (0.5, 0.5, 0.5), (255, 255, 255), "Neon"),
    P("Nebula_Star", (0.8, 12.5, -2.2), (0.5, 0.5, 0.5), (255, 255, 255), "Neon"),
], vfx=True, base=True, note="Water Nebula column that crashes down at the aim point")

model("Earthquake", [
    P("Quake_Core", (0, 0.4, 0), (3.2, 0.8, 3.2), rgb(130, 98, 70), "Slate", rot=(0, 20, 0)),
] + [
    P("Quake_Crack", (math.cos(math.radians(a + 8 * k)) * r, 0.1, math.sin(math.radians(a + 8 * k)) * r),
      (0.55, 0.25, 3.2 - 0.3 * k), rgb(40, 28, 20), "Slate", rot=(0, -(a + 8 * k) + 90, 0), collide=False)
    for a in range(0, 360, 45) for k, r in enumerate((4.5, 7.5, 10.5))
] + [
    P("Quake_Rubble", (math.cos(math.radians(a)) * 6.5, 0.5, math.sin(math.radians(a)) * 6.5),
      (1.1, 1.0, 1.1), rgb(150, 118, 86), "Slate", rot=(10, a, 8))
    for a in range(22, 360, 90)
], vfx=True, base=True, note="Earthquake ground cracks (the wind-up zone)")

model("EarthPillar", [
    P("Pillar_Stone", (0, 2.0, 0), (5.5, 4.0, 5.5), rgb(150, 118, 86), "Slate"),
    P("Pillar_Stone", (0, 5.0, 0), (4.8, 3.2, 4.8), rgb(138, 108, 80), "Slate", rot=(0, 12, 0)),
    P("Pillar_Stone", (0, 7.8, 0), (4.0, 3.0, 4.0), rgb(160, 126, 92), "Slate", rot=(0, -10, 0)),
    P("Pillar_Stone", (0, 10.3, 0), (3.3, 2.4, 3.3), rgb(146, 114, 84), "Slate", rot=(0, 20, 0)),
    P("Pillar_Tip", (0, 12.4, 0), (2.4, 2.0, 2.4), rgb(168, 134, 98), "Slate", rot=(0, 35, 0)),
    P("Pillar_Rubble", (3.4, 0.5, 1.0), (1.4, 1.0, 1.4), rgb(128, 100, 72), "Slate", rot=(10, 30, 0)),
    P("Pillar_Rubble", (-3.2, 0.4, -1.6), (1.2, 0.8, 1.2), rgb(128, 100, 72), "Slate", rot=(0, 55, 12)),
    P("Pillar_Rubble", (0.8, 0.4, 3.4), (1.0, 0.8, 1.0), rgb(150, 118, 86), "Slate", rot=(8, 15, 0)),
], vfx=True, base=True, note="Earth Pillar stone spike")

model("EarthPunch", [
    P("Boulder_Core", (0, 3.6, 0), (6.4, 5.4, 6.2), rgb(150, 118, 86), "Slate", rot=(0, 20, 0)),
    P("Boulder_Top", (0.6, 6.8, -0.3), (4.2, 3.2, 4.0), rgb(164, 130, 96), "Slate", rot=(8, 45, 0)),
    P("Boulder_Side", (3.6, 2.4, 0.6), (3.2, 3.2, 3.2), rgb(138, 108, 80), "Slate", rot=(15, 10, 20)),
    P("Boulder_Side", (-3.4, 2.0, 1.0), (3.0, 2.8, 3.0), rgb(142, 112, 82), "Slate", rot=(0, 55, 15)),
    P("Boulder_Spike", (-0.8, 8.7, 0.5), (1.6, 2.2, 1.6), rgb(176, 142, 104), "Slate", rot=(10, 30, 12)),
    P("Boulder_Rubble", (1.2, 0.5, 4.0), (1.3, 1.0, 1.3), rgb(128, 100, 72), "Slate", rot=(0, 25, 0)),
], vfx=True, base=True, note="Earth Punch boulder that bursts out of the ground")

def rubble_wall():
    """A wide, rectangular wall of piled stones, centered on the origin.

    Fills the same 23.04 x 12.38 x 9.72 box as the old RockWall mesh, so placement and the
    spell's `visual.size` stay valid. Five rows of uneven, staggered stones make the rectangle;
    the top rows are broken away in places for a ragged skyline, and loose rubble spills along
    both long faces. Every stone is its own chunk when the wall is hit.
    """
    rng = random.Random(5)
    width, height, depth = 23.04, 12.38, 9.72
    ground = -height / 2
    stones = [(150, 118, 86), (138, 108, 80), (160, 126, 92), (128, 100, 72), (168, 134, 98),
              (120, 96, 72)]
    rows = 5
    row_h = height / rows
    # How many rows are still standing in each fifth of the wall (the broken skyline).
    standing = [4, 5, 3, 5, 4]
    parts = []
    for r in range(rows):
        x = -width / 2
        # Offset every other row so the joints don't line up, like a stacked wall.
        first = rng.uniform(1.6, 2.4) if r % 2 else rng.uniform(3.4, 4.6)
        edge = x + first
        while x < width / 2 - 0.05:
            w = min(edge - x, width / 2 - x)
            if width / 2 - edge < 2.0:
                w = width / 2 - x  # no sliver at the end of the row
            cx = x + w / 2
            fifth = min(int((cx + width / 2) / width * len(standing)), len(standing) - 1)
            if r < standing[fifth]:
                top = r == standing[fifth] - 1 and standing[fifth] < rows
                h = row_h * rng.uniform(0.9, 1.0) * (rng.uniform(0.55, 0.8) if top else 1.0)
                d = rng.uniform(5.2, 6.4)
                parts.append(
                    P("Wall_Cap" if top else "Wall_Stone",
                      (round(cx, 2), round(ground + r * row_h + h / 2, 2), round(rng.uniform(-0.5, 0.5), 2)),
                      (round(w * rng.uniform(0.93, 0.99), 2), round(h, 2), round(d, 2)),
                      rng.choice(stones), "Slate", rot=(0, round(rng.uniform(-4, 4), 1), 0))
                )
            x += w
            edge = x + rng.uniform(3.2, 6.0)
    # Fallen rubble along both long faces.
    for n in range(10):
        side = 1 if n % 2 == 0 else -1
        s = rng.uniform(1.1, 2.3)
        x = -width / 2 + 1.4 + (width - 2.8) * (n + rng.uniform(0.1, 0.9)) / 10
        z = side * (depth / 2 - s * 0.75 - rng.uniform(0, 0.5))
        parts.append(
            P("Wall_Rubble", (round(x, 2), round(ground + s * 0.42, 2), round(z, 2)),
              (round(s, 2), round(s * rng.uniform(0.7, 0.95), 2), round(s * rng.uniform(0.9, 1.2), 2)),
              rng.choice(stones), "Slate",
              rot=(round(rng.uniform(-9, 9), 1), round(rng.uniform(0, 70), 1), round(rng.uniform(-9, 9), 1)))
        )
    return parts


model("EarthWall", rubble_wall(), solid=True,
      note="Earth Wall: a wide rectangular wall of piled rubble, each stone breaks off on its own")

model("RockThrow", [
    P("Rock_Main", (0, 0, 0), (4.4, 4.0, 4.4), rgb(150, 118, 86), "Slate", rot=(15, 25, 10)),
    P("Rock_Lump", (1.4, 1.2, 0.8), (3.0, 3.0, 3.0), rgb(164, 130, 96), "Slate", rot=(30, 10, 20)),
    P("Rock_Lump", (-1.5, -1.0, -0.7), (3.0, 2.8, 2.8), rgb(132, 104, 76), "Slate", rot=(5, 55, 25)),
    P("Rock_Chip", (0.4, -1.8, 1.4), (1.3, 1.3, 1.3), rgb(176, 142, 104), "Slate", rot=(20, 40, 0)),
], vfx=True, note="Rock Throw boulder")

model("WaterWave", [
    P("Wave_Body", (-7.2, -2.0, 0), (4.8, 4.0, 3.0), rgb(60, 150, 255), "Glass", t=0.2),
    P("Wave_Body", (-2.4, -1.4, 0), (4.8, 5.2, 3.0), rgb(50, 140, 250), "Glass", t=0.2),
    P("Wave_Body", (2.4, -1.4, 0), (4.8, 5.2, 3.0), rgb(50, 140, 250), "Glass", t=0.2),
    P("Wave_Body", (7.2, -2.0, 0), (4.8, 4.0, 3.0), rgb(60, 150, 255), "Glass", t=0.2),
    P("Wave_Crest", (0, 1.9, -0.7), (9.6, 1.8, 2.0), rgb(110, 195, 255), "Glass", t=0.15, rot=(-14, 0, 0)),
    P("Wave_Crest", (-6.6, 0.5, -0.5), (4.6, 1.4, 1.8), rgb(110, 195, 255), "Glass", t=0.15, rot=(-14, 0, 0)),
    P("Wave_Crest", (6.6, 0.5, -0.5), (4.6, 1.4, 1.8), rgb(110, 195, 255), "Glass", t=0.15, rot=(-14, 0, 0)),
    P("Wave_Foam", (-3.6, 3.0, -1.4), (1.6, 0.9, 1.0), rgb(255, 255, 255), "Neon", t=0.1),
    P("Wave_Foam", (0.8, 3.3, -1.6), (2.0, 1.0, 1.1), rgb(255, 255, 255), "Neon", t=0.1),
    P("Wave_Foam", (4.4, 2.8, -1.3), (1.5, 0.8, 1.0), rgb(255, 255, 255), "Neon", t=0.1),
    P("Wave_Foam", (-8.0, 0.8, -1.2), (1.2, 0.7, 0.9), rgb(255, 255, 255), "Neon", t=0.1),
    P("Wave_Foam", (8.0, 0.8, -1.2), (1.2, 0.7, 0.9), rgb(255, 255, 255), "Neon", t=0.1),
], vfx=True, note="Water Wave: a blocky breaking wave")

_tornado = []
for i in range(8):
    f = i / 7
    w = 2.2 + 7.3 * f
    _tornado.append(
        P("Twister_Layer", (0, -7.8 + i * 2.1, 0), (w, 2.0, w), lerp((190, 215, 210), (235, 248, 245), f),
          "SmoothPlastic", t=0.3, rot=(0, i * 27, 0))
    )
for i, (x, y, z) in enumerate([(4.8, -2.0, 1.0), (-4.6, 1.5, -2.0), (3.0, 5.5, 3.6), (-3.2, -5.5, -3.0)]):
    _tornado.append(P("Twister_Debris", (x, y, z), (0.9, 0.7, 0.9), rgb(110, 96, 80), "Slate",
                      rot=(20 * i, 30 * i, 10)))
model("Tornado", _tornado, vfx=True, note="Tornado twister of stacked, turning slabs")

# ---------------------------------------------------------------- scenery
LEAF = (64, 160, 72)
model("TreeOak", [
    P("Trunk", (0, 3.0, 0), (1.7, 6.0, 1.7), rgb(110, 80, 56), "Wood", collide=True),
    P("TreeRoot", (1.1, 0.4, 0.2), (1.0, 0.8, 0.9), rgb(110, 80, 56), "Wood", rot=(0, 20, 0), collide=False),
    P("TreeRoot", (-1.0, 0.4, -0.4), (0.9, 0.8, 1.0), rgb(110, 80, 56), "Wood", rot=(0, -20, 0), collide=False),
    P("Leaves", (0, 7.4, 0), (7.4, 3.2, 7.4), lerp(LEAF, (40, 130, 60), 0.4), "Grass", collide=False),
    P("Leaves", (0.6, 10.0, -0.3), (5.6, 3.0, 5.6), LEAF, "Grass", rot=(0, 15, 0), collide=False),
    P("Leaves", (-0.4, 12.2, 0.4), (3.6, 2.6, 3.6), lerp(LEAF, (110, 200, 100), 0.3), "Grass", rot=(0, 35, 0),
      collide=False),
    P("Leaves", (3.4, 7.0, 1.4), (3.2, 2.6, 3.2), LEAF, "Grass", rot=(0, 25, 0), collide=False),
    P("Leaves", (-3.3, 7.8, -1.2), (3.4, 2.6, 3.0), LEAF, "Grass", rot=(0, -20, 0), collide=False),
], solid=True, base=True, note="Oak tree: round block canopy")

PINE = (36, 110, 70)
model("TreePine", [
    P("Trunk", (0, 2.2, 0), (1.5, 4.4, 1.5), rgb(96, 70, 50), "Wood", collide=True),
    P("Needles", (0, 4.6, 0), (8.0, 2.0, 8.0), PINE, "Grass", collide=False),
    P("Needles", (0, 6.4, 0), (6.4, 2.0, 6.4), lerp(PINE, (60, 140, 90), 0.3), "Grass", rot=(0, 20, 0), collide=False),
    P("Needles", (0, 8.2, 0), (4.8, 2.0, 4.8), PINE, "Grass", rot=(0, 40, 0), collide=False),
    P("Needles", (0, 10.0, 0), (3.2, 2.0, 3.2), lerp(PINE, (60, 140, 90), 0.3), "Grass", rot=(0, 10, 0),
      collide=False),
    P("Needles", (0, 11.7, 0), (1.5, 1.8, 1.5), PINE, "Grass", rot=(0, 45, 0), collide=False),
], solid=True, base=True, note="Pine tree: stacked tiers")

model("TreeBirch", [
    P("Trunk", (0, 3.4, 0), (1.3, 6.8, 1.3), rgb(240, 236, 226), "SmoothPlastic", collide=True),
    P("Bark", (0, 1.8, 0), (1.34, 0.4, 1.34), rgb(40, 40, 44), "SmoothPlastic", collide=False),
    P("Bark", (0, 3.8, 0), (1.34, 0.35, 1.34), rgb(40, 40, 44), "SmoothPlastic", collide=False),
    P("Bark", (0, 5.6, 0), (1.34, 0.4, 1.34), rgb(40, 40, 44), "SmoothPlastic", collide=False),
    P("Leaves", (0, 8.0, 0), (5.8, 2.8, 5.8), rgb(140, 200, 90), "Grass", collide=False),
    P("Leaves", (0.3, 10.2, 0.2), (4.2, 2.6, 4.2), rgb(160, 214, 104), "Grass", rot=(0, 25, 0), collide=False),
    P("Leaves", (-0.2, 12.0, -0.2), (2.4, 2.0, 2.4), rgb(176, 224, 120), "Grass", rot=(0, 45, 0), collide=False),
], solid=True, base=True, note="Birch tree: white trunk, bright canopy")

model("Cactus", [
    P("Cactus", (0, 4.5, 0), (1.9, 9.0, 1.9), rgb(80, 150, 80), "Grass", collide=True),
    P("CactusArm", (1.6, 5.2, 0), (1.5, 0.9, 1.0), rgb(80, 150, 80), "Grass", collide=False),
    P("CactusArm", (2.2, 6.4, 0), (0.9, 2.6, 1.0), rgb(90, 162, 90), "Grass", collide=False),
    P("CactusArm", (-1.5, 3.4, 0), (1.3, 0.9, 1.0), rgb(80, 150, 80), "Grass", collide=False),
    P("CactusArm", (-2.0, 4.4, 0), (0.9, 2.0, 1.0), rgb(90, 162, 90), "Grass", collide=False),
    P("CactusFlower", (0, 9.2, 0), (0.7, 0.5, 0.7), rgb(255, 120, 160), "Neon", collide=False),
], solid=True, base=True, note="Desert cactus")

# ---------------------------------------------------------------- the wand
# Every player's wand (WandService welds it to the right hand). The grip is at
# the origin and the wand points forward (-Z). The crystal `Tip`, its `TipGlow`
# halo and the `Rune` inlays are tinted with the player's element colour in
# game; the wood and gold keep their colours.
WAND_DARK = rgb(92, 58, 38)
WAND_WOOD = rgb(150, 100, 62)
WAND_GOLD = rgb(216, 166, 52)
model("Wand", [
    P("Pommel", (0, 0, 0.62), (0.42, 0.42, 0.42), WAND_GOLD, "SmoothPlastic", shape="Ball"),
    P("Grip", (0, 0, 0.05), (0.36, 0.36, 1.1), WAND_DARK, "Wood"),
    P("GripWrap", (0, 0, 0.25), (0.4, 0.4, 0.12), rgb(60, 36, 24), "Fabric"),
    P("GripWrap", (0, 0, -0.1), (0.4, 0.4, 0.12), rgb(60, 36, 24), "Fabric"),
    P("Band", (0, 0, -0.55), (0.44, 0.44, 0.14), WAND_GOLD, "SmoothPlastic"),
    P("Shaft", (0, 0, -1.55), (0.26, 0.26, 1.9), WAND_WOOD, "Wood"),
    P("Rune", (0, 0.135, -1.3), (0.1, 0.02, 0.5), rgb(255, 255, 255), "Neon"),
    P("Rune", (0, 0.135, -1.95), (0.1, 0.02, 0.3), rgb(255, 255, 255), "Neon"),
    P("Band", (0, 0, -2.55), (0.36, 0.36, 0.14), WAND_GOLD, "SmoothPlastic"),
    P("Prong", (0.16, 0, -2.78), (0.08, 0.08, 0.4), WAND_GOLD, "SmoothPlastic", rot=(0, -12, 0)),
    P("Prong", (-0.16, 0, -2.78), (0.08, 0.08, 0.4), WAND_GOLD, "SmoothPlastic", rot=(0, 12, 0)),
    P("Prong", (0, 0.16, -2.78), (0.08, 0.08, 0.4), WAND_GOLD, "SmoothPlastic", rot=(12, 0, 0)),
    P("Prong", (0, -0.16, -2.78), (0.08, 0.08, 0.4), WAND_GOLD, "SmoothPlastic", rot=(-12, 0, 0)),
    P("Tip", (0, 0, -3.0), (0.34, 0.34, 0.34), rgb(255, 255, 255), "Neon", rot=(45, 45, 0)),
    P("TipGlow", (0, 0, -3.0), (0.62, 0.62, 0.62), rgb(255, 255, 255), "Neon", t=0.65, shape="Ball"),
], note="Every player's wand: grip at the origin, pointing forward (-Z); Tip, TipGlow and Rune take the element colour")

# ---------------------------------------------------------------- props
model("TrainingDummy", [
    P("Foot", (0, 0.25, 0), (3.4, 0.5, 3.4), rgb(120, 86, 56), "Wood", collide=True),
    P("Foot", (0, 0.65, 0), (2.4, 0.3, 2.4), rgb(140, 102, 66), "Wood", collide=True),
    P("Pole", (0, 1.9, 0), (0.8, 2.4, 0.8), rgb(120, 86, 56), "Wood", collide=True),
    P("Body", (0, 4.6, 0), (3.0, 3.4, 1.8), rgb(224, 184, 110), "Fabric", collide=True),
    P("Stitch", (0, 4.6, -0.92), (0.2, 3.0, 0.06), rgb(120, 86, 56), "Fabric", collide=False),
    P("Arms", (0, 5.6, 0), (5.6, 0.8, 0.9), rgb(140, 102, 66), "Wood", collide=True),
    P("Hand", (2.9, 5.6, 0), (0.8, 1.0, 1.0), rgb(224, 184, 110), "Fabric", collide=False),
    P("Hand", (-2.9, 5.6, 0), (0.8, 1.0, 1.0), rgb(224, 184, 110), "Fabric", collide=False),
    P("Head", (0, 7.4, 0), (2.2, 2.2, 2.2), rgb(236, 204, 140), "Fabric", collide=True),
    P("TargetRing", (0, 4.7, -0.95), (2.2, 2.2, 0.08), rgb(220, 50, 50), "SmoothPlastic", collide=False),
    P("TargetRing", (0, 4.7, -1.0), (1.5, 1.5, 0.08), rgb(255, 255, 255), "SmoothPlastic", collide=False),
    P("TargetRing", (0, 4.7, -1.05), (0.8, 0.8, 0.08), rgb(220, 50, 50), "SmoothPlastic", collide=False),
    P("Eye", (-0.5, 7.6, -1.12), (0.4, 0.4, 0.06), rgb(30, 30, 30), "SmoothPlastic", collide=False),
    P("Eye", (0.5, 7.6, -1.12), (0.4, 0.4, 0.06), rgb(30, 30, 30), "SmoothPlastic", collide=False),
    P("Mouth", (0, 7.0, -1.12), (1.0, 0.18, 0.06), rgb(30, 30, 30), "SmoothPlastic", collide=False),
    P("Cap", (0, 8.6, 0), (2.4, 0.5, 2.4), rgb(200, 60, 50), "Fabric", collide=False),
], solid=True, base=True, note="Straw training dummy on a post (parts Body and Head are the hit parts)")

CRATE_WOOD = rgb(140, 92, 52)
GOLD = rgb(216, 166, 52)
CYAN = rgb(76, 216, 255)


def crate_parts(open_lid):
    parts = [
        P("Crate_Body", (0, -0.4, 0), (3.8, 3.2, 3.8), CRATE_WOOD, "WoodPlanks", collide=True),
        P("Crate_Trim", (0, -1.55, 0), (4.0, 0.5, 4.0), GOLD, "Metal", collide=False),
        P("Crate_Trim", (0, 0.2, 0), (4.0, 0.4, 4.0), GOLD, "Metal", collide=False),
    ]
    for x in (-1.9, 1.9):
        for z in (-1.9, 1.9):
            parts.append(P("Crate_Trim", (x, -0.4, z), (0.5, 3.4, 0.5), GOLD, "Metal", collide=False))
    if not open_lid:
        parts.append(P("Crate_Lid", (0, 1.6, 0), (4.0, 1.0, 4.0), rgb(120, 78, 44), "WoodPlanks", collide=True))
        parts.append(P("Crate_Trim", (0, 2.15, 0), (4.1, 0.2, 1.0), GOLD, "Metal", collide=False))
        parts.append(P("Crate_Gem", (0, 0.9, -2.0), (0.9, 0.9, 0.3), CYAN, "Neon", rot=(0, 0, 45),
                       collide=False))
    else:
        parts.append(P("Crate_Lid", (0, 3.2, 2.2), (4.0, 0.5, 3.6), rgb(120, 78, 44), "WoodPlanks",
                       rot=(-100, 0, 0), collide=False))
        parts.append(P("Crate_Glow", (0, 1.25, 0), (3.2, 0.3, 3.2), rgb(255, 235, 150), "Neon", collide=False))
        parts.append(P("Crate_Gem", (0.8, 2.4, -0.4), (0.7, 0.7, 0.7), CYAN, "Neon", rot=(20, 45, 20),
                       collide=False))
        parts.append(P("Crate_Gem", (-0.9, 2.9, 0.5), (0.55, 0.55, 0.55), rgb(255, 120, 200), "Neon",
                       rot=(30, 10, 40), collide=False))
        parts.append(P("Crate_Gem", (0.1, 3.5, 0.0), (0.45, 0.45, 0.45), rgb(255, 235, 120), "Neon",
                       rot=(10, 30, 10), collide=False))
    return parts


model("ElementCrate", crate_parts(False), solid=True,
      note="Element Crate: wooden crate with gold trim and a gem (Crate_Trim and Crate_Gem are tinted per use)")
model("ElementCrateOpen", crate_parts(True), solid=False,
      note="The Element Crate with its lid thrown back and treasure glowing inside (crate reveal)")


def chest_parts(open_lid):
    wood = rgb(125, 84, 48)
    gold = rgb(255, 200, 60)
    parts = [
        P("Chest_Body", (0, 1.4, 0), (6.0, 2.8, 4.0), wood, "WoodPlanks", collide=True),
        P("Chest_Gold", (0, 0.2, 0), (6.2, 0.4, 4.2), gold, "Metal", collide=False),
        P("Chest_Gold", (-2.6, 1.4, 0), (0.5, 2.9, 4.1), gold, "Metal", collide=False),
        P("Chest_Gold", (2.6, 1.4, 0), (0.5, 2.9, 4.1), gold, "Metal", collide=False),
    ]
    if not open_lid:
        parts.append(P("Chest_Lid", (0, 2.8, 0), (6.0, 4.0, 4.0), wood, "WoodPlanks", shape="Cylinder",
                       collide=True))
        parts.append(P("Chest_Gold", (-2.6, 2.8, 0), (0.6, 4.2, 4.2), gold, "Metal", shape="Cylinder",
                       collide=False))
        parts.append(P("Chest_Gold", (2.6, 2.8, 0), (0.6, 4.2, 4.2), gold, "Metal", shape="Cylinder",
                       collide=False))
        parts.append(P("Chest_Lock", (0, 2.7, -2.1), (1.0, 1.3, 0.3), gold, "Neon", collide=False))
    else:
        parts.append(P("Chest_Lid", (0, 4.4, 2.6), (6.0, 4.0, 4.0), wood, "WoodPlanks", shape="Cylinder",
                       rot=(-115, 0, 0), collide=False))
        parts.append(P("Chest_Glow", (0, 2.85, 0), (5.2, 0.3, 3.2), rgb(255, 230, 120), "Neon", collide=False))
        for i, (x, z) in enumerate([(-1.6, -0.5), (0.2, 0.7), (1.7, -0.2), (-0.4, -0.9)]):
            parts.append(P("Chest_Coin", (x, 3.2 + 0.15 * i, z), (1.0, 0.18, 1.0), gold, "Neon",
                           rot=(0, 20 * i, 6 * i), collide=False))
    return parts


model("QuestChest", chest_parts(False), solid=True, base=True,
      note="Daily Quests treasure chest: wooden, with gold bands and a lock")
model("QuestChestOpen", chest_parts(True), solid=False, base=True,
      note="The Daily Quests chest thrown open with coins glowing inside (quest rewards)")

STONE = rgb(158, 158, 170)
STONE_DARK = rgb(112, 112, 124)
model("WizardStatue", [
    P("Plinth", (0, 0.6, 0), (10.0, 1.2, 10.0), STONE_DARK, "Slate", collide=True),
    P("Plinth", (0, 1.7, 0), (8.0, 1.0, 8.0), STONE, "Slate", collide=True),
    P("Plinth_Rune", (0, 2.25, 0), (6.0, 0.12, 6.0), rgb(124, 92, 255), "Neon", rot=(0, 45, 0), collide=False),
    P("Robe", (0, 4.2, 0), (5.2, 3.0, 4.2), STONE, "Slate", collide=True),
    P("Robe", (0, 7.0, 0), (4.6, 2.8, 3.8), STONE, "Slate", collide=True),
    P("Robe", (0, 9.6, 0), (4.0, 2.6, 3.4), STONE, "Slate", collide=True),
    P("Shoulders", (0, 11.4, 0), (5.2, 1.2, 3.2), STONE, "Slate", collide=True),
    P("Belt", (0, 7.5, 0), (4.8, 0.5, 4.0), rgb(216, 166, 52), "Metal", collide=False),
    P("Arm", (-3.2, 9.8, -0.6), (1.3, 3.4, 1.3), STONE, "Slate", rot=(-25, 0, 8), collide=False),
    P("Arm", (3.0, 11.6, -1.0), (1.3, 3.2, 1.3), STONE, "Slate", rot=(-35, 0, -10), collide=False),
    P("Hand", (3.1, 13.3, -1.7), (1.4, 1.3, 1.4), STONE, "Slate", collide=False),
    P("Staff", (3.1, 12.6, -1.7), (0.6, 13.0, 0.6), rgb(120, 86, 56), "Wood", collide=False),
    P("Staff_Orb", (3.1, 19.6, -1.7), (1.8, 1.8, 1.8), rgb(120, 210, 255), "Neon", rot=(0, 45, 45),
      collide=False),
    P("Staff_Claw", (3.1, 18.7, -1.7), (1.3, 0.5, 1.3), rgb(216, 166, 52), "Metal", collide=False),
    P("Head", (0, 13.1, 0), (2.4, 2.4, 2.4), STONE, "Slate", collide=True),
    P("Beard", (0, 11.9, -1.15), (1.6, 1.8, 0.7), STONE, "Slate", collide=False),
    P("Beard", (0, 10.9, -1.1), (1.0, 1.4, 0.6), STONE, "Slate", collide=False),
    P("Hat_Brim", (0, 14.4, 0), (5.2, 0.5, 5.2), STONE, "Slate", collide=False),
    P("Hat", (0, 15.4, 0), (3.6, 1.6, 3.6), STONE, "Slate", collide=False),
    P("Hat", (0, 16.9, 0), (2.7, 1.6, 2.7), STONE, "Slate", rot=(0, 20, 0), collide=False),
    P("Hat", (0.2, 18.3, 0), (1.9, 1.4, 1.9), STONE, "Slate", rot=(0, 40, 0), collide=False),
    P("Hat_Tip", (0.9, 19.5, 0), (1.1, 1.3, 1.1), STONE, "Slate", rot=(0, 20, -25), collide=False),
    P("Hat_Star", (0, 15.2, -1.85), (0.9, 0.9, 0.2), rgb(255, 224, 80), "Neon", rot=(0, 0, 45), collide=False),
], solid=True, base=True, note="Stone wizard statue for the center of the arena (staff orb glows)")


# ---------------------------------------------------------------- portals
def portal(ring_stone, ring_trim, glow, layers):
    """A big octagonal stone gateway with a swirling portal in it, in the given palette. The model faces -Z,
    stands on y = 0, and the opening (about 24 studs wide) is open at the bottom to walk
    through. The hub tags an invisible trigger over the opening (see Maps/InkwellPlaza)."""
    gold = rgb(216, 166, 52)
    cy, a, t, depth = 15.5, 12.0, 3.0, 4.0  # ring centre height, inner apothem, thickness, depth
    mid = a + t / 2
    length = 2 * mid * math.tan(math.radians(22.5)) + 0.8
    parts = [
        P("Base", (0, 0.6, 0), (50, 1.2, 18), ring_trim, "Slate", collide=True),
        P("Base", (0, 1.4, 0), (42, 0.5, 14), ring_stone, "Slate", collide=True),
        P("Base_Rune", (0, 1.7, -4.5), (0.15, 9, 9), glow, "Neon", rot=(0, 0, 90), shape="Cylinder",
          collide=False),
    ]
    # Seven of the eight ring segments; the bottom one is left out so you can walk through.
    for k in (0, 1, 2, 3, 5, 6, 7):
        phi = k * 45.0
        x = mid * math.sin(math.radians(phi))
        y = cy + mid * math.cos(math.radians(phi))
        parts.append(P("Ring", (round(x, 3), round(y, 3), 0), (round(length, 3), t, depth), ring_stone,
                       "Slate", rot=(0, 0, -phi), collide=True))
        for z in (-(depth / 2 + 0.05), depth / 2 + 0.05):
            parts.append(P("Ring_Rune", (round(x, 3), round(y, 3), z),
                           (round(length * 0.55, 3), round(t * 0.3, 3), 0.15), glow, "Neon",
                           rot=(0, 0, -phi), collide=False))
    # Keystone and gold trim over the top.
    parts += [
        P("Keystone", (0, cy + a + t + 0.8, 0), (5.0, 2.2, depth + 1), gold, "Metal", collide=True),
        P("Keystone_Gem", (0, cy + a + t + 0.8, -(depth / 2 + 0.7)), (1.6, 1.6, 0.3), glow, "Neon",
          rot=(0, 0, 45), collide=False),
    ]
    # A tall pylon with a floating crystal on each side.
    for side in (-1, 1):
        px = side * (a + t + 5.5)
        parts += [
            P("Pylon", (px, 5.5, 0), (5.0, 9.0, 5.0), ring_stone, "Slate", collide=True),
            P("Pylon", (px, 11.5, 0), (3.6, 3.0, 3.6), ring_trim, "Slate", collide=True),
            P("Pylon_Band", (px, 8.0, 0), (5.2, 0.6, 5.2), gold, "Metal", collide=False),
            P("Pylon_Crystal", (px, 16.5, 0), (2.4, 4.4, 2.4), glow, "Neon", rot=(0, 45, 0), collide=False),
        ]
    # The portal itself: stacked, glowing discs, brighter toward the middle.
    for index, (diameter, color, transparency) in enumerate(layers):
        parts.append(P("Portal_Swirl", (0, cy, round(index * 0.12, 2)), (0.25, diameter, diameter), color,
                       "Neon", t=transparency, rot=(0, 90, 0), shape="Cylinder", collide=False))
    return parts


model("BattlegroundPortal",
      portal(rgb(88, 92, 122), rgb(62, 66, 94), rgb(90, 180, 255),
             [(23, rgb(40, 110, 255), 0.5), (19, rgb(70, 150, 255), 0.45), (15, rgb(120, 200, 255), 0.4),
              (11, rgb(190, 235, 255), 0.35), (6, rgb(255, 255, 255), 0.3)]),
      solid=True, base=True,
      note="Big stone portal gateway with a swirling blue portal: the hub's way into the Battleground")
model("ArenaPortal",
      portal(rgb(122, 80, 88), rgb(94, 58, 66), rgb(255, 96, 96),
             [(23, rgb(210, 30, 50), 0.5), (19, rgb(235, 60, 70), 0.45), (15, rgb(255, 110, 100), 0.4),
              (11, rgb(255, 190, 170), 0.35), (6, rgb(255, 245, 235), 0.3)]),
      solid=True, base=True,
      note="The Arena Gate: the same stone portal in red, at the north end of the hub")


# ---------------------------------------------------------------- outputs
MATERIAL_ENUMS = {
    "SmoothPlastic", "Neon", "Glass", "Slate", "Wood", "WoodPlanks", "Grass", "Metal", "Fabric",
}


def luau_number(value):
    text = f"{value:.3f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def write_luau(repo):
    lines = [
        "--!strict",
        "-- GENERATED by tools/blender/block_models.py: do not edit by hand. Edit the spec there and",
        "-- rerun `python tools/blender/block_models.py --luau .`.",
        "--",
        "-- The classic-Roblox blocky models (spell effects, trees, the training dummy, crates, the",
        "-- quest chest, the wizard statue) as plain data. ModelKit builds each one from Parts, so",
        "-- they exist in every place without importing meshes. Blender builds the same models from",
        "-- the same spec for the FBX/blend sources (assets/models/blocks).",
        "--   n name  p position  s size  c color  m material  t transparency  r rotation (degrees,",
        "--   YXZ)  sh shape (Ball | Cylinder)  k collides (omitted: follows the model's `solid`)",
        "-- Coordinates are studs, y up, forward = -Z; `base` models stand on y = 0.",
        "",
        "export type BlockPart = {",
        "\tn: string,",
        "\tp: { number },",
        "\ts: { number },",
        "\tc: { number },",
        "\tm: string,",
        "\tt: number?,",
        "\tr: { number }?,",
        "\tsh: string?,",
        "\tk: boolean?,",
        "}",
        "",
        "export type BlockModel = {",
        "\tparts: { BlockPart },",
        "\tvfx: boolean,",
        "\tsolid: boolean,",
        "\tbase: boolean,",
        "\tnote: string,",
        "}",
        "",
        "-- stylua: ignore start",
        "local Models: { [string]: BlockModel } = {",
    ]
    for name, m in MODELS.items():
        lines.append(f"\t{name} = {{")
        lines.append(f"\t\tvfx = {str(m['vfx']).lower()}, solid = {str(m['solid']).lower()}, "
                     f"base = {str(m['base']).lower()},")
        note = m["note"].replace('"', "'")
        lines.append(f'\t\tnote = "{note}",')
        lines.append("\t\tparts = {")
        for part in m["parts"]:
            assert part["mat"] in MATERIAL_ENUMS, part["mat"]
            fields = [
                f'n = "{part["name"]}"',
                "p = {" + ", ".join(luau_number(v) for v in part["pos"]) + "}",
                "s = {" + ", ".join(luau_number(v) for v in part["size"]) + "}",
                "c = {" + ", ".join(str(v) for v in part["color"]) + "}",
                f'm = "{part["mat"]}"',
            ]
            if part["t"]:
                fields.append(f"t = {luau_number(part['t'])}")
            if part["rot"]:
                fields.append("r = {" + ", ".join(luau_number(v) for v in part["rot"]) + "}")
            if part["shape"] != "Block":
                fields.append(f'sh = "{part["shape"]}"')
            if part["collide"] is not None:
                fields.append(f"k = {str(part['collide']).lower()}")
            lines.append("\t\t\t{ " + ", ".join(fields) + " },")
        lines.append("\t\t},")
        lines.append("\t},")
    lines += ["}", "-- stylua: ignore end", "", "return table.freeze(Models)", ""]
    path = os.path.join(repo, "src", "shared", "Models", "BlockModels.luau")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as handle:
        handle.write("\n".join(lines))
    return path


# ---------------------------------------------------------------- Blender
def blender_build(repo):
    import bpy
    from mathutils import Matrix

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 0.01
    scene.unit_settings.length_unit = "CENTIMETERS"

    # Roblox (x right, y up, z back) -> Blender (x right, y forward, z up).
    to_blender = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))

    def rotation(rot):
        rx, ry, rz = (math.radians(v) for v in rot)

        def axis(angle, kind):
            c, s = math.cos(angle), math.sin(angle)
            if kind == "x":
                return Matrix(((1, 0, 0), (0, c, -s), (0, s, c)))
            if kind == "y":
                return Matrix(((c, 0, s), (0, 1, 0), (-s, 0, c)))
            return Matrix(((c, -s, 0), (s, c, 0), (0, 0, 1)))

        return axis(ry, "y") @ axis(rx, "x") @ axis(rz, "z")

    materials = {}

    def material_for(color, t):
        key = (color, round(t, 2))
        if key not in materials:
            mat = bpy.data.materials.new(f"Block_{color[0]}_{color[1]}_{color[2]}_{int(t * 100)}")
            mat.diffuse_color = (color[0] / 255, color[1] / 255, color[2] / 255, 1 - t)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = mat.diffuse_color
                if t > 0:
                    bsdf.inputs["Alpha"].default_value = 1 - t
            materials[key] = mat
        return materials[key]

    # Start from an empty scene.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col)

    out_dir = os.path.join(repo, "assets", "models", "blocks")
    os.makedirs(out_dir, exist_ok=True)
    offset_x = 0.0
    exported = {}
    for name, m in MODELS.items():
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
        objs = []
        for index, part in enumerate(m["parts"]):
            if part["shape"] == "Ball":
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=16, ring_count=8)
            elif part["shape"] == "Cylinder":
                bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.0, vertices=16)
            else:
                bpy.ops.mesh.primitive_cube_add(size=1)
            obj = bpy.context.active_object
            obj.name = part["name"]
            sx, sy, sz = part["size"]
            if part["shape"] == "Cylinder":
                # Roblox cylinders run along X; Blender's primitive runs along Z.
                obj.rotation_euler = (0, math.pi / 2, 0)
                bpy.ops.object.transform_apply(rotation=True)
                dims = (sx, sy, sz)
            else:
                dims = (sx, sy, sz)
            # Size in Roblox axes (x, y, z) -> Blender object scale (x, z->y, y->z) on a unit mesh.
            obj.scale = (dims[0] * STUD, dims[2] * STUD, dims[1] * STUD)
            bpy.ops.object.transform_apply(scale=True)
            px, py, pz = part["pos"]
            rot = rotation(part["rot"] or (0, 0, 0))
            matrix = to_blender @ rot @ to_blender.inverted()
            obj.rotation_euler = matrix.to_euler()
            obj.location = (px * STUD, -pz * STUD, py * STUD)
            obj.data.materials.append(material_for(part["color"], part["t"]))
            for c in list(obj.users_collection):
                c.objects.unlink(obj)
            col.objects.link(obj)
            objs.append(obj)
        exported[name] = (col, objs)

    # Export each model centered on the origin, then lay them out in a row.
    for name, (col, objs) in exported.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        path = os.path.join(out_dir, f"{name}.fbx")
        bpy.ops.export_scene.fbx(
            filepath=path,
            use_selection=True,
            object_types={"MESH"},
            apply_unit_scale=True,
            apply_scale_options="FBX_SCALE_UNITS",
            axis_forward="-Z",
            axis_up="Y",
            mesh_smooth_type="FACE",
            add_leaf_bones=False,
            bake_anim=False,
        )
    # Lay out for the .blend so the models can be looked at side by side.
    bpy.context.view_layer.update()
    for name, (col, objs) in exported.items():
        width = max((o.dimensions.x for o in objs), default=0)
        for o in objs:
            o.location.x += offset_x
        offset_x += width + 4 * STUD
    blend = os.path.join(repo, "assets", "models", "source", "BlockModels.blend")
    os.makedirs(os.path.dirname(blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend, copy=True)
    return list(exported)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    repo = next((a for a in args if not a.startswith("--")), os.getcwd())
    if "--luau" in args:
        print(write_luau(repo))
    else:
        print(write_luau(repo))
        print(blender_build(repo))
