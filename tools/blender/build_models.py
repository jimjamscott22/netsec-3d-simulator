"""Builds the room's rack, switch and router models (task 1.32) and exports GLB.

Run from the repo root (Blender 4.x or newer):

    blender --background --factory-startup --python tools/blender/build_models.py -- .

The single argument after `--` is the repo root. Output goes to
assets/models/blender/. Re-run this and commit the GLBs if a dimension changes.

All geometry is written in Godot axes (x right, y up, z out of the front) and
converted to Blender's Z-up, front = -Y in one place (`g2b`), so a model's
origin and size match the scene it replaces:

- rack_frame: origin at floor centre, 0.6 x 2.0 x 0.8 m, front face at z = +0.4
  (the plane the device slot markers sit on).
- switch_24 / router_2port: origin at the back-bottom-centre of the chassis, the
  same envelope as the box chassis. The sockets and console port stay where the
  device scenes put them, just in front of the face plate.
"""

import math
import os
import sys

import bmesh
import bpy

ROOT = os.path.abspath(sys.argv[sys.argv.index("--") + 1]) if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "assets", "models", "blender")
TEX = os.path.join(ROOT, "assets", "textures", "polyhaven", "metal_plate")


def g2b(x, y, z):
    """Godot (x right, y up, z front) to Blender (x, y, z) coordinates."""
    return (x, -z, y)


def lin(rgb):
    """sRGB triple (as typed in Godot's colour picker) to the linear values glTF stores."""
    return tuple(c ** 2.2 for c in rgb)


def make_material(name, color, metallic=0.0, roughness=0.5, emission=None, base_tex=None, normal_tex=None):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:  # newer Blender creates the node tree itself
        mat.use_nodes = True
    tree = mat.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*lin(color), 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*lin(emission), 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    if base_tex:
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(base_tex, check_existing=True)
        tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if normal_tex:
        image = bpy.data.images.load(normal_tex, check_existing=True)
        image.colorspace_settings.name = "Non-Color"
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        normal = tree.nodes.new("ShaderNodeNormalMap")
        tree.links.new(node.outputs["Color"], normal.inputs["Color"])
        tree.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


class Builder:
    """Collects boxes into one mesh with a material per face group."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.materials = []
        self.world_uv = {}  # material index -> metres per UV unit

    def material_index(self, mat, world_uv_metres=None):
        if mat not in self.materials:
            self.materials.append(mat)
        index = self.materials.index(mat)
        if world_uv_metres is not None:
            self.world_uv[index] = world_uv_metres
        return index

    def box(self, center, size, mat, bevel=0.0):
        """Axis-aligned box. `center` and `size` are in Godot axes."""
        index = self.material_index(mat)
        bm = self.bm
        verts = bmesh.ops.create_cube(bm, size=1.0)["verts"]
        bmesh.ops.scale(bm, vec=(size[0], size[2], size[1]), verts=verts)
        bmesh.ops.translate(bm, vec=g2b(*center), verts=verts)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = index
        if bevel > 0.0:
            # Bevelling replaces the box's faces, so the new ones need the material too.
            edges = list({e for v in verts for e in v.link_edges})
            result = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES")
            for face in result["faces"]:
                face.material_index = index

    def finish(self):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # World-scale box UVs for the textured material, so the texture keeps one
        # texel density on every face whatever its size.
        uv = bm.loops.layers.uv.verify()
        for face in bm.faces:
            metres = self.world_uv.get(face.material_index)
            if metres is None:
                continue
            n = face.normal
            axis = max(range(3), key=lambda i: abs(n[i]))
            for loop in face.loops:
                co = loop.vert.co
                u, v = {0: (co.y, co.z), 1: (co.x, co.z), 2: (co.x, co.y)}[axis]
                loop[uv].uv = (u / metres, v / metres)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for mat in self.materials:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def export(obj, filename):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_image_format="JPEG",
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print("exported", path, os.path.getsize(path), "bytes")


def build_rack():
    metal = make_material(
        "RackPanel", (0.62, 0.63, 0.66), metallic=0.5, roughness=0.55,
        base_tex=os.path.join(TEX, "metal_plate_diff_1k.jpg"),
        normal_tex=os.path.join(TEX, "metal_plate_nor_gl_1k.jpg"),
    )
    trim = make_material("RackTrim", (0.09, 0.09, 0.1), metallic=0.6, roughness=0.5)
    rail = make_material("RackRail", (0.62, 0.64, 0.68), metallic=0.9, roughness=0.4)
    dark = make_material("RackVent", (0.02, 0.02, 0.025), roughness=0.8)

    b = Builder("RackFrame")
    b.material_index(metal, world_uv_metres=1.0)
    # Plinth and top cap.
    b.box((0, 0.025, 0), (0.6, 0.05, 0.8), trim, bevel=0.004)
    b.box((0, 1.985, 0), (0.6, 0.03, 0.8), trim, bevel=0.004)
    # Top vent slots, a millimetre proud of the cap.
    for z in (-0.2, -0.1, 0.0, 0.1):
        b.box((0, 2.0, z), (0.4, 0.002, 0.03), dark)
    # Side and back panels between plinth and cap.
    b.box((-0.29, 1.01, 0), (0.02, 1.92, 0.8), metal)
    b.box((0.29, 1.01, 0), (0.02, 1.92, 0.8), metal)
    b.box((0, 1.01, -0.39), (0.56, 1.92, 0.02), metal)
    # Mounting rails: the front pair is flush with z = 0.4, where devices mount.
    for x in (-0.2625, 0.2625):
        b.box((x, 1.01, 0.385), (0.035, 1.92, 0.03), rail)
        b.box((x, 1.01, -0.37), (0.035, 1.92, 0.03), rail)
    export(b.finish(), "rack_frame.glb")


def build_device(name, filename, width, height, depth, body_rgb, accent_rgb, layout):
    """A rack-mount chassis with a face plate. `layout(b, mats)` adds the front detail."""
    body = make_material(name + "Body", body_rgb, metallic=0.6, roughness=0.5)
    face = make_material(name + "Face", (0.13, 0.14, 0.16), metallic=0.3, roughness=0.6)
    bay = make_material(name + "Bay", (0.02, 0.02, 0.025), roughness=0.8)
    metal = make_material(name + "Metal", (0.7, 0.72, 0.75), metallic=0.9, roughness=0.35)
    accent = make_material(name + "Accent", accent_rgb, metallic=0.2, roughness=0.5)
    led = make_material(name + "Led", (0.1, 0.8, 0.3), emission=(0.1, 0.8, 0.3))

    plate = 0.008
    b = Builder(name)
    b.box((0, height / 2, (depth - plate) / 2), (width, height, depth - plate), body, bevel=0.002)
    b.box((0, height / 2, depth - plate / 2), (width, height, plate), face)
    layout(b, {"bay": bay, "metal": metal, "accent": accent, "led": led})
    export(b.finish(), filename)


def switch_layout(b, m):
    front = 0.2707  # face plate front is z = 0.27; details sit 0.7 mm proud
    # Port bays behind the two jack rows (sockets sit at y = 0.083 and 0.034).
    b.box((-0.039, 0.083, front), (0.402, 0.024, 0.0014), m["bay"])
    b.box((-0.039, 0.034, front), (0.402, 0.024, 0.0014), m["bay"])
    b.box((0.204, 0.034, front), (0.03, 0.02, 0.0014), m["bay"])  # console surround
    b.box((0.2035, 0.083, front), (0.07, 0.024, 0.0014), m["metal"])  # SFP cages
    b.box((0, 0.1115, front + 0.0005), (0.48, 0.003, 0.002), m["accent"])
    b.box((-0.236, 0.012, front + 0.0008), (0.005, 0.005, 0.003), m["led"])  # power LED
    for x in (-0.2465, 0.2465):  # rack-ear screws
        for y in (0.03, 0.085):
            b.box((x, y, front + 0.0008), (0.005, 0.005, 0.003), m["metal"])


def router_layout(b, m):
    front = 0.2407  # face plate front is z = 0.24
    b.box((-0.05, 0.05, front), (0.07, 0.024, 0.0014), m["bay"])  # two ports at x = -0.07, -0.03
    b.box((0.17, 0.05, front), (0.03, 0.02, 0.0014), m["bay"])  # console surround
    for i in range(6):  # front vent slots
        b.box((0.03 + 0.02 * i, 0.0525, front), (0.004, 0.06, 0.0014), m["bay"])
    b.box((0, 0.1025, front + 0.0005), (0.46, 0.003, 0.002), m["accent"])
    b.box((-0.215, 0.05, front + 0.0008), (0.005, 0.005, 0.003), m["led"])
    for x in (-0.2335, 0.2335):
        for y in (0.03, 0.075):
            b.box((x, y, front + 0.0008), (0.005, 0.005, 0.003), m["metal"])


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_rack()
    build_device("Switch24", "switch_24.glb", 0.5, 0.115, 0.27, (0.24, 0.31, 0.35), (0.1, 0.6, 0.65), switch_layout)
    build_device("Router2Port", "router_2port.glb", 0.48, 0.105, 0.24, (0.30, 0.34, 0.39), (0.9, 0.55, 0.1), router_layout)


main()
