class_name Pursuer
extends CharacterBody3D
## The thing behind you. It doesn't path-find: it follows the exact trail of
## breadcrumbs you leave, so it always comes the way you came. Its speed is
## rubber-banded to stay just behind you; only mistakes get you killed.
## The body's origin is at its feet.

enum State {
	DORMANT,     ## Hidden, waiting for a chase trigger.
	CHASING,
	BASHING,     ## Smashing through a door.
	STUNNED,     ## Caught in the focused flashlight beam.
	LOST,        ## Player slipped into a crawlspace.
	RETREATING,  ## Player reached a safe zone.
	FEEDING,     ## Caught the player.
	STALKING,    ## Before a chase: shows itself at a distance, vanishes when seen.
}

@export_group("Chase")
## Gap (metres along the trail) it tries to hold. At or below this it runs at near_speed_scale.
@export var ideal_gap := 6.5
## At or beyond this gap it runs at far_speed_scale to catch back up.
@export var far_gap := 16.0
## Multiples of the player's sprint speed. Just under 1: a sprinting player
## slowly escapes, anyone else doesn't.
@export var near_speed_scale := 0.9
@export var far_speed_scale := 1.35
## Hidden mercy: eases off a little when the player is out of breath.
@export var exhaustion_mercy := 0.85
@export var kill_distance := 1.8
@export var crumb_spacing := 0.6
@export var bash_time := 2.5
@export var stun_duration := 1.3
@export var stun_cooldown := 3.5
## How long it lingers at a crawlspace before vanishing to go round.
@export var lost_conceal_delay := 2.5
## Falling below this height (a chasm) loses the player until an ambush.
@export var fall_lose_height := -6.0

@export_group("Stalking")
## How far from the player it chooses to appear.
@export var stalk_min_distance := 7.0
@export var stalk_max_distance := 28.0
## Seconds of being looked at before it vanishes.
@export var stalk_seen_time := 0.6
## It vanishes if you get this close.
@export var stalk_flee_distance := 7.0

@export_group("Movement")
@export var acceleration := 30.0
@export var braking := 25.0
@export var turn_rate := 540.0
@export var jump_velocity := 6.0

@export_group("Sounds")
@export var roar_sound: AudioStream
@export var footstep_sound: AudioStream
@export var bash_sound: AudioStream
@export var screech_sound: AudioStream
@export var vanish_sound: AudioStream
@export var footstep_stride := 1.9

const RADIUS := 0.6
const HEIGHT := 2.8  # 2.8m and hunched: it fits through doorways, never through vents.

var state := State.DORMANT
## Set by terrain it's crossing (a swaying rope bridge slows it).
var terrain_speed_scale := 1.0
var trail_gap := INF
var concealed := false

var _state_time := 0.0
var _stun_cooldown_left := 0.0
var _stuck_time := 0.0
var _next_bash_hit := 0.0
var _anim_phase := 0.0
var _step_distance := 0.0
var _max_speed := 5.5
var _move_dir := Vector3.ZERO
var _trail: Array[Vector3] = []
var _trail_index := 0
var _bash_target: ChaseDoor

var _stalk_points: Array[Node3D] = []
var _stalk_wait := 0.0
var _stalk_seen := 0.0
var body: CreatureBody


func _ready() -> void:
	collision_layer = Chase.LAYER_PURSUER
	collision_mask = Chase.LAYER_WORLD
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = HEIGHT * 0.5
	add_child(collider)
	body = CreatureBody.new()
	add_child(body)

	Chase.register_pursuer(self)
	_set_concealed(true)
	_enter_state(State.DORMANT)


# ---------------------------------------------------------------------------
# Control from the chase manager
# ---------------------------------------------------------------------------

func activate() -> void:
	_set_concealed(false)
	_reset_trail()
	_enter_state(State.CHASING)
	_play(roar_sound)


func reset_to(where: Transform3D) -> void:
	_teleport(where)
	_set_concealed(true)
	_trail.clear()
	_trail_index = 0
	trail_gap = INF
	_bash_target = null
	_enter_state(State.DORMANT)


func try_stun() -> void:
	if state != State.CHASING or _stun_cooldown_left > 0.0:
		return
	_enter_state(State.STUNNED)


func lose_player() -> void:
	if state in [State.CHASING, State.BASHING, State.STUNNED]:
		_enter_state(State.LOST)


func reappear(where: Transform3D) -> void:
	_teleport(where)
	resume_chase()


func resume_chase() -> void:
	_set_concealed(false)
	_reset_trail()
	_enter_state(State.CHASING)
	_play(roar_sound)


func retreat() -> void:
	if concealed:
		_enter_state(State.DORMANT)
		return
	_enter_state(State.RETREATING)


## Starts shadowing the player from these points until a chase begins.
func begin_stalk(points: Array[Node3D]) -> void:
	if state != State.DORMANT:
		return
	_stalk_points = points
	_set_concealed(true)
	_enter_state(State.STALKING)
	_stalk_wait = 1.5


func is_active_threat() -> bool:
	if concealed:
		return false
	return state in [State.CHASING, State.BASHING, State.STUNNED, State.FEEDING]


func get_head_position() -> Vector3:
	return body.get_head_position()


func get_center_position() -> Vector3:
	return global_position + Vector3.UP * HEIGHT * 0.5


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	_stun_cooldown_left = maxf(0.0, _stun_cooldown_left - delta)
	_move_dir = Vector3.ZERO
	var player := Chase.player

	match state:
		State.CHASING:
			if is_instance_valid(player) and not player.dead:
				_record_trail(player)
				_update_gap(player)
				_update_speed(player)
				if not _check_catch(player) and not _check_doors():
					_follow_trail(player, delta)

		State.BASHING:
			if is_instance_valid(player):
				_record_trail(player)
				_update_gap(player)
			if is_instance_valid(_bash_target):
				var to_door := _bash_target.global_position - global_position
				rotation.y = Chase.facing(to_door)
				if _state_time >= _next_bash_hit:
					_next_bash_hit += 0.6
					_bash_target.rattle()
					_play(bash_sound)
				if _state_time >= bash_time:
					_bash_target.smash(-global_basis.z)
					_play(roar_sound, 0.7)
					_enter_state(State.CHASING)
			else:
				_enter_state(State.CHASING)

		State.STUNNED:
			if is_instance_valid(player):
				_record_trail(player)
				_update_gap(player)
			if _state_time >= stun_duration:
				_enter_state(State.CHASING)

		State.LOST:
			if not concealed and _state_time >= lost_conceal_delay:
				_set_concealed(true)

		State.STALKING:
			if is_instance_valid(player):
				_update_stalk(player, delta)

		State.RETREATING:
			if is_instance_valid(player):
				_move_dir = global_position - player.global_position
				_move_dir.y = 0.0
				_move_dir = _move_dir.normalized()
			if _state_time >= 1.5:
				_set_concealed(true)
				_enter_state(State.DORMANT)

	if concealed:
		return
	if global_position.y < fall_lose_height and state != State.LOST:
		# Fell into a chasm. It will climb back out somewhere else.
		_play(screech_sound)
		_enter_state(State.LOST)
		_set_concealed(true)
		return
	_move(delta)
	body.animate(delta, state, _state_time, Vector2(velocity.x, velocity.z).length())

	var speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed > 0.5:
		_step_distance += speed * delta
		if _step_distance >= footstep_stride:
			_step_distance = 0.0
			_play(footstep_sound)


func _move(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := _move_dir * _max_speed
	horizontal = horizontal.move_toward(target, (acceleration if _move_dir != Vector3.ZERO else braking) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	# Turn to face where it's going.
	if horizontal.length() > 0.3 and state != State.BASHING:
		var want := Chase.facing(horizontal)
		var step := deg_to_rad(turn_rate) * delta
		rotation.y += clampf(wrapf(want - rotation.y, -PI, PI), -step, step)


func _enter_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_stuck_time = 0.0

	match new_state:
		State.STUNNED:
			_stun_cooldown_left = stun_cooldown
			velocity = Vector3.ZERO
			_play(screech_sound)
		State.BASHING:
			_next_bash_hit = 0.3
			velocity = Vector3.ZERO
		State.LOST, State.FEEDING:
			velocity = Vector3.ZERO


func _set_concealed(conceal: bool) -> void:
	concealed = conceal
	visible = not conceal
	collision_layer = 0 if conceal else Chase.LAYER_PURSUER
	collision_mask = 0 if conceal else Chase.LAYER_WORLD
	velocity = Vector3.ZERO


func _teleport(where: Transform3D) -> void:
	global_position = where.origin
	rotation = Vector3(0.0, where.basis.get_euler().y, 0.0)
	velocity = Vector3.ZERO
	body.reset_particles()


# ---------------------------------------------------------------------------
# Stalking
# ---------------------------------------------------------------------------

func _update_stalk(player: RelentlessPlayer, delta: float) -> void:
	if concealed:
		_stalk_wait -= delta
		if _stalk_wait <= 0.0:
			_try_appear(player)
		return

	var to_player := player.global_position - global_position
	rotation.y = Chase.facing(Vector3(to_player.x, 0.0, to_player.z))
	var head := get_head_position()
	var eye := player.get_eye_position()
	var seen := false
	if player.camera.is_position_in_frustum(head) and eye.distance_to(head) < stalk_max_distance + 5.0:
		var query := PhysicsRayQueryParameters3D.create(eye, head, Chase.LAYER_WORLD)
		seen = get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	# A flashlight on it drives it off faster.
	_stalk_seen += delta * (0.0 if not seen else (2.0 if player.flashlight_on else 1.0))
	if _stalk_seen >= stalk_seen_time or to_player.length() < stalk_flee_distance or _state_time > 9.0:
		Chase.play_at(vanish_sound, head, 0.8)
		_set_concealed(true)
		_stalk_wait = randf_range(3.5, 7.0)


## Shows itself at a stalk point the player isn't looking at, at a distance.
func _try_appear(player: RelentlessPlayer) -> void:
	var forward := -player.global_basis.z
	var beside: Array[Node3D] = []
	var behind: Array[Node3D] = []
	for p in _stalk_points:
		var offset := p.global_position - player.global_position
		var d := offset.length()
		if d < stalk_min_distance or d > stalk_max_distance:
			continue
		if player.camera.is_position_in_frustum(p.global_position + Vector3.UP * 1.5):
			continue  # Never pops in where you're looking.
		# Prefer just out of view to the side, where a glance will catch it.
		(beside if offset.normalized().dot(forward) > -0.3 else behind).append(p)
	var candidates := beside if not beside.is_empty() else behind
	if candidates.is_empty():
		_stalk_wait = 1.0
		return
	var pick: Node3D = candidates.pick_random()
	_teleport(pick.global_transform)
	_set_concealed(false)
	_enter_state(State.STALKING)
	_stalk_seen = 0.0


# ---------------------------------------------------------------------------
# Trail following
# ---------------------------------------------------------------------------

func _reset_trail() -> void:
	_trail.clear()
	_trail_index = 0
	_trail.append(global_position)


func _record_trail(player: RelentlessPlayer) -> void:
	var feet := player.get_feet_position()
	if _trail.is_empty() or _trail.back().distance_squared_to(feet) > crumb_spacing * crumb_spacing:
		_trail.append(feet)


func _update_gap(player: RelentlessPlayer) -> void:
	var prev := global_position
	var gap := 0.0
	for i in range(_trail_index, _trail.size()):
		gap += prev.distance_to(_trail[i])
		prev = _trail[i]
	gap += prev.distance_to(player.get_feet_position())
	trail_gap = gap


func _update_speed(player: RelentlessPlayer) -> void:
	var t := clampf((trail_gap - ideal_gap) / maxf(far_gap - ideal_gap, 0.01), 0.0, 1.0)
	var s := lerpf(near_speed_scale, far_speed_scale, t)
	if player.exhausted:
		s *= exhaustion_mercy
	_max_speed = player.sprint_speed * s * terrain_speed_scale


func _check_catch(player: RelentlessPlayer) -> bool:
	if get_center_position().distance_to(player.get_center_position()) > kill_distance:
		return false
	# No killing through a closed door.
	var query := PhysicsRayQueryParameters3D.create(get_head_position(), player.get_eye_position(), Chase.LAYER_WORLD)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	_enter_state(State.FEEDING)
	_play(roar_sound)
	player.caught(self)
	return true


func _check_doors() -> bool:
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() < 0.05 and _trail_index < _trail.size():
		dir = _trail[_trail_index] - global_position
		dir.y = 0.0
	if dir.length() < 0.05:
		return false
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP) * 0.35
	var space := get_world_3d().direct_space_state
	for offset in [Vector3.ZERO, side, -side]:
		var from: Vector3 = get_center_position() + offset
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 1.3, Chase.LAYER_WORLD)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var door := Chase.find_interactable(hit.collider) as ChaseDoor
		if door != null and door.is_blocking():
			_bash_target = door
			_enter_state(State.BASHING)
			return true
	return false


func _follow_trail(player: RelentlessPlayer, delta: float) -> void:
	var feet := global_position
	while _trail_index < _trail.size() - 1 and _flat_distance(feet, _trail[_trail_index]) < 0.9:
		_trail_index += 1

	var target := _trail[_trail_index] if _trail_index < _trail.size() else player.get_feet_position()
	if _trail_index >= _trail.size() - 1 and _flat_distance(feet, target) < 0.9:
		# End of the trail: go straight for them.
		target = player.get_feet_position()

	_move_dir = target - feet
	_move_dir.y = 0.0
	_move_dir = _move_dir.normalized()

	if target.y - feet.y > 0.5 and is_on_floor():
		velocity.y = jump_velocity

	# If something snags it, skip ahead along the trail rather than standing there.
	if Vector2(velocity.x, velocity.z).length() < 0.4:
		_stuck_time += delta
		if _stuck_time > 0.8:
			_trail_index = mini(_trail_index + 4, _trail.size() - 1)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	if _trail_index > 256:
		_trail = _trail.slice(_trail_index)
		_trail_index = 0


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _play(stream: AudioStream, volume := 1.0) -> void:
	if stream != null and not concealed:
		Chase.play_at(stream, global_position, volume)
