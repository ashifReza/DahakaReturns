extends Node
## Autoload "Chase". Owns the state of a chase: who is chasing whom, the
## current checkpoint, and the single "danger" value (0..1) that drives music,
## camera and lights. Also holds a few small helpers shared by every script.

signal chase_started
signal chase_ended
signal chase_reset

## Physics layers (see Project Settings > Layer Names > 3D Physics).
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_PURSUER := 4
const LAYER_DEBRIS := 8

## Gap (metres along the pursuer's trail) at which danger is 1 and 0.
var danger_near_gap := 2.0
var danger_far_gap := 20.0
var restart_delay := 2.2
var restart_grace := 1.5

var danger := 0.0
var chase_active := false
var pursuer: Pursuer
var player: RelentlessPlayer

var _has_checkpoint := false
var _player_respawn := Transform3D.IDENTITY
var _pursuer_start := Transform3D.IDENTITY
var _pursuer_timer: Timer
var _restart_timer: Timer
var _pursuer_timer_action := Callable()
var _noise := FastNoiseLite.new()


# _init, not _ready: the first level enters the tree before this autoload is ready.
func _init() -> void:
	_pursuer_timer = _make_timer(_on_pursuer_timer)
	_restart_timer = _make_timer(restart_from_checkpoint)
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	_noise.seed = 1


## Called by each level as it enters the tree, before its children register.
func begin_level() -> void:
	chase_active = false
	_has_checkpoint = false
	danger = 0.0
	pursuer = null
	player = null
	_pursuer_timer.stop()
	_restart_timer.stop()


func register_pursuer(p: Pursuer) -> void:
	pursuer = p


func register_player(p: RelentlessPlayer) -> void:
	player = p


func _process(delta: float) -> void:
	var target := 0.0
	if chase_active and is_instance_valid(pursuer):
		if pursuer.is_active_threat():
			var pct := (pursuer.trail_gap - danger_near_gap) / (danger_far_gap - danger_near_gap)
			target = 1.0 - clampf(pct, 0.0, 1.0)
		elif pursuer.state == Pursuer.State.LOST:
			# You can't see it, but it's still out there.
			target = 0.35
	# Rise fast, fall slowly: relief should take a moment to arrive.
	danger = finterp(danger, target, delta, 4.0 if target > danger else 1.0)


## Starts the chase, or just moves the checkpoint if one is already running.
func start_chase(trigger: ChaseTrigger) -> void:
	if trigger == null:
		return
	_has_checkpoint = true
	_player_respawn = trigger.get_player_respawn()
	_pursuer_start = trigger.get_pursuer_start()

	if chase_active:
		return
	chase_active = true
	if is_instance_valid(pursuer):
		pursuer.reset_to(_pursuer_start)
		_schedule_pursuer(maxf(trigger.activation_delay, 0.01), _activate_pursuer)
	chase_started.emit()


func end_chase() -> void:
	if not chase_active:
		return
	chase_active = false
	_pursuer_timer.stop()
	if is_instance_valid(pursuer):
		pursuer.retreat()
	chase_ended.emit()


func notify_player_caught() -> void:
	_pursuer_timer.stop()
	_restart_timer.start(restart_delay)


func restart_from_checkpoint() -> void:
	if not _has_checkpoint:
		get_tree().reload_current_scene()
		return
	if is_instance_valid(player):
		player.respawn(_player_respawn)
	if is_instance_valid(pursuer):
		pursuer.reset_to(_pursuer_start)
	chase_reset.emit()

	chase_active = true
	danger = 0.0
	_schedule_pursuer(restart_grace, _activate_pursuer)


func _activate_pursuer() -> void:
	if is_instance_valid(pursuer) and chase_active:
		pursuer.activate()


func player_entered_crawlspace(_zone: VentZone) -> void:
	if is_instance_valid(pursuer) and chase_active:
		pursuer.lose_player()


func player_exited_crawlspace(zone: VentZone) -> void:
	if not is_instance_valid(pursuer) or not is_instance_valid(player) or zone == null:
		return
	if not chase_active or pursuer.state != Pursuer.State.LOST:
		return

	# Came out the far end: it finds another way round. Backed out: it was waiting.
	var ambush := zone.get_ambush()
	var player_pos := player.global_position
	var far_side := player_pos.distance_to(ambush.origin) < player_pos.distance_to(pursuer.global_position)
	var p := pursuer
	_schedule_pursuer(zone.ambush_delay if far_side else 0.3, func() -> void:
		if is_instance_valid(p) and p.state == Pursuer.State.LOST:
			if far_side:
				p.reappear(ambush)
			else:
				p.resume_chase()
	)


# ---------------------------------------------------------------------------
# Timers
# ---------------------------------------------------------------------------

func _make_timer(callback: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(callback)
	add_child(t)
	return t


func _schedule_pursuer(delay: float, action: Callable) -> void:
	_pursuer_timer_action = action
	_pursuer_timer.start(delay)


func _on_pursuer_timer() -> void:
	if _pursuer_timer_action.is_valid():
		_pursuer_timer_action.call()


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Smooth noise in roughly -1..1, like Unreal's PerlinNoise1D.
func perlin(x: float) -> float:
	return clampf(_noise.get_noise_1d(x) * 1.6, -1.0, 1.0)


## Frame-rate independent approach, like Unreal's FInterpTo.
static func finterp(current: float, target: float, delta: float, speed: float) -> float:
	if speed <= 0.0:
		return target
	return current + (target - current) * clampf(delta * speed, 0.0, 1.0)


static func ease_in_out(alpha: float, exponent: float) -> float:
	if alpha < 0.5:
		return 0.5 * pow(2.0 * alpha, exponent)
	return 1.0 - 0.5 * pow(2.0 * (1.0 - alpha), exponent)


## Unreal-style yaw (0 = +X, 90 = +Z in Godot) to a Godot node's rotation.y.
static func yaw_to_rotation(yaw_degrees: float) -> float:
	var r := deg_to_rad(yaw_degrees)
	return atan2(-cos(r), -sin(r))


## Rotation.y that makes a node's forward (-Z) face a horizontal direction.
static func facing(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func play_at(stream: AudioStream, where: Vector3, volume := 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	get_tree().current_scene.add_child(p)
	p.global_position = where
	p.finished.connect(p.queue_free)
	p.play()


func play_2d(stream: AudioStream, volume := 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Walks up from a collider to the node that handles interaction (a door).
static func find_interactable(node: Node) -> Node:
	while node != null:
		if node.has_method("begin_interact"):
			return node
		node = node.get_parent()
	return null
