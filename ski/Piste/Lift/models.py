"""Metre-scale Penkenbahn models. Stations face +X; the cabin origin is its rope carriage."""

from math import pi

import bpy
from mathutils import Vector


def material(name, color, metallic=0, roughness=0.45):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return mat


def finishes():
    return {
        name: material(name, rgb, metal, rough)
        for name, rgb, metal, rough in [
            ("Chalk aluminium", (0.78, 0.79, 0.76), 0.38, 0.37),
            ("Concrete", (0.41, 0.42, 0.40), 0.05, 0.8),
            ("Glazing", (0.064, 0.15, 0.19), 0.65, 0.16),
            ("Anthracite", (0.038, 0.048, 0.056), 0.55, 0.35),
            ("Steel", (0.38, 0.43, 0.45), 0.75, 0.32),
            ("Larch", (0.57, 0.34, 0.16), 0.02, 0.55),
            ("Solar glass", (0.045, 0.087, 0.12), 0.55, 0.23),
            ("Cabin yellow", (0.95, 0.59, 0.015), 0.55, 0.27),
            ("Cabin blue", (0.014, 0.13, 0.36), 0.55, 0.24),
            ("Snow", (0.91, 0.94, 0.97), 0.02, 0.72),
        ]
    }


class Model:
    """Batch repeated architectural parts of one finish into an editable mesh."""

    def __init__(self, name):
        self.collection = bpy.data.collections.new(name)
        self.parts = {}

    def solid(self, name, verts, faces):
        vertices, polygons = self.parts.setdefault(name, ([], []))
        offset = len(vertices)
        vertices.extend(verts)
        polygons.extend([tuple(offset + i for i in face) for face in faces])

    def prism(self, name, outline, bottom, top):
        n = len(outline)
        verts = [(x, y, z) for z in (bottom, top) for x, y in outline]
        faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
        faces.extend((i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n))
        self.solid(name, verts, faces)

    def box(self, name, center, dims):
        x, y, z = center
        a, b, c = (v / 2 for v in dims)
        self.prism(
            name,
            [(x - a, y - b), (x + a, y - b), (x + a, y + b), (x - a, y + b)],
            z - c,
            z + c,
        )

    def beam(self, name, start, end, width, depth=None):
        p, q = Vector(start), Vector(end)
        direction = (q - p).normalized()
        cross = direction.cross(Vector((0, 0, 1)))
        if cross.length < 0.001:
            cross = Vector((1, 0, 0))
        a = cross.normalized() * (width / 2)
        b = direction.cross(a).normalized() * ((depth or width) / 2)
        vertices = [
            point + da * a + db * b
            for point in (p, q)
            for da, db in [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        ]
        self.solid(
            name,
            vertices,
            [
                (3, 2, 1, 0),
                (4, 5, 6, 7),
                (0, 1, 5, 4),
                (1, 2, 6, 5),
                (2, 3, 7, 6),
                (3, 0, 4, 7),
            ],
        )

    def text(self, value, location, size, finish):
        font = bpy.data.curves.new(value, "FONT")
        font.body, font.size, font.align_x = value, size, "CENTER"
        font.extrude = 0.007
        obj = bpy.data.objects.new(value, font)
        self.collection.objects.link(obj)
        obj.location = location
        # Local text horizontal = +Y, up = +Z, face = +X.
        obj.rotation_euler = (pi / 2, 0, pi / 2)
        font.materials.append(finish)

    def finish(self, palette):
        for name, (vertices, faces) in self.parts.items():
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata(vertices, [], faces)
            mesh.update()
            obj = bpy.data.objects.new(name, mesh)
            self.collection.objects.link(obj)
            mesh.materials.append(palette[name])
        return self.collection


def station(upper, palette):
    m = Model("Penkenbahn upper station" if upper else "Penkenbahn valley station")
    # CCW footprints rounded to metres from OSM ways 141123075 and 236173117.
    outline = (
        [(34, -53), (32, 9), (7, 9), (8, 16), (-25, 16), (-25, -54)]
        if upper
        else [(-34, -7), (27, -9), (27, 12), (16, 27), (-34, 17)]
    )
    rail = 9 if upper else 16
    deck = rail - 5.8
    front, back = (32, -25) if upper else (27, -34)
    if upper:
        m.prism("Concrete", outline, -9, deck - 0.35)
    else:
        # Recess the shopfront and arcade beneath the cantilevered upper storey.
        m.box("Concrete", (-3, 2, -2), (56, 16, 13))
        m.box("Glazing", (-2, 3, (deck + 2.8) / 2), (51, 20, deck - 2.8))
        for x in range(-26, 24, 4):
            m.box("Larch", (x, 13.06, (deck + 3) / 2), (0.18, 0.25, deck - 3))
        for y in range(-6, 14, 3):
            m.box("Anthracite", (23.55, y, (deck + 3) / 2), (0.16, 0.10, deck - 3))
        for x, y in [(-28, -6), (22, -6), (21, 14), (-22, 14), (7, 20)]:
            m.box("Concrete", (x, y, deck / 2), (1.15, 1.15, deck))
        m.prism("Chalk aluminium", outline, deck - 1.25, deck - 0.35)
    m.prism("Larch" if upper else "Concrete", outline, deck - 0.35, deck)
    m.prism("Anthracite", outline, rail + 1.35, rail + 1.65)
    m.prism("Chalk aluminium", outline, rail + 1.65, rail + 3.15)
    m.prism("Snow", outline, rail + 3.15, rail + 3.3)
    # Two open portals share one boarding hall, with the turn at its rear.
    m.box(
        "Concrete",
        (back + 0.5, 0, (deck + rail + 1.35) / 2),
        (1, 17, rail + 1.35 - deck),
    )
    for side in (-1, 1):
        for x in range(back + 4, front - 1, 6):
            y = 8.15 * side
            m.box(
                "Steel",
                (x, y, (deck + rail + 1.35) / 2),
                (0.22, 0.28, rail + 1.35 - deck),
            )
            if x < front - 9:
                m.box("Glazing", (x + 2.9, y, deck + 3.5), (5.58, 0.12, 6.9))
        m.box("Anthracite", (1, side * 5.5, rail + 0.8), (front - back - 7, 0.42, 0.48))
    m.box("Anthracite", (front - 0.5, 0, rail + 0.85), (1, 16.3, 0.95))
    sign_x = 33.1 if upper else 27.2
    m.box("Anthracite", (sign_x, 0, rail + 1.87), (0.34, 16, 1.34))
    m.text("P E N K E N B A H N", (sign_x + 0.2, 0, rail + 1.54), 0.88, palette["Snow"])

    if upper:
        # Mountain station: long garage podium, ribbed metal, timber sun deck and PV clerestory.
        m.box("Concrete", (1, -32, deck + 2.55), (52, 40, 5.1))
        # Recessed concourse windows behind slender silver facade piers.
        m.box("Glazing", (29.5, -30, deck + 2.55), (2.3, 38, 5.1))
        for y in range(-49, -10, 4):
            m.box("Steel", (30.72, y, deck + 2.55), (0.16, 0.12, 5.1))
            m.box("Steel", (30.72, y + 1.9, deck + 3.9), (0.16, 3.8, 0.10))
        m.box("Concrete", (32, -30, rail + 0.5), (3.3, 40, 1.5))
        m.box("Glazing", (0, -31, rail + 4.65), (41, 28, 3))
        for x in range(-20, 21, 3):
            m.box("Steel", (x, -45.05, rail + 4.65), (0.1, 0.18, 3))
        m.box("Anthracite", (0, -31, rail + 6.25), (42, 29, 0.35))
        for y in range(-49, -10, 4):
            m.box("Chalk aluminium", (32, y, deck + 2.8), (0.53, 0.23, 5.6))
        m.box("Larch", (32, -30, deck + 0.12), (8, 39, 0.24))
        for y in range(-49, -10):
            m.box("Anthracite", (34, y, deck + 0.247), (4, 0.035, 0.015))
        for row in range(6):
            for col in range(13):
                m.box(
                    "Solar glass",
                    (-19.2 + col * 3.2, -43 + row * 4.8, rail + 6.48),
                    (3.13, 4.70, 0.12),
                )
        for y in range(-47, -10, 4):
            m.box("Steel", (35.6, y, deck + 0.8), (0.10, 0.10, 1.4))
        for z in (0.7, 1.45):
            m.beam("Steel", (35.6, -47, deck + z), (35.6, -11, deck + z), 0.09)
        for y in (-43, -28, -17):
            m.box("Concrete", (33, y, -1), (1, 1, 9))
        m.text(
            "B E R G S T A T I O N",
            (33.68, -30, rail + 0.09),
            0.96,
            palette["Anthracite"],
        )
    else:
        # Stepped white outer shell, glazed street level and separate ticket canopy.
        m.box("Glazing", (-4, 14, deck + 2.6), (45, 10, 5.2))
        m.box("Chalk aluminium", (-7, 14, rail - 0.5), (44, 11, 3.7))
        for x in range(-28, 14):
            m.box("Steel", (x, 19.53, rail - 0.5), (0.055, 0.06, 3.35))
        m.box("Glazing", (9, 12, 5.85), (30, 13, 3.8))
        for x in range(-4, 25, 3):
            m.box("Larch", (x, 18.6, 4.0), (0.18, 0.24, 4.4))
        m.box("Concrete", (1, 32, 1.75), (20, 8, 7.5))
        m.box("Glazing", (1, 32, 6.0), (20, 8, 2.7))
        m.box("Chalk aluminium", (1, 32, 7.6), (28, 14, 0.65))
    return m.finish(palette)


def cabin(palette):
    m = Model("Penkenbahn cabin")
    # Octagonal cross-sections taper from the floor to a broad panoramic glass band.
    outline = [
        (1, 0.70),
        (0.78, 1),
        (-0.78, 1),
        (-1, 0.70),
        (-1, -0.70),
        (-0.78, -1),
        (0.78, -1),
        (1, -0.70),
    ]
    levels = [
        (-5.65, 1.67, 1.20),
        (-5.37, 1.98, 1.49),
        (-4.94, 2.02, 1.52),
        (-4.85, 2.06, 1.55),
        (-3.0, 2.01, 1.50),
        (-2.78, 1.89, 1.40),
        (-2.68, 1.74, 1.24),
    ]
    rings = [[(x * a, y * b, z) for x, y in outline] for z, a, b in levels]
    for lo, hi, name in zip(
        rings,
        rings[1:],
        [
            "Anthracite",
            "Cabin blue",
            "Cabin yellow",
            "Glazing",
            "Cabin yellow",
            "Anthracite",
        ],
    ):
        m.solid(
            name, lo + hi, [(i, (i + 1) % 8, (i + 1) % 8 + 8, i + 8) for i in range(8)]
        )
    m.solid(
        "Anthracite",
        rings[0] + rings[-1],
        [tuple(reversed(range(8))), tuple(range(8, 16))],
    )
    for p, q in zip(rings[3], rings[4]):
        m.beam("Anthracite", p, q, 0.085)
    for side in (-1, 1):
        for x in (-0.7, 0, 0.7):
            m.beam("Anthracite", (x, side * 1.55, -4.86), (x, side * 1.50, -3.0), 0.065)
        m.box("Steel", (0, side * 1.55, -4.68), (0.52, 0.055, 0.045))
        m.beam("Steel", (-0.65, side * 0.42, -2.70), (-0.9, side * 0.35, -1.9), 0.15)
        m.beam(
            "Anthracite", (-0.9, side * 0.35, -1.9), (0.15, side * 0.34, -0.32), 0.16
        )
        m.box("Steel", (0, side * 0.58, 0.03), (1.72, 0.20, 0.32))
        for x in (-0.56, 0.56):
            m.box("Anthracite", (x, side * 0.62, 0.13), (0.31, 0.25, 0.29))
    m.box("Anthracite", (0, 0, -0.2), (1.25, 1.35, 0.24))
    return m.finish(palette)
