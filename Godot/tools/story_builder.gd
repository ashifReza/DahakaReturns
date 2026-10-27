extends RefCounted
## Builds the story level, "Blackwood":
##
##   Route 9 at sunset: your police car on the shoulder, the forest trail
##   across the road -> the trail, with Daniel's 7 belongings along it and a
##   thicket at the end -> drag marks through the thicket to a clearing ->
##   the house: living room, study, kitchen, bedroom -> out the kitchen's
##   back door -> a second trail back to Route 9, where backup is waiting.
##
## The story itself (dialogue, scares, sunset) is run by scripts/story.gd.
## Godot units: metres, Y up. The road runs along X; the forest is toward -Z.

const PlayerScript := preload("res://scripts/player.gd")
const PursuerScript := preload("res://scripts/pursuer.gd")
const ForestScript := preload("res://scripts/forest.gd")
const TriggerScript := preload("res://scripts/chase_trigger.gd")
const VentScript := preload("res://scripts/vent_zone.gd")
const SafeScript := preload("res://scripts/safe_zone.gd")
const BatteryScript := preload("res://scripts/battery_pickup.gd")
const MusicScript := preload("res://scripts/music_director.gd")
const LevelScript := preload("res://scripts/level.gd")
const DoorScript := preload("res://scripts/chase_door.gd")
const FlickerScript := preload("res://scripts/flicker_light.gd")
const StoryScript := preload("res://scripts/story.gd")
const ZoneScript := preload("res://scripts/story_zone.gd")
const ItemScript := preload("res://scripts/story_interactable.gd")
const FigureScript := preload("res://scripts/shadow_figure.gd")
const SirenScript := preload("res://scripts/siren.gd")
const Audio := preload("res://tools/level_audio.gd")

## The road's edges (z), and the forest's edge along it.
const ROAD := Vector2(12.0, 22.0)
const FOREST_EDGE := 3.6
## Everything north of the forest edge is kept clear of trees.
const STREET_CLEAR := Rect2(-200, FOREST_EDGE, 400, 100)
## A barricade across the road: the far side is only reached at the end.
const BARRICADE_X := -40.0

## The search trail, from the road to the house's clearing.
const TRAIL := [
	Vector2(0, 6), Vector2(0, -12), Vector2(5, -30), Vector2(2, -50), Vector2(-5, -68),
	Vector2(-7, -86), Vector2(-2, -104), Vector2(4, -122), Vector2(3, -140), Vector2(0, -156),
]
## The escape trail, from the kitchen's back door back to the road.
const ESCAPE := [
	Vector2(-16, -178), Vector2(-32, -180), Vector2(-46, -172), Vector2(-58, -156), Vector2(-64, -136),
	Vector2(-60, -114), Vector2(-64, -92), Vector2(-62, -70), Vector2(-66, -48), Vector2(-63, -26),
	Vector2(-64, -6), Vector2(-64, 6),
]
## The house: front wall centre at ground level. Rooms are built relative to it.
const HOUSE := Vector3(0, 0, -168)
const CLEARING := Rect2(-20, -196, 40, 40)
const FLOOR := 1.0
const CEIL := 4.4
const DOOR_H := 3.0
const WALL_T := 0.3
## Where along TRAIL (0..1) the thicket blocks the way until every clue is found.
const THICKET_T := 0.84

var root: Node3D
var _folders := {}
var GROUND := _mat(Color(0.07, 0.06, 0.045))
var ASPHALT := _mat(Color(0.05, 0.05, 0.055), 0.7)
var GRAVEL := _mat(Color(0.12, 0.11, 0.1))
var PAINT_Y := _mat(Color(0.75, 0.6, 0.15), 0.6)
var PAINT_W := _mat(Color(0.7, 0.7, 0.68), 0.6)
var BARK := _mat(Color(0.09, 0.065, 0.045))
var SIDING := _mat(Color(0.2, 0.17, 0.13))
var WALLPAPER := _mat(Color(0.26, 0.28, 0.2))
var PLANKS := _mat(Color(0.17, 0.11, 0.07))
var DARK_WOOD := _mat(Color(0.09, 0.055, 0.035))
var ROOF := _mat(Color(0.08, 0.08, 0.085))
var FABRIC := _mat(Color(0.18, 0.12, 0.1))
var METAL := _mat(Color(0.25, 0.25, 0.27), 0.4)
var BLOOD := _mat(Color(0.22, 0.008, 0.008), 0.25)
var OLD_BLOOD := _mat(Color(0.11, 0.02, 0.015), 0.5)
var BOARDS := _mat(Color(0.13, 0.09, 0.06))


static func _mat(c: Color, roughness := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	return m


static func _emissive(c: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func p3(v: Vector2, y := 0.0) -> Vector3:
	return Vector3(v.x, y, v.y)


func build() -> Node3D:
	root = Node3D.new()
	root.name = "Blackwood"
	root.set_script(LevelScript)
	_environment()
	_ground()
	_street()
	_car()
	_forests()
	_trail_set_pieces()
	_clues()
	_house()
	_escape_route()
	_gameplay()
	_zones()
	_atmosphere()
	var director: Node = StoryScript.new()
	director.name = "Director"
	director.set("car_door_sound", Audio.sfx("car_door"))
	director.set("branch_sound", Audio.sfx("branch_snap"))
	director.set("whoosh_sound", Audio.sfx("whoosh"))
	director.set("screech_sound", Audio.sfx("screech"))
	director.set("creak_sound", Audio.sfx("creak"))
	director.set("stinger_sound", Audio.sfx("stinger"))
	director.set("click_sound", Audio.sfx("click"))
	director.set("house_ambience", load("res://audio/ambience/building.wav"))
	director.set("jungle_ambience", load("res://audio/ambience/jungle.wav"))
	_add(director, "")
	return root


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add(node: Node, folder: String) -> Node:
	_folder(folder).add_child(node)
	_own(node)
	return node


func _own(node: Node) -> void:
	node.owner = root


func _folder(path: String) -> Node:
	if path == "":
		return root
	if _folders.has(path):
		return _folders[path]
	var parent := root
	var leaf := path
	if "/" in path:
		parent = _folder(path.get_base_dir())
		leaf = path.get_file()
	var n := Node3D.new()
	n.name = leaf
	parent.add_child(n)
	n.owner = root
	_folders[path] = n
	return n


func _box(label: String, folder: String, center: Vector3, size: Vector3, mat: Material, collide := true, rot := Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = label
	b.position = center
	b.rotation_degrees = rot
	b.size = size
	b.material = mat
	b.use_collision = collide
	b.collision_layer = 1
	b.collision_mask = 0
	return _add(b, folder)


## A plain mesh box (no CSG, no collision): props and decals.
func _prop(label: String, parent: Node, at: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot
	parent.add_child(mi)
	_own(mi)
	return mi


func _cyl(label: String, parent: Node, at: Vector3, radius: float, height: float, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot
	parent.add_child(mi)
	_own(mi)
	return mi


## An invisible wall (or ramp) of the given size and transform.
func _collider(label: String, folder: String, xform: Transform3D, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = xform
	_add(body, folder)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)
	_own(cs)
	return body


## Invisible wall from a to b (on the ground), 4m tall.
func _wall_line(label: String, folder: String, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var mid := (a + b) * 0.5
	_collider(label, folder, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(mid.x, 2.0, mid.y)), Vector3(0.5, 4.0, d.length() + 0.5))


func _marker(parent: Node3D, label: String, at: Vector3, face: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = label
	parent.add_child(m)
	m.owner = root
	# The level isn't in the scene tree while it's built, so work out the
	# parent's frame by hand.
	m.transform = Transform3D(Basis(Vector3.UP, Chase.facing(face) - _yaw_of(parent)), _to_local(parent, at))
	return m


## World yaw of a node (the builder only ever rotates around Y).
func _yaw_of(n: Node) -> float:
	var yaw := 0.0
	while n != null and n is Node3D:
		yaw += (n as Node3D).rotation.y
		n = n.get_parent()
	return yaw


## World point to a node's local frame, for nodes not yet in the tree.
func _to_local(n: Node3D, world: Vector3) -> Vector3:
	var chain: Array[Node3D] = []
	var c: Node = n
	while c != null and c is Node3D:
		chain.push_front(c)
		c = c.get_parent()
	var xf := Transform3D.IDENTITY
	for node in chain:
		xf = xf * node.transform
	return xf.affine_inverse() * world


static func _along(path: Array, t: float) -> Vector3:
	var total := 0.0
	for i in path.size() - 1:
		total += (path[i] as Vector2).distance_to(path[i + 1])
	var want := t * total
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var l := a.distance_to(b)
		if want <= l:
			return p3(a.lerp(b, want / l))
		want -= l
	return p3(path[-1])


## Path direction near a point (toward the end of the path).
static func _heading(path: Array, at: Vector3) -> Vector3:
	var best := 0
	var best_d := INF
	var q := Vector2(at.x, at.z)
	for i in path.size() - 1:
		var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, path[i], path[i + 1]))
		if d < best_d:
			best_d = d
			best = i
	var dir: Vector2 = ((path[best + 1] as Vector2) - path[best]).normalized()
	return Vector3(dir.x, 0, dir.y)


func _house_pos(local: Vector3) -> Vector3:
	return HOUSE + local


# ---------------------------------------------------------------------------
# Ground, road and the city behind
# ---------------------------------------------------------------------------

func _ground() -> void:
	_box("Ground", "Terrain", Vector3(-30, -1, -85), Vector3(220, 2, 300), GROUND)


func _street() -> void:
	var road_mid := (ROAD.x + ROAD.y) * 0.5
	_box("Road", "Street", Vector3(-30, 0.01, road_mid), Vector3(220, 0.04, ROAD.y - ROAD.x), ASPHALT, false)
	_box("Shoulder_North", "Street", Vector3(-30, 0.005, ROAD.y + 3), Vector3(220, 0.02, 6), GRAVEL, false)
	_box("Verge_South", "Street", Vector3(-30, 0.005, (FOREST_EDGE + ROAD.x) * 0.5), Vector3(220, 0.02, ROAD.x - FOREST_EDGE), GRAVEL, false)
	var marks := _folder("Street/Markings")
	for k in 44:
		_prop("Dash_%02d" % k, marks, Vector3(-135 + k * 5.0, 0.035, road_mid), Vector3(2.4, 0.01, 0.16), PAINT_Y)
	for z in [ROAD.x + 0.3, ROAD.y - 0.3]:
		_prop("Edge_%d" % int(z), marks, Vector3(-30, 0.035, z), Vector3(220, 0.01, 0.12), PAINT_W)

	# Street lamps along the north side, and one at the trail entrance.
	var posts := _folder("Street/LampPosts")
	var k := 0
	for at in [Vector2(-30, 27.5), Vector2(-5, 27.5), Vector2(20, 27.5), Vector2(42, 27.5), Vector2(6, 8.5), Vector2(-75, 27.5), Vector2(-55, 8.5)]:
		var arm := 1.6 if at.y > 20 else -1.6
		_cyl("Post_%d" % k, posts, Vector3(at.x, 3.0, at.y), 0.09, 6.0, METAL)
		_prop("Arm_%d" % k, posts, Vector3(at.x, 5.9, at.y - arm * 0.5), Vector3(0.1, 0.1, 1.6), METAL)
		_prop("Lamp_%d" % k, posts, Vector3(at.x, 5.8, at.y - arm), Vector3(0.45, 0.12, 0.3), _emissive(Color(1.0, 0.7, 0.35), 2.0))
		var light := OmniLight3D.new()
		light.name = "Light_%d" % k
		light.light_color = Color(1.0, 0.68, 0.38)
		light.omni_range = 16.0
		light.omni_attenuation = 1.4
		light.light_energy = 0.3
		light.light_volumetric_fog_energy = 0.3
		light.position = Vector3(at.x, 5.5, at.y - arm)
		_add(light, "Street/Lamps")
		k += 1

	# Trail sign and a missing poster at the entrance.
	var board := _folder("Street/Sign")
	_prop("SignPost_L", board, Vector3(-6.2, 1.1, 6.0), Vector3(0.14, 2.2, 0.14), DARK_WOOD)
	_prop("SignPost_R", board, Vector3(-3.8, 1.1, 6.0), Vector3(0.14, 2.2, 0.14), DARK_WOOD)
	_prop("SignBoard", board, Vector3(-5.0, 1.85, 6.05), Vector3(2.8, 0.9, 0.08), PLANKS)
	_label("SignText", board, Vector3(-5.0, 1.87, 6.11), "BLACKWOOD FOREST\nTRAIL ENTRANCE", 34, Color(0.9, 0.85, 0.7), 0.0)
	_label("Poster", posts, Vector3(6.0, 1.7, 8.38), "MISSING\nDANIEL REYES, 34\nLast seen Oct 20\nCall 555-0142", 22, Color(0.1, 0.08, 0.06), 180.0, Color(0.85, 0.82, 0.72))

	# Invisible bounds: the forest edge (gaps for both trails), the far side,
	# the east end, and the barricade.
	_wall_line("Edge_East", "Street/Bounds", Vector2(7.0, FOREST_EDGE), Vector2(48, FOREST_EDGE))
	_wall_line("Edge_Mid", "Street/Bounds", Vector2(-57.0, FOREST_EDGE), Vector2(-7.0, FOREST_EDGE))
	_wall_line("Edge_West", "Street/Bounds", Vector2(-110, FOREST_EDGE), Vector2(-71.0, FOREST_EDGE))
	# Short walls joining the edge to each trail's own walls.
	for x in [-71.0, -57.0, -7.0, 7.0]:
		_wall_line("Trailhead_%d" % int(x), "Street/Bounds", Vector2(x, FOREST_EDGE), Vector2(x, 6.5))
	_wall_line("North", "Street/Bounds", Vector2(-110, 34), Vector2(48, 34))
	_wall_line("East", "Street/Bounds", Vector2(48, FOREST_EDGE), Vector2(48, 34))
	_wall_line("West", "Street/Bounds", Vector2(-110, FOREST_EDGE), Vector2(-110, 34))
	_wall_line("Barricade", "Street/Bounds", Vector2(BARRICADE_X, FOREST_EDGE), Vector2(BARRICADE_X, 34))
	var barricade := _folder("Street/Barricade")
	for z in [9.0, 14.0, 18.5, 23.0]:
		for side in [-0.6, 0.6]:
			_prop("Leg_%d_%d" % [int(z), int(side * 10)], barricade, Vector3(BARRICADE_X + side * 0.3, 0.5, z), Vector3(0.08, 1.0, 1.4), PAINT_W, Vector3(0, 0, side * 14.0))
		var stripe := _emissive(Color(0.9, 0.35, 0.05), 0.3)
		_prop("Board_%d" % int(z), barricade, Vector3(BARRICADE_X, 0.9, z), Vector3(0.1, 0.3, 2.6), stripe)
	_label("ClosedSign", barricade, Vector3(BARRICADE_X + 0.1, 1.5, 16.3), "ROAD CLOSED", 40, Color(0.95, 0.9, 0.85), 90.0, Color(0.6, 0.1, 0.05))

	# A barrier at the trailhead until you have the flashlight.
	_collider("EntranceBarrier", "Street", Transform3D(Basis.IDENTITY, Vector3(0, 2.0, 4.6)), Vector3(15, 4, 0.5))

	_city()


func _label(label: String, parent: Node, at: Vector3, text: String, size: int, color: Color, yaw: float, back := Color(0, 0, 0, 0)) -> void:
	if back.a > 0.0:
		var lines := text.split("\n").size()
		var w := 0.0
		for l in text.split("\n"):
			w = maxf(w, l.length())
		_prop(label + "_Back", parent, at - Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.01), Vector3(w * size * 0.0011 + 0.15, lines * size * 0.0026 + 0.1, 0.01), _mat(back), Vector3(0, yaw, 0))
	var l3 := Label3D.new()
	l3.name = label
	l3.text = text
	l3.font_size = size
	l3.pixel_size = 0.004
	l3.modulate = color
	l3.outline_size = 0
	l3.position = at
	l3.rotation_degrees.y = yaw
	l3.double_sided = false
	parent.add_child(l3)
	_own(l3)


## Dark blocks of buildings across the road, a few windows still lit.
func _city() -> void:
	var city := _folder("City")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var windows: Array[Transform3D] = []
	var x := -120.0
	while x < 60.0:
		var w := rng.randf_range(10, 18)
		var h := rng.randf_range(8, 28)
		var d := rng.randf_range(10, 16)
		var z := rng.randf_range(44, 56)
		_prop("Block_%d" % int(x), city, Vector3(x + w * 0.5, h * 0.5, z + d * 0.5), Vector3(w, h, d), _mat(Color(0.05, 0.05, 0.06)))
		for fy in range(1, int(h / 3.2)):
			for fx in range(1, int(w / 2.6)):
				if rng.randf() < 0.22:
					windows.append(Transform3D(Basis.IDENTITY, Vector3(x + fx * 2.6, fy * 3.2, z - 0.02)))
		x += w + rng.randf_range(1, 5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.5)
	mm.mesh = quad
	mm.instance_count = windows.size()
	for i in windows.size():
		mm.set_instance_transform(i, windows[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LitWindows"
	mmi.multimesh = mm
	var lit := _emissive(Color(1.0, 0.8, 0.5), 1.5)
	lit.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = lit
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mmi, "City")


# ---------------------------------------------------------------------------
# Hale's car
# ---------------------------------------------------------------------------

## A police cruiser, parked facing +X on the north shoulder. Its local
## forward is -Z and the driver sits on its left (-X), toward the road.
func _police_car(label: String, folder: String, at: Vector3, face: Vector3, siren_on: bool) -> Node3D:
	var car := Node3D.new()
	car.name = label
	car.position = at
	car.rotation.y = Chase.facing(face)
	_add(car, folder)
	var navy := _mat(Color(0.03, 0.04, 0.08), 0.45)
	var white := _mat(Color(0.75, 0.75, 0.75), 0.45)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.1, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	var tyre := _mat(Color(0.02, 0.02, 0.02))

	var body := CSGBox3D.new()
	body.name = "Body"
	body.size = Vector3(1.9, 0.7, 4.7)
	body.position = Vector3(0, 0.6, 0)
	body.material = navy
	body.use_collision = true
	body.collision_layer = 1
	body.collision_mask = 0
	car.add_child(body)
	_own(body)
	for side in [-1.0, 1.0]:
		_prop("Door_%d" % int(side), car, Vector3(0.955 * side, 0.65, 0.15), Vector3(0.02, 0.5, 2.0), white)
		var text := Label3D.new()
		text.name = "Police_%d" % int(side)
		text.text = "POLICE"
		text.font_size = 48
		text.pixel_size = 0.004
		text.modulate = Color(0.05, 0.08, 0.2)
		text.position = Vector3(0.97 * side, 0.68, 0.15)
		text.rotation_degrees.y = 90.0 * side
		car.add_child(text)
		_own(text)
		for end in [-1.0, 1.0]:
			_cyl("Wheel_%d_%d" % [int(side), int(end)], car, Vector3(0.88 * side, 0.36, 1.45 * end), 0.36, 0.26, tyre, Vector3(0, 0, 90))

	# Cabin: roof, pillars, glass, dash, seats, wheel.
	_prop("Roof", car, Vector3(0, 1.5, 0.25), Vector3(1.7, 0.07, 2.0), white)
	for px in [-0.82, 0.82]:
		for pz in [-0.65, 1.2]:
			_prop("Pillar_%d_%d" % [int(px * 10), int(pz * 10)], car, Vector3(px, 1.22, pz), Vector3(0.06, 0.58, 0.08), navy, Vector3(-18 if pz < 0 else 12, 0, 0))
	_prop("Windshield", car, Vector3(0, 1.22, -0.72), Vector3(1.62, 0.62, 0.02), glass, Vector3(-38, 0, 0))
	_prop("RearWindow", car, Vector3(0, 1.22, 1.28), Vector3(1.62, 0.55, 0.02), glass, Vector3(30, 0, 0))
	for side in [-1.0, 1.0]:
		_prop("SideWindow_%d" % int(side), car, Vector3(0.84 * side, 1.22, 0.27), Vector3(0.02, 0.5, 1.85), glass)
	_prop("Dash", car, Vector3(0, 1.0, -0.6), Vector3(1.75, 0.22, 0.35), _mat(Color(0.04, 0.04, 0.045)))
	var wheel := MeshInstance3D.new()
	wheel.name = "SteeringWheel"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.18
	wheel.mesh = torus
	wheel.material_override = _mat(Color(0.03, 0.03, 0.03))
	wheel.position = Vector3(-0.42, 1.08, -0.4)
	wheel.rotation_degrees.x = 60.0
	car.add_child(wheel)
	_own(wheel)
	_prop("Radio", car, Vector3(0.05, 1.05, -0.43), Vector3(0.14, 0.04, 0.02), _emissive(Color(0.2, 0.9, 0.4), 0.25))
	for side in [-1.0, 1.0]:
		_prop("Seat_%d" % int(side), car, Vector3(0.42 * side, 0.95, 0.35), Vector3(0.55, 0.12, 0.55), FABRIC)
		_prop("SeatBack_%d" % int(side), car, Vector3(0.42 * side, 1.25, 0.65), Vector3(0.55, 0.6, 0.12), FABRIC, Vector3(-10, 0, 0))
		_prop("Headlight_%d" % int(side), car, Vector3(0.65 * side, 0.72, -2.36), Vector3(0.35, 0.14, 0.04), _emissive(Color(1, 0.95, 0.85), 2.0))
		_prop("Taillight_%d" % int(side), car, Vector3(0.7 * side, 0.75, 2.36), Vector3(0.3, 0.12, 0.04), _emissive(Color(1, 0.05, 0.03), 1.2))
	var headlight := SpotLight3D.new()
	headlight.name = "Headlights"
	headlight.light_color = Color(1, 0.95, 0.85)
	headlight.light_energy = 2.0
	headlight.spot_range = 24.0
	headlight.spot_angle = 35.0
	headlight.position = Vector3(0, 0.75, -2.5)
	headlight.rotation_degrees.x = -6.0
	car.add_child(headlight)
	_own(headlight)

	var siren: Node3D = SirenScript.new()
	siren.name = "Siren"
	siren.position = Vector3(0, 1.62, 0.25)
	siren.set("active", siren_on)
	car.add_child(siren)
	_own(siren)
	return car


func _car() -> void:
	var car := _police_car("Car", "Street", Vector3(8, 0, 25.2), Vector3(1, 0, 0), false)
	var seat := Marker3D.new()
	seat.name = "Seat"
	seat.position = Vector3(-0.42, -0.45, 0.3)
	car.add_child(seat)
	_own(seat)
	var out := Marker3D.new()
	out.name = "ExitPoint"
	out.position = Vector3(-2.0, 0.0, 0.2)
	out.rotation.y = Chase.facing(Vector3(-1, 0, 0))
	car.add_child(out)
	_own(out)

	var trunk: StoryInteractable = ItemScript.new()
	trunk.name = "Trunk"
	trunk.position = Vector3(0, 0.95, 2.1)
	trunk.prompt = "[E] Take your flashlight from the trunk"
	trunk.label = "Flashlight"
	trunk.available = false
	trunk.consume = false
	trunk.radius = 0.55
	trunk.use_sound = Audio.sfx("click")
	car.add_child(trunk)
	_own(trunk)


# ---------------------------------------------------------------------------
# Forests
# ---------------------------------------------------------------------------

func _forest(label: String, path: Array, clearings: Array[Rect2], walls := true, half_width := 7.0, depth := 16.0, grow := 1) -> Node3D:
	var forest: Node3D = ForestScript.new()
	forest.name = label
	_add(forest, "Jungle")
	var points := PackedVector3Array()
	for v in path:
		points.append(p3(v))
	forest.set("path", points)
	forest.set("clearings", clearings)
	forest.set("walls", walls)
	forest.set("cap_start", false)
	forest.set("cap_end", false)
	forest.set("corridor_half_width", half_width)
	forest.set("forest_depth", depth)
	forest.set("grow_seed", grow)
	forest.set("rustle_sound", Audio.sfx("rustle"))
	if not walls:
		forest.set("trail_half_width", 0.0)
	return forest


func _forests() -> void:
	var house_clear := CLEARING
	var keep_clear: Array[Rect2] = [STREET_CLEAR, house_clear]
	_forest("TrailForest", TRAIL, keep_clear, true, 7.0, 16.0, 3)
	_forest("EscapeForest", ESCAPE, keep_clear, true, 7.0, 16.0, 8)
	# A belt of trees along the road, with gaps for the two trails.
	var belt: Array[Rect2] = [STREET_CLEAR, Rect2(-7.5, -40, 15, 44), Rect2(-72, -40, 16, 44)]
	_forest("RoadsideTrees", [Vector2(-115, -9), Vector2(50, -9)], belt, false, 0.0, 12.0, 5)
	# And a ring round the house's clearing.
	var ring: Array[Rect2] = [house_clear, Rect2(-8, -170, 16, 60), Rect2(-42, -188, 24, 18)]
	_forest("ClearingTrees", [Vector2(-23, -153), Vector2(23, -153), Vector2(23, -199), Vector2(-23, -199), Vector2(-23, -153)],
		ring, false, 0.0, 12.0, 6)

	# The clearing's own invisible bounds, open where the two trails meet it.
	var c := CLEARING
	_wall_line("Clearing_N1", "Jungle/Bounds", Vector2(c.position.x, c.end.y), Vector2(-6.4, c.end.y))
	_wall_line("Clearing_N2", "Jungle/Bounds", Vector2(6.4, c.end.y), Vector2(c.end.x, c.end.y))
	_wall_line("Clearing_S", "Jungle/Bounds", Vector2(c.position.x, c.position.y), Vector2(c.end.x, c.position.y))
	_wall_line("Clearing_E", "Jungle/Bounds", Vector2(c.end.x, c.position.y), Vector2(c.end.x, c.end.y))
	_wall_line("Clearing_W1", "Jungle/Bounds", Vector2(c.position.x, c.position.y), Vector2(c.position.x, -185.5))
	_wall_line("Clearing_W2", "Jungle/Bounds", Vector2(c.position.x, -170.5), Vector2(c.position.x, c.end.y))


func _trail_set_pieces() -> void:
	# The thicket: impassable until every clue is found.
	var at := _along(TRAIL, THICKET_T)
	var dir := _heading(TRAIL, at)
	var yaw := Chase.facing(dir)
	_collider("ThicketBarrier", "Jungle", Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 2.0), Vector3(16, 4, 1.0))
	var thicket := Node3D.new()
	thicket.name = "Thicket"
	thicket.position = at
	thicket.rotation.y = yaw
	_add(thicket, "Jungle")
	var leaves := _mat(Color(0.03, 0.07, 0.03))
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for k in 26:
		var s := rng.randf_range(1.0, 2.2)
		var mi := MeshInstance3D.new()
		mi.name = "Bush_%d" % k
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 0.9
		sphere.radial_segments = 8
		sphere.rings = 4
		mi.mesh = sphere
		mi.material_override = leaves
		mi.position = Vector3(rng.randf_range(-7.5, 7.5), s * 0.35, rng.randf_range(-1.0, 1.0))
		mi.scale = Vector3(s, s * rng.randf_range(0.8, 1.3), s)
		thicket.add_child(mi)
		_own(mi)
	for k in 9:
		_cyl("Branch_%d" % k, thicket, Vector3(rng.randf_range(-5, 5), rng.randf_range(0.6, 2.2), rng.randf_range(-0.6, 0.6)),
			0.05, rng.randf_range(4.0, 8.0), BARK, Vector3(rng.randf_range(-15, 15), rng.randf_range(-30, 30), 90 + rng.randf_range(-25, 25)))

	# Drag marks from the thicket to the house steps.
	var marks := _folder("Jungle/DragMarks")
	var steps := 46
	for k in steps:
		var t := THICKET_T - 0.01 + (1.0 - THICKET_T + 0.01) * k / float(steps)
		var p := _along(TRAIL, t)
		var d := _heading(TRAIL, p)
		var across := d.cross(Vector3.UP)
		for side in [-0.22, 0.22]:
			_prop("Mark_%02d_%d" % [k, int(side * 10)], marks, p + across * (side + sin(k * 0.7) * 0.15) + Vector3.UP * 0.012,
				Vector3(0.09, 0.012, 1.3), OLD_BLOOD, Vector3(0, rad_to_deg(Chase.facing(d)), 0))
	# ...across the porch to the door.
	for k in 5:
		_prop("PorchMark_%d" % k, marks, _house_pos(Vector3(0.1 * sin(k), FLOOR + 0.012, 2.8 - k * 0.6)), Vector3(0.5, 0.012, 0.5), OLD_BLOOD)


# ---------------------------------------------------------------------------
# Daniel's belongings
# ---------------------------------------------------------------------------

func _clues() -> void:
	var specs := [
		[0.07, 2.2, "Car keys", "[E] Pick up the keys",
			"Car keys. A Toyota fob... Daniel drives a Toyota. So he did come this way."],
		[0.18, -2.4, "Torn sleeve", "[E] Pick up the torn cloth",
			"Blue denim, torn off at the seam. Torn, not cut. He was caught on something. Or by something."],
		[0.29, 1.8, "Phone", "[E] Pick up the phone",
			"His phone. Screen's smashed, battery's dead. Last place it pinged was the road. So he was out here by then."],
		[0.4, -2.0, "Wallet", "[E] Pick up the wallet",
			"Daniel Reyes. License, forty dollars, a photo of his kid. Nobody robbed him."],
		[0.51, 2.4, "Shoe", "[E] Pick up the shoe",
			"One shoe. Laces still tied. You don't lose a tied shoe walking. You lose it being dragged."],
		[0.62, -2.2, "Glasses", "[E] Pick up the glasses",
			"Glasses, snapped clean in half. Out here without these, he'd have been blind in the dark."],
		[0.74, 1.6, "Backpack", "[E] Pick up the backpack",
			"His backpack. The strap's soaked through. That's blood. Not old, either."],
	]
	var folder := _folder("Clues")
	for i in specs.size():
		var spec: Array = specs[i]
		var at := _along(TRAIL, spec[0])
		var dir := _heading(TRAIL, at)
		var item: StoryInteractable = ItemScript.new()
		item.name = "Clue_%d" % (i + 1)
		item.position = at + dir.cross(Vector3.UP) * float(spec[1])
		item.rotation.y = float(i) * 1.7
		item.label = spec[2]
		item.prompt = spec[3]
		item.thought = spec[4]
		item.use_sound = Audio.sfx("pickup")
		folder.add_child(item)
		_own(item)
		_clue_mesh(item, i)


func _clue_mesh(item: Node3D, i: int) -> void:
	var leather := _mat(Color(0.25, 0.13, 0.06), 0.6)
	match i:
		0:  # keys on a ring
			var ring := MeshInstance3D.new()
			ring.name = "Ring"
			var torus := TorusMesh.new()
			torus.inner_radius = 0.025
			torus.outer_radius = 0.032
			ring.mesh = torus
			ring.material_override = METAL
			ring.position.y = 0.01
			item.add_child(ring)
			_own(ring)
			_prop("Key_A", item, Vector3(0.06, 0.01, 0.01), Vector3(0.07, 0.006, 0.018), METAL, Vector3(0, 20, 0))
			_prop("Key_B", item, Vector3(0.02, 0.01, 0.06), Vector3(0.02, 0.006, 0.07), METAL, Vector3(0, -15, 0))
			_prop("Fob", item, Vector3(-0.05, 0.015, -0.03), Vector3(0.035, 0.018, 0.06), _mat(Color(0.03, 0.03, 0.03)))
		1:  # torn sleeve draped over a rock
			_prop("Rock", item, Vector3(0, 0.12, 0), Vector3(0.5, 0.25, 0.4), _mat(Color(0.2, 0.2, 0.19)), Vector3(0, 0, 8))
			_prop("Cloth", item, Vector3(0.02, 0.26, 0), Vector3(0.42, 0.03, 0.22), _mat(Color(0.12, 0.2, 0.36)), Vector3(0, 30, 12))
		2:  # phone
			_prop("Phone", item, Vector3(0, 0.006, 0), Vector3(0.075, 0.009, 0.155), _mat(Color(0.02, 0.02, 0.025), 0.2))
			_prop("Screen", item, Vector3(0, 0.0115, 0), Vector3(0.068, 0.001, 0.142), _mat(Color(0.05, 0.06, 0.07), 0.05))
		3:  # wallet
			_prop("Wallet", item, Vector3(0, 0.012, 0), Vector3(0.11, 0.022, 0.09), leather)
			_prop("Card", item, Vector3(0.03, 0.025, 0.01), Vector3(0.085, 0.002, 0.054), _mat(Color(0.75, 0.75, 0.7)), Vector3(0, 25, 0))
		4:  # shoe
			_prop("Upper", item, Vector3(0, 0.06, 0), Vector3(0.1, 0.1, 0.26), _mat(Color(0.15, 0.15, 0.17)))
			_prop("Sole", item, Vector3(0, 0.012, 0), Vector3(0.11, 0.025, 0.28), _mat(Color(0.7, 0.68, 0.62)))
			_prop("Laces", item, Vector3(0, 0.115, -0.02), Vector3(0.06, 0.01, 0.1), _mat(Color(0.7, 0.68, 0.62)))
		5:  # broken glasses
			for side in [-1.0, 1.0]:
				var rim := MeshInstance3D.new()
				rim.name = "Rim_%d" % int(side)
				var torus := TorusMesh.new()
				torus.inner_radius = 0.022
				torus.outer_radius = 0.027
				rim.mesh = torus
				rim.material_override = _mat(Color(0.02, 0.02, 0.02), 0.3)
				rim.position = Vector3(0.05 * side + (0.03 if side > 0 else 0.0), 0.005, 0.02 * side)
				rim.rotation_degrees.y = 25.0 * side
				item.add_child(rim)
				_own(rim)
			_prop("Arm", item, Vector3(-0.02, 0.005, -0.06), Vector3(0.004, 0.004, 0.12), _mat(Color(0.02, 0.02, 0.02)), Vector3(0, 40, 0))
		6:  # bloody backpack
			_prop("Pack", item, Vector3(0, 0.12, 0), Vector3(0.34, 0.24, 0.42), _mat(Color(0.12, 0.16, 0.1)), Vector3(80, 0, 0))
			_prop("Pocket", item, Vector3(0, 0.25, 0.05), Vector3(0.24, 0.04, 0.18), _mat(Color(0.1, 0.13, 0.08)))
			_prop("Strap", item, Vector3(0.12, 0.05, 0.3), Vector3(0.06, 0.02, 0.3), BLOOD, Vector3(0, 30, 0))
			_prop("Stain", item, Vector3(0.05, 0.003, 0.25), Vector3(0.4, 0.004, 0.35), BLOOD, Vector3(0, 20, 0))


# ---------------------------------------------------------------------------
# The house
# ---------------------------------------------------------------------------

func _hbox(label: String, local_center: Vector3, size: Vector3, mat: Material, collide := true, rot := Vector3.ZERO) -> CSGBox3D:
	return _box(label, "House/Structure", _house_pos(local_center), size, mat, collide, rot)


## A wall along X at local z, from x0 to x1, with doorways [centre_x, width].
func _wall_x(label: String, z: float, x0: float, x1: float, doors: Array, mat: Material) -> void:
	var edges := [x0]
	for d in doors:
		edges.append(d[0] - d[1] * 0.5)
		edges.append(d[0] + d[1] * 0.5)
	edges.append(x1)
	var h := CEIL - FLOOR
	for k in range(0, edges.size(), 2):
		var a: float = edges[k]
		var b: float = edges[k + 1]
		if b - a > 0.01:
			_hbox("%s_%d" % [label, k / 2], Vector3((a + b) * 0.5, FLOOR + h * 0.5, z), Vector3(b - a, h, WALL_T), mat)
	for d in doors:
		_hbox("%s_Lintel_%d" % [label, int(d[0])], Vector3(d[0], (FLOOR + DOOR_H + CEIL) * 0.5, z), Vector3(d[1], CEIL - FLOOR - DOOR_H, WALL_T), mat)


## A wall along Z at local x, from z0 to z1 (z0 > z1), with doorways [centre_z, width].
func _wall_z(label: String, x: float, z0: float, z1: float, doors: Array, mat: Material) -> void:
	var edges := [z0]
	for d in doors:
		edges.append(d[0] + d[1] * 0.5)
		edges.append(d[0] - d[1] * 0.5)
	edges.append(z1)
	var h := CEIL - FLOOR
	for k in range(0, edges.size(), 2):
		var a: float = edges[k]
		var b: float = edges[k + 1]
		if a - b > 0.01:
			_hbox("%s_%d" % [label, k / 2], Vector3(x, FLOOR + h * 0.5, (a + b) * 0.5), Vector3(WALL_T, h, a - b), mat)
	for d in doors:
		_hbox("%s_Lintel_%d" % [label, int(d[0])], Vector3(x, (FLOOR + DOOR_H + CEIL) * 0.5, d[0]), Vector3(WALL_T, CEIL - FLOOR - DOOR_H, d[1]), mat)


func _house() -> void:
	# Raised floor, ceiling, roof.
	_hbox("Floor", Vector3(0, FLOOR * 0.5, -9.5), Vector3(18.3, FLOOR, 19.3), PLANKS)
	_hbox("Ceiling", Vector3(0, CEIL + 0.1, -9.5), Vector3(18.3, 0.2, 19.3), DARK_WOOD)
	for side in [-1.0, 1.0]:
		_hbox("Roof_%d" % int(side), Vector3(4.7 * side, CEIL + 2.75, -9.5), Vector3(11.2, 0.25, 20.5), ROOF, false, Vector3(0, 0, -30 * side))
	for z in [0.0, -19.0]:
		_hbox("Gable_%d" % int(z), Vector3(0, CEIL + 1.4, z), Vector3(12.0, 2.6, 0.25), SIDING, false)

	# Outer walls: front door, back door (kitchen, west), boarded windows.
	_wall_x("Wall_Front", 0.0, -9.15, 9.15, [[0.0, 1.8]], SIDING)
	_wall_x("Wall_Back", -19.0, -9.15, 9.15, [], SIDING)
	_wall_z("Wall_West", -9.0, 0.0, -19.0, [[-10.0, 1.8]], SIDING)
	_wall_z("Wall_East", 9.0, 0.0, -19.0, [], SIDING)
	# Inside: living room | study + kitchen | bedroom.
	_wall_x("Wall_LivingBack", -7.0, -8.85, 8.85, [[5.0, 1.8]], WALLPAPER)
	_wall_x("Wall_BedroomFront", -13.0, -8.85, 8.85, [[-5.0, 1.8], [5.0, 1.8]], WALLPAPER)
	_wall_z("Wall_Divider", 0.0, -7.15, -12.85, [], WALLPAPER)

	# Porch, steps (a ramp underneath), railings and posts.
	_hbox("Porch", Vector3(0, FLOOR * 0.5, 1.6), Vector3(12, FLOOR, 3.2), PLANKS)
	for k in 4:
		_hbox("Step_%d" % k, Vector3(0, FLOOR - 0.25 * (k + 1) + 0.125, 3.45 + 0.6 * k), Vector3(3, 0.25, 0.6), DARK_WOOD, false)
	var rise := FLOOR
	var run := 2.6
	_collider("FrontSteps", "House/Structure", Transform3D(Basis(Vector3.RIGHT, atan2(rise, run)), _house_pos(Vector3(0, rise * 0.5 - 0.1, 3.2 + run * 0.5))), Vector3(3, 0.2, sqrt(rise * rise + run * run)))
	for x in [-5.8, -1.7, 1.7, 5.8]:
		_hbox("PorchPost_%d" % int(x * 10), Vector3(x, FLOOR + 1.5, 3.0), Vector3(0.18, 3.0, 0.18), DARK_WOOD, false)
	for x in [-3.75, 3.75]:
		_hbox("Rail_%d" % int(x), Vector3(x, FLOOR + 0.9, 3.0), Vector3(4.1, 0.08, 0.08), DARK_WOOD)
	_hbox("PorchRoof", Vector3(0, FLOOR + 3.05, 1.7), Vector3(12.4, 0.15, 3.6), ROOF, false, Vector3(-8, 0, 0))
	for x in [-6.0, 6.0]:
		_board_window("Window_Front_%d" % int(x), Vector3(x, FLOOR + 1.7, 0.17), 0.0)
	for z in [-4.0, -16.0]:
		_board_window("Window_East_%d" % int(-z), Vector3(9.17, FLOOR + 1.7, z), 90.0)
		_board_window("Window_West_%d" % int(-z), Vector3(-9.17, FLOOR + 1.7, z), 90.0)

	# Back door landing and steps down to the escape trail.
	_hbox("BackLanding", Vector3(-10.4, FLOOR * 0.5, -10.0), Vector3(2.6, FLOOR, 2.6), PLANKS)
	_collider("BackSteps", "House/Structure", Transform3D(Basis(Vector3.FORWARD, -atan2(rise, run)), _house_pos(Vector3(-11.7 - run * 0.5, rise * 0.5 - 0.1, -10.0))), Vector3(sqrt(rise * rise + run * run), 0.2, 2.4))
	for k in 4:
		_hbox("BackStep_%d" % k, Vector3(-12.0 - 0.6 * k, FLOOR - 0.25 * (k + 1) + 0.125, -10.0), Vector3(0.6, 0.25, 2.4), DARK_WOOD, false)

	# Doors.
	var front := _door("FrontDoor", Vector3(0, FLOOR, 0), 0.0, 90.0, true, false)
	front.set("color", Color(0.12, 0.07, 0.04))
	_door("KitchenDoor", Vector3(-5, FLOOR, -13), 0.0, 90.0, true, false)
	var back := _door("BackDoor", Vector3(-9, FLOOR, -10), 90.0, -95.0, false, true)
	back.set("locked", true)
	back.set("hold_time", 1.4)

	_house_lights()
	_living_room()
	_study()
	_bedroom()
	_kitchen()


func _board_window(label: String, at: Vector3, yaw: float) -> void:
	var parent := _folder("House/Windows")
	_prop(label, parent, _house_pos(at), Vector3(1.6, 1.3, 0.04), _mat(Color(0.01, 0.01, 0.012)), Vector3(0, yaw, 0))
	for k in 3:
		_prop("%s_Board_%d" % [label, k], parent, _house_pos(at) + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, -0.4 + k * 0.4, 0.04),
			Vector3(1.9, 0.18, 0.04), BOARDS, Vector3(0, yaw, (k - 1) * 9.0))


func _door(label: String, local: Vector3, yaw: float, open_yaw: float, starts_open: bool, heavy: bool) -> Node3D:
	var door: Node3D = DoorScript.new()
	door.name = label
	door.position = _house_pos(local)
	door.rotation_degrees.y = yaw
	door.set("width", 1.8)
	door.set("height", 2.95)
	door.set("open_yaw", open_yaw)
	door.set("starts_open", starts_open)
	door.set("heavy", heavy)
	door.set("slam_sound", Audio.sfx("door_slam"))
	door.set("creak_sound", Audio.sfx("creak"))
	door.set("break_sound", Audio.sfx("door_break"))
	return _add(door, "House")


func _house_lights() -> void:
	for spec in [["Living_A", Vector3(-4, 0, -3.5)], ["Living_B", Vector3(4, 0, -3.5)], ["Study", Vector3(4.5, 0, -10)],
			["Kitchen", Vector3(-4.5, 0, -10)], ["Bedroom_A", Vector3(-4.5, 0, -16)], ["Bedroom_B", Vector3(4.5, 0, -16)]]:
		var light: OmniLight3D = FlickerScript.new()
		light.name = "Light_" + spec[0]
		light.light_color = Color(1.0, 0.72, 0.45)
		light.omni_range = 9.0
		light.omni_attenuation = 1.0
		light.light_volumetric_fog_energy = 0.0
		# Two shadowed lights are plenty; each one costs a cube shadow map.
		light.shadow_enabled = spec[0] in ["Living_A", "Bedroom_A"]
		light.position = _house_pos(spec[1] + Vector3(0, CEIL - 0.25, 0))
		light.set("energy", 2.4)
		light.set("faultiness", 0.25)
		light.set("powered", false)
		_add(light, "House/Lights")


func _living_room() -> void:
	var f := _folder("House/Props")
	var o := HOUSE
	# The sofa, still against the wall; the coffee table and armchair thrown over.
	_box("Sofa", "House/Props", o + Vector3(-6.4, FLOOR + 0.4, -6.2), Vector3(2.6, 0.8, 0.9), FABRIC)
	_prop("SofaBack", f, o + Vector3(-6.4, FLOOR + 0.95, -6.55), Vector3(2.6, 0.6, 0.2), FABRIC)
	_box("CoffeeTable", "House/Props", o + Vector3(-5.2, FLOOR + 0.3, -3.4), Vector3(1.4, 0.08, 0.8), DARK_WOOD, true, Vector3(0, 30, 72))
	_box("Armchair", "House/Props", o + Vector3(-2.6, FLOOR + 0.35, -2.2), Vector3(1.0, 0.7, 1.0), FABRIC, true, Vector3(0, 40, 85))
	_prop("Rug", f, o + Vector3(-4.5, FLOOR + 0.01, -3.5), Vector3(4.0, 0.01, 2.8), _mat(Color(0.25, 0.08, 0.06)), Vector3(0, 8, 0))
	_box("Shelf", "House/Props", o + Vector3(8.5, FLOOR + 1.0, -2.5), Vector3(0.5, 2.0, 2.2), DARK_WOOD, true, Vector3(0, 0, 12))
	for k in 6:
		_prop("Book_%d" % k, f, o + Vector3(7.2 + 0.25 * k, FLOOR + 0.04, -1.8 - 0.3 * (k % 3)), Vector3(0.18, 0.05, 0.25), _mat(Color(0.2 + 0.1 * (k % 3), 0.1, 0.08)), Vector3(0, 30 * k, 0))
	# Blood: a pool, smears on the wall, and the drag marks toward the study.
	_prop("Pool", f, o + Vector3(1.8, FLOOR + 0.012, -3.4), Vector3(1.6, 0.012, 1.1), BLOOD, Vector3(0, 20, 0))
	_prop("Smear_Wall", f, o + Vector3(8.84, FLOOR + 1.3, -4.6), Vector3(0.01, 1.1, 0.5), BLOOD, Vector3(-25, 0, 0))
	_prop("Hand_1", f, o + Vector3(8.84, FLOOR + 1.6, -5.4), Vector3(0.01, 0.2, 0.15), BLOOD)
	_prop("Hand_2", f, o + Vector3(8.84, FLOOR + 1.35, -5.9), Vector3(0.01, 0.2, 0.15), BLOOD, Vector3(-15, 0, 0))
	_drag_trail(f, [Vector2(0, -0.6), Vector2(1.8, -3.4), Vector2(5, -6.6), Vector2(5, -7.6)])


func _study() -> void:
	var f := _folder("House/Props")
	var o := HOUSE
	_box("Desk", "House/Props", o + Vector3(7.8, FLOOR + 0.4, -9.2), Vector3(1.4, 0.8, 2.4), DARK_WOOD)
	_box("Chair_Broken", "House/Props", o + Vector3(6.2, FLOOR + 0.2, -10.5), Vector3(0.5, 0.4, 0.5), DARK_WOOD, false, Vector3(70, 20, 0))
	for k in 9:
		_prop("Paper_%d" % k, f, o + Vector3(3.0 + (k % 3) * 1.2, FLOOR + 0.01, -8.0 - (k / 3) * 1.1), Vector3(0.21, 0.003, 0.3), _mat(Color(0.75, 0.72, 0.62)), Vector3(0, k * 37.0, 0))
	_prop("Scratches", f, o + Vector3(0.16, FLOOR + 1.6, -10.5), Vector3(0.01, 1.2, 0.6), OLD_BLOOD, Vector3(-10, 0, 0))
	for k in 4:
		_prop("Claw_%d" % k, f, o + Vector3(0.16, FLOOR + 2.0, -9.7 - k * 0.12), Vector3(0.012, 1.0, 0.025), _mat(Color(0.05, 0.04, 0.03)), Vector3(-8, 0, 0))
	_drag_trail(f, [Vector2(5, -7.6), Vector2(4.2, -10.0), Vector2(5, -12.4), Vector2(5, -13.8)])
	var battery: Area3D = BatteryScript.new()
	battery.name = "Battery_Study"
	battery.position = o + Vector3(7.8, FLOOR + 0.9, -8.6)
	battery.set("pickup_sound", Audio.sfx("pickup"))
	_add(battery, "Gameplay")


func _bedroom() -> void:
	var f := _folder("House/Props")
	var o := HOUSE
	# The bed, with chains bolted to the frame.
	_box("BedFrame", "House/Props", o + Vector3(5.0, FLOOR + 0.3, -17.3), Vector3(2.2, 0.6, 3.0), DARK_WOOD)
	_prop("Mattress", f, o + Vector3(5.0, FLOOR + 0.68, -17.3), Vector3(2.0, 0.18, 2.8), _mat(Color(0.45, 0.42, 0.35)))
	_prop("Stain", f, o + Vector3(5.2, FLOOR + 0.775, -17.0), Vector3(1.2, 0.01, 1.3), OLD_BLOOD, Vector3(0, 15, 0))
	for k in 5:
		var chain_mat := _mat(Color(0.18, 0.17, 0.16), 0.4)
		_cyl("Chain_%d" % k, f, o + Vector3(3.95 - 0.04 * k, FLOOR + 0.55 - 0.08 * k, -16.2 - 0.18 * k), 0.025, 0.2, chain_mat, Vector3(60, 0, 30 * (k % 2)))
	_prop("Shackle", f, o + Vector3(3.7, FLOOR + 0.03, -15.3), Vector3(0.14, 0.04, 0.14), _mat(Color(0.18, 0.17, 0.16), 0.4))
	# Bones in the corner. It was not the first.
	for k in 7:
		_cyl("Bone_%d" % k, f, o + Vector3(8.2 - 0.15 * (k % 3), FLOOR + 0.05, -18.3 + 0.2 * k), 0.035, 0.35 + 0.05 * (k % 3), _mat(Color(0.75, 0.72, 0.62)), Vector3(0, 40 * k, 90))
	# The desk where Daniel left his note, and a candle burning on it.
	_box("NoteDesk", "House/Props", o + Vector3(-6.5, FLOOR + 0.4, -18.3), Vector3(1.6, 0.8, 0.9), DARK_WOOD)
	_cyl("Candle", f, o + Vector3(-7.0, FLOOR + 0.88, -18.4), 0.035, 0.16, _mat(Color(0.85, 0.82, 0.7)))
	var candle := OmniLight3D.new()
	candle.name = "CandleLight"
	candle.light_color = Color(1.0, 0.6, 0.3)
	candle.light_energy = 0.8
	candle.omni_range = 3.0
	candle.light_volumetric_fog_energy = 0.0
	candle.position = o + Vector3(-7.0, FLOOR + 1.05, -18.4)
	_add(candle, "House/Props")
	_drag_trail(f, [Vector2(5, -13.8), Vector2(4.2, -15.0), Vector2(4.0, -16.0)])

	var note: StoryInteractable = ItemScript.new()
	note.name = "Note"
	note.position = o + Vector3(-6.4, FLOOR + 0.81, -18.1)
	note.prompt = "[E] Read the note"
	note.label = "Daniel's note"
	note.radius = 0.3
	note.consume = false
	note.glint_color = Color(1.0, 0.8, 0.6)
	note.use_sound = Audio.sfx("click")
	_add(note, "House")
	_prop("Paper", note, Vector3.ZERO, Vector3(0.24, 0.004, 0.32), _mat(Color(0.82, 0.77, 0.64)), Vector3(0, 12, 0))


func _kitchen() -> void:
	var f := _folder("House/Props")
	var o := HOUSE
	_box("Counter", "House/Props", o + Vector3(-4.5, FLOOR + 0.45, -7.5), Vector3(7.0, 0.9, 0.7), DARK_WOOD)
	_box("Fridge", "House/Props", o + Vector3(-0.8, FLOOR + 0.95, -7.6), Vector3(0.9, 1.9, 0.75), _mat(Color(0.5, 0.48, 0.43)))
	# The table stands against the wall, clear of the run to the back door.
	_box("Table", "House/Props", o + Vector3(-1.2, FLOOR + 0.4, -10.4), Vector3(1.1, 0.8, 1.9), DARK_WOOD)
	_prop("Cleaver", f, o + Vector3(-1.0, FLOOR + 0.82, -11.0), Vector3(0.1, 0.01, 0.3), METAL, Vector3(0, 30, 0))
	_prop("TableBlood", f, o + Vector3(-1.2, FLOOR + 0.805, -10.6), Vector3(0.6, 0.005, 0.8), BLOOD)
	# Meat hooks from the ceiling. Some of them are not empty.
	for k in 4:
		var x := -7.6 + k * 1.3
		_cyl("HookChain_%d" % k, f, o + Vector3(x, CEIL - 0.5, -8.2), 0.012, 1.0, METAL)
		_cyl("Hook_%d" % k, f, o + Vector3(x, CEIL - 1.05, -8.2), 0.02, 0.18, METAL, Vector3(0, 0, 30))
		if k % 2 == 0:
			_prop("Meat_%d" % k, f, o + Vector3(x, CEIL - 1.55, -8.2), Vector3(0.35, 0.8, 0.25), _mat(Color(0.3, 0.06, 0.05), 0.4), Vector3(0, 20 * k, 4))

	var gun: StoryInteractable = ItemScript.new()
	gun.name = "Gun"
	gun.position = o + Vector3(-1.5, FLOOR + 0.82, -10.0)
	gun.prompt = "[E] Take the revolver"
	gun.label = "Revolver"
	gun.radius = 0.35
	gun.available = false
	gun.glint_color = Color(1.0, 0.9, 0.7)
	gun.use_sound = Audio.sfx("pickup")
	_add(gun, "House")
	var dark := _mat(Color(0.04, 0.04, 0.045), 0.35)
	_prop("Frame", gun, Vector3(0, 0.02, 0), Vector3(0.05, 0.035, 0.17), dark, Vector3(0, 70, 0))
	_prop("Barrel", gun, Vector3(-0.1, 0.02, 0.035), Vector3(0.02, 0.02, 0.18), dark, Vector3(0, 70, 0))
	_prop("Grip", gun, Vector3(0.09, 0.02, -0.04), Vector3(0.04, 0.03, 0.1), _mat(Color(0.12, 0.07, 0.04)), Vector3(0, 40, 0))


## Dark streaks along the floor between house-local (x, z) points.
func _drag_trail(parent: Node, points: Array) -> void:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var d := b - a
		var mid := (a + b) * 0.5
		var yaw := rad_to_deg(atan2(d.x, d.y))
		for side in [-0.18, 0.18]:
			var off := Vector2(d.y, -d.x).normalized() * float(side)
			_prop("Drag_%d_%d_%d" % [int(a.x * 10), int(a.y * 10), int(side * 100)], parent,
				HOUSE + Vector3(mid.x + off.x, FLOOR + 0.011, mid.y + off.y), Vector3(0.1, 0.006, d.length()), OLD_BLOOD, Vector3(0, yaw, 0))


# ---------------------------------------------------------------------------
# The escape trail
# ---------------------------------------------------------------------------

func _escape_route() -> void:
	# A fallen log to jump.
	var log_at := _along(ESCAPE, 0.22)
	var log_dir := _heading(ESCAPE, log_at)
	var fallen := CSGCylinder3D.new()
	fallen.name = "FallenLog"
	fallen.radius = 0.32
	fallen.height = 16.0
	fallen.sides = 10
	fallen.material = BARK
	fallen.use_collision = true
	fallen.collision_layer = 1
	# A cylinder's axis is Y: lay it on its side, across the trail.
	fallen.transform = Transform3D(Basis(Vector3.UP, Chase.facing(log_dir) + 0.12) * Basis(Vector3.FORWARD, PI * 0.5), log_at + Vector3.UP * 0.28)
	_add(fallen, "Escape")

	# A tangle of roots with only a crawlspace underneath: it loses you there.
	var tangle_at := _along(ESCAPE, 0.52)
	var tangle_dir := _heading(ESCAPE, tangle_at)
	var yaw := Chase.facing(tangle_dir)
	var tangle := CSGBox3D.new()
	tangle.name = "RootTangle"
	tangle.size = Vector3(18, 4.0, 10)
	tangle.material = BARK
	tangle.use_collision = true
	tangle.collision_layer = 1
	tangle.position = tangle_at + Vector3.UP * 3.15
	tangle.rotation.y = yaw
	_add(tangle, "Escape")
	for k in 5:
		var root_log := CSGCylinder3D.new()
		root_log.name = "Root_%d" % k
		root_log.radius = 0.5 + 0.15 * (k % 3)
		root_log.height = 12.0
		root_log.material = BARK
		root_log.position = tangle_at + Basis(Vector3.UP, yaw) * Vector3((k - 2) * 2.5, 2.0 + (k % 2) * 1.5, (k - 2) * 1.6)
		root_log.rotation = Vector3(deg_to_rad(80 + k * 6), yaw + deg_to_rad(20 * (k - 2)), 0)
		_add(root_log, "Escape")

	var vent: Area3D = VentScript.new()
	vent.name = "RootCrawl"
	vent.position = tangle_at + Vector3.UP
	vent.rotation.y = yaw
	vent.set("extent", Vector3(8, 1, 5.5))
	vent.set("ambush_delay", 1.0)
	_add(vent, "Gameplay")
	vent.set("ambush_point", _marker(vent, "AmbushPoint", tangle_at + tangle_dir * 13.0 + tangle_dir.cross(Vector3.UP) * 4.0, -tangle_dir))

	_trigger("Checkpoint_AfterRoots", tangle_at + tangle_dir * 9.0 + Vector3.UP * 1.75, yaw, Vector3(8, 1.75, 0.8),
		tangle_at + tangle_dir * 12.0 + tangle_dir.cross(Vector3.UP) * 3.0, -tangle_dir,
		tangle_at + tangle_dir * 10.0, tangle_dir)

	# Backup waiting on the road where the trail comes out.
	_police_car("Backup_1", "Street", Vector3(-70, 0, 16.5), Vector3(1, 0, 0.3), true)
	_police_car("Backup_2", "Street", Vector3(-57, 0, 18), Vector3(-1, 0, 0.4), true)


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------

func _gameplay() -> void:
	var player: CharacterBody3D = _add(PlayerScript.new(), "Gameplay")
	player.name = "Player"
	player.position = Vector3(8, 0, 25)
	player.set("has_flashlight", false)
	player.set("battery_drain", 0.18)
	player.set("gunshot_sound", Audio.sfx("gunshot"))
	player.set("dry_fire_sound", Audio.sfx("click"))
	Audio.setup_player(player)

	var pursuer: CharacterBody3D = _add(PursuerScript.new(), "Gameplay")
	pursuer.name = "Pursuer"
	pursuer.position = HOUSE + Vector3(0, 0, -40)
	pursuer.set("cryptid", true)
	Audio.setup_pursuer(pursuer)

	var figure: Node3D = _add(FigureScript.new(), "Gameplay")
	figure.name = "ShadowFigure"
	figure.position = Vector3(0, -50, 0)
	figure.set("footstep_sound", Audio.sfx("footstep"))

	var music: Node = _add(MusicScript.new(), "Gameplay")
	music.name = "MusicDirector"
	Audio.setup_music(music, "jungle")

	# The chase begins in the bedroom, from a cutscene: it's in the doorway behind you.
	var start := _trigger("Chase_House", _house_pos(Vector3(0, FLOOR + 1.5, -16)), 0.0, Vector3(0.5, 0.5, 0.5),
		_house_pos(Vector3(5, FLOOR, -14.0)), Vector3(-1, 0, -0.4),
		_house_pos(Vector3(-5.0, FLOOR, -16.0)), Vector3(0.3, 0, 1))
	start.set("manual", true)
	start.set("activation_delay", 1.8)

	# Out of the back door: a checkpoint, with it coming out of the kitchen.
	_trigger("Checkpoint_Outside", Vector3(-19, 1.75, -178), 0.0, Vector3(0.8, 1.75, 7),
		_house_pos(Vector3(-5, FLOOR, -10)), Vector3(-1, 0, 0),
		Vector3(-21, 0, -178), Vector3(-1, 0, 0))

	var safe: Area3D = _add(SafeScript.new(), "Gameplay")
	safe.name = "SafeZone_Road"
	safe.position = p3(ESCAPE[-1]) + Vector3(0, 1.5, 1.5)
	safe.set("extent", Vector3(9, 1.5, 3))

	for b in [["Battery_Trail", _along(TRAIL, 0.46) + Vector3(-3.2, 0.4, 0)], ["Battery_Escape", _along(ESCAPE, 0.4) + Vector3(2.5, 0.4, 0)]]:
		var pickup: Area3D = BatteryScript.new()
		pickup.name = b[0]
		pickup.position = b[1]
		pickup.set("pickup_sound", Audio.sfx("pickup"))
		_add(pickup, "Gameplay")


func _trigger(label: String, at: Vector3, yaw: float, extent: Vector3, pursuer_at: Vector3, pursuer_face: Vector3,
		respawn_at: Vector3, respawn_face: Vector3) -> Area3D:
	var t: Area3D = TriggerScript.new()
	t.name = label
	t.position = at
	t.rotation.y = yaw
	t.set("extent", extent)
	_add(t, "Gameplay")
	t.set("pursuer_start", _marker(t, "PursuerStart", pursuer_at, pursuer_face))
	t.set("player_respawn", _marker(t, "PlayerRespawn", respawn_at, respawn_face))
	return t


func _zones() -> void:
	var specs := [
		["Entrance", Vector3(0, 1.5, 7.2), Vector3(7, 1.5, 1.4), 0.0, true],
		["JungleIn", _along(TRAIL, 0.04) + Vector3.UP * 1.5, Vector3(7, 1.5, 1.0), 0.0, true],
		["Thicket", _along(TRAIL, THICKET_T - 0.012) + Vector3.UP * 1.5, Vector3(7.5, 1.5, 1.2), Chase.facing(_heading(TRAIL, _along(TRAIL, THICKET_T))), false],
		["Clearing", Vector3(0, 1.5, -157), Vector3(7, 1.5, 1.0), 0.0, true],
		["HouseInside", _house_pos(Vector3(0, FLOOR + 1.5, -1.8)), Vector3(3.0, 1.5, 0.8), 0.0, true],
		["LivingRoom", _house_pos(Vector3(0, FLOOR + 1.5, -4.8)), Vector3(8.5, 1.5, 1.4), 0.0, true],
		["Study", _house_pos(Vector3(4.5, FLOOR + 1.5, -10)), Vector3(4.0, 1.5, 2.6), 0.0, true],
		["Bedroom", _house_pos(Vector3(0, FLOOR + 1.5, -16)), Vector3(8.5, 1.5, 2.6), 0.0, true],
		["Kitchen", _house_pos(Vector3(-4.5, FLOOR + 1.5, -10)), Vector3(4.0, 1.5, 2.6), 0.0, false],
		["Outside", Vector3(-15.5, 1.5, -178), Vector3(1.5, 1.5, 3.0), 0.0, true],
	]
	for spec in specs:
		var z: Area3D = ZoneScript.new()
		z.name = spec[0]
		z.position = spec[1]
		z.rotation.y = spec[3]
		z.set("extent", spec[2])
		z.set("once", spec[4])
		_add(z, "Zones")


# ---------------------------------------------------------------------------
# Atmosphere
# ---------------------------------------------------------------------------

func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.62, 0.36)
	sun.light_energy = 1.25
	sun.light_volumetric_fog_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation_degrees = Vector3(-7, 200, 0)
	_add(sun, "Environment")

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-52, 25, 0)
	_add(moon, "Environment")

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_sky_affect = 0.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_albedo = Color(0.6, 0.6, 0.6)
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_length = 40.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_add(world_env, "Environment")


func _atmosphere() -> void:
	# Glowing mushrooms along the escape trail: a little guidance in the dark.
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.05, 0.1, 0.1)
	cap.emission_enabled = true
	cap.emission = Color(0.2, 0.9, 0.85)
	cap.emission_energy_multiplier = 1.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 12:
		var at := _along(ESCAPE, 0.04 + k * 0.08)
		var side := -1.0 if k % 2 == 0 else 1.0
		var spot := at + _heading(ESCAPE, at).cross(Vector3.UP) * side * rng.randf_range(2.3, 3.2)
		var cluster := Node3D.new()
		cluster.name = "Mushrooms_%02d" % k
		cluster.position = spot
		_add(cluster, "Atmosphere")
		for m in rng.randi_range(3, 6):
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = rng.randf_range(0.05, 0.12)
			s.height = s.radius
			mi.mesh = s
			mi.material_override = cap
			mi.position = Vector3(rng.randf_range(-0.4, 0.4), s.radius * 0.6, rng.randf_range(-0.4, 0.4))
			cluster.add_child(mi)
			_own(mi)
		if k % 2 == 0:
			var glow := OmniLight3D.new()
			glow.light_color = Color(0.3, 1.0, 0.9)
			glow.light_energy = 0.35
			glow.omni_range = 3.5
			glow.position = Vector3(0, 0.3, 0)
			cluster.add_child(glow)
			_own(glow)
