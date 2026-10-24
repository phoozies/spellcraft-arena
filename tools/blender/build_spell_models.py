# Builds the crate-spell models (Gust, Zap, Heal, BlackHole, Turret) and the
# shop Crate in Blender, then exports each to assets/models/<Name>.fbx.
#
# Run it through the Blender MCP (execute_blender_code) or with
#   blender --background --python tools/blender/build_spell_models.py -- <repo>
#
# Scene units are set up for Roblox Studio: metric, unit scale 0.01, length
# in centimeters, so 1 Blender unit = 1 cm and FBX files carry centimeters
# (Studio's importer reads them at the right size). Sizes below use
# 1 stud = 28 cm, so imports land close to game size; tools/prepare-models.luau
# still rescales each model to its exact target size.
#
# Object names are a contract: tools/prepare-models.luau colours parts by
# name and tests/Models.spec.luau checks them. Each model lives in its own
# collection named after the model. Orientation: Blender +Z becomes Roblox
# up (+Y) and Blender +Y becomes Roblox forward (-Z, a part's LookVector).

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

STUD = 28.0  # cm

# rgba base colours (prepare-models applies the final Roblox colours).
COLORS = {
    "Gust_Swirl": (0.86, 0.94, 1.0, 1),
    "Gust_Core": (1.0, 1.0, 1.0, 1),
    "Gust_Streaks": (0.70, 0.85, 1.0, 1),
    "Zap_Bolt": (1.0, 0.93, 0.35, 1),
    "Zap_Glow": (0.55, 0.80, 1.0, 1),
    "Heal_Cross": (0.40, 0.73, 0.42, 1),
    "Heal_Ring": (0.78, 1.0, 0.80, 1),
    "BlackHole_Core": (0.02, 0.0, 0.05, 1),
    "BlackHole_Disk": (0.55, 0.20, 0.95, 1),
    "BlackHole_Ring": (1.0, 0.55, 0.20, 1),
    "Turret_Base": (0.27, 0.35, 0.39, 1),
    "Turret_Head": (0.33, 0.43, 0.48, 1),
    "Turret_Barrel": (0.15, 0.15, 0.17, 1),
    "Turret_Lens": (1.0, 0.25, 0.25, 1),
    "Crate_Body": (0.55, 0.36, 0.20, 1),
    "Crate_Trim": (0.85, 0.65, 0.20, 1),
    "Crate_Gem": (0.30, 0.85, 1.0, 1),
}


def setup_units():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 0.01
    scene.unit_settings.length_unit = "CENTIMETERS"
    # Grid/clip sized for centimeter-scale objects.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.overlay.grid_scale = 0.01
                        space.clip_start = 1
                        space.clip_end = 100000


def material(name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = COLORS[name]
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = COLORS[name]
    return mat


def collection(name):
    old = bpy.data.collections.get(name)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def finish(obj, col, name, smooth=True):
    obj.name = name
    obj.data.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    obj.data.materials.clear()
    obj.data.materials.append(material(name))
    if smooth and hasattr(obj.data, "polygons"):
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def apply_all(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def mesh_from_bmesh(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tube_along(points, radius, name, segments=8):
    """A tube (curve with bevel) through 3D points, converted to a mesh."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, p in enumerate(points):
        spline.points[i].co = (p[0], p[1], p[2], 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    out = bpy.context.view_layer.objects.active
    out.name = name
    return out


# ---------------------------------------------------------------- Gust
def build_gust():
    col = collection("Gust")
    r = 3.5 * STUD  # ~7 stud wide gust
    # Swirl: a cone-shaped spiral ribbon opening forward (+Y).
    pts = []
    turns = 3.0
    steps = 90
    for i in range(steps + 1):
        t = i / steps
        a = t * turns * 2 * math.pi
        rad = r * (0.25 + 0.75 * t)
        pts.append((math.cos(a) * rad, (t - 0.5) * r * 1.6, math.sin(a) * rad))
    swirl = tube_along(pts, 0.09 * STUD * 3, "Gust_Swirl")
    finish(swirl, col, "Gust_Swirl")
    # Core: soft puff at the center.
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r * 0.35)
    core = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(core.data)
    for v in bm.verts:  # lumpy cloud
        n = 1 + 0.12 * math.sin(v.co.x * 0.08) * math.cos(v.co.z * 0.07)
        v.co *= n
    bm.to_mesh(core.data)
    bm.free()
    finish(core, col, "Gust_Core")
    # Streaks: three swept wind lines trailing behind (-Y).
    streaks = []
    for k in range(3):
        a0 = k * 2 * math.pi / 3
        pts = []
        for i in range(25):
            t = i / 24
            a = a0 + t * 1.6
            rad = r * (0.55 + 0.25 * t)
            pts.append((math.cos(a) * rad, -r * 0.3 - t * r * 1.1, math.sin(a) * rad))
        streaks.append(tube_along(pts, 0.07 * STUD * 3, f"Streak{k}"))
    finish(join(streaks, "Gust_Streaks"), col, "Gust_Streaks")
    return col


# ---------------------------------------------------------------- Zap
def build_zap():
    col = collection("Zap")
    h = 22 * STUD  # tall bolt from the sky; prepare-models sets the height
    # Zig-zag lightning bolt as a flat-ish extruded polygon in the XZ plane.
    zig = [
        (0.0, 1.00), (0.10, 0.70), (-0.06, 0.66), (0.14, 0.36),
        (-0.04, 0.32), (0.10, 0.0),
    ]
    width = 0.75 * STUD
    bm = bmesh.new()
    left, right = [], []
    for x, z in zig:
        left.append(bm.verts.new(Vector((x * h * 0.25 - width / 2, 0, z * h))))
        right.append(bm.verts.new(Vector((x * h * 0.25 + width / 2, 0, z * h))))
    for i in range(len(zig) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    # Thickness and a pointed tip at the ground.
    tip = bm.verts.new(Vector((zig[-1][0] * h * 0.25, 0, -0.6 * STUD)))
    bm.faces.new((left[-1], right[-1], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bolt = mesh_from_bmesh("Zap_Bolt", bm)
    mod = bolt.modifiers.new("Thickness", "SOLIDIFY")
    mod.thickness = 0.5 * STUD
    mod.offset = 0
    apply_all(bolt)
    finish(bolt, col, "Zap_Bolt", smooth=False)
    # Glow: a soft glass sleeve around the bolt.
    glow_pts = [(x * h * 0.25, 0, z * h) for x, z in zig]
    glow = tube_along(glow_pts, 0.9 * STUD, "Zap_Glow")
    finish(glow, col, "Zap_Glow")
    return col


# ---------------------------------------------------------------- Heal
def build_heal():
    col = collection("Heal")
    s = 2.5 * STUD
    # Rounded plus sign facing forward (+Y), standing upright.
    bars = []
    for size in ((s * 0.34, s * 0.25, s), (s, s * 0.25, s * 0.34)):
        bpy.ops.mesh.primitive_cube_add(size=1)
        bar = bpy.context.active_object
        bar.scale = size
        bev = bar.modifiers.new("Bevel", "BEVEL")
        bev.width = s * 0.08
        bev.segments = 4
        apply_all(bar)
        bars.append(bar)
    cross = join(bars, "Heal_Cross")
    rem = cross.modifiers.new("Merge", "WELD")
    apply_all(cross)
    finish(cross, col, "Heal_Cross")
    # Ring: a halo around the cross.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=s * 0.78, minor_radius=s * 0.05, major_segments=48, minor_segments=12
    )
    ring = bpy.context.active_object
    ring.rotation_euler = (math.pi / 2, 0, 0)  # face forward like the cross
    apply_all(ring)
    finish(ring, col, "Heal_Ring")
    return col


# ---------------------------------------------------------------- BlackHole
def build_black_hole():
    col = collection("BlackHole")
    r = 3 * STUD
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 0.45, segments=32, ring_count=16)
    core = bpy.context.active_object
    finish(core, col, "BlackHole_Core")
    # Accretion disk: a flattened, slightly tilted torus.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=r * 0.95, minor_radius=r * 0.35, major_segments=64, minor_segments=16
    )
    disk = bpy.context.active_object
    disk.scale = (1, 1, 0.18)
    disk.rotation_euler = (math.radians(12), 0, 0)
    apply_all(disk)
    finish(disk, col, "BlackHole_Disk")
    # Outer ring: thin glowing band, tilted the other way.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=r * 1.45, minor_radius=r * 0.04, major_segments=64, minor_segments=8
    )
    ring = bpy.context.active_object
    ring.rotation_euler = (math.radians(-18), math.radians(10), 0)
    apply_all(ring)
    finish(ring, col, "BlackHole_Ring")
    return col


# ---------------------------------------------------------------- Turret
def build_turret():
    col = collection("Turret")
    # 4 x 5 x 4 studs overall, sitting on z = 0, barrel pointing +Y (forward).
    w = 4 * STUD
    bpy.ops.mesh.primitive_cylinder_add(radius=w * 0.5, depth=1.6 * STUD, vertices=24)
    base = bpy.context.active_object
    base.location = (0, 0, 0.8 * STUD)
    bev = base.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.15 * STUD
    bev.segments = 3
    apply_all(base)
    bpy.ops.object.transform_apply(location=True)
    finish(base, col, "Turret_Base")

    bpy.ops.mesh.primitive_cube_add(size=1)
    head = bpy.context.active_object
    head.scale = (w * 0.72, w * 0.72, 2.0 * STUD)
    head.location = (0, 0, 1.6 * STUD + 1.0 * STUD)
    bev = head.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.3 * STUD
    bev.segments = 4
    apply_all(head)
    bpy.ops.object.transform_apply(location=True)
    finish(head, col, "Turret_Head")

    barrels = []
    for x in (-0.45 * STUD, 0.45 * STUD):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.28 * STUD, depth=2.2 * STUD, vertices=16)
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.pi / 2, 0, 0)  # along Y
        barrel.location = (x, w * 0.36 + 1.0 * STUD, 2.6 * STUD)
        apply_all(barrel)
        bpy.ops.object.transform_apply(location=True)
        barrels.append(barrel)
    finish(join(barrels, "Turret_Barrel"), col, "Turret_Barrel")

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32 * STUD, segments=16, ring_count=8)
    lens = bpy.context.active_object
    lens.location = (0, w * 0.36, 3.35 * STUD)
    bpy.ops.object.transform_apply(location=True)
    finish(lens, col, "Turret_Lens")
    return col


# ---------------------------------------------------------------- Crate
def build_crate():
    col = collection("Crate")
    s = 4 * STUD
    bpy.ops.mesh.primitive_cube_add(size=s * 0.94)
    body = bpy.context.active_object
    bev = body.modifiers.new("Bevel", "BEVEL")
    bev.width = s * 0.03
    bev.segments = 2
    apply_all(body)
    finish(body, col, "Crate_Body", smooth=False)
    # Trim: metal edges + corner caps (a wireframe of a slightly larger cube).
    bpy.ops.mesh.primitive_cube_add(size=s)
    trim = bpy.context.active_object
    wire = trim.modifiers.new("Wire", "WIREFRAME")
    wire.thickness = s * 0.08
    wire.use_even_offset = True
    apply_all(trim)
    finish(trim, col, "Crate_Trim", smooth=False)
    # Gem on the front face (+Y).
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=s * 0.16)
    gem = bpy.context.active_object
    gem.scale = (1, 0.55, 1)
    gem.location = (0, s * 0.5 + s * 0.02, 0)
    apply_all(gem)
    bpy.ops.object.transform_apply(location=True)
    finish(gem, col, "Crate_Gem", smooth=False)
    return col


BUILDERS = {
    "Gust": build_gust,
    "Zap": build_zap,
    "Heal": build_heal,
    "BlackHole": build_black_hole,
    "Turret": build_turret,
    "Crate": build_crate,
}


def lay_out():
    """Spread the collections along X so they're easy to look at."""
    x = 0.0
    for name in BUILDERS:
        col = bpy.data.collections[name]
        objs = list(col.objects)
        bpy.context.view_layer.update()
        width = 0.0
        for o in objs:
            width = max(width, max(o.dimensions.x, o.dimensions.y))
        for o in objs:
            o.location.x += x
        col["layout_offset_x"] = x
        x += width + 3 * STUD


def export(repo):
    out_dir = os.path.join(repo, "assets", "models")
    paths = {}
    for name in BUILDERS:
        col = bpy.data.collections[name]
        offset = col.get("layout_offset_x", 0.0)
        bpy.ops.object.select_all(action="DESELECT")
        for o in col.objects:
            o.location.x -= offset  # export each model centered on the origin
            o.select_set(True)
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
        for o in col.objects:
            o.location.x += offset
        paths[name] = path
    return paths


def _viewport_override():
    """Operators need a 3D-viewport context when run from an add-on server
    (the Blender MCP) rather than from a click in the UI."""
    wm = bpy.context.window_manager
    for window in wm.windows if wm else []:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                region = next(r for r in area.regions if r.type == "WINDOW")
                return {"window": window, "area": area, "region": region}
    return None


def main(repo, save_blend=True):
    override = _viewport_override()
    if override and bpy.context.area is None:
        with bpy.context.temp_override(**override):
            return _main(repo, save_blend)
    return _main(repo, save_blend)


def _main(repo, save_blend=True):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    setup_units()
    for builder in BUILDERS.values():
        builder()
    lay_out()
    paths = export(repo)
    if save_blend:
        blend = os.path.join(repo, "assets", "models", "source", "SpellModels.blend")
        os.makedirs(os.path.dirname(blend), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=blend, copy=True)
        paths["blend"] = blend
    return paths


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    print(main(argv[0] if argv else os.getcwd()))
