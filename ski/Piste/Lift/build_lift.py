# /// script
# requires-python = "==3.11.*"
# dependencies = ["bpy==4.5.3", "rasterio==1.4.3", "pyproj==3.7.2", "Pillow>=11,<13"]
# ///
"""Build linked Blender assets, the animated test scene and its contact sheet."""

import itertools
from math import atan2, ceil, cos, pi, sin
from pathlib import Path
from tempfile import TemporaryDirectory

import bpy
import numpy as np
import rasterio
from mathutils import Vector
from models import Model, cabin, finishes, station
from PIL import Image
from pyproj import Transformer

ROOT = Path(__file__).resolve().parent
TERRAIN = ROOT.parent / "Terrain"
FPS = 24
GAUGE = 11
# OSM way 30978865, from valley to upper station. Offsets are prototype rope heights.
ANCHORS = [
    (11.8606363, 47.1634171, 16),
    (11.8475032, 47.1692257, 44),
    (11.8331561, 47.1741653, 37),
    (11.8308014, 47.1749630, 19),
    (11.8293403, 47.1754503, 9),
]


def flat_direction(a, b):
    delta = b - a
    return Vector((delta.x, delta.y, 0)).normalized()


def left(direction):
    return Vector((-direction.y, direction.x, 0))


def group(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def instance(name, asset, collection, position=(0, 0, 0), angle=0):
    ob = bpy.data.objects.new(name, None)
    collection.objects.link(ob)
    ob.instance_type, ob.instance_collection = "COLLECTION", asset
    ob.empty_display_size = 0.25
    ob.location = position
    ob.rotation_euler.z = angle
    return ob


def write_asset(name, collection):
    path = ROOT / "Assets" / (name + ".blend")
    scene = bpy.context.scene
    scene.name = name
    scene.unit_settings.system = "METRIC"
    scene.collection.children.link(collection)
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            view = area.spaces.active
            view.shading.color_type = "MATERIAL"
            view.overlay.show_overlays = False
            view.region_3d.view_rotation = Vector((-1, 0.65, -0.36)).to_track_quat(
                "-Z", "Y"
            )
            view.region_3d.view_distance = 10 if name == "Cabin" else 100
            view.region_3d.view_location = (
                (0, -12, 8)
                if name == "Upper"
                else (0, 0, -2.6 if name == "Cabin" else 8)
            )
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(path), copy=True, compress=True)
    scene.collection.children.unlink(collection)
    return path, collection.name


def read_asset(entry):
    path, name = entry
    with bpy.data.libraries.load(str(path), link=True, relative=True) as (_, dest):
        dest.collections = [name]
    return dest.collections[0]


def make_tower(i, support, direction, ground, palette, slopes):
    m = Model(f"Tower {i} · lattice and saddles")
    height = ANCHORS[i][2]
    half = height * 0.105
    # Four independent foundations meet the sloping terrain at their own heights.
    signs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    bases = []
    for sx, sy in signs:
        foot = support + direction * (sx * half) + left(direction) * (sy * half)
        z = ground(foot) - support.z
        m.box("Concrete", (sx * half, sy * half, z - 0.35), (2.1, 2.1, 2.3))
        bases.append(Vector((sx * half, sy * half, z + 0.8)))
    top = [Vector((sx * 1.35, sy * 1.35, 1.5)) for sx, sy in signs]
    for i0 in range(4):
        i1 = (i0 + 1) % 4
        m.beam("Steel", bases[i0], top[i0], 0.42)
        for j in range(5):
            a, b = [bases[i0].lerp(top[i0], k / 5) for k in (j, j + 1)]
            c, d = [bases[i1].lerp(top[i1], k / 5) for k in (j, j + 1)]
            m.beam("Steel", a, d, 0.16)
            m.beam("Steel", c, b, 0.16)
            m.beam("Anthracite", b, d, 0.18)
    saddle_length = (38, 17, 11)[i - 1]
    for side in (-1, 1):
        y = side * GAUGE / 2
        m.beam("Steel", (0, 0, 1.7), (0, y, 2.7), 0.55)
        m.beam("Steel", (0, 0, -2), (0, y, 2.7), 0.31)
        # The saddle beams run outside the track ropes.
        for off in (-1.08, 1.08):
            for sign, slope in zip((-1, 1), slopes):
                x = sign * saddle_length / 2
                m.beam(
                    "Steel",
                    (0, y + off, 0.20),
                    (x, y + off, slope * x + 0.20),
                    0.32,
                    0.40,
                )
                m.beam(
                    "Steel",
                    (0, y, 2.7),
                    (x * 0.74, y + off, slope * x * 0.74 + 0.45),
                    0.21,
                )
    return m.finish(palette)


def rope(name, points, radius, mat, collection):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 1
    data.bevel_depth, data.bevel_resolution = radius, 1
    line = data.splines.new("POLY")
    line.points.add(len(points) - 1)
    line.points.foreach_set(
        "co", np.array([(*p, 1) for p in points], dtype=np.float32).ravel()
    )
    ob = bpy.data.objects.new(name, data)
    collection.objects.link(ob)
    data.materials.append(mat)


SPAN_SAG = (28, 30, 3.5, 1.1)


def route_lane(anchors, headings, side, cables, palette):
    ends = list(anchors)
    ends[0] = ends[0] + headings[0] * 27
    ends[-1] = ends[-1] - headings[-1] * 32
    centers = [v + left(h) * side * GAUGE / 2 for v, h in zip(ends, headings)]
    track = []
    widths = []
    for i, (a, b) in enumerate(itertools.pairwise(centers)):
        n = ceil((b - a).length / 4)
        sag = SPAN_SAG[i]
        for j in range(0 if i == 0 else 1, n + 1):
            t = j / n
            p = a.lerp(b, t)
            p.z -= 4 * sag * t * (1 - t)
            track.append(p)
            widths.append(left(headings[i].lerp(headings[i + 1], t).normalized()))
    label = "Uphill" if side == 1 else "Downhill"
    for off, z, name in [
        (-0.62, 0, "track L"),
        (0.62, 0, "track R"),
        (0, -0.22, "haul"),
    ]:
        pts = [p + w * off + Vector((0, 0, z)) for p, w in zip(track, widths)]
        rope(
            label + " · " + name,
            pts,
            0.029 if off else 0.028,
            palette["Anthracite"],
            cables,
        )
    return track


def turnaround(anchor, direction, portal):
    # Starts at the incoming portal. The return arc is entirely inside the hall.
    side = left(direction) * GAUGE / 2
    rear = anchor + direction * 11
    mouth = anchor - direction * portal
    pts = [mouth.lerp(rear, t) + side for t in np.linspace(0, 1, 18)]
    pts += [
        rear + side * cos(a) + direction * (GAUGE / 2) * sin(a)
        for a in np.linspace(0, pi, 37)[1:]
    ]
    pts += [rear.lerp(mouth, t) - side for t in np.linspace(0, 1, 18)[1:]]
    return pts


def motion(track_up, track_down, anchors, headings, cable_group, palette):
    upper = turnaround(anchors[-1], headings[-1], 32)
    valley = turnaround(anchors[0], -headings[0], 27)
    for name, pts in [("Upper", upper), ("Valley", valley)]:
        rope(name + " · terminal guide rail", pts, 0.11, palette["Steel"], cable_group)
    points = track_up + upper[1:] + list(reversed(track_down))[1:] + valley[1:]
    assert (points[0] - points[-1]).length < 0.005
    # A short transition outside each portal eases between station and travel speeds.
    speeds = []
    for p in points:
        outside = min(
            (p - track_up[0]).dot(headings[0]), (track_up[-1] - p).dot(headings[-1])
        )
        speeds.append(1.6 + 5.9 * np.clip(outside / 55, 0, 1))
    lengths = np.array([(b - a).length for a, b in itertools.pairwise(points)])
    times = np.r_[0, np.cumsum(lengths / ((np.array(speeds[:-1]) + speeds[1:]) / 2))]
    period = round(times[-1] * FPS)
    frames = times / times[-1] * period + 1
    tangents = [
        points[(i + 1) % (len(points) - 1)] - points[(i - 1) % (len(points) - 1)]
        for i in range(len(points))
    ]
    yaws = np.unwrap([atan2(d.y, d.x) for d in tangents])
    action = bpy.data.actions.new("Cabin · continuous Penkenbahn circuit")
    for path, axis, values in [
        ("location", k, [p[k] for p in points]) for k in range(3)
    ] + [("rotation_euler", 2, yaws)]:
        curve = action.fcurves.new(path, index=axis)
        curve.keyframe_points.add(len(points))
        curve.keyframe_points.foreach_set(
            "co", np.column_stack((frames, values)).astype("f").ravel()
        )
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
        curve.update()
    # Start with a cabin in front of the upper portal, visible in the default view.
    arrival = len(track_up) - 1
    preview_phase = frames[arrival - 5] - 1
    return action, period, preview_phase


def camera(name, position, target, width):
    data = bpy.data.cameras.new(name)
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = position
    ob.rotation_euler = (target - position).to_track_quat("-Z", "Y").to_euler()
    data.type, data.ortho_scale, data.clip_end = "ORTHO", width, 16000
    return ob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette = finishes()
    files = [
        write_asset(n, c)
        for n, c in [
            ("Valley", station(False, palette)),
            ("Upper", station(True, palette)),
            ("Cabin", cabin(palette)),
        ]
    ]
    bpy.ops.wm.open_mainfile(filepath=str(TERRAIN / "Penken.blend"))
    scene = bpy.context.scene
    palette = finishes()
    scene.collection.children["Penkenbahn · location guides"].hide_viewport = True
    scene.collection.children["Penkenbahn · location guides"].hide_render = True
    terminals = group("01 · Stations")
    towers = group("02 · Towers")
    cables = group("03 · Ropes")
    fleet = group("04 · Cabins")
    base = bpy.data.objects["Penken · bare earth"][
        "origin_easting_northing_elevation_m"
    ]
    source = rasterio.open(TERRAIN / "Penken-5m.tif")
    heights = source.read(1)

    def ground(point):
        row, col = source.index(point.x + base[0], point.y + base[1])
        return float(heights[row, col]) - base[2]

    coords = Transformer.from_crs(4326, source.crs, always_xy=True)
    anchors = []
    for lon, lat, offset in ANCHORS:
        x, y = coords.transform(lon, lat)
        p = Vector((x - base[0], y - base[1], 0))
        p.z = ground(p) + offset
        anchors.append(p)
    spans = [flat_direction(a, b) for a, b in itertools.pairwise(anchors)]
    headings = (
        [spans[0]]
        + [(a + b).normalized() for a, b in itertools.pairwise(spans)]
        + [spans[-1]]
    )
    valley_asset, upper_asset, cabin_asset = map(read_asset, files)
    for index, sign, asset in [(0, 1, valley_asset), (-1, -1, upper_asset)]:
        p = anchors[index].copy()
        p.z = ground(p)
        d = headings[index] * sign
        instance(asset.name, asset, terminals, p, atan2(d.y, d.x))
    for i in range(1, 4):
        slopes = []
        for span_id, sign in [(i - 1, 1), (i, -1)]:
            delta = anchors[span_id + 1] - anchors[span_id]
            length = delta.xy.length - (
                27 if span_id == 0 else 32 if span_id == 3 else 0
            )
            slopes.append((delta.z + sign * 4 * SPAN_SAG[span_id]) / length)
        tower = make_tower(i, anchors[i], headings[i], ground, palette, slopes)
        instance(
            f"Support {i}",
            tower,
            towers,
            anchors[i],
            atan2(headings[i].y, headings[i].x),
        )
    up, down = [route_lane(anchors, headings, s, cables, palette) for s in (1, -1)]
    for lane in (up, down):
        clearance = min(p.z - 5.65 - ground(p) for p in lane)
        print(
            f"Minimum sampled cabin-to-ground clearance: {clearance:.2f} m", flush=True
        )
        if clearance <= 0:
            raise ValueError("Cabin intersects terrain")
    action, period, phase = motion(up, down, anchors, headings, cables, palette)
    for i in range(30):
        ob = instance(f"Cabin {i + 1:02}", cabin_asset, fleet)
        start = 1 - round((phase + i * period / 30) % period)
        strip = (
            ob.animation_data_create()
            .nla_tracks.new()
            .strips.new("Lift circuit", start, action)
        )
        strip.repeat = 2
        strip.extrapolation = "NOTHING"
    source.close()
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, period
    scene.frame_set(1)
    cams = []
    for i, sign, side, reach in [(-1, -1, -1, 98), (0, 1, 1, 99), (1, 1, 1, 100)]:
        a, d = anchors[i], headings[i] * sign
        target = a + (left(d) * (-16) if i == -1 else Vector((0, 0, 0)))
        target.z -= 4 if i != 1 else 19
        name = {-1: "Upper station", 0: "Valley station", 1: "Tower 1"}[i]
        eye = (
            target
            + d * (reach * 0.83)
            + left(d) * (side * reach * 0.54)
            + Vector((0, 0, reach * 0.26))
        )
        cams.append(camera("Inspect · " + name, eye, target, reach))
    scene.camera = cams[0]
    scene.sync_mode = "FRAME_DROP"
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            view = area.spaces.active
            view.region_3d.view_rotation = cams[0].rotation_euler.to_quaternion()
            view.region_3d.view_location = anchors[-1] + left(-headings[-1]) * (-16)
            view.region_3d.view_distance = 105
            view.region_3d.view_perspective = "CAMERA"
            view.overlay.show_overlays = False
            view.shading.color_type = "MATERIAL"
            view.shading.show_shadows = True
            view.shading.show_cavity = True
    scene.render.resolution_x, scene.render.resolution_y = 1000, 640
    scene.cycles.samples = 12
    # Preserve the relative library paths when moving from Terrain/ to Lift/.
    bpy.context.preferences.filepaths.save_version = 0
    scene.render.filepath = "//Penkenbahn-render.png"
    bpy.ops.wm.save_as_mainfile(
        filepath=str(ROOT / "Penkenbahn.blend"), compress=True, relative_remap=True
    )
    with TemporaryDirectory() as tmp:
        images = []
        for i, cam in enumerate(cams):
            scene.camera = cam
            scene.render.filepath = str(Path(tmp) / f"{i}.png")
            bpy.ops.render.render(write_still=True)
            with Image.open(scene.render.filepath) as im:
                images.append(im.convert("RGB"))
        sheet = Image.new("RGB", (1508, 640), "#ffffff")
        sheet.paste(images[0], (0, 0))
        for i, im in enumerate(images[1:]):
            sheet.paste(
                im.resize((500, 320), Image.Resampling.LANCZOS), (1008, i * 320)
            )
        sheet.save(ROOT / "Penkenbahn-preview.jpg", quality=93)


if __name__ == "__main__":
    main()
