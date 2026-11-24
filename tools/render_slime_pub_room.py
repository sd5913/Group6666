"""Build and light the Slime Pub cover room in Blender from primitive geometry."""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector


random.seed(24)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def rgb(hex_code):
    values = [int(hex_code[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values)


def material(name, color, roughness=0.75, emission=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*rgb(color), 1)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Specular IOR Level'].default_value = 0.25
    if emission:
        shader.inputs['Emission Color'].default_value = (*rgb(color), 1)
        shader.inputs['Emission Strength'].default_value = emission
    return mat


def box(name, pos, size, mat, bevel=0, segments=1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new('Rounded corners', 'BEVEL')
        modifier.width = bevel
        modifier.segments = segments
    return obj


def disc(name, pos, radius, depth, mat, vertical=False, vertices=32):
    rotation = (math.pi / 2, 0, 0) if vertical else (0, 0, 0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def ring(name, pos, radius, thickness, mat, vertical=False):
    rotation = (math.pi / 2, 0, 0) if vertical else (0, 0, 0)
    bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=6, location=pos, rotation=rotation,
                                     major_radius=radius, minor_radius=thickness)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def beam(name, start, end, width, mat):
    span = Vector(end) - Vector(start)
    obj = box(name, (Vector(start) + Vector(end)) / 2, (width, width, span.length), mat)
    obj.rotation_euler = span.to_track_quat('Z', 'Y').to_euler()
    return obj


def area(name, pos, target, power, size, color):
    light = bpy.data.lights.new(name, 'AREA')
    light.energy = power
    light.shape = 'DISK'
    light.size = size
    light.color = color
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector(target) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()


black = material('Dark chocolate', '1b1217')
shadow = material('Espresso', '301c1b')
wall = material('Plum brick', '442a29')
wood = material('Smoked walnut', '683a2d')
wood_light = material('Honey walnut', '98563a')
wood_dark = material('Dark walnut', '472825')
copper = material('Burnished copper', 'bb744d', 0.52)
brass = material('Old brass', 'ca935e', 0.46)
lamp = material('Milk glass', 'ffca7c', 0.62, 1.25)
record_black = material('Vinyl', '251c23', 0.58)
record_groove = material('Vinyl grooves', '655055', 0.65)

# A small room with a stepped rear alcove, lit from its own practical fixtures.
box('Floor', (0, 0, -0.16), (24, 24, 0.3), black)
box('Back wall', (0, 4.15, 3.5), (17.8, 0.45, 7.4), wall)
for side in (-1, 1):
    box('Side wall', (side * 8.35, 0.65, 3.5), (0.4, 7.3, 7.0), wood_dark)
    box('Side ceiling beam', (side * 7.75, 0.9, 5.85), (0.45, 6.85, 0.42), shadow, 0.035)
    box('Rear timber', (side * 6.45, 3.78, 3.0), (0.41, 0.47, 6.1), wood_dark, 0.035)
    box('Inner timber', (side * 2.95, 3.75, 2.5), (0.22, 0.30, 4.75), shadow, 0.02)
box('Rear cross beam', (0, 3.77, 6.09), (16.5, 0.48, 0.44), shadow, 0.05)
box('Rear wainscot', (0, 3.82, 1.04), (16.0, 0.25, 2.08), wood_dark)
box('Rear wainscot cap', (0, 3.65, 2.11), (16, 0.32, 0.12), wood, 0.02)
box('Alcove rear', (0, 3.85, 2.72), (5.7, 0.21, 4.28), shadow)

brick_colors = [material('Brick glaze', color) for color in ('472a29', '52312b', '482e2b', '3d2425', '58332c')]
for row in range(9):
    for col in range(-8, 9):
        x = (col + (row % 2) * 0.5) * 0.94
        if abs(x) > 7.95 or abs(x) < 2.9:
            continue
        box('Brick', (x, 3.911, 2.25 + row * 0.39), (0.905, 0.05, 0.365), random.choice(brick_colors))

tiles = [material('Clay tile', color) for color in ('352027', '3c2529', '362329', '412729', '302027')]
for row in range(11):
    for col in range(-8, 9):
        x = (col + (row % 2) * 0.5) * 1.15
        if abs(x) > 9.05:
            continue
        box('Clay tile', (x, 3.60 - row * 0.77, -0.043), (1.126, 0.745, 0.10), random.choice(tiles))

# Layered sign with room for the live Upheaval heading.
sign_z = 5.03
box('Sign shadow', (0, 3.57, sign_z - 0.06), (8.68, 0.22, 1.7), black, 0.15)
box('Sign outer frame', (0, 3.39, sign_z), (8.42, 0.33, 1.60), copper, 0.16)
box('Sign walnut bezel', (0, 3.19, sign_z), (8.18, 0.13, 1.42), wood_dark, 0.14)
box('Sign lettering plate', (0, 3.10, sign_z), (7.90, 0.08, 1.18), black, 0.11)
for side in (-1, 1):
    for z in (sign_z - 0.55, sign_z + 0.55):
        disc('Sign bolt', (side * 3.87, 3.035, z), 0.056, 0.038, brass, True, 8)
    for i, height in enumerate((0.18, 0.39, 0.27)):
        box('Sign equalizer', (side * (3.05 + i * 0.17), 3.028, sign_z), (0.091, 0.052, height), copper, 0.015)
    box('Sign bracket', (side * 2.82, 3.62, 5.86), (0.13, 0.16, 0.33), shadow, 0.02)

# Low-contrast organ pipes echo the runner's spectrum pillars behind the hero.
pipe_heights = (0.95, 1.29, 1.68, 2.13, 2.42, 2.20, 1.66, 1.28, 1.06, 0.73, 1.04, 1.28, 0.87)
for i, height in enumerate(pipe_heights):
    x = (i - 6) * 0.38
    box('Spectrum pillar', (x, 3.36, 1.9 + height / 2), (0.30, 0.42, height), wood_dark, 0.018)
    box('Spectrum pillar cap', (x, 3.37, 1.89 + height), (0.32, 0.44, 0.085), wood)

for side in (-1, 1):
    x = side * 5.19
    box('Shelf inset', (x, 3.68, 2.67), (1.95, 0.28, 1.72), shadow, 0.03)
    for z in (2.1, 2.68, 3.25):
        box('Shelf', (x, 3.45, z), (2.12, 0.57, 0.105), wood, 0.022)
    for i in range(6):
        px = x + (i - 2.5) * 0.267
        z = 2.15 if (i + side) % 3 else 2.73
        height = random.choice((0.24, 0.32, 0.40))
        mat = random.choice((copper, wood_light, wood_dark, brass))
        box('Square bottle', (px, 3.33, z + height / 2), (0.16, 0.16, height), mat, 0.026)
        box('Bottle neck', (px, 3.33, z + height + 0.032), (0.08, 0.08, 0.11), mat, 0.014)
        box('Bottle cork', (px, 3.33, z + height + 0.10), (0.092, 0.092, 0.065), shadow, 0.015)
    x = side * 5.23
    beam('Pendant wire', (x, 2.35, 6.73), (x, 2.35, 4.99), 0.048, black)
    disc('Pendant shade', (x, 2.35, 4.96), 0.37, 0.12, wood_dark, vertices=12)
    disc('Pendant brass lip', (x, 2.35, 4.88), 0.41, 0.06, brass, vertices=12)
    disc('Pendant glow', (x, 2.35, 4.822), 0.275, 0.09, lamp, vertices=12)
    area('Pendant pool', (x, 2.35, 4.76), (x * 0.9, 2.95, 1.43), 85, 1.15, (1.0, 0.69, 0.43))

# A long counter with a deep face for the single entry action.
box('Counter plinth', (0, -0.17, 0.11), (11.50, 1.91, 0.24), black, 0.045)
box('Counter body', (0, -0.17, 0.68), (11.30, 1.82, 1.25), wood_dark, 0.075)
box('Counter front inset', (0, -1.111, 0.69), (10.83, 0.10, 0.82), shadow, 0.06)
box('Counter front base molding', (0, -1.18, 0.247), (11.20, 0.17, 0.10), wood, 0.028)
box('Counter leading edge', (0, -0.17, 1.255), (11.65, 2.15, 0.26), wood_light, 0.075)
box('Counter surface', (0, -0.17, 1.407), (11.51, 2.04, 0.10), wood, 0.048)
box('Counter rim', (0, -1.19, 1.29), (11.39, 0.08, 0.075), copper, 0.018)
for side in (-1, 1):
    for index in range(5):
        x = side * (2.08 + index * 0.65)
        box('Raised counter slat', (x, -1.175, 0.71), (0.57, 0.09, 0.71), wood_dark, 0.048)
    box('Corner panel', (side * 5.53, -1.15, 0.71), (0.28, 0.19, 1.0), wood, 0.028)

for y in (-0.70, -0.17, 0.36):
    box('Walnut board joint', (0, y, 1.459), (11.33, 0.025, 0.008), wood_dark)

# The round wooden tray is a foreground prop, in front of the live bartender.
disc('Bar tray', (0, -0.02, 1.492), 1.54, 0.074, shadow, vertices=48)
ring('Tray inlay', (0, -0.02, 1.532), 1.38, 0.025, copper)

# Working objects on the bar tell the music story without extra copy.
box('Turntable plinth', (3.32, -0.12, 1.545), (2.42, 1.49, 0.15), black, 0.05)
box('Turntable chassis', (3.32, -0.12, 1.655), (2.36, 1.43, 0.12), wood_light, 0.04)
box('Turntable top', (3.32, -0.12, 1.737), (2.27, 1.35, 0.055), shadow, 0.028)
turn = (3.04, -0.10)
disc('Platter', (*turn, 1.79), 0.634, 0.054, brass)
disc('The record', (*turn, 1.833), 0.595, 0.044, record_black, vertices=48)
for radius in (0.32, 0.41, 0.50):
    ring('Record groove', (*turn, 1.857), radius, 0.022, record_groove)
disc('Record label', (*turn, 1.862), 0.15, 0.012, copper, vertices=24)
disc('Spindle', (*turn, 1.895), 0.038, 0.072, brass, vertices=12)
disc('Tonearm pivot', (4.19, 0.35, 1.84), 0.128, 0.16, copper, vertices=12)
beam('Bent tonearm', (4.19, 0.35, 1.94), (4.06, -0.20, 1.94), 0.065, brass)
beam('Bent tonearm head', (4.06, -0.20, 1.94), (3.76, -0.40, 1.94), 0.065, brass)
box('Needle', (3.75, -0.41, 1.91), (0.15, 0.10, 0.091), shadow, 0.015)
for i in range(3):
    box('Turntable switch', (4.15 + (i % 2) * 0.14, -0.64 + (i // 2) * 0.14, 1.79),
        (0.085, 0.085, 0.069), brass, 0.015)

for x, y in ((-3.92, -0.25), (-3.23, 0.26)):
    disc('Coaster', (x, y, 1.478), 0.31, 0.035, shadow, vertices=12)
    disc('Tankard body', (x, y, 1.75), 0.224, 0.51, wood_light, vertices=10)
    for z in (1.55, 1.93):
        disc('Tankard band', (x, y, z), 0.241, 0.085, brass, vertices=10)
    ring('Tankard handle', (x - 0.245, y - 0.035, 1.76), 0.154, 0.047, copper, True)
    disc('Foam cap', (x, y, 2.00), 0.213, 0.063, lamp, vertices=10)
    box('Foam drip', (x + 0.07, y - 0.201, 1.942), (0.095, 0.055, 0.132), lamp, 0.02)

for x, y in ((-5.65, -2.46), (5.70, -2.85)):
    disc('Stool seat silhouette', (x, y, 0.635), 0.57, 0.18, shadow, vertices=12)
    disc('Stool upholstery', (x, y, 0.752), 0.51, 0.09, wood_light, vertices=12)
    for dx, dy in ((-0.34, -0.31), (-0.34, 0.31), (0.34, -0.31), (0.34, 0.31)):
        beam('Splayed stool leg', (x + dx, y + dy, 0.08), (x + dx * 0.81, y + dy * 0.81, 0.59), 0.12, wood_dark)

world = bpy.data.worlds.new('Dim tavern ambient')
world.use_nodes = True
world.node_tree.nodes.get('Background').inputs[0].default_value = (0.31, 0.21, 0.22, 1)
world.node_tree.nodes.get('Background').inputs[1].default_value = 0.26
scene.world = world
area('Jelly key', (-1.85, -2.8, 5.12), (0, 0.1, 2.25), 285, 3.3, (1.0, 0.78, 0.55))
area('Jelly rim', (1.1, 2.43, 4.19), (0, 0, 2.3), 120, 1.75, (1.0, 0.41, 0.15))
area('Sign wash', (0, 1.24, 6.03), (0, 3.1, 5.0), 62, 4.4, (1.0, 0.67, 0.46))
area('Bar fill', (3.4, -3.1, 3.9), (2.75, -0.3, 1.15), 125, 5.6, (1.0, 0.68, 0.58))

bpy.ops.object.camera_add(location=(0, -18.0, 8.27))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0.38, 2.50)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 15.7
scene.camera = camera

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 14
scene.cycles.use_denoising = True
scene.cycles.pixel_filter_type = 'BOX'
scene.cycles.max_bounces = 5
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = 0.16
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
output = Path(sys.argv[sys.argv.index('--') + 1]).resolve() if '--' in sys.argv else Path(bpy.app.tempdir) / 'slime_pub_room_raw.png'
output.parent.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(output)

bpy.ops.render.render(write_still=True)
