"""Shared helpers for this film's Blender scenes (Blender 5.2).

Every scene script under blender/ starts with `exec(open(BLENDER_LIB).read())` and then builds its set from scratch,
so the same file runs live through the Blender MCP (look-dev) and headless through tools/render-shot.py (finals).
MCP call: BLENDER_LIB = r"<project>/blender/lib.py"; SHOT = "<variant>"; exec(open(r"<project>/blender/s_<set>.py").read())
Each MCP call starts in a fresh namespace, and bpy.ops lose their context after read_homefile: use the data API.
Assets come only from <media>/assets (Poly Haven CC0, NASA PD), fetched by tools/polyhaven.py.
"""
import math
import os
from pathlib import Path

import bpy
from mathutils import Vector

MEDIA = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos" / "video" / "{{name}}"))
PH = MEDIA / "assets" / "polyhaven"
FPS = 30
W, H = 1080, 1920

# Design system (brief.md): near-black, CCTV cyan, sodium amber, red only on recording LEDs.
CYAN = (0.37, 0.83, 0.90)
AMBER = (1.0, 0.70, 0.28)
RED = (1.0, 0.05, 0.03)


def reset(name: str):
    """Empty scene with the film's render settings."""
    bpy.ops.wm.read_homefile(use_empty=True)
    sc = bpy.context.scene
    sc.name = name
    r = sc.render
    r.resolution_x, r.resolution_y, r.resolution_percentage = W, H, 100
    r.fps = FPS
    r.engine = "BLENDER_EEVEE"
    ee = sc.eevee
    ee.taa_render_samples = 24  # measured: 64 = 16 s, 24 = 5.6 s per 1080x1920 frame (GTX 1660 Ti)
    ee.use_raytracing = True
    ee.ray_tracing_options.resolution_scale = "1"
    ee.use_shadows = True
    ee.volumetric_tile_size = "4"
    ee.volumetric_samples = 64  # tile 8 shows blocky haze; keep tile 4
    ee.use_volumetric_shadows = True
    ee.volumetric_end = 60
    r.use_motion_blur = True
    r.motion_blur_shutter = 0.5
    r.film_transparent = False
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Punchy"
    sc.view_settings.exposure = 0.0
    sc.world = bpy.data.worlds.new("World")
    return sc


def use_cycles(samples: int = 96):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    cy = sc.cycles
    cy.device = "GPU"
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.02
    cy.use_denoising = True
    cy.denoiser = "OPTIX"
    cy.max_bounces = 6
    cy.volume_bounces = 1
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.refresh_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"


def world_hdri(exr: str, strength: float = 0.4, rotate_deg: float = 0.0, haze: float = 0.0, haze_color=(0.6, 0.7, 0.8)):
    """HDRI lighting plus optional uniform volumetric haze."""
    w = bpy.context.scene.world
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(str(PH / "hdri" / exr), check_existing=True)
    mapn = nt.nodes.new("ShaderNodeMapping")
    co = nt.nodes.new("ShaderNodeTexCoord")
    mapn.inputs["Rotation"].default_value[2] = math.radians(rotate_deg)
    nt.links.new(co.outputs["Generated"], mapn.inputs["Vector"])
    nt.links.new(mapn.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    if haze > 0:
        vol = nt.nodes.new("ShaderNodeVolumePrincipled")
        vol.inputs["Density"].default_value = haze
        vol.inputs["Color"].default_value = (*haze_color, 1)
        vol.inputs["Anisotropy"].default_value = 0.55
        nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    return w


def append_collection(blend: Path, coll: str):
    """Append a Poly Haven collection (keeps its rig) and link it to the scene."""
    with bpy.data.libraries.load(str(blend), link=False) as (src, dst):
        dst.collections = [coll]
    c = dst.collections[0]
    bpy.context.scene.collection.children.link(c)
    return c


def append_material(blend: Path, name: str):
    with bpy.data.libraries.load(str(blend), link=False) as (src, dst):
        dst.materials = [name]
    return dst.materials[0]


def plane(name: str, size: float, loc, rot_deg=(0, 0, 0), mat=None, subdiv: int = 0):
    # Data API, not bpy.ops: operators lose their context after read_homefile inside the MCP server.
    h = size / 2
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for loop, co in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = co
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot_deg]
    if subdiv:
        m = o.modifiers.new("subd", "SUBSURF")
        m.subdivision_type = "SIMPLE"
        m.levels = m.render_levels = subdiv
    if mat:
        o.data.materials.append(mat)
    return o


def area_light(name: str, loc, look_at, power: float, color, size: float = 1.0, spread_deg: float = 180):
    d = bpy.data.lights.new(name, "AREA")
    d.energy = power
    d.color = color
    d.size = size
    d.spread = math.radians(spread_deg)
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    aim(o, look_at)
    return o


def spot_light(name: str, loc, look_at, power: float, color, angle_deg: float = 40, blend: float = 0.6, radius: float = 0.05):
    d = bpy.data.lights.new(name, "SPOT")
    d.energy = power
    d.color = color
    d.spot_size = math.radians(angle_deg)
    d.spot_blend = blend
    d.shadow_soft_size = radius
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    aim(o, look_at)
    return o


def point_light(name: str, loc, power: float, color, radius: float = 0.02):
    d = bpy.data.lights.new(name, "POINT")
    d.energy = power
    d.color = color
    d.shadow_soft_size = radius
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    return o


def aim(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def camera(name: str, loc, look_at, lens: float = 50, fstop: float = 2.0, focus=None, sensor: float = 36):
    d = bpy.data.cameras.new(name)
    d.lens = lens
    d.sensor_width = sensor
    d.sensor_fit = "AUTO"
    d.dof.use_dof = True
    d.dof.aperture_fstop = fstop
    d.dof.aperture_blades = 7
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    aim(o, look_at)
    if focus is not None:
        if isinstance(focus, bpy.types.Object):
            d.dof.focus_object = focus
        else:
            d.dof.focus_distance = (Vector(focus) - Vector(loc)).length
    bpy.context.scene.camera = o
    return o


def emission_mat(name: str, color, strength: float):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def smooth_keys(obj, path: str, keys, index: int = -1):
    """Keyframe (frame, value) pairs with soft in-out Bezier curves only (rule R17: no expo or back easing)."""
    for f, v in keys:
        setattr_path(obj, path, v)
        obj.keyframe_insert(path, frame=f, index=index)
    ad = obj.id_data.animation_data  # pose bones keep their keys on the armature object
    if ad and ad.action:
        for fc in iter_fcurves(ad.action):
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
                kp.easing = "AUTO"
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"


def iter_fcurves(action):
    """F-curves of an action in Blender 5.x (layered actions) and older flat actions."""
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    elif hasattr(action, "fcurves"):
        yield from action.fcurves


def setattr_path(obj, path: str, v):
    target = obj
    parts = path.split(".")
    for p in parts[:-1]:
        target = getattr(target, p)
    setattr(target, parts[-1], v)


def bloom(threshold: float = 0.9, strength: float = 0.45, size: float = 0.75):
    """Compositor: render layers -> bloom glare -> output. No chromatic aberration or lens dispersion: their
    fringes read as white outlines around objects (alignment-now v7 verdict)."""
    sc = bpy.context.scene
    ng = bpy.data.node_groups.new("comp", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = ng.nodes.new("CompositorNodeRLayers")
    gl = ng.nodes.new("CompositorNodeGlare")
    gl.inputs["Type"].default_value = "Bloom"
    gl.inputs["Quality"].default_value = "High"
    gl.inputs["Threshold"].default_value = threshold
    gl.inputs["Strength"].default_value = strength
    gl.inputs["Size"].default_value = size
    out = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
    ng.links.new(gl.outputs["Image"], out.inputs[0])
    sc.compositing_node_group = ng
    sc.render.use_compositing = True
    return ng


def frames(start: int, end: int):
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = start, end
    sc.frame_set(start)


def lookdev_sheet(script, shots, frame=60, scale=30, name="sheet", preroll=0):
    """One MCP call -> one contact sheet: runs `script` once per SHOT variant (each in its own namespace, like a
    fresh MCP call), renders `frame` at `scale` %, and tiles the stills with ImageMagick. Returns the sheet path.
    Cuts look-dev round trips (and the tokens of reading many single stills) to one per change."""
    import subprocess
    lib = globals().get("BLENDER_LIB") or str(Path(script).with_name("lib.py"))
    out_dir = MEDIA / "lookdev"
    out_dir.mkdir(parents=True, exist_ok=True)
    stills = []
    for shot in shots:
        ns = {"SHOT": shot, "BLENDER_LIB": lib, "__name__": "__main__"}
        exec(open(script, encoding="utf-8").read(), ns)
        sc = bpy.context.scene
        sc.render.resolution_percentage = scale
        for f in range(frame - preroll, frame + 1):
            sc.frame_set(f)
        p = out_dir / f"{name}_{shot}.png"
        sc.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        stills.append(str(p))
    sheet = out_dir / f"{name}.png"
    subprocess.run(["magick", *stills, "+append", str(sheet)], check=True)
    return str(sheet)
