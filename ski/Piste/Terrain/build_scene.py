# /// script
# requires-python = "==3.11.*"
# dependencies = ["bpy==4.5.3", "rasterio==1.4.3", "pyproj==3.7.2"]
# ///
"""Run with uv to rebuild the terrain reference from the adjacent GeoTIFF."""
from pathlib import Path

import bpy
import numpy as np
import rasterio
from mathutils import Vector
from pyproj import Transformer

ROOT = Path(__file__).resolve().parent
ORIGIN = (113500, 227000, 600)  # Easting, northing and source elevation in metres.
STATIONS = {
    "Penkenbahn · valley station": (11.8606363, 47.1634171),
    "Penkenbahn · upper station": (11.8293403, 47.1754503),
}


def make_terrain(src):
    heights = src.read(1, masked=True)
    if heights.count() != heights.size or not np.isfinite(heights).all():
        raise ValueError("The terrain crop contains missing elevations")
    if src.crs.to_epsg() != 31254 or src.res != (5, 5):
        raise ValueError("Expected the Land Tirol 5 m grid in EPSG:31254")

    # Sample every other pixel centre. Keep the full-resolution raster for placement.
    rows, cols = np.mgrid[0:src.height:2, 0:src.width:2]
    east, north = src.transform * (cols + 0.5, rows + 0.5)
    vertices = np.stack((east - ORIGIN[0], north - ORIGIN[1],
                         heights.data[::2, ::2] - ORIGIN[2]), axis=-1)
    indices = np.arange(rows.size, dtype=np.int32).reshape(rows.shape)
    faces = np.stack((indices[:-1, :-1], indices[1:, :-1], indices[1:, 1:],
                      indices[:-1, 1:]), axis=-1).reshape(-1, 4)
    mesh = bpy.data.meshes.new("Penken · 10 m grid")
    mesh.from_pydata(vertices.reshape(-1, 3).tolist(), [], faces.tolist(), shade_flat=False)
    mesh.update()
    ground = bpy.data.objects.new("Penken · bare earth", mesh)
    bpy.context.collection.objects.link(ground)
    ground["crs"] = "EPSG:31254"
    ground["origin_easting_northing_elevation_m"] = list(ORIGIN)
    ground["source"] = "Datenquelle: Land Tirol – data.tirol.gv.at"
    return ground


def station_guides(src):
    guides = bpy.data.collections.new("Penkenbahn · location guides")
    bpy.context.scene.collection.children.link(guides)
    project = Transformer.from_crs(4326, src.crs, always_xy=True)
    for name, coords in STATIONS.items():
        east, north = project.transform(*coords)
        elevation = float(next(src.sample([(east, north)]))[0])
        point = bpy.data.objects.new(name, None)
        guides.objects.link(point)
        point.location = (east - ORIGIN[0], north - ORIGIN[1], elevation - ORIGIN[2])
        point.empty_display_type = 'PLAIN_AXES'
        point.empty_display_size = 45
        point.show_name = True
        point.show_in_front = True
        point["source_ground_elevation_m"] = elevation


def frame_landscape(scene):
    focus = Vector((0, 0, 900))
    offset = Vector((5400, -3700, 3600))
    bpy.ops.object.camera_add(location=focus + offset)
    camera = bpy.context.object
    camera.name = "Overview from the southeast"
    camera.rotation_euler = (-offset).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 7900
    camera.data.clip_end = 20000
    scene.camera = camera

    bpy.ops.object.light_add(type='SUN')
    sun = bpy.context.object
    sun.rotation_euler = Vector((-0.85, -0.6, -0.75)).to_track_quat('-Z', 'Y').to_euler()
    sun.data.energy = 3
    sun.data.angle = 0.12
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            view = area.spaces.active
            view.clip_end = 30000
            view.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
            view.region_3d.view_distance = 8700
            view.region_3d.view_location = focus
            view.region_3d.view_perspective = 'ORTHO'
            view.overlay.show_floor = False
            view.overlay.show_axis_x = view.overlay.show_axis_y = False


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    with rasterio.open(ROOT / "Penken-5m.tif") as src:
        ground = make_terrain(src)
        station_guides(src)
    frame_landscape(scene)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = ground

    scene.world = bpy.data.worlds.new("Overcast sky")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.44, 0.55, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1200, 800
    scene.render.resolution_percentage = 100
    scene.render.filepath = "//Penken-preview.png"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "Penken.blend"), compress=True)
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
