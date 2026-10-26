"""Shared helpers for the field-dressing generator scripts in this folder.

Run the generators with Blender in background mode (paths relative to the
repo root), props first, since both layouts link their meshes from it:

    blender -b --python assets/blender/scripts/build_park_props.py
    blender -b --python assets/blender/scripts/build_park_oval.py
    blender -b assets/blender/field.blend --python assets/blender/scripts/build_oval1_layout.py

Everything here is low-poly and flat-shaded on purpose. The two reference
images are pixel art, and the 3D read of that is chunky faceted blobs with a
few single-colour "pixel" cubes for flowers, fruit and berries, plus no
textures. It matches the faceted trees already in newbasictrees.blend.

Axes: Blender (x, y, z) exports to Godot (x, z, -y). So Blender +Y is north,
the top of both reference images, and Godot -Z.
"""

import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.dirname(HERE)
REPO_DIR = os.path.dirname(os.path.dirname(BLENDER_DIR))
IMPORTED_DIR = os.path.join(REPO_DIR, "assets", "imported")
PROPS_BLEND = os.path.join(BLENDER_DIR, "park_props.blend")

# Tuning.FIELD_HALF_LENGTH / FIELD_HALF_WIDTH plus field.blend's 9 m
# REF_Fence offset: the wooden fence ellipse both ovals share.
FENCE_A = 91.5
FENCE_B = 76.5


# ── Colour ───────────────────────────────────────────────────────────

def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_linear(hex_colour):
    h = hex_colour.lstrip("#")
    return tuple(_srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def material(name, hex_colour, roughness=0.95, emission=0.0):
    """A flat Principled material. Reused by name, so re-running a script
    updates colours in place instead of piling up Material.001s."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        nodes.clear()
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        out = nodes.new("ShaderNodeOutputMaterial")
        m.node_tree.links.new(bsdf.outputs[0], out.inputs[0])
    rgb = hex_linear(hex_colour)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    m.diffuse_color = (*rgb, 1.0)
    return m


# ── Mesh building ────────────────────────────────────────────────────

class MeshBuilder:
    """Accumulates primitives into one bmesh, one material slot per
    distinct material. A prop is one mesh with a few slots, so in Godot it
    batches into one MultiMesh with a draw call per colour."""

    def __init__(self):
        self.bm = bmesh.new()
        self.materials = []

    def _tag(self, verts, mat):
        if mat not in self.materials:
            self.materials.append(mat)
        index = self.materials.index(mat)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = index

    def box(self, centre, size, mat, rot=(0.0, 0.0, 0.0)):
        m = (Matrix.Translation(Vector(centre)) @ Euler(rot).to_matrix().to_4x4()
             @ Matrix.Diagonal((*size, 1.0)))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._tag(r["verts"], mat)

    def blob(self, centre, radius, mat, squash=(1.0, 1.0, 1.0), rng=None, jitter=0.12,
             subdivisions=1):
        """A faceted icosphere, nudged per vertex so a cluster of them reads
        as foliage rather than as a pile of identical balls."""
        spin = rng.uniform(0.0, math.tau) if rng else 0.0
        m = (Matrix.Translation(Vector(centre)) @ Matrix.Rotation(spin, 4, "Z")
             @ Matrix.Diagonal((radius * squash[0], radius * squash[1], radius * squash[2], 1.0)))
        r = bmesh.ops.create_icosphere(self.bm, subdivisions=subdivisions, radius=1.0, matrix=m)
        if rng and jitter > 0.0:
            for v in r["verts"]:
                v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * jitter * radius
        self._tag(r["verts"], mat)

    def cylinder(self, base, height, r_bottom, r_top, mat, segments=6, tilt=None):
        m = Matrix.Translation(Vector(base))
        if tilt is not None:
            m = m @ Euler(tilt).to_matrix().to_4x4()
        m = m @ Matrix.Translation((0.0, 0.0, height * 0.5))
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments,
                                  radius1=r_bottom, radius2=r_top, depth=height, matrix=m)
        self._tag(r["verts"], mat)

    def ngon(self, points, z, mat):
        verts = [self.bm.verts.new((p[0], p[1], z)) for p in points]
        face = self.bm.faces.new(verts)
        if face.normal.z < 0.0:
            face.normal_flip()
        self._tag(verts, mat)

    def ribbon(self, points, width, z, mat):
        """A flat strip along a polyline, for paths."""
        half = width * 0.5
        left, right = [], []
        n = len(points)
        for i, p in enumerate(points):
            a = Vector(points[max(i - 1, 0)])
            b = Vector(points[min(i + 1, n - 1)])
            t = (b - a).normalized()
            side = Vector((-t.y, t.x)) * half
            left.append(self.bm.verts.new((p[0] + side.x, p[1] + side.y, z)))
            right.append(self.bm.verts.new((p[0] - side.x, p[1] - side.y, z)))
        for i in range(n - 1):
            f = self.bm.faces.new((right[i], right[i + 1], left[i + 1], left[i]))
            if f.normal.z < 0.0:
                f.normal_flip()
        self._tag(left + right, mat)

    def text(self, body, centre, size, mat):
        """Flat text standing upright and facing -Y (the scoreboard's front)."""
        curve = bpy.data.curves.new("tmp_text", type="FONT")
        curve.body = body
        curve.size = size
        curve.align_x = "CENTER"
        curve.align_y = "CENTER"
        obj = bpy.data.objects.new("tmp_text", curve)
        bpy.context.scene.collection.objects.link(obj)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        before = set(self.bm.verts)
        self.bm.from_mesh(me)
        new_verts = [v for v in self.bm.verts if v not in before]
        # Text lies in XY facing +Z; rotate it up to face -Y.
        m = Matrix.Translation(Vector(centre)) @ Matrix.Rotation(math.radians(90.0), 4, "X")
        bmesh.ops.transform(self.bm, matrix=m, verts=new_verts)
        self._tag(new_verts, mat)
        bpy.data.objects.remove(obj)
        bpy.data.curves.remove(curve)
        bpy.data.meshes.remove(me)

    def build(self, name):
        me = bpy.data.meshes.get(name)
        if me is None:
            me = bpy.data.meshes.new(name)
        else:
            me.clear_geometry()
            me.materials.clear()
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.materials:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        return me


# ── Scene plumbing ───────────────────────────────────────────────────

def collection(name, parent=None, clear=True):
    """Get or make a collection, emptied of its objects when `clear`."""
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    if clear:
        for child in list(col.children):
            for o in list(child.objects):
                bpy.data.objects.remove(o)
            col.children.unlink(child)
            bpy.data.collections.remove(child)
        for o in list(col.objects):
            bpy.data.objects.remove(o)
    return col


def place(col, name, mesh, location, rot_z=0.0, scale=1.0):
    obj = bpy.data.objects.new(name, mesh)
    obj.location = (location[0], location[1], location[2] if len(location) > 2 else 0.0)
    obj.rotation_euler = (0.0, 0.0, rot_z)
    obj.scale = (scale, scale, scale)
    col.objects.link(obj)
    return obj


def link_meshes(blend_path, names):
    """Link mesh datablocks from another .blend (the prop library), so an
    edit to a prop there flows into every layout on its next export."""
    # Save the layout .blend before calling this, so the library path is
    # stored relative ("//park_props.blend") and survives a moved checkout.
    with bpy.data.libraries.load(blend_path, link=True, relative=True) as (src, dst):
        missing = [n for n in names if n not in src.meshes]
        if missing:
            raise RuntimeError("not in %s: %s" % (blend_path, missing))
        dst.meshes = list(names)
    # On exit the name list has been swapped for the linked datablocks.
    return {me.name: me for me in dst.meshes}


def export_glb(objects, filename):
    """glTF binary, +Y up, modifiers applied, only these objects."""
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path = os.path.join(IMPORTED_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    print("exported", path, "(%d objects)" % len(objects))


# ── Layout geometry ──────────────────────────────────────────────────

def ellipse_point(offset, angle):
    """A point `offset` metres beyond the fence ellipse at parametric angle
    `angle` (radians; 0 = east, pi/2 = north). Like field.gd's tree band, the
    offset is a scaled ellipse, not a true parallel curve."""
    return Vector(((FENCE_A + offset) * math.cos(angle), (FENCE_B + offset) * math.sin(angle)))


def outside_offset(p):
    """Roughly how far beyond the fence a point sits (negative inside)."""
    r = math.sqrt((p[0] / FENCE_A) ** 2 + (p[1] / FENCE_B) ** 2)
    return (r - 1.0) * (FENCE_A + FENCE_B) * 0.5


def face_centre_rot(p):
    """rot_z that turns a prop whose front faces -Y toward the oval centre."""
    return math.atan2(-p[0], p[1]) + math.pi


def catmull_rom(points, steps=8):
    """Smooths a hand-placed path polyline."""
    pts = [Vector(p) for p in points]
    out = []
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def distance_to_polyline(p, polyline):
    best = 1e9
    p = Vector((p[0], p[1]))
    for a, b in zip(polyline, polyline[1:]):
        a, b = Vector((a[0], a[1])), Vector((b[0], b[1]))
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        best = min(best, (a + ab * t - p).length)
    return best


class Scatter:
    """Rejection sampler with keep-out circles, path clearances and spacing.
    Deterministic for a given seed, so a re-run regenerates the same park."""

    def __init__(self, seed, paths=()):
        self.rng = random.Random(seed)
        self.paths = list(paths)
        self.taken = []   # (Vector, radius)

    def reserve(self, p, radius):
        self.taken.append((Vector((p[0], p[1])), radius))

    def clear_of_paths(self, p, clearance):
        return all(distance_to_polyline(p, path) >= clearance for path in self.paths)

    def free(self, p, radius, path_clearance):
        p = Vector((p[0], p[1]))
        if not self.clear_of_paths(p, path_clearance):
            return False
        return all((p - q).length >= radius + r for q, r in self.taken)

    def try_place(self, p, radius, path_clearance):
        if self.free(p, radius, path_clearance):
            self.reserve(p, radius)
            return True
        return False


def angle_deg(p):
    """Parametric fence angle of a point, 0..360."""
    return math.degrees(math.atan2(p[1] / FENCE_B, p[0] / FENCE_A)) % 360.0


def in_sector(angle, lo, hi):
    angle %= 360.0
    lo %= 360.0
    hi %= 360.0
    return lo <= angle <= hi if lo <= hi else angle >= lo or angle <= hi


def pick(rng, weights):
    total = sum(w for _, w in weights)
    x = rng.uniform(0.0, total)
    for item, w in weights:
        x -= w
        if x <= 0.0:
            return item
    return weights[-1][0]
