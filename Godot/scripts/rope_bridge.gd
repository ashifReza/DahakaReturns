class_name RopeBridge
extends Node3D
## A rope bridge across a chasm, running from this node along -Z. Once you're
## across, hold E at the far posts to cut the ropes: the deck drops into the
## chasm, along with anything still on it. Rebuilt when the chase resets.

@export var length := 24.0
@export var width := 2.2
@export var hold_time := 1.3
## It's heavy: it slows right down on the swaying bridge, which is your chance.
@export var pursuer_speed_scale := 0.5
@export var snap_sound: AudioStream
@export var collapse_sound: AudioStream

var collapsed := false

var _deck: StaticBody3D
var _visual: Node3D
var _planks: Array[MeshInstance3D] = []
var _debris: Array[RigidBody3D] = []
var _hold_progress := 0.0
var _holder: RelentlessPlayer
var _wood: StandardMaterial3D
var _rope: StandardMaterial3D
var _slowing := false


func _ready() -> void:
	_wood = Greybox.material(Color(0.16, 0.11, 0.07))
	_rope = Greybox.material(Color(0.22, 0.18, 0.12))
	_deck = StaticBody3D.new()
	_deck.collision_layer = Chase.LAYER_WORLD
	_deck.collision_mask = 0
	add_child(_deck)
	_box_shape(_deck, Vector3(width, 0.2, length + 0.4), Vector3(0, -0.1, -length * 0.5))
	for side in [-1.0, 1.0]:
		_box_shape(_deck, Vector3(0.1, 1.3, length), Vector3(side * width * 0.5, 0.65, -length * 0.5))

	_visual = Node3D.new()
	add_child(_visual)
	var count := int(length / 0.36)
	for i in count:
		var plank := Greybox.box(Vector3(width * randf_range(0.92, 1.0), 0.06, 0.28), Color.WHITE)
		plank.material_override = _wood
		plank.position = Vector3(randf_range(-0.05, 0.05), -0.03, -(i + 0.5) * length / count)
		plank.rotation.y = randf_range(-0.04, 0.04)
		_visual.add_child(plank)
		_planks.append(plank)
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 + 0.08)
		_rope_between(Vector3(x, 1.05, 0.3), Vector3(x, 1.05, -length - 0.3))
		_rope_between(Vector3(x, 0.02, 0.3), Vector3(x, 0.02, -length - 0.3))
		var hangers := int(length / 1.5)
		for k in hangers + 1:
			var z := -k * length / hangers
			_rope_between(Vector3(x, 0.02, z), Vector3(x, 1.05, z))

	# Posts: plain on the near side, cuttable on the far side. A lantern on
	# one post at each end, so you can see where you're running.
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 + 0.2)
		var near := _post(Vector3(x, 0, 0.4))
		add_child(near)
		var far := _post(Vector3(x, 0, -length - 0.4))
		if side > 0.0:
			_lantern(near)
		else:
			_lantern(far)
		var body := StaticBody3D.new()
		body.collision_layer = Chase.LAYER_WORLD
		body.collision_mask = 0
		far.add_child(body)
		_box_shape(body, Vector3(0.35, 1.5, 0.35), Vector3(0, 0.75, 0))
		add_child(far)

	Chase.chase_reset.connect(_rebuild)


func _box_shape(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	body.add_child(cs)


func _rope_between(a: Vector3, b: Vector3) -> void:
	var rope := Greybox.cylinder(0.025, a.distance_to(b), Color.WHITE)
	rope.material_override = _rope
	rope.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	rope.basis = Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(rope)


func _post(at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	var post := Greybox.cylinder(0.14, 1.5, Color.WHITE)
	post.material_override = _wood
	post.position = Vector3(0, 0.75, 0)
	holder.add_child(post)
	return holder


func _lantern(post: Node3D) -> void:
	var flame := Greybox.sphere(0.07, Color.BLACK)
	flame.material_override = Greybox.material(Color.BLACK, Color(1.0, 0.55, 0.2) * 3.0)
	flame.position = Vector3(0, 1.62, 0)
	post.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.shadow_enabled = true
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.position = Vector3(0, 1.65, 0)
	post.add_child(light)


func _physics_process(delta: float) -> void:
	_update_pursuer_speed()
	if collapsed:
		return
	if is_instance_valid(_holder):
		if _holder.dead or _holder.global_position.distance_to(_far_end()) > 3.5:
			_holder = null
		else:
			_hold_progress += delta / maxf(hold_time, 0.1)
			if _hold_progress >= 1.0:
				_holder = null
				_hold_progress = 0.0
				collapse()
	else:
		_hold_progress = maxf(0.0, _hold_progress - delta)
	# A gentle sway, more while someone is on it.
	var t := Time.get_ticks_msec() / 1000.0
	for i in _planks.size():
		var k := sin(PI * i / _planks.size())
		_planks[i].position.y = -0.03 + sin(t * 2.0 + i * 0.3) * 0.015 * k
		_planks[i].rotation.z = sin(t * 1.3 + i * 0.2) * 0.03 * k


func _update_pursuer_speed() -> void:
	var p := Chase.pursuer
	if not is_instance_valid(p):
		return
	var local := to_local(p.global_position)
	var on := not collapsed and not p.concealed and absf(local.x) < width and local.z < 0.5 and local.z > -length - 0.5
	if on != _slowing:
		_slowing = on
		p.terrain_speed_scale = pursuer_speed_scale if on else 1.0


func _far_end() -> Vector3:
	return to_global(Vector3(0, 0, -length))


# --- Interaction (called by the player) ------------------------------------

func can_interact() -> bool:
	return not collapsed


func get_interact_prompt() -> String:
	return "" if collapsed else "Hold [E] to cut the ropes"


func begin_interact(by: RelentlessPlayer) -> void:
	if not collapsed:
		_holder = by


func end_interact(by: RelentlessPlayer) -> void:
	if _holder == by:
		_holder = null


func get_interact_progress() -> float:
	return _hold_progress if is_instance_valid(_holder) else -1.0


# --- Collapse and reset -----------------------------------------------------

func collapse() -> void:
	if collapsed:
		return
	collapsed = true
	_deck.collision_layer = 0
	Chase.play_at(snap_sound, _far_end())
	Chase.play_at(collapse_sound, to_global(Vector3(0, 0, -length * 0.5)))
	_visual.visible = false
	# Every plank falls on its own, the far end first.
	for i in _planks.size():
		var src := _planks[i]
		var rb := RigidBody3D.new()
		rb.collision_layer = Chase.LAYER_DEBRIS
		rb.collision_mask = Chase.LAYER_WORLD
		rb.mass = 2.0
		var shape := BoxShape3D.new()
		shape.size = (src.mesh as BoxMesh).size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		mi.material_override = _wood
		rb.add_child(mi)
		add_child(rb)
		rb.global_transform = src.global_transform
		rb.linear_velocity = Vector3(randf_range(-0.5, 0.5), randf_range(-1.0, 0.5), randf_range(-0.5, 0.5))
		rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-1, 1), randf_range(-3, 3))
		_debris.append(rb)
	get_tree().create_timer(6.0).timeout.connect(_clear_debris)


func _clear_debris() -> void:
	for rb in _debris:
		if is_instance_valid(rb):
			rb.queue_free()
	_debris.clear()


func _rebuild() -> void:
	_clear_debris()
	collapsed = false
	_holder = null
	_hold_progress = 0.0
	_deck.collision_layer = Chase.LAYER_WORLD
	_visual.visible = true
