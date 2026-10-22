extends RefCounted
## Builds the greybox "Building" level: lobby -> long corridor (chase starts) ->
## ward (slam the door) -> corridor -> heavy door (hold E) -> storage -> vent
## crawl -> ambush corridor -> outside (safe).
##
## Ported from the Unreal script, so the layout below is still written in
## Unreal units: centimetres, +X right, +Y up the page, Z up. ue() converts to
## Godot (metres, Y up). Floor is z = 0.
##
##                          outside(safe) <== corridor C ==<< vent <<== storage
##                                               closet(ambush)          ^ heavy door
##                                                                       | corridor B
##                                                                       ^ door (slam)
##     lobby ==> corridor A (chase trigger) ==========================> ward

const T := 20.0  # wall thickness

const PlayerScript := preload("res://scripts/player.gd")
const PursuerScript := preload("res://scripts/pursuer.gd")
const DoorScript := preload("res://scripts/chase_door.gd")
const TriggerScript := preload("res://scripts/chase_trigger.gd")
const VentScript := preload("res://scripts/vent_zone.gd")
const SafeScript := preload("res://scripts/safe_zone.gd")
const BatteryScript := preload("res://scripts/battery_pickup.gd")
const LightScript := preload("res://scripts/flicker_light.gd")
const MusicScript := preload("res://scripts/music_director.gd")
const LevelScript := preload("res://scripts/level.gd")
const Audio := preload("res://tools/level_audio.gd")

var root: Node3D
var _folders := {}
var WALL := _mat(Color(0.10, 0.115, 0.10))     # stained institutional green-grey
var FLOOR := _mat(Color(0.045, 0.045, 0.045))
var VENT := _mat(Color(0.16, 0.16, 0.17))
var PROP := _mat(Color(0.08, 0.07, 0.06))
var GROUND := _mat(Color(0.03, 0.04, 0.025))   # outside: mud and moss


static func ue(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, y) / 100.0


## Unreal-style yaw (0 = +X, 90 = +Y) to a Godot node's rotation.y.
static func _yaw(degrees: float) -> float:
	var r := deg_to_rad(degrees)
	return atan2(-cos(r), -sin(r))


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func build() -> Node3D:
	root = Node3D.new()
	root.name = "Building"
	root.set_script(LevelScript)
	_environment()
	_rooms()
	_props()
	_gameplay()
	_lights()
	return root


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Adds a node under root/<folder path>, owned by root so it's saved.
func _add(node: Node, folder: String) -> Node:
	_folder(folder).add_child(node)
	node.owner = root
	return node


func _folder(path: String) -> Node:
	if path == "":
		return root
	if _folders.has(path):
		return _folders[path]
	var parts := path.split("/")
	var parent := _folder("/".join(parts.slice(0, parts.size() - 1)))
	var n := Node3D.new()
	n.name = parts[-1]
	parent.add_child(n)
	n.owner = root
	_folders[path] = n
	return n


func _block(label: String, folder: String, center: Vector3, size: Vector3, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = label
	b.position = ue(center.x, center.y, center.z)
	b.size = ue(size.x, size.y, size.z)
	b.material = mat
	b.use_collision = true
	b.collision_layer = 1
	b.collision_mask = 0
	return _add(b, folder)


func _marker(parent: Node3D, label: String, world: Vector4) -> Marker3D:
	# world = (x, y, z, yaw) in Unreal units.
	var m := Marker3D.new()
	m.name = label
	parent.add_child(m)
	m.owner = root
	m.position = ue(world.x, world.y, world.z) - parent.position
	m.rotation.y = _yaw(world.w)
	return m


# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

## Floor, ceiling and four walls with doorway gaps.
## openings: {"N"|"S"|"E"|"W": [[start, end, top], ...]} in world coords along that wall.
## Walls sit just outside the room's footprint so neighbouring rooms can share a gap.
func _room(name: String, x0: float, x1: float, y0: float, y1: float, h: float,
		openings := {}, ceiling := true, wall_mat: Material = null, floor_mat: Material = null) -> void:
	wall_mat = wall_mat if wall_mat else WALL
	floor_mat = floor_mat if floor_mat else FLOOR
	var folder := "Building/" + name
	_block(name + "_Floor", folder, Vector3((x0 + x1) / 2, (y0 + y1) / 2, -T / 2), Vector3(x1 - x0, y1 - y0, T), floor_mat)
	if ceiling:
		_block(name + "_Ceiling", folder, Vector3((x0 + x1) / 2, (y0 + y1) / 2, h + T / 2), Vector3(x1 - x0, y1 - y0, T), wall_mat)

	var sides := {
		"S": ["x", y0 - T / 2, x0 - T, x1 + T],
		"N": ["x", y1 + T / 2, x0 - T, x1 + T],
		"W": ["y", x0 - T / 2, y0, y1],
		"E": ["y", x1 + T / 2, y0, y1],
	}
	var z_bottom := -T
	var z_top := h + T
	for side in sides:
		var axis: String = sides[side][0]
		var fixed: float = sides[side][1]
		var a0: float = sides[side][2]
		var a1: float = sides[side][3]
		var pieces := []  # [start, end, z0, z1]
		var cursor := a0
		var gaps: Array = openings.get(side, []).duplicate()
		gaps.sort_custom(func(a, b): return a[0] < b[0])
		for gap in gaps:
			var o0: float = gap[0]
			var o1: float = gap[1]
			var top: float = gap[2]
			if o0 > cursor:
				pieces.append([cursor, o0, z_bottom, z_top])
			if top < h:
				pieces.append([o0, o1, top, z_top])
			cursor = maxf(cursor, o1)
		if cursor < a1:
			pieces.append([cursor, a1, z_bottom, z_top])

		for i in pieces.size():
			var s: float = pieces[i][0]
			var e: float = pieces[i][1]
			var z0: float = pieces[i][2]
			var z1: float = pieces[i][3]
			if e - s < 1:
				continue
			var mid := (s + e) / 2
			var length := e - s
			var zc := (z0 + z1) / 2
			var zh := z1 - z0
			var label := "%s_Wall%s%d" % [name, side, i]
			if axis == "x":
				_block(label, folder, Vector3(mid, fixed, zc), Vector3(length, T, zh), wall_mat)
			else:
				_block(label, folder, Vector3(fixed, mid, zc), Vector3(T, length, zh), wall_mat)


func _rooms() -> void:
	_room("Lobby", -800, 0, -400, 400, 400, {"E": [[-150, 150, 350]]})
	_room("CorridorA", 0, 3000, -150, 150, 350, {"W": [[-150, 150, 350]], "E": [[-150, 150, 350]]})
	_room("Ward", 3000, 3800, -400, 600, 400, {"W": [[-150, 150, 350]], "N": [[3300, 3500, 300]]})
	_room("CorridorB", 3250, 3550, 600, 2600, 350, {"S": [[3300, 3500, 300]], "N": [[3300, 3500, 300]]})
	_room("Storage", 3000, 3800, 2600, 3400, 400, {"S": [[3300, 3500, 300]], "W": [[2900, 3020, 120]]})
	_room("Vent", 1500, 3000, 2900, 3020, 120, {"E": [[2900, 3020, 120]], "W": [[2900, 3020, 120]]}, true, VENT, VENT)
	_room("CorridorC", -1500, 1500, 2810, 3110, 350, {"E": [[2900, 3020, 120]], "W": [[2810, 3110, 350]], "N": [[1200, 1400, 300]]})
	_room("Closet", 1200, 1400, 3110, 3400, 350, {"S": [[1200, 1400, 300]]})
	_room("Outside", -3500, -1500, 2000, 3900, 900, {"E": [[2810, 3110, 350]]}, false, GROUND, GROUND)


## Things to weave around. They never fully block the route.
func _props() -> void:
	_block("Lobby_Desk", "Props", Vector3(-350, -250, 50), Vector3(300, 90, 100), PROP)
	_block("CorridorA_Gurney", "Props", Vector3(1500, 85, 45), Vector3(200, 80, 90), PROP)
	_block("CorridorA_Crates", "Props", Vector3(2300, -90, 35), Vector3(120, 100, 70), PROP)
	var beds := [Vector2(3200, -250), Vector2(3600, -250), Vector2(3200, 350), Vector2(3600, 150)]
	for i in beds.size():
		_block("Ward_Bed%d" % i, "Props", Vector3(beds[i].x, beds[i].y, 30), Vector3(200, 90, 60), PROP)
	_block("Storage_Shelves", "Props", Vector3(3700, 3000, 150), Vector3(100, 600, 300), PROP)
	_block("CorridorC_Cabinet", "Props", Vector3(-200, 3050, 40), Vector3(160, 100, 80), PROP)


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------

func _gameplay() -> void:
	# Doors. The doorway runs along X, so the panel spans X and swings toward +Y (north).
	var ward_door: Node3D = _add(DoorScript.new(), "Gameplay")
	ward_door.name = "Door_WardToCorridorB"
	ward_door.position = ue(3400, 600, 0)
	ward_door.set("width", 2.0)
	ward_door.set("open_yaw", 90.0)
	ward_door.set("starts_open", true)
	_door_sounds(ward_door)

	var heavy_door: Node3D = _add(DoorScript.new(), "Gameplay")
	heavy_door.name = "HeavyDoor_Storage"
	heavy_door.position = ue(3400, 2600, 0)
	heavy_door.set("width", 2.0)
	heavy_door.set("open_yaw", 90.0)
	heavy_door.set("heavy", true)
	heavy_door.set("hold_time", 1.6)
	heavy_door.set("color", Color(0.12, 0.13, 0.14))
	_door_sounds(heavy_door)

	# Chase triggers / checkpoints.
	_trigger("Hint_Controls", Vector3(-600, 0, 175), Vector3(150, 300, 175), Vector4.ZERO, Vector4.ZERO,
		"[F] flashlight    [SHIFT] run    [Q] look back    [RMB] focus beam", false)
	# It bursts out of the lobby behind you.
	_trigger("Chase_Start", Vector3(700, 0, 175), Vector3(60, 150, 175),
		Vector4(-650, 0, 0, 0), Vector4(850, 0, 0, 0), "Run.")
	get_node_or_null_trigger("Chase_Start").set("stinger", Audio.sfx("stinger"))
	_trigger("Checkpoint_Storage", Vector3(3400, 2800, 200), Vector3(300, 120, 200),
		Vector4(3400, 1500, 0, 90), Vector4(3400, 2900, 0, 180))
	_trigger("Checkpoint_CorridorC", Vector3(1000, 2960, 175), Vector3(60, 150, 175),
		Vector4(1300, 3300, 0, -90), Vector4(850, 2960, 0, 180))

	# Vent crawlspace: extends past both mouths so the player crouches before reaching it.
	var vent: Area3D = _add(VentScript.new(), "Gameplay")
	vent.name = "VentZone"
	vent.position = ue(2250, 2960, 100)
	vent.set("extent", ue(900, 150, 100))
	vent.set("ambush_point", _marker(vent, "AmbushPoint", Vector4(1300, 3300, 0, -90)))

	var safe: Area3D = _add(SafeScript.new(), "Gameplay")
	safe.name = "SafeZone_Outside"
	safe.position = ue(-2600, 2950, 300)
	safe.set("extent", ue(800, 900, 300))
	safe.set("message", "It won't follow you into the open. Not yet.")
	safe.set("next_level", "res://scenes/jungle.tscn")

	# Pickups.
	for b in [["Battery_Lobby", ue(-350, -250, 120)], ["Battery_Ward", ue(3650, 450, 40)], ["Battery_Storage", ue(3150, 3300, 40)]]:
		var pickup: Area3D = _add(BatteryScript.new(), "Gameplay")
		pickup.name = b[0]
		pickup.position = b[1]
		pickup.set("pickup_sound", Audio.sfx("pickup"))

	# Player, pursuer, music.
	var player: CharacterBody3D = _add(PlayerScript.new(), "Gameplay")
	player.name = "Player"
	player.position = ue(-600, 0, 0)
	player.rotation.y = _yaw(0.0)
	Audio.setup_player(player)

	var pursuer: CharacterBody3D = _add(PursuerScript.new(), "Gameplay")
	pursuer.name = "Pursuer"
	pursuer.position = ue(-700, 300, 0)
	Audio.setup_pursuer(pursuer)

	var music: Node = _add(MusicScript.new(), "Gameplay")
	music.name = "MusicDirector"
	Audio.setup_music(music, "building")


func get_node_or_null_trigger(label: String) -> Node:
	return _folder("Gameplay").get_node(label)


func _door_sounds(door: Node) -> void:
	door.set("slam_sound", Audio.sfx("door_slam"))
	door.set("creak_sound", Audio.sfx("creak"))
	door.set("break_sound", Audio.sfx("door_break"))


## pursuer_world / respawn_world are (x, y, z, yaw) at floor level, in Unreal units.
func _trigger(label: String, loc: Vector3, extent: Vector3, pursuer_world: Vector4, respawn_world: Vector4,
		hint := "", starts_chase := true) -> void:
	var t: Area3D = _add(TriggerScript.new(), "Gameplay")
	t.name = label
	t.position = ue(loc.x, loc.y, loc.z)
	t.set("extent", ue(extent.x, extent.y, extent.z))
	t.set("starts_chase", starts_chase)
	t.set("hint", hint)
	if starts_chase:
		t.set("pursuer_start", _marker(t, "PursuerStart", pursuer_world))
		t.set("player_respawn", _marker(t, "PlayerRespawn", respawn_world))


# ---------------------------------------------------------------------------
# Lights and atmosphere
# ---------------------------------------------------------------------------

func _light(label: String, loc: Vector3, energy := 1.0, color := Color(0.85, 0.95, 1.0), faultiness := 0.3, radius := 9.0) -> void:
	var l: OmniLight3D = _add(LightScript.new(), "Lights")
	l.name = label
	l.position = ue(loc.x, loc.y, loc.z)
	l.light_color = color
	l.omni_range = radius
	l.shadow_enabled = true
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	l.set("energy", energy)
	l.set("faultiness", faultiness)


func _lights() -> void:
	_light("Light_Lobby", Vector3(-400, 0, 370), 0.45, Color(0.85, 0.95, 1.0), 0.6)
	var xs := [400, 1200, 2000, 2800]
	for i in xs.size():
		_light("Light_CorridorA_%d" % i, Vector3(xs[i], 0, 325), 1.0, Color(0.85, 0.95, 1.0), 0.15 + 0.15 * i)
	_light("Light_Ward_Emergency", Vector3(3400, 100, 375), 1.4, Color(1.0, 0.12, 0.05), 0.05, 12.0)
	var ys := [1000, 1800, 2400]
	for i in ys.size():
		_light("Light_CorridorB_%d" % i, Vector3(3400, ys[i], 325), 1.0, Color(0.85, 0.95, 1.0), 0.4)
	_light("Light_Storage", Vector3(3400, 3000, 375), 0.35, Color(0.85, 0.95, 1.0), 0.7)
	xs = [1000, 200, -600, -1300]
	for i in xs.size():
		_light("Light_CorridorC_%d" % i, Vector3(xs[i], 2960, 325), 0.75, Color(0.85, 0.95, 1.0), 0.5)


func _environment() -> void:
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color8(150, 170, 255)
	moon.light_energy = 0.25
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	_add(moon, "Environment")
	# Unreal pitch -55, yaw 35.
	moon.rotation = Vector3(deg_to_rad(-55.0), _yaw(35.0), 0.0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.02, 0.022, 0.03)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	# Fog that glows on its own ruins the dark; only lights should reveal it.
	env.fog_enabled = true
	env.fog_light_color = Color(0.002, 0.002, 0.003)
	env.fog_density = 0.015
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_albedo = Color(0.6, 0.6, 0.6)
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_length = 40.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_add(world_env, "Environment")
