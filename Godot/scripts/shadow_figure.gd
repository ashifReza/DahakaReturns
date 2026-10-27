class_name ShadowFigure
extends Node3D
## A man-shaped shadow between the trees. It stands and watches for a moment,
## then bolts sideways and is gone behind the trunks. Purely a scare: it has
## no collision and can't hurt you.

@export var run_speed := 7.5
## It's gone if you get this close.
@export var flee_distance := 6.0
@export var footstep_sound: AudioStream

var _parts: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _material: StandardMaterial3D
var _target := Vector3.ZERO
var _watch_left := 0.0
var _running := false
var _phase := 0.0
var _alpha := 0.0
var _step := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.disable_receive_shadows = true

	_add(Greybox.box(Vector3(0.44, 0.7, 0.22), Color.BLACK), Vector3(0, 1.3, 0))     # chest
	_add(Greybox.box(Vector3(0.36, 0.3, 0.2), Color.BLACK), Vector3(0, 0.88, 0))     # hips
	_add(Greybox.sphere(0.13, Color.BLACK), Vector3(0, 1.82, 0))                     # head
	for side in [-1.0, 1.0]:
		var leg := _pivot(Vector3(0.11 * side, 0.85, 0))
		_add(Greybox.box(Vector3(0.14, 0.85, 0.14), Color.BLACK), Vector3(0, -0.42, 0), leg)
		_legs.append(leg)
		var arm := _pivot(Vector3(0.28 * side, 1.6, 0))
		_add(Greybox.box(Vector3(0.1, 0.72, 0.1), Color.BLACK), Vector3(0, -0.36, 0), arm)
		_arms.append(arm)
	visible = false
	set_process(false)


func _pivot(at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = at
	add_child(p)
	return p


func _add(mi: MeshInstance3D, at: Vector3, parent: Node3D = self) -> void:
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)
	_parts.append(mi)


## Appears at `from`, facing the player, watches for `watch` seconds, then runs to `to`.
func scare(from: Vector3, to: Vector3, watch := 0.9) -> void:
	global_position = from
	_target = to
	_watch_left = watch
	_running = false
	_alpha = 1.0
	_step = 0.0
	var player := Chase.player
	if is_instance_valid(player):
		var d := player.global_position - from
		rotation.y = Chase.facing(Vector3(d.x, 0, d.z))
	visible = true
	set_process(true)


func is_busy() -> bool:
	return visible


func _process(delta: float) -> void:
	var player := Chase.player
	if not _running:
		_watch_left -= delta
		var close := is_instance_valid(player) and player.global_position.distance_to(global_position) < flee_distance
		if _watch_left <= 0.0 or close:
			_running = true
			var d := _target - global_position
			rotation.y = Chase.facing(Vector3(d.x, 0, d.z))
	else:
		var to := _target - global_position
		to.y = 0.0
		var step := run_speed * delta
		if to.length() <= step:
			global_position = _target
			_alpha -= delta * 4.0
		else:
			global_position += to.normalized() * step
			_alpha = minf(1.0, _alpha)
		_phase += delta * run_speed * 1.6
		_step += step
		if _step > 1.6:
			_step = 0.0
			Chase.play_at(footstep_sound, global_position, 0.35)
	var swing := sin(_phase) * (45.0 if _running else 0.0)
	_legs[0].rotation_degrees.x = swing
	_legs[1].rotation_degrees.x = -swing
	_arms[0].rotation_degrees.x = -swing
	_arms[1].rotation_degrees.x = swing
	_material.albedo_color.a = clampf(_alpha, 0.0, 1.0) * 0.96
	if _alpha <= 0.0:
		visible = false
		set_process(false)
