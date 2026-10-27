@tool
class_name Forest
extends Node3D
## Grows a jungle along a path: a walkable corridor with scattered trees and
## ferns, a dense wall of undergrowth (with invisible walls behind it) at the
## corridor's edge, and thick forest beyond. Everything is drawn with
## MultiMeshes so it stays cheap. Ferns and bushes thrash when the pursuer
## pushes through them, and sway a little as you pass.
##
## Edit `path` or `grow_seed` and reopen the scene to regrow it.

## Centre line of the walkable corridor, at ground level.
@export var path := PackedVector3Array()
## Half-width of the clear trail in the middle.
@export var trail_half_width := 2.0
## Half-width of the walkable corridor (invisible walls sit here).
@export var corridor_half_width := 7.0
## How far beyond the walls the forest is drawn.
@export var forest_depth := 16.0
## Path segments whose midpoint z falls in any of these (min_z, max_z) ranges
## get no walls or trees: chasms, rivers.
@export var gaps: Array[Vector2] = []
## Nothing grows inside these XZ rectangles (a road, a house's clearing).
@export var clearings: Array[Rect2] = []
## Off for a plain belt of trees with no invisible walls.
@export var walls := true
## Walls across the start and end of the corridor; turn off where the path
## opens into somewhere else.
@export var cap_start := true
@export var cap_end := true
@export var grow_seed := 1
@export var rustle_sound: AudioStream

const THRASH_RADIUS := 3.2
const CELL := 6.0

var _rng := RandomNumberGenerator.new()
var _foliage: Array[MultiMesh] = []
var _foliage_rest: Array = []  # per foliage multimesh: Array[Transform3D]
var _grid := {}  # Vector2i -> Array of keys (foliage index * KEY + instance)
var _shake := {}  # key -> amount
const KEY := 1000000
var _rustle_cooldown := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_foliage.clear()
	_foliage_rest.clear()
	_grid.clear()
	if path.size() < 2:
		return
	_rng.seed = grow_seed

	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var ferns: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var area := _bounds()
	# Scatter by area: each candidate keeps or drops based on where it lands.
	var count := int(area.get_area() / 6.0)
	for i in count:
		var p := Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0, _rng.randf_range(area.position.y, area.end.y))
		var info := _nearest(p)
		var d: float = info[0]
		if info[2] or _in_clearing(p):
			continue  # over a gap, or kept clear
		if d > corridor_half_width + forest_depth:
			continue
		if d < trail_half_width:
			if _rng.randf() < 0.04:
				ferns.append(_fern(p, 0.6))
			continue
		if d < corridor_half_width - 1.4:
			# Inside the corridor: sparse trees you weave between, ferns everywhere.
			if _rng.randf() < 0.07 and d > trail_half_width + 0.8:
				_tree(p, trunks, canopies, body)
			elif _rng.randf() < 0.5:
				ferns.append(_fern(p, 1.0))
		elif d < corridor_half_width + 1.5:
			# The wall of undergrowth that hides the invisible walls.
			bushes.append(_bush(p))
			if _rng.randf() < 0.6:
				bushes.append(_bush(p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))))
		else:
			if _rng.randf() < 0.32:
				_tree(p, trunks, canopies, null)
			elif _rng.randf() < 0.25:
				bushes.append(_bush(p))

	if walls:
		_walls(body)

	add_child(_multimesh("Trunks", _trunk_mesh(), trunks, Color(0.11, 0.08, 0.06), true))
	# Only trunks cast shadows: canopy and bush shadows cost more than a third
	# of the frame on a weak GPU, for little you can see at night.
	add_child(_multimesh("Canopy", _canopy_mesh(), canopies, Color(0.025, 0.06, 0.03), false))
	var bush_mmi := _multimesh("Bushes", _bush_mesh(), bushes, Color(0.025, 0.08, 0.03), false)
	var fern_mmi := _multimesh("Ferns", _fern_mesh(), ferns, Color(0.05, 0.16, 0.05), false)
	add_child(bush_mmi)
	add_child(fern_mmi)
	for mmi in [bush_mmi, fern_mmi]:
		var fi := _foliage.size()
		_foliage.append(mmi.multimesh)
		var rest: Array[Transform3D] = []
		for k in mmi.multimesh.instance_count:
			var xf: Transform3D = mmi.multimesh.get_instance_transform(k)
			rest.append(xf)
			var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
			if not _grid.has(cell):
				_grid[cell] = []
			_grid[cell].append(fi * KEY + k)
		_foliage_rest.append(rest)


func _bounds() -> Rect2:
	var r := Rect2(Vector2(path[0].x, path[0].z), Vector2.ZERO)
	for p in path:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(corridor_half_width + forest_depth)


## [distance to the path in XZ, segment index, over a gap]
func _nearest(p: Vector3) -> Array:
	var best := INF
	var best_i := 0
	var q := Vector2(p.x, p.z)
	for i in path.size() - 1:
		var a := Vector2(path[i].x, path[i].z)
		var b := Vector2(path[i + 1].x, path[i + 1].z)
		var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))
		if d < best:
			best = d
			best_i = i
	return [best, best_i, _in_gap(p.z)]


func _in_clearing(p: Vector3) -> bool:
	for r in clearings:
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return false


func _in_gap(z: float) -> bool:
	for g in gaps:
		if z >= g.x and z <= g.y:
			return true
	return false


func _segment_in_gap(i: int) -> bool:
	return _in_gap((path[i].z + path[i + 1].z) * 0.5)


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------

func _tree(p: Vector3, trunks: Array[Transform3D], canopies: Array[Transform3D], body: StaticBody3D) -> void:
	var height := _rng.randf_range(9.0, 15.0)
	var radius := _rng.randf_range(0.22, 0.55)
	var lean := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.08))
	var trunk := Transform3D(lean.scaled(Vector3(radius, height, radius)), p + lean * Vector3(0, height * 0.5, 0))
	trunks.append(trunk)
	var top := p + lean * Vector3(0, height, 0)
	for k in _rng.randi_range(2, 3):
		var s := _rng.randf_range(3.0, 5.5)
		var off := Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 0.8), _rng.randf_range(-1.5, 1.5))
		canopies.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(s, s * 0.45, s)), top + off))
	if body:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(lean, trunk.origin)
		body.add_child(cs)


func _bush(p: Vector3) -> Transform3D:
	var s := _rng.randf_range(1.2, 2.4)
	return Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.1), s)), p)


func _fern(p: Vector3, size: float) -> Transform3D:
	var s := _rng.randf_range(0.7, 1.4) * size
	return Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(s, s, s)), p)


## Invisible walls along both sides of the corridor, with mitred corners.
func _walls(body: StaticBody3D) -> void:
	for side in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		for i in path.size():
			pts.append(path[i] + _offset_dir(i) * corridor_half_width * side)
		for i in pts.size() - 1:
			if _segment_in_gap(i):
				continue
			_wall_box(body, pts[i], pts[i + 1])
	# Caps behind the start and beyond the end.
	for end in [[0, 1], [path.size() - 1, path.size() - 2]]:
		if (end[0] == 0 and not cap_start) or (end[0] != 0 and not cap_end):
			continue
		var p := path[end[0]]
		var back := (p - path[end[1]]).normalized()
		var across := back.cross(Vector3.UP) * corridor_half_width
		_wall_box(body, p + back * 1.5 - across, p + back * 1.5 + across)


## Mitred offset direction at a path vertex: walls stay corridor_half_width
## from both neighbouring segments.
func _offset_dir(i: int) -> Vector3:
	if i == 0:
		return _normal(path[0], path[1])
	if i == path.size() - 1:
		return _normal(path[i - 1], path[i])
	var n1 := _normal(path[i - 1], path[i])
	var m := (n1 + _normal(path[i], path[i + 1])).normalized()
	return m / maxf(m.dot(n1), 0.5)


static func _normal(a: Vector3, b: Vector3) -> Vector3:
	var d := (b - a)
	d.y = 0.0
	d = d.normalized()
	return Vector3(-d.z, 0.0, d.x)


func _wall_box(body: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	d.y = 0.0
	var length := d.length() + 0.6
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 4.0, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var mid := (a + b) * 0.5 + Vector3.UP * 2.0
	cs.transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), mid)
	body.add_child(cs)


# ---------------------------------------------------------------------------
# Meshes (unit-sized, scaled per instance)
# ---------------------------------------------------------------------------

func _multimesh(label: String, mesh: Mesh, xforms: Array[Transform3D], color: Color, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if label == "Ferns":
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


static func _trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.7
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 7
	m.rings = 1
	return m


static func _canopy_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 7
	m.rings = 3
	return m


static func _bush_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 0.9
	m.radial_segments = 7
	m.rings = 4
	return m


## A fern: a few drooping fronds made of flat quads around a centre.
static func _fern_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 9
	for f in fronds:
		var a := TAU * f / fronds + 0.3 * sin(f * 2.1)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP) * 0.24
		var p0 := Vector3.ZERO
		var p1 := dir * 0.45 + Vector3.UP * 0.55
		var p2 := dir * 0.9 + Vector3.UP * 0.25
		for seg in [[p0, p1, 1.0], [p1, p2, 0.6]]:
			var s0: Vector3 = seg[0]
			var s1: Vector3 = seg[1]
			var w: float = seg[2]
			st.set_normal(Vector3.UP)
			st.add_vertex(s0 - side * w)
			st.add_vertex(s0 + side * w)
			st.add_vertex(s1 + side * w * 0.6)
			st.add_vertex(s0 - side * w)
			st.add_vertex(s1 + side * w * 0.6)
			st.add_vertex(s1 - side * w * 0.6)
	return st.commit()


# ---------------------------------------------------------------------------
# Thrashing
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _foliage.is_empty():
		return
	_rustle_cooldown -= delta
	var pursuer: Pursuer = Chase.pursuer
	if is_instance_valid(pursuer) and not pursuer.concealed:
		var speed := Vector2(pursuer.velocity.x, pursuer.velocity.z).length()
		if speed > 1.0 or pursuer.state == Pursuer.State.STALKING:
			if _stir(pursuer.global_position, THRASH_RADIUS, clampf(speed / 5.0, 0.4, 1.0)) and _rustle_cooldown <= 0.0 and speed > 1.0:
				Chase.play_at(rustle_sound, pursuer.global_position, 0.7)
				_rustle_cooldown = 0.35
	var player: RelentlessPlayer = Chase.player
	if is_instance_valid(player):
		_stir(player.global_position, 1.3, 0.25)

	var t := Time.get_ticks_msec() / 1000.0
	var done := []
	for key in _shake:
		var mm := _foliage[key / KEY]
		var i: int = key % KEY
		var amount: float = _shake[key]
		amount = maxf(0.0, amount - delta * 1.2)
		_shake[key] = amount
		var rest: Transform3D = _foliage_rest[key / KEY][i]
		var wobble := Vector3(sin(t * 23.0 + i), 0.0, cos(t * 19.0 + i * 1.7)) * amount * 0.45
		var b := Basis(Vector3(wobble.z, 0, -wobble.x).normalized() if wobble.length() > 0.001 else Vector3.RIGHT, wobble.length())
		mm.set_instance_transform(i, Transform3D(b * rest.basis, rest.origin))
		if amount <= 0.0:
			mm.set_instance_transform(i, rest)
			done.append(key)
	for key in done:
		_shake.erase(key)


## Shakes foliage near `where`. Returns true if anything was disturbed.
func _stir(where: Vector3, radius: float, strength: float) -> bool:
	var hit := false
	var c := Vector2i(floori(where.x / CELL), floori(where.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(cell):
				continue
			for key in _grid[cell]:
				var rest: Transform3D = _foliage_rest[key / KEY][key % KEY]
				var d := Vector2(rest.origin.x - where.x, rest.origin.z - where.z).length()
				if d < radius:
					var amount := strength * (1.0 - d / radius)
					if amount > _shake.get(key, 0.0):
						_shake[key] = amount
						hit = hit or strength > 0.3
	return hit
