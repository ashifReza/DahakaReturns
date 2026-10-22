extends RefCounted
## Builds "The Jungle": you come out of the building into the trees at night.
##
##   start -> stalked (it shows itself between the trees, vanishes when you
##   look) -> it bursts out of the ferns: run -> jump the fallen log -> crawl
##   under the root tangle (it loses you, comes round) -> rope bridge over a
##   chasm: cut the ropes behind you -> it climbs back out -> into the river,
##   which it won't cross.
##
## Godot units: metres, Y up, the route runs toward -Z.

const PlayerScript := preload("res://scripts/player.gd")
const PursuerScript := preload("res://scripts/pursuer.gd")
const ForestScript := preload("res://scripts/forest.gd")
const TriggerScript := preload("res://scripts/chase_trigger.gd")
const StalkScript := preload("res://scripts/stalk_zone.gd")
const VentScript := preload("res://scripts/vent_zone.gd")
const SafeScript := preload("res://scripts/safe_zone.gd")
const KillScript := preload("res://scripts/kill_zone.gd")
const BridgeScript := preload("res://scripts/rope_bridge.gd")
const BatteryScript := preload("res://scripts/battery_pickup.gd")
const MusicScript := preload("res://scripts/music_director.gd")
const LevelScript := preload("res://scripts/level.gd")
const Audio := preload("res://tools/level_audio.gd")

const PATH := [
	Vector2(0, 8), Vector2(0, -15), Vector2(7, -35), Vector2(3, -55), Vector2(-4, -74),
	Vector2(-8, -92), Vector2(-6, -108), Vector2(-6, -127), Vector2(-2, -150), Vector2(6, -165),
	Vector2(6, -172), Vector2(6, -196), Vector2(8, -212), Vector2(0, -235), Vector2(-6, -250),
	Vector2(-4, -266),
]
const CHASM := Vector2(-196.0, -172.0)  # z range
const RIVER := Vector2(-284.0, -258.0)

var root: Node3D
var _folders := {}
var GROUND := _mat(Color(0.035, 0.03, 0.02))
var ROCK := _mat(Color(0.05, 0.05, 0.055))
var BARK := _mat(Color(0.09, 0.065, 0.045))


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


static func p3(v: Vector2, y := 0.0) -> Vector3:
	return Vector3(v.x, y, v.y)


func build() -> Node3D:
	root = Node3D.new()
	root.name = "Jungle"
	root.set_script(LevelScript)
	_environment()
	_terrain()
	_forest()
	_set_pieces()
	_gameplay()
	_atmosphere()
	return root


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add(node: Node, folder: String) -> Node:
	_folder(folder).add_child(node)
	node.owner = root
	return node


func _folder(path: String) -> Node:
	if path == "":
		return root
	if _folders.has(path):
		return _folders[path]
	var n := Node3D.new()
	n.name = path
	root.add_child(n)
	n.owner = root
	_folders[path] = n
	return n


func _box(label: String, folder: String, center: Vector3, size: Vector3, mat: Material, collide := true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = label
	b.position = center
	b.size = size
	b.material = mat
	b.use_collision = collide
	b.collision_layer = 1
	b.collision_mask = 0
	return _add(b, folder)


func _marker(parent: Node3D, label: String, at: Vector3, face: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = label
	parent.add_child(m)
	m.owner = root
	m.position = at - parent.position
	m.rotation.y = Chase.facing(face)
	return m


## Point `t` of the way along the path (0 = start, 1 = end), by distance.
func _along(t: float) -> Vector3:
	var lengths := []
	var total := 0.0
	for i in PATH.size() - 1:
		var l: float = PATH[i].distance_to(PATH[i + 1])
		lengths.append(l)
		total += l
	var want := t * total
	for i in lengths.size():
		if want <= lengths[i]:
			return p3(PATH[i].lerp(PATH[i + 1], want / lengths[i]))
		want -= lengths[i]
	return p3(PATH[-1])


## Path direction near a point (toward the end of the route).
func _heading(at: Vector3) -> Vector3:
	var best := 0
	var best_d := INF
	for i in PATH.size() - 1:
		var d := Vector2(at.x, at.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), PATH[i], PATH[i + 1]))
		if d < best_d:
			best_d = d
			best = i
	var dir: Vector2 = (PATH[best + 1] - PATH[best]).normalized()
	return Vector3(dir.x, 0, dir.y)


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------

func _terrain() -> void:
	# Deep blocks so the chasm has proper cliffs.
	_box("Ground_Near", "Terrain", Vector3(2.5, -25, (15 + CHASM.y) / 2), Vector3(110, 50, 15 - CHASM.y), GROUND)
	_box("Ground_Far", "Terrain", Vector3(2.5, -25, (CHASM.x + RIVER.y) / 2), Vector3(110, 50, CHASM.x - RIVER.y), GROUND)
	_box("RiverBed", "Terrain", Vector3(2.5, -25.8, (RIVER.x + RIVER.y) / 2), Vector3(110, 50, RIVER.y - RIVER.x), GROUND)
	_box("Ground_FarBank", "Terrain", Vector3(2.5, -25, RIVER.x - 15), Vector3(110, 50, 30), GROUND)
	_box("Chasm_Floor", "Terrain", Vector3(2.5, -46, (CHASM.x + CHASM.y) / 2), Vector3(110, 2, CHASM.y - CHASM.x), ROCK)
	# Jagged rock teeth along both lips of the chasm.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for lip in [CHASM.x, CHASM.y]:
		for k in 16:
			var x := -45.0 + k * 6.5 + rng.randf_range(-1.5, 1.5)
			if absf(x - 6.0) < 3.0:
				continue  # keep the bridge's ends clear
			var h := rng.randf_range(0.4, 1.6)
			_box("Lip_%d_%d" % [int(lip), k], "Terrain", Vector3(x, h * 0.5 - 0.2, lip + (1.0 if lip == CHASM.x else -1.0) * 0.6),
				Vector3(rng.randf_range(1.5, 3.5), h, 1.2), ROCK, false)


func _forest() -> void:
	var forest: Node3D = _add(ForestScript.new(), "")
	forest.name = "Forest"
	var path := PackedVector3Array()
	for v in PATH:
		path.append(p3(v))
	forest.set("path", path)
	var gaps: Array[Vector2] = [Vector2(CHASM.x + 0.5, CHASM.y - 0.5)]
	forest.set("gaps", gaps)
	forest.set("rustle_sound", Audio.sfx("rustle"))


# ---------------------------------------------------------------------------
# Set pieces
# ---------------------------------------------------------------------------

func _set_pieces() -> void:
	# A fallen log across the trail: jump it.
	var fallen := CSGCylinder3D.new()
	fallen.name = "FallenLog"
	fallen.radius = 0.32
	fallen.height = 16.0
	fallen.sides = 10
	fallen.material = BARK
	fallen.use_collision = true
	fallen.collision_layer = 1
	fallen.position = Vector3(-7, 0.28, -100)
	fallen.rotation_degrees = Vector3(0, 8, 90)
	_add(fallen, "SetPieces")

	# The root tangle: only a crawlspace underneath. It's far too big to follow.
	_box("RootTangle", "SetPieces", Vector3(-6, 3.15, -122), Vector3(18, 4.0, 12), BARK)
	for k in 5:
		var root_log := CSGCylinder3D.new()
		root_log.name = "Root_%d" % k
		root_log.radius = 0.5 + 0.15 * (k % 3)
		root_log.height = 14.0
		root_log.material = BARK
		root_log.position = Vector3(-6 + (k - 2) * 2.5, 2.0 + (k % 2) * 1.5, -122 + (k - 2) * 2.0)
		root_log.rotation_degrees = Vector3(80 + k * 6, 20 * (k - 2), 0)
		_add(root_log, "SetPieces")

	# The rope bridge over the chasm, from the near lip toward -Z.
	var bridge: Node3D = _add(BridgeScript.new(), "SetPieces")
	bridge.name = "RopeBridge"
	bridge.position = Vector3(6, 0, CHASM.y)
	bridge.set("length", CHASM.y - CHASM.x)
	bridge.set("snap_sound", Audio.sfx("rope_snap"))
	bridge.set("collapse_sound", Audio.sfx("bridge_collapse"))

	# The river, and a waterfall pouring off a cliff on the far bank.
	var water := MeshInstance3D.new()
	water.name = "River"
	var plane := PlaneMesh.new()
	plane.size = Vector2(110, RIVER.y - RIVER.x)
	var water_mat := ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	plane.material = water_mat
	water.mesh = plane
	water.position = Vector3(2.5, -0.3, (RIVER.x + RIVER.y) / 2)
	_add(water, "SetPieces")

	_box("Cliff", "SetPieces", Vector3(0, 7, RIVER.x - 2), Vector3(60, 14, 4), ROCK, false)
	var fall := MeshInstance3D.new()
	fall.name = "Waterfall"
	var quad := QuadMesh.new()
	quad.size = Vector2(7, 14)
	var fall_mat := ShaderMaterial.new()
	fall_mat.shader = preload("res://shaders/waterfall.gdshader")
	quad.material = fall_mat
	fall.mesh = quad
	fall.position = Vector3(-3, 7, RIVER.x + 0.05)
	_add(fall, "SetPieces")
	var roar := AudioStreamPlayer3D.new()
	roar.name = "WaterfallSound"
	roar.stream = load("res://audio/ambience/water.wav")
	roar.autoplay = true
	roar.unit_size = 12.0
	roar.position = Vector3(-3, 1, RIVER.x + 1)
	_add(roar, "SetPieces")
	var mist := _particles(Color(0.6, 0.7, 0.75, 0.25), 40, 3.0, Vector3(4, 0.5, 1), 0.9, false)
	mist.name = "Mist"
	mist.position = Vector3(-3, 0.2, RIVER.x + 1.5)
	(mist.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.3, 0.4)
	_add(mist, "SetPieces")


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------

func _gameplay() -> void:
	var start := p3(PATH[0])
	var player: CharacterBody3D = _add(PlayerScript.new(), "Gameplay")
	player.name = "Player"
	player.position = start
	player.rotation.y = Chase.facing(Vector3(0, 0, -1))
	Audio.setup_player(player)

	var pursuer: CharacterBody3D = _add(PursuerScript.new(), "Gameplay")
	pursuer.name = "Pursuer"
	pursuer.position = Vector3(30, 0, 30)
	Audio.setup_pursuer(pursuer)

	var music: Node = _add(MusicScript.new(), "Gameplay")
	music.name = "MusicDirector"
	Audio.setup_music(music, "jungle")

	# Stalking: from the start until it attacks. It shows itself off the trail.
	var stalk: Area3D = _add(StalkScript.new(), "Gameplay")
	stalk.name = "StalkZone"
	stalk.position = start + Vector3(0, 1.5, -3)
	stalk.set("extent", Vector3(7, 1.5, 3))
	stalk.set("hint", "The jungle. Keep moving.\nDon't stare into the trees.")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 18:
		var at := _along(0.03 + k * 0.012)
		var side := -1.0 if k % 2 == 0 else 1.0
		var dir := _heading(at)
		var spot := at + dir.cross(Vector3.UP) * side * rng.randf_range(5.0, 6.3) + dir * rng.randf_range(-2, 2)
		_marker(stalk, "Stalk_%02d" % k, spot, -dir)

	# It bursts out of the ferns just behind you.
	_trigger("Chase_Start", Vector3(-4, 1.75, -72), Vector3(8, 1.75, 0.8),
		Vector3(3, 0, -59), Vector3(-1, 0, -1), Vector3(-5, 0, -76), Vector3(-0.2, 0, -1),
		"RUN.", true, Audio.sfx("stinger"))

	_trigger("Hint_Log", Vector3(-6.5, 1.75, -94), Vector3(8, 1.75, 0.8), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		"[SPACE] jump", false)

	# Root tangle crawlspace: it loses you and comes round the side.
	var vent: Area3D = _add(VentScript.new(), "Gameplay")
	vent.name = "RootCrawl"
	vent.position = Vector3(-6, 1, -122)
	vent.set("extent", Vector3(8, 1, 7.5))
	vent.set("ambush_delay", 1.0)
	vent.set("ambush_point", _marker(vent, "AmbushPoint", Vector3(1.2, 0, -138), Vector3(-1, 0, -0.3)))

	_trigger("Checkpoint_AfterRoots", Vector3(-3, 1.75, -142), Vector3(8, 1.75, 0.8),
		Vector3(1.2, 0, -137), Vector3(-1, 0, -0.5), Vector3(-3, 0, -145), Vector3(0.3, 0, -1))

	_trigger("Hint_Bridge", Vector3(7, 1.75, -199), Vector3(6, 1.75, 1.5), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		"Cut the ropes! Hold [E] at the posts.", false)

	# Past the bridge: it climbs out of the chasm behind you.
	var ambush := _trigger("Ambush_Climb", Vector3(8, 1.75, -214), Vector3(8, 1.75, 0.8),
		Vector3(3, 0, -198), Vector3(0.2, 0, -1), Vector3(8, 0, -216), Vector3(-0.3, 0, -1))
	ambush.set("ambush", true)
	ambush.set("activation_delay", 0.6)

	var chasm: Area3D = _add(KillScript.new(), "Gameplay")
	chasm.name = "ChasmKillZone"
	chasm.position = Vector3(2.5, -9, (CHASM.x + CHASM.y) / 2)
	chasm.set("extent", Vector3(55, 3, (CHASM.y - CHASM.x) / 2))

	var safe: Area3D = _add(SafeScript.new(), "Gameplay")
	safe.name = "SafeZone_River"
	safe.position = Vector3(-4, 0, -265)
	safe.set("extent", Vector3(14, 2, 5))
	safe.set("message", "It won't cross the water.\nFor now.")

	for b in [["Battery_Ferns", Vector3(5.5, 0.4, -42)], ["Battery_Log", Vector3(-11, 0.4, -98)], ["Battery_Ravine", Vector3(10, 0.4, -162)]]:
		var pickup: Area3D = _add(BatteryScript.new(), "Gameplay")
		pickup.name = b[0]
		pickup.position = b[1]
		pickup.set("pickup_sound", Audio.sfx("pickup"))


func _trigger(label: String, at: Vector3, extent: Vector3, pursuer_at: Vector3, pursuer_face: Vector3,
		respawn_at: Vector3, respawn_face: Vector3, hint := "", starts_chase := true,
		stinger: AudioStream = null) -> Area3D:
	var t: Area3D = _add(TriggerScript.new(), "Gameplay")
	t.name = label
	t.position = at
	t.set("extent", extent)
	t.set("starts_chase", starts_chase)
	t.set("hint", hint)
	if stinger:
		t.set("stinger", stinger)
	if starts_chase:
		t.set("pursuer_start", _marker(t, "PursuerStart", pursuer_at, pursuer_face))
		t.set("player_respawn", _marker(t, "PlayerRespawn", respawn_at, respawn_face))
	return t


# ---------------------------------------------------------------------------
# Atmosphere
# ---------------------------------------------------------------------------

func _environment() -> void:
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.35
	moon.light_volumetric_fog_energy = 2.0
	# Off by default: moon shadows through the trees cost about 15 FPS on a
	# GeForce 930MX. Turn on for crisper trunks on a stronger GPU.
	moon.shadow_enabled = false
	moon.directional_shadow_max_distance = 35.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_add(moon, "Environment")
	moon.rotation_degrees = Vector3(-52, 25, 0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.01, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.02, 0.035, 0.03)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.004, 0.008, 0.007)
	env.fog_density = 0.025
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.5, 0.6, 0.55)
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_length = 40.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_add(world_env, "Environment")


func _atmosphere() -> void:
	# Fireflies drifting over the trail.
	for k in 9:
		var f := _particles(Color(0.7, 1.0, 0.35, 1.0), 22, 6.0, Vector3(9, 2.5, 9), 0.06, true)
		f.name = "Fireflies_%d" % k
		f.position = _along(0.04 + k * 0.11) + Vector3(0, 1.8, 0)
		var pm := f.process_material as ParticleProcessMaterial
		pm.gravity = Vector3.ZERO
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_speed_random = 0.5
		_add(f, "Atmosphere")

	# Glowing mushrooms at the trail's edge: a little guidance in the dark.
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.05, 0.1, 0.1)
	cap.emission_enabled = true
	cap.emission = Color(0.2, 0.9, 0.85)
	cap.emission_energy_multiplier = 1.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 14:
		var at := _along(0.02 + k * 0.07)
		if at.z < CHASM.y + 3 and at.z > CHASM.x - 3:
			continue
		var side := -1.0 if k % 2 == 0 else 1.0
		var spot := at + _heading(at).cross(Vector3.UP) * side * rng.randf_range(2.3, 3.2)
		var cluster := Node3D.new()
		cluster.name = "Mushrooms_%02d" % k
		_add(cluster, "Atmosphere")
		cluster.position = spot
		for m in rng.randi_range(3, 6):
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = rng.randf_range(0.05, 0.12)
			s.height = s.radius
			mi.mesh = s
			mi.material_override = cap
			mi.position = Vector3(rng.randf_range(-0.4, 0.4), s.radius * 0.6, rng.randf_range(-0.4, 0.4))
			cluster.add_child(mi)
			mi.owner = root
		if k % 2 == 0:
			var glow := OmniLight3D.new()
			glow.light_color = Color(0.3, 1.0, 0.9)
			glow.light_energy = 0.35
			glow.omni_range = 3.5
			glow.position = Vector3(0, 0.3, 0)
			cluster.add_child(glow)
			glow.owner = root


func _particles(color: Color, amount: int, lifetime: float, box: Vector3, size: float, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.visibility_aabb = AABB(-box - Vector3.ONE * 3, (box + Vector3.ONE * 3) * 2)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 1))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = color * 2.5
	quad.material = m
	p.draw_pass_1 = quad
	return p
