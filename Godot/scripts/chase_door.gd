class_name ChaseDoor
extends Node3D
## A door you can slam in its face (it bashes through after a few seconds), or
## a heavy door you must hold E to force open while you hear it coming.
## The node sits at the bottom-centre of the doorway; the hinge is on its -X
## edge and the closed panel spans the doorway along X.

enum DoorState { OPEN, CLOSED, BROKEN }

@export var width := 2.0
@export var height := 2.9
@export var thickness := 0.1
## Positive swings toward +Z of the door node.
@export var open_yaw := 90.0
@export var starts_open := true
## Heavy doors start shut, must be held open, and can't be slammed again.
@export var heavy := false
@export var hold_time := 1.6
@export var color := Color(0.16, 0.09, 0.05)

@export_group("Sounds")
@export var slam_sound: AudioStream
@export var creak_sound: AudioStream
@export var break_sound: AudioStream

var state := DoorState.OPEN

var _panel: AnimatableBody3D
var _debris: RigidBody3D
var _current_yaw := 0.0
var _target_yaw := 0.0
var _swing_speed := 4.0
var _rattle_time := 0.0
var _hold_progress := 0.0
var _holder: RelentlessPlayer


func _ready() -> void:
	_panel = AnimatableBody3D.new()
	_panel.collision_layer = Chase.LAYER_WORLD
	_panel.collision_mask = 0
	add_child(_panel)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, thickness)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_panel.add_child(collider)
	_panel.add_child(Greybox.box(shape.size, color))

	_reset_door()
	Chase.chase_reset.connect(_reset_door)


func _reset_door() -> void:
	if is_instance_valid(_debris):
		_debris.queue_free()
	_debris = null
	_panel.visible = true
	_panel.collision_layer = Chase.LAYER_WORLD

	_holder = null
	_hold_progress = 0.0
	_rattle_time = 0.0
	state = DoorState.OPEN if (starts_open and not heavy) else DoorState.CLOSED
	_current_yaw = open_yaw if state == DoorState.OPEN else 0.0
	_target_yaw = _current_yaw
	_swing_to(_current_yaw)


func _physics_process(delta: float) -> void:
	if state == DoorState.BROKEN:
		return

	# Forcing a heavy door open.
	if is_instance_valid(_holder):
		if _holder.dead or _holder.global_position.distance_to(global_position) > 3.5:
			_holder = null
		else:
			_hold_progress += delta / maxf(hold_time, 0.1)
			_rattle_time = maxf(_rattle_time, 0.1)
			if _hold_progress >= 1.0:
				_holder = null
				_hold_progress = 0.0
				_set_state(DoorState.OPEN, 3.0)
				Chase.play_at(creak_sound, global_position)
	else:
		_hold_progress = maxf(0.0, _hold_progress - delta * 0.5)

	_current_yaw = Chase.finterp(_current_yaw, _target_yaw, delta, _swing_speed)
	var shake := 0.0
	if _rattle_time > 0.0:
		_rattle_time -= delta
		shake = sin(Time.get_ticks_msec() / 1000.0 * 70.0) * 1.5
	# Show a crack opening while it's being forced.
	var strain := _hold_progress * 6.0
	_swing_to(_current_yaw + shake + strain)


## Places the panel swung open by `yaw` degrees around the hinge on the -X edge.
## The body is moved itself (not through a parent) so its collision follows.
func _swing_to(yaw: float) -> void:
	var basis := Basis(Vector3.UP, -deg_to_rad(yaw))
	var hinge := Vector3(-width * 0.5, 0.0, 0.0)
	_panel.transform = Transform3D(basis, hinge + basis * Vector3(width * 0.5, height * 0.5, 0.0))


func _set_state(new_state: DoorState, speed: float) -> void:
	state = new_state
	_swing_speed = speed
	_target_yaw = open_yaw if new_state == DoorState.OPEN else 0.0


# --- Interaction (called by the player) ------------------------------------

func can_interact() -> bool:
	if state == DoorState.BROKEN:
		return false
	return not (heavy and state == DoorState.OPEN)


func get_interact_prompt() -> String:
	if not can_interact():
		return ""
	if heavy:
		return "Hold [E] to force the door"
	return "[E] Slam the door" if state == DoorState.OPEN else "[E] Open"


func begin_interact(by: RelentlessPlayer) -> void:
	if not can_interact():
		return
	if heavy:
		_holder = by
		return
	if state == DoorState.OPEN:
		_set_state(DoorState.CLOSED, 18.0)
		Chase.play_at(slam_sound, global_position)
	else:
		_set_state(DoorState.OPEN, 5.0)


func end_interact(by: RelentlessPlayer) -> void:
	if _holder == by:
		_holder = null


## 0..1 for hold interactions, negative when there is no progress to show.
func get_interact_progress() -> float:
	if heavy and state == DoorState.CLOSED and is_instance_valid(_holder):
		return _hold_progress
	return -1.0


# --- Called by the pursuer -------------------------------------------------

func is_blocking() -> bool:
	return state == DoorState.CLOSED and absf(_current_yaw) < 45.0


func rattle() -> void:
	_rattle_time = 0.35


func smash(direction: Vector3) -> void:
	if state == DoorState.BROKEN:
		return
	state = DoorState.BROKEN
	_holder = null

	# Swap the panel for loose wreckage that flies but no longer blocks anyone.
	_panel.visible = false
	_panel.collision_layer = 0

	_debris = RigidBody3D.new()
	_debris.collision_layer = Chase.LAYER_DEBRIS
	_debris.collision_mask = Chase.LAYER_WORLD | Chase.LAYER_DEBRIS
	_debris.mass = 20.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, thickness)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_debris.add_child(collider)
	_debris.add_child(Greybox.box(shape.size, color))
	add_child(_debris)
	_debris.global_transform = _panel.global_transform
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	_debris.linear_velocity = dir * 9.0 + Vector3.UP * 1.5
	_debris.angular_velocity = Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))

	Chase.play_at(break_sound, global_position)
