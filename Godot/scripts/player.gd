class_name RelentlessPlayer
extends CharacterBody3D
## First-person survivor: flashlight, stamina, and the look-back.
## The body's origin is at its feet. Everything it needs is built in _ready,
## so the scene only has to contain this one node.

@export_group("Movement")
@export var walk_speed := 3.0
@export var sprint_speed := 6.2
## Speed while holding sprint with no stamina left.
@export var exhausted_speed := 4.0
@export var crouch_speed := 1.8
## Running while looking over your shoulder costs you.
@export var look_back_speed_scale := 0.85
@export var acceleration := 20.0
@export var braking := 16.0
@export var jump_velocity := 4.2
@export var air_control := 0.3

@export_group("Stamina")
@export var max_stamina := 100.0
@export var sprint_drain := 10.0
## Gentler drain while actually being chased, so chases are about routes, not meters.
@export var chase_sprint_drain := 4.0
@export var stamina_regen := 15.0
@export var exhausted_recover_at := 30.0

@export_group("Flashlight")
@export var max_battery := 100.0
@export var battery_drain := 0.4
## Focusing the beam (right mouse) stuns the pursuer but eats the battery.
@export var focus_drain := 7.0
@export var flashlight_energy := 6.0
@export var focus_multiplier := 2.2
@export var outer_cone := 28.0
@export var focus_outer_cone := 13.0
@export var stun_range := 15.0

@export_group("Camera")
## Horizontal field of view.
@export var base_fov := 90.0
@export var sprint_fov_boost := 8.0
@export var look_back_yaw := 170.0
@export var look_back_blend_speed := 7.0
@export var standing_eye_height := 1.65
@export var crouched_eye_height := 0.75
@export var mouse_sensitivity := 0.12
## Degrees per second when looking with the arrow keys (for touchpads that
## switch off while a key is held).
@export var key_look_speed := 120.0

@export_group("Interaction")
@export var interact_range := 2.3

@export_group("Story")
## Off when the story hands you the flashlight later.
@export var has_flashlight := true

@export_group("Gun")
@export var max_ammo := 6
@export var shot_range := 45.0
@export var shot_cooldown := 0.55
@export var gunshot_sound: AudioStream
@export var dry_fire_sound: AudioStream

@export_group("Sounds")
@export var flashlight_click_sound: AudioStream
@export var death_sound: AudioStream

const RADIUS := 0.34
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 0.88

var camera: Camera3D
var flashlight: SpotLight3D
var hud: RelentlessHUD

var stamina := 100.0
var battery := 100.0
var exhausted := false
var dead := false
var crouched := false
var sprinting := false
var flashlight_on := true
## Cutscenes and dialogue: you can look around but not move or use things.
var controls_locked := false
## Sitting in the car: no movement or gravity at all.
var frozen := false
var has_gun := false
var ammo := 0

var _shape: CapsuleShape3D
var _collider: CollisionShape3D
var _move_input := Vector2.ZERO
var _sprint_held := false
var _crouch_held := false
var _forced_crouch := false
var _look_back_held := false
var _focus_held := false
var _yaw := 0.0
var _pitch := 0.0
var _look_back_alpha := 0.0
var _bob_phase := 0.0
var _eye_height := 1.65
var _view := Vector3.ZERO  # pitch, yaw, roll actually shown
var _killed_by: Pursuer
var _focused: Node
var _interacting: Node
var _hint_text := ""
var _hint_end := -1.0
var _hint_duration := 1.0
var _torch: MeshInstance3D
var _gun: Node3D
var _muzzle: OmniLight3D
var _dark_left := 0.0
var _shot_cooldown_left := 0.0
var _recoil := 0.0


func _ready() -> void:
	collision_layer = Chase.LAYER_PLAYER
	collision_mask = Chase.LAYER_WORLD
	floor_snap_length = 0.3

	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	_collider.position.y = STAND_HEIGHT * 0.5
	add_child(_collider)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = base_fov
	camera.near = 0.05
	camera.position.y = standing_eye_height
	add_child(camera)
	camera.make_current()

	# Offset from the eye so shadows have parallax: things move in the dark as you turn.
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.16, -0.14, -0.25)
	flashlight.light_color = Color8(255, 241, 220)
	flashlight.light_energy = flashlight_energy
	flashlight.light_volumetric_fog_energy = 1.0
	flashlight.spot_range = 26.0
	flashlight.spot_angle = outer_cone
	flashlight.spot_angle_attenuation = 0.6
	flashlight.shadow_enabled = true
	camera.add_child(flashlight)

	var torch := MeshInstance3D.new()
	_torch = torch
	var torch_mesh := CylinderMesh.new()
	torch_mesh.top_radius = 0.0225
	torch_mesh.bottom_radius = 0.0225
	torch_mesh.height = 0.2
	torch.mesh = torch_mesh
	# Unshaded, or the flashlight right beside it lights it up.
	var torch_material := StandardMaterial3D.new()
	torch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torch_material.albedo_color = Color(0.015, 0.015, 0.015)
	torch.material_override = torch_material
	torch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torch.position = Vector3(0.18, -0.2, -0.32)
	torch.rotation_degrees.x = -90.0
	camera.add_child(torch)

	hud = RelentlessHUD.new()
	hud.player = self
	add_child(hud)

	stamina = max_stamina
	battery = max_battery
	_eye_height = standing_eye_height
	_yaw = rotation.y
	_view = Vector3(0.0, _yaw, 0.0)
	Chase.register_player(self)
	_grab_mouse()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## On X11, Godot's captured mouse drops most touchpad motion, so there we hide
## the cursor, keep it in the window, and pull it back to the centre after
## every move instead.
var _warp_look := DisplayServer.get_name() == "X11"


func _grab_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN if _warp_look else Input.MOUSE_MODE_CAPTURED
	if _warp_look:
		get_viewport().warp_mouse(_screen_center())


func _mouse_grabbed() -> bool:
	return Input.mouse_mode in [Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_CONFINED_HIDDEN]


func _screen_center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not _mouse_grabbed():
		if event is InputEventMouseButton and event.pressed:
			_grab_mouse()
		return
	if dead:
		return
	if controls_locked and not event is InputEventMouseMotion:
		return

	if event is InputEventMouseMotion:
		var moved: Vector2 = event.relative
		if _warp_look:
			# Measure from the centre, then put the cursor back there. The warp
			# itself arrives as a motion event that lands on the centre: ignore it.
			var center := _screen_center()
			moved = event.position - center
			if moved.length_squared() < 0.25:
				return
			get_viewport().warp_mouse(center)
		# Steering is clumsy while you're staring behind you.
		var sens := lerpf(1.0, 0.35, _look_back_alpha) * deg_to_rad(mouse_sensitivity)
		_yaw -= moved.x * sens
		_pitch = clampf(_pitch - moved.y * sens, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("crouch"):
		_crouch_held = true
	elif event.is_action_released("crouch"):
		_crouch_held = false
	elif event.is_action_pressed("jump"):
		if not crouched and is_on_floor():
			velocity.y = jump_velocity
	elif event.is_action_pressed("flashlight") and has_flashlight:
		flashlight_on = not flashlight_on and battery > 0.0
		Chase.play_2d(flashlight_click_sound)
	elif has_gun and event.is_action_pressed("shoot"):
		_shoot()
	elif event.is_action_pressed("interact"):
		_interact_pressed()
	elif event.is_action_released("interact"):
		_interact_released()


func _interact_pressed() -> void:
	if _focused != null and is_instance_valid(_focused):
		_interacting = _focused
		_interacting.begin_interact(self)


func _interact_released() -> void:
	if _interacting != null and is_instance_valid(_interacting):
		_interacting.end_interact(self)
	_interacting = null


func set_forced_crouch(force: bool) -> void:
	# Standing back up waits until there's headroom (see _update_crouch).
	_forced_crouch = force


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		return
	_shot_cooldown_left = maxf(0.0, _shot_cooldown_left - delta)
	if controls_locked and not dead:
		_move_input = Vector2.ZERO
		_sprint_held = false
		_look_back_held = false
		_focus_held = false
		_focused = null
		sprinting = false
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)
		velocity.z = move_toward(velocity.z, 0.0, braking * delta)
	elif not dead:
		_sprint_held = Input.is_action_pressed("sprint")
		_look_back_held = Input.is_action_pressed("look_back")
		_focus_held = Input.is_action_pressed("focus_beam")
		_move_input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		var key_look := Input.get_vector("look_left", "look_right", "look_down", "look_up")
		if key_look != Vector2.ZERO:
			var turn := lerpf(1.0, 0.35, _look_back_alpha) * deg_to_rad(key_look_speed) * delta
			_yaw -= key_look.x * turn
			_pitch = clampf(_pitch + key_look.y * turn, deg_to_rad(-89.0), deg_to_rad(89.0))
		_update_crouch()
		_update_movement(delta)
		_update_interact_target()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func _process(delta: float) -> void:
	_update_flashlight(delta)
	_update_camera(delta)


func _update_crouch() -> void:
	var want := _crouch_held or _forced_crouch
	if want == crouched:
		return
	if not want and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT)):
		return  # No headroom yet; keep trying.
	crouched = want
	var h := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	_shape.height = h
	_collider.position.y = h * 0.5


func _update_movement(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	var forward := _move_input.y > -0.1
	sprinting = _sprint_held and moving and forward and not crouched and not exhausted

	var speed := walk_speed
	if crouched:
		speed = crouch_speed
	elif sprinting:
		speed = sprint_speed
	elif _sprint_held and exhausted and moving:
		speed = exhausted_speed
	speed *= lerpf(1.0, look_back_speed_scale, _look_back_alpha)

	rotation.y = _yaw
	var wish := (transform.basis * Vector3(_move_input.x, 0.0, -_move_input.y))
	wish.y = 0.0
	var target := wish.limit_length(1.0) * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if wish.length() > 0.01 else braking
	if not is_on_floor():
		rate *= air_control
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if sprinting:
		stamina -= (chase_sprint_drain if Chase.chase_active else sprint_drain) * delta
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * (0.8 if exhausted else 1.0) * delta)
		if exhausted and stamina >= exhausted_recover_at:
			exhausted = false


func _update_flashlight(delta: float) -> void:
	var danger := Chase.danger
	var time := Time.get_ticks_msec() / 1000.0
	_dark_left = maxf(0.0, _dark_left - delta)
	var lit := has_flashlight and flashlight_on and battery > 0.0 and _dark_left <= 0.0
	var focusing := lit and _focus_held and not dead

	if lit and not frozen:
		battery = maxf(0.0, battery - (focus_drain if focusing else battery_drain) * delta)
		if battery <= 0.0:
			flashlight_on = false

	var energy := flashlight_energy * (focus_multiplier if focusing else 1.0)
	var charge := battery / max_battery
	if charge < 0.2:
		energy *= lerpf(0.35, 1.0, charge / 0.2)

	# The light gets unreliable as it gets closer, and when the battery is dying.
	# Driven by danger, not randomness, so the flicker itself becomes a warning.
	var instability := maxf(clampf((danger - 0.55) / 0.45, 0.0, 1.0), 0.6 if charge < 0.1 else 0.0)
	if instability > 0.0:
		var n := Chase.perlin(time * 11.0) * 0.5 + 0.5
		if n > 1.0 - 0.45 * instability:
			energy *= 0.06

	flashlight.visible = lit
	_torch.visible = has_flashlight
	if is_instance_valid(_muzzle):
		_muzzle.light_energy = maxf(0.0, _muzzle.light_energy - delta * 60.0)
	if is_instance_valid(_gun):
		_recoil = Chase.finterp(_recoil, 0.0, delta, 12.0)
		_gun.position = Vector3(0.2, -0.2 + _recoil * 0.03, -0.38 + _recoil * 0.06)
		_gun.rotation_degrees.x = _recoil * 14.0
	flashlight.light_energy = energy
	var target_cone := focus_outer_cone if focusing else outer_cone
	flashlight.spot_angle = Chase.finterp(flashlight.spot_angle, target_cone, delta, 10.0)

	if focusing:
		_try_stun_pursuer()


func _try_stun_pursuer() -> void:
	var p := Chase.pursuer
	if not is_instance_valid(p) or not p.is_active_threat():
		return
	var from := camera.global_position
	var head := p.get_head_position()
	var to_head := head - from
	if to_head.length() > stun_range:
		return
	var cos_angle := to_head.normalized().dot(-camera.global_basis.z)
	if cos_angle < cos(deg_to_rad(focus_outer_cone * 0.8)):
		return
	var query := PhysicsRayQueryParameters3D.create(from, head, Chase.LAYER_WORLD)
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		p.try_stun()


func _update_camera(delta: float) -> void:
	var danger := Chase.danger
	var time := Time.get_ticks_msec() / 1000.0
	var view: Vector3

	if dead:
		# Forced to look at it.
		view = _view
		if is_instance_valid(_killed_by):
			var dir := _killed_by.get_head_position() - camera.global_position
			var want_yaw := Chase.facing(dir)
			var want_pitch := atan2(dir.y, Vector2(dir.x, dir.z).length())
			var t := clampf(delta * 8.0, 0.0, 1.0)
			view.x = lerp_angle(_view.x, want_pitch, t)
			view.y = lerp_angle(_view.y, want_yaw, t)
		view.z = 0.0
	else:
		_look_back_alpha = Chase.finterp(_look_back_alpha, 1.0 if _look_back_held else 0.0, delta, look_back_blend_speed)
		var eased := Chase.ease_in_out(_look_back_alpha, 2.0)
		view = Vector3(lerpf(_pitch, _pitch * 0.3, eased) + deg_to_rad(_recoil * 2.5), _yaw + deg_to_rad(look_back_yaw) * eased, 0.0)
	_view = view

	# Head bob scales with speed.
	var speed_2d := Vector2(velocity.x, velocity.z).length()
	var bob_amount := 0.0 if dead else clampf(speed_2d / sprint_speed, 0.0, 1.0)
	if is_on_floor() and speed_2d > 0.2:
		_bob_phase += delta * speed_2d * 2.2
	var bob_y := sin(_bob_phase * 2.0) * 0.026 * bob_amount
	var bob_x := sin(_bob_phase) * 0.015 * bob_amount
	var shown := view
	shown.z += deg_to_rad(sin(_bob_phase) * 0.9 * bob_amount)

	# Fear shake: subtle until it's right behind you.
	var shake := deg_to_rad(danger * danger * 1.4)
	shown.x += Chase.perlin(time * 7.0) * shake
	shown.y += Chase.perlin(time * 7.0 + 31.0) * shake
	if exhausted:
		shown.x += deg_to_rad(sin(time * 2.4) * 0.9)

	# Eye height eases from the feet so crouching doesn't snap.
	_eye_height = Chase.finterp(_eye_height, crouched_eye_height if crouched else standing_eye_height, delta, 10.0)
	camera.position = Vector3(bob_x, _eye_height + bob_y, 0.0)
	camera.global_rotation = shown

	var target_fov := base_fov + (sprint_fov_boost if sprinting else 0.0) + danger * 4.0
	camera.fov = Chase.finterp(camera.fov, target_fov, delta, 6.0)

	hud.set_post(0.45 + 0.65 * danger, 0.15 + 0.45 * danger, danger * 3.0,
		0.55 if exhausted else lerpf(0.9, 0.7, danger))


func _update_interact_target() -> void:
	_focused = null
	var from := camera.global_position
	var to := from - camera.global_basis.z * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Chase.LAYER_WORLD | Chase.LAYER_INTERACT)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target := Chase.find_interactable(hit.collider)
	if target != null and target.can_interact():
		_focused = target


# ---------------------------------------------------------------------------
# Death and checkpoints
# ---------------------------------------------------------------------------

## The pursuer reached us.
func caught(killer: Pursuer) -> void:
	if dead:
		return
	dead = true
	_killed_by = killer
	_interact_released()
	velocity = Vector3.ZERO
	Chase.play_2d(death_sound)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if dead:
			hud.fade_to(1.0, 0.5)
	)
	Chase.notify_player_caught()


func respawn(where: Transform3D) -> void:
	global_position = where.origin
	_yaw = where.basis.get_euler().y
	_pitch = 0.0
	rotation.y = _yaw
	_view = Vector3(0.0, _yaw, 0.0)
	velocity = Vector3.ZERO

	dead = false
	_killed_by = null
	_crouch_held = false
	_forced_crouch = false
	exhausted = false
	_look_back_alpha = 0.0
	stamina = max_stamina
	battery = maxf(battery, max_battery * 0.4)
	flashlight_on = true
	controls_locked = false
	if has_gun:
		ammo = maxi(ammo, mini(3, max_ammo))
	hud.fade_to(0.0, 1.2)


func add_battery(amount: float) -> void:
	battery = minf(max_battery, battery + amount)


func give_flashlight() -> void:
	has_flashlight = true
	flashlight_on = true
	Chase.play_2d(flashlight_click_sound)


## Kills the flashlight for a moment, whatever the battery says.
func force_dark(seconds: float) -> void:
	_dark_left = seconds


## Snaps the view to face a direction (for cutscenes).
func look_toward(dir: Vector3) -> void:
	_yaw = Chase.facing(dir)
	_pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	rotation.y = _yaw


func give_gun(rounds: int) -> void:
	ammo = mini(max_ammo, ammo + rounds)
	if has_gun:
		return
	has_gun = true
	# Revolver in the right hand; the torch moves to the left.
	_gun = Node3D.new()
	camera.add_child(_gun)
	var dark := Greybox.material(Color(0.03, 0.03, 0.035))
	var frame := Greybox.box(Vector3(0.05, 0.07, 0.16), Color.BLACK)
	frame.material_override = dark
	_gun.add_child(frame)
	var barrel := Greybox.cylinder(0.014, 0.2, Color.BLACK)
	barrel.material_override = dark
	barrel.rotation_degrees.x = -90.0
	barrel.position = Vector3(0, 0.015, -0.16)
	_gun.add_child(barrel)
	var cylinder := Greybox.cylinder(0.032, 0.06, Color.BLACK)
	cylinder.material_override = dark
	cylinder.rotation_degrees.x = -90.0
	cylinder.position = Vector3(0, 0.0, -0.05)
	_gun.add_child(cylinder)
	var grip := Greybox.box(Vector3(0.04, 0.12, 0.05), Color.BLACK)
	grip.material_override = Greybox.material(Color(0.12, 0.07, 0.04))
	grip.position = Vector3(0, -0.08, 0.07)
	grip.rotation_degrees.x = -18.0
	_gun.add_child(grip)
	for child in _gun.get_children():
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color(1.0, 0.75, 0.4)
	_muzzle.omni_range = 9.0
	_muzzle.light_energy = 0.0
	_muzzle.position = Vector3(0, 0.02, -0.32)
	_gun.add_child(_muzzle)
	_torch.position.x = -0.18
	flashlight.position.x = -0.16


func _shoot() -> void:
	if _shot_cooldown_left > 0.0:
		return
	_shot_cooldown_left = shot_cooldown
	if ammo <= 0:
		Chase.play_2d(dry_fire_sound)
		return
	ammo -= 1
	_recoil = 1.0
	_muzzle.light_energy = 8.0
	Chase.play_2d(gunshot_sound)
	var from := camera.global_position
	var to := from - camera.global_basis.z * shot_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Chase.LAYER_WORLD | Chase.LAYER_PURSUER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is Pursuer:
		hit.collider.shot()


func show_hint(text: String, duration := 4.0) -> void:
	_hint_text = text
	_hint_duration = maxf(duration, 0.5)
	_hint_end = Time.get_ticks_msec() / 1000.0 + _hint_duration


func get_hint_text() -> String:
	return _hint_text


func get_hint_alpha() -> float:
	var remaining := _hint_end - Time.get_ticks_msec() / 1000.0
	var elapsed := _hint_duration - remaining
	return clampf(minf(remaining, elapsed) / 0.5, 0.0, 1.0)


func get_interact_prompt() -> String:
	var target := _interacting if is_instance_valid(_interacting) else _focused
	return target.get_interact_prompt() if is_instance_valid(target) else ""


func get_interact_progress() -> float:
	return _interacting.get_interact_progress() if is_instance_valid(_interacting) else -1.0


func get_stamina01() -> float:
	return stamina / max_stamina


func get_battery01() -> float:
	return battery / max_battery


func get_feet_position() -> Vector3:
	return global_position


func get_center_position() -> Vector3:
	return global_position + Vector3.UP * _shape.height * 0.5


func get_eye_position() -> Vector3:
	return camera.global_position
