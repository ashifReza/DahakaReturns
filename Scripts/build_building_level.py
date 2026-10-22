"""
Builds the greybox "Building" level: lobby -> long corridor (chase starts) ->
ward (slam the door) -> corridor -> heavy door (hold E) -> storage -> vent crawl
-> ambush corridor -> outside (safe).

Run inside the Unreal editor:  Tools > Execute Python Script... > this file
Re-running rebuilds everything it made (actors in the "Relentless" outliner folders).

Units are centimetres. Floor is z = 0. Layout (top-down, +X right, +Y up):

                         outside(safe) <== corridor C ==<< vent <<== storage
                                              closet(ambush)          ^ heavy door
                                                                      | corridor B
                                                                      ^ door (slam)
    lobby ==> corridor A (chase trigger) ==========================> ward
"""
import unreal

LEVEL_PATH = "/Game/Maps/Building"
MAT_DIR = "/Game/Greybox"
ROOT_FOLDER = "Relentless"
T = 20.0  # wall thickness

actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
levels = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
asset_tools = unreal.AssetToolsHelpers.get_asset_tools()

CUBE = unreal.EditorAssetLibrary.load_asset("/Engine/BasicShapes/Cube")
BASE_MAT = unreal.EditorAssetLibrary.load_asset("/Engine/BasicShapes/BasicShapeMaterial")


def game_class(name):
    cls = unreal.load_class(None, f"/Script/Relentless.{name}")
    if cls is None:
        raise RuntimeError(f"Class {name} not found. Compile the C++ project first.")
    return cls


def material(name, rgb):
    path = f"{MAT_DIR}/{name}"
    if unreal.EditorAssetLibrary.does_asset_exist(path):
        mi = unreal.EditorAssetLibrary.load_asset(path)
    else:
        mi = asset_tools.create_asset(name, MAT_DIR, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    unreal.MaterialEditingLibrary.set_material_instance_parent(mi, BASE_MAT)
    unreal.MaterialEditingLibrary.set_material_instance_vector_parameter_value(mi, "Color", unreal.LinearColor(rgb[0], rgb[1], rgb[2], 1.0))
    unreal.EditorAssetLibrary.save_loaded_asset(mi)
    return mi


def vec(x, y, z):
    return unreal.Vector(float(x), float(y), float(z))


def rot(yaw=0.0):
    return unreal.Rotator(roll=0.0, pitch=0.0, yaw=float(yaw))


def xform(x, y, z, yaw=0.0):
    return unreal.Transform(location=vec(x, y, z), rotation=rot(yaw), scale=vec(1, 1, 1))


def spawn(cls, label, folder, loc, yaw=0.0):
    a = actors.spawn_actor_from_class(cls, vec(*loc), rot(yaw))
    a.set_actor_label(label)
    a.set_folder_path(f"{ROOT_FOLDER}/{folder}")
    return a


def block(label, folder, center, size, mat):
    a = spawn(unreal.StaticMeshActor, label, folder, center)
    comp = a.get_editor_property("static_mesh_component")
    comp.set_static_mesh(CUBE)
    comp.set_material(0, mat)
    a.set_actor_scale3d(vec(size[0] / 100.0, size[1] / 100.0, size[2] / 100.0))
    return a


# ---------------------------------------------------------------------------
# Level
# ---------------------------------------------------------------------------

if unreal.EditorAssetLibrary.does_asset_exist(LEVEL_PATH):
    levels.load_level(LEVEL_PATH)
    for a in actors.get_all_level_actors():
        if str(a.get_folder_path()).startswith(ROOT_FOLDER):
            actors.destroy_actor(a)
else:
    levels.new_level(LEVEL_PATH)

WALL = material("MI_Wall", (0.10, 0.115, 0.10))      # stained institutional green-grey
FLOOR = material("MI_Floor", (0.045, 0.045, 0.045))
VENT = material("MI_Vent", (0.16, 0.16, 0.17))
PROP = material("MI_Prop", (0.08, 0.07, 0.06))
GROUND = material("MI_Ground", (0.03, 0.04, 0.025))  # outside: mud and moss


def room(name, x0, x1, y0, y1, h, openings=None, ceiling=True, wall_mat=WALL, floor_mat=FLOOR):
    """Floor, ceiling and four walls with doorway gaps.

    openings: {"N"|"S"|"E"|"W": [(start, end, top), ...]} in world coords along that wall.
    Walls sit just outside the room's footprint so neighbouring rooms can share a gap.
    """
    openings = openings or {}
    folder = f"Building/{name}"
    block(f"{name}_Floor", folder, ((x0 + x1) / 2, (y0 + y1) / 2, -T / 2), (x1 - x0, y1 - y0, T), floor_mat)
    if ceiling:
        block(f"{name}_Ceiling", folder, ((x0 + x1) / 2, (y0 + y1) / 2, h + T / 2), (x1 - x0, y1 - y0, T), wall_mat)

    sides = {
        "S": ("x", y0 - T / 2, x0 - T, x1 + T),
        "N": ("x", y1 + T / 2, x0 - T, x1 + T),
        "W": ("y", x0 - T / 2, y0, y1),
        "E": ("y", x1 + T / 2, y0, y1),
    }
    z_bottom, z_top = -T, h + T
    for side, (axis, fixed, a0, a1) in sides.items():
        pieces = []  # (start, end, z0, z1)
        cursor = a0
        for (o0, o1, top) in sorted(openings.get(side, [])):
            if o0 > cursor:
                pieces.append((cursor, o0, z_bottom, z_top))
            if top < h:
                pieces.append((o0, o1, top, z_top))
            cursor = max(cursor, o1)
        if cursor < a1:
            pieces.append((cursor, a1, z_bottom, z_top))

        for i, (s, e, z0, z1) in enumerate(pieces):
            if e - s < 1:
                continue
            mid, length, zc, zh = (s + e) / 2, e - s, (z0 + z1) / 2, z1 - z0
            if axis == "x":
                block(f"{name}_Wall{side}{i}", folder, (mid, fixed, zc), (length, T, zh), wall_mat)
            else:
                block(f"{name}_Wall{side}{i}", folder, (fixed, mid, zc), (T, length, zh), wall_mat)


# Rooms -----------------------------------------------------------------------
room("Lobby", -800, 0, -400, 400, 400, {"E": [(-150, 150, 350)]})
room("CorridorA", 0, 3000, -150, 150, 350, {"W": [(-150, 150, 350)], "E": [(-150, 150, 350)]})
room("Ward", 3000, 3800, -400, 600, 400, {"W": [(-150, 150, 350)], "N": [(3300, 3500, 300)]})
room("CorridorB", 3250, 3550, 600, 2600, 350, {"S": [(3300, 3500, 300)], "N": [(3300, 3500, 300)]})
room("Storage", 3000, 3800, 2600, 3400, 400, {"S": [(3300, 3500, 300)], "W": [(2900, 3020, 120)]})
room("Vent", 1500, 3000, 2900, 3020, 120, {"E": [(2900, 3020, 120)], "W": [(2900, 3020, 120)]}, wall_mat=VENT, floor_mat=VENT)
room("CorridorC", -1500, 1500, 2810, 3110, 350, {"E": [(2900, 3020, 120)], "W": [(2810, 3110, 350)], "N": [(1200, 1400, 300)]})
room("Closet", 1200, 1400, 3110, 3400, 350, {"S": [(1200, 1400, 300)]})
room("Outside", -3500, -1500, 2000, 3900, 900, {"E": [(2810, 3110, 350)]}, ceiling=False, wall_mat=GROUND, floor_mat=GROUND)

# Props: things to weave around. They never fully block the route.
block("Lobby_Desk", "Props", (-350, -250, 50), (300, 90, 100), PROP)
block("CorridorA_Gurney", "Props", (1500, 85, 45), (200, 80, 90), PROP)
block("CorridorA_Crates", "Props", (2300, -90, 35), (120, 100, 70), PROP)
for i, (bx, by) in enumerate([(3200, -250), (3600, -250), (3200, 350), (3600, 150)]):
    block(f"Ward_Bed{i}", "Props", (bx, by, 30), (200, 90, 60), PROP)
block("Storage_Shelves", "Props", (3700, 3000, 150), (100, 600, 300), PROP)
block("CorridorC_Cabinet", "Props", (-200, 3050, 40), (160, 100, 80), PROP)

# Doors -----------------------------------------------------------------------
door_cls = game_class("ChaseDoor")
ward_door = spawn(door_cls, "Door_WardToCorridorB", "Gameplay", (3400, 600, 0))
ward_door.set_editor_property("width", 200.0)
ward_door.set_editor_property("open_yaw", 90.0)
ward_door.set_editor_property("starts_open", True)

heavy_door = spawn(door_cls, "HeavyDoor_Storage", "Gameplay", (3400, 2600, 0))
heavy_door.set_editor_property("width", 200.0)
heavy_door.set_editor_property("open_yaw", 90.0)
heavy_door.set_editor_property("heavy", True)
heavy_door.set_editor_property("hold_time", 1.6)
heavy_door.set_editor_property("color", unreal.LinearColor(0.12, 0.13, 0.14, 1.0))

# Chase triggers / checkpoints ------------------------------------------------
trigger_cls = game_class("ChaseTrigger")


def trigger(label, loc, extent, pursuer_world=None, respawn_world=None, hint="", starts_chase=True):
    t = spawn(trigger_cls, label, "Gameplay", loc)
    t.get_component_by_class(unreal.BoxComponent).set_box_extent(vec(*extent), True)
    t.set_editor_property("starts_chase", starts_chase)
    if pursuer_world:
        px, py, pz, pyaw = pursuer_world
        t.set_editor_property("pursuer_start", xform(px - loc[0], py - loc[1], pz - loc[2], pyaw))
    if respawn_world:
        rx, ry, rz, ryaw = respawn_world
        t.set_editor_property("player_respawn", xform(rx - loc[0], ry - loc[1], rz - loc[2], ryaw))
    if hint:
        t.set_editor_property("hint", unreal.Text(hint))
    return t


trigger("Hint_Controls", (-600, 0, 175), (150, 300, 175),
        hint="[F] flashlight    [SHIFT] run    [Q] look back    [RMB] focus beam", starts_chase=False)
# It bursts out of the lobby behind you.
trigger("Chase_Start", (700, 0, 175), (60, 150, 175),
        pursuer_world=(-650, 0, 150, 0), respawn_world=(850, 0, 100, 0),
        hint="Run.")
trigger("Checkpoint_Storage", (3400, 2800, 200), (300, 120, 200),
        pursuer_world=(3400, 1500, 150, 90), respawn_world=(3400, 2900, 100, 180))
trigger("Checkpoint_CorridorC", (1000, 2960, 175), (60, 150, 175),
        pursuer_world=(1300, 3300, 150, -90), respawn_world=(850, 2960, 100, 180))

# Vent crawlspace: extends past both mouths so the player crouches before reaching it.
vent = spawn(game_class("VentZone"), "VentZone", "Gameplay", (2250, 2960, 100))
vent.get_component_by_class(unreal.BoxComponent).set_box_extent(vec(900, 150, 100), True)
vent.set_editor_property("ambush_point", xform(1300 - 2250, 3300 - 2960, 150 - 100, -90))

safe = spawn(game_class("SafeZone"), "SafeZone_Outside", "Gameplay", (-2600, 2950, 300))
safe.get_component_by_class(unreal.BoxComponent).set_box_extent(vec(800, 900, 300), True)
safe.set_editor_property("message", unreal.Text("It won't follow you into the open. Not yet."))

# Pickups ---------------------------------------------------------------------
battery_cls = game_class("BatteryPickup")
spawn(battery_cls, "Battery_Lobby", "Gameplay", (-350, -250, 120))
spawn(battery_cls, "Battery_Ward", "Gameplay", (3650, 450, 40))
spawn(battery_cls, "Battery_Storage", "Gameplay", (3150, 3300, 40))

# Lights ----------------------------------------------------------------------
light_cls = game_class("FlickerLight")


def light(label, loc, lumens=60.0, color=(0.85, 0.95, 1.0), faultiness=0.3, radius=900.0):
    l = spawn(light_cls, label, "Lights", loc)
    l.set_editor_property("lumens", lumens)
    l.set_editor_property("light_color", unreal.LinearColor(color[0], color[1], color[2], 1.0))
    l.set_editor_property("faultiness", faultiness)
    l.set_editor_property("radius", radius)
    return l


light("Light_Lobby", (-400, 0, 370), lumens=25.0, faultiness=0.6)
for i, x in enumerate([400, 1200, 2000, 2800]):
    light(f"Light_CorridorA_{i}", (x, 0, 325), faultiness=0.15 + 0.15 * i)
light("Light_Ward_Emergency", (3400, 100, 375), lumens=80.0, color=(1.0, 0.12, 0.05), faultiness=0.05, radius=1200.0)
for i, y in enumerate([1000, 1800, 2400]):
    light(f"Light_CorridorB_{i}", (3400, y, 325), faultiness=0.4)
light("Light_Storage", (3400, 3000, 375), lumens=20.0, faultiness=0.7)
for i, x in enumerate([1000, 200, -600, -1300]):
    light(f"Light_CorridorC_{i}", (x, 2960, 325), lumens=45.0, faultiness=0.5)

moon = spawn(unreal.DirectionalLight, "Moonlight", "Environment", (0, 0, 2000))
moon.set_actor_rotation(unreal.Rotator(roll=0.0, pitch=-55.0, yaw=35.0), False)
moon_comp = moon.get_component_by_class(unreal.DirectionalLightComponent)
moon_comp.set_mobility(unreal.ComponentMobility.MOVABLE)
moon_comp.set_editor_property("intensity", 2.0)
moon_comp.set_editor_property("light_color", unreal.Color(r=150, g=170, b=255, a=255))

fog = spawn(unreal.ExponentialHeightFog, "Fog", "Environment", (0, 0, 0))
fog_comp = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
fog_comp.set_editor_property("fog_density", 0.03)
fog_comp.set_editor_property("volumetric_fog", True)
# Fog that glows on its own ruins the dark; only lights should reveal it.
for prop in ("fog_inscattering_luminance", "fog_inscattering_color"):
    try:
        fog_comp.set_editor_property(prop, unreal.LinearColor(0.002, 0.002, 0.003, 1.0))
        break
    except Exception:
        pass

# Player, pursuer, music --------------------------------------------------------
spawn(unreal.PlayerStart, "PlayerStart", "Gameplay", (-600, 0, 100), yaw=0)
spawn(game_class("PursuerCharacter"), "Pursuer", "Gameplay", (-700, 300, 150))
spawn(game_class("ChaseMusicDirector"), "MusicDirector", "Gameplay", (0, 0, 0))

levels.save_current_level()
unreal.log("Relentless: Building level built and saved to " + LEVEL_PATH)
