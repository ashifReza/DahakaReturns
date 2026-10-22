extends Node
## Automated run of a level's route, for checking the chase logic without
## playing it by hand. Steers the player along waypoints and logs what happens:
##   godot --headless --path Godot --fixed-fps 60 res://tools/playtest.tscn -- --jungle
## (no --jungle: the Building). A folder argument also saves screenshots.

const Builder := preload("res://tools/building_builder.gd")

var level: Node
var player: RelentlessPlayer
var steps := []
var step := 0
var wait := 0.0
var time := 0.0
var deaths := 0
var last_pursuer_state := -1
var last_line := ""
var last_concealed := true
var _wait_time := 0.0
var shot_dir := ""
var shots := {}


func _ready() -> void:
	# Pass a folder after "--" to also save screenshots (needs a window, not --headless).
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--") and DisplayServer.get_name() != "headless":
		shot_dir = args[0]
	var jungle := "--jungle" in OS.get_cmdline_user_args()
	level = load("res://scenes/jungle.tscn" if jungle else "res://scenes/building.tscn").instantiate()
	add_child(level)
	# Perf experiments: "--no-volumetric" and/or "--no-light-shadows" after "--".
	var user_args := OS.get_cmdline_user_args()
	if "--no-volumetric" in user_args:
		level.get_node("Environment/WorldEnvironment").environment.volumetric_fog_enabled = false
	if "--no-light-shadows" in user_args and level.has_node("Lights"):
		for l in level.get_node("Lights").get_children():
			l.shadow_enabled = false
	var env: Environment = level.get_node("Environment/WorldEnvironment").environment
	if "--no-glow" in user_args:
		env.glow_enabled = false
	if "--no-moon-shadows" in user_args:
		level.get_node("Environment/Moonlight").shadow_enabled = false
	if "--cheap-moon" in user_args:
		var moon: DirectionalLight3D = level.get_node("Environment/Moonlight")
		moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		moon.directional_shadow_max_distance = 20.0
	if "--no-fog" in user_args:
		env.fog_enabled = false
	player = Chase.player
	Chase.chase_started.connect(func(): _log("chase started"))
	Chase.chase_ended.connect(func(): _log("chase ended"))
	Chase.chase_reset.connect(func(): _log("chase reset to checkpoint"))
	if jungle:
		steps = [
			["goj", 0, -15], ["goj", 7, -35], ["goj", 3, -55], ["goj", -4, -74], ["goj", -8, -92],
			["goj", -6, -108], ["goj", -6, -127], ["goj", -2, -150], ["goj", 6, -165], ["goj", 6, -172],
			["goj", 6, -197.6], ["cut"], ["goj", 8, -212], ["goj", 0, -235], ["goj", -6, -250],
			["goj", -4, -265], ["wait", 3.0], ["done"],
		]
		return
	steps = [
		["go", 850, 0], ["go", 2900, 0], ["go", 3400, 0], ["go", 3400, 750],
		["slam", "Gameplay/Door_WardToCorridorB"],
		["go", 3400, 2450], ["force", "Gameplay/HeavyDoor_Storage"],
		["go", 3400, 2850], ["go", 3100, 2960], ["go", 1400, 2960],
		["go", 1000, 2900], ["go", -1000, 2900], ["go", -2600, 2950], ["wait", 3.0], ["done"],
	]


func _log(msg: String) -> void:
	print("[%6.2fs] %s" % [time, msg])


func _physics_process(delta: float) -> void:
	time += delta
	if DisplayServer.get_name() != "headless" and int(time / 5.0) != int((time - delta) / 5.0):
		_log("fps %d" % Engine.get_frames_per_second())
	var p := Chase.pursuer
	if p.state != last_pursuer_state or p.concealed != last_concealed:
		last_pursuer_state = p.state
		last_concealed = p.concealed
		_log("pursuer -> %s%s at %s (gap %.1fm, danger %.2f)" % [Pursuer.State.keys()[p.state], " (hidden)" if p.concealed else "", p.global_position.snapped(Vector3.ONE * 0.1), p.trail_gap, Chase.danger])
	if int(time * 0.5) != int((time - delta) * 0.5) and p.state == Pursuer.State.CHASING:
		_log("  pursuer at %s trail %d/%d gap %.1f speed %.1f" % [p.global_position.snapped(Vector3.ONE * 0.1), p._trail_index, p._trail.size(), p.trail_gap, Vector2(p.velocity.x, p.velocity.z).length()])
		for i in p.get_slide_collision_count():
			var c := p.get_slide_collision(i)
			if absf(c.get_normal().y) < 0.7:
				_log("    blocked by %s (%s) normal %s" % [c.get_collider().name, c.get_collider_shape().name if c.get_collider_shape() else "?", c.get_normal().snapped(Vector3.ONE * 0.01)])
	if time > 180.0:
		_log("TIMEOUT at step %d" % step)
		get_tree().quit(1)
		return

	if player.dead:
		if wait == 0.0:
			deaths += 1
			_log("player CAUGHT at %s (death %d)" % [player.global_position, deaths])
			if deaths >= 3:
				get_tree().quit(1)
		wait = 1.0
		_release()
		return
	if wait == 1.0:
		wait = 0.0
		_log("respawned at %s" % player.global_position)
		# Resume from the waypoint after the respawn point.
		step = _nearest_go_step()

	_screenshots()
	var s: Array = steps[step]
	match s[0]:
		"go", "goj":
			var target := Builder.ue(s[1], s[2], 0) if s[0] == "go" else Vector3(s[1], 0, s[2])
			var to := target - player.global_position
			to.y = 0.0
			if to.length() < 0.5:
				_next()
				return
			player._yaw = Chase.facing(to)
			Input.action_press("move_forward")
			Input.action_press("sprint")
			# Hop over anything low in the way (the fallen log).
			if player.is_on_floor() and player.is_on_wall() and not player.crouched:
				player.velocity.y = player.jump_velocity
				_log("jump")
			_report_if_stuck(delta)
		"cut":
			_release()
			var bridge: RopeBridge = level.get_node("SetPieces/RopeBridge")
			var post := bridge.to_global(Vector3(1.3, 0.9, -bridge.length - 0.4))
			var to := post - player.camera.global_position
			player._yaw = Chase.facing(to)
			player._pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if player._focused == bridge and player._interacting == null:
				player._interact_pressed()
				_log("cut: '%s'" % bridge.get_interact_prompt())
			if bridge.collapsed:
				player._interact_released()
				_log("bridge collapsed")
				_next()
		"slam", "force":
			_release()
			var door: ChaseDoor = level.get_node(s[1])
			# Look at the panel itself; an open door's panel is beside the doorway.
			var to: Vector3 = door._panel.global_position - player.global_position
			player._yaw = Chase.facing(to)
			player._pitch = 0.0
			if player._focused == door and player._interacting == null:
				player._interact_pressed()
				_log("%s: '%s'" % [s[0], door.get_interact_prompt()])
			if s[0] == "slam" and door.state == ChaseDoor.DoorState.CLOSED:
				player._interact_released()
				_next()
			elif s[0] == "force" and door.state == ChaseDoor.DoorState.OPEN:
				player._interact_released()
				_log("heavy door forced open")
				_next()
		"wait":
			_release()
			_wait_time += delta
			if _wait_time >= s[1]:
				_wait_time = 0.0
				_next()
		"done":
			_log("ROUTE COMPLETE. deaths=%d chase_active=%s crouched=%s battery=%.0f" % [deaths, Chase.chase_active, player.crouched, player.battery])
			get_tree().quit(0)

	var line := "crouched" if player.crouched else ""
	if line != last_line:
		last_line = line
		_log("player crouched=%s at %s" % [player.crouched, player.global_position])


var _stuck := 0.0


func _report_if_stuck(delta: float) -> void:
	if Vector2(player.velocity.x, player.velocity.z).length() > 0.5:
		_stuck = 0.0
		return
	_stuck += delta
	if _stuck > 0.5:
		_stuck = -100.0
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			_log("STUCK on %s at %s normal %s" % [c.get_collider().get_path(), c.get_position(), c.get_normal()])


func _next() -> void:
	step += 1
	_log("reached step %d -> %s" % [step, steps[step]])


func _release() -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")


func _nearest_go_step() -> int:
	var best := step
	var best_d := INF
	for i in steps.size():
		if not steps[i][0] in ["go", "goj"]:
			continue
		var pos := Builder.ue(steps[i][1], steps[i][2], 0) if steps[i][0] == "go" else Vector3(steps[i][1], 0, steps[i][2])
		var d := pos.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


## Saves a few frames at moments worth looking at.
func _screenshots() -> void:
	if shot_dir == "":
		return
	var p := Chase.pursuer
	if "--jungle" in OS.get_cmdline_user_args():
		_jungle_screenshots(p)
		return
	var moments := {
		"1_lobby": time > 1.0,
		"2_chase_lookback": p.state == Pursuer.State.CHASING and step == 2 and p._state_time > 2.5,
		"3_bashing": p.state == Pursuer.State.BASHING and p._state_time > 1.0,
		"4_vent": player.crouched and step == 9 and player.global_position.x < 25.0,
		"5_ambush_lookback": step == 11 and p.state == Pursuer.State.CHASING and p._state_time > 0.6,
		"6_outside": step == 13,
	}
	# Look back for the chase shots.
	if (step == 2 and p.state == Pursuer.State.CHASING) or (step == 11 and p.state == Pursuer.State.CHASING):
		Input.action_press("look_back")
	else:
		Input.action_release("look_back")
	for key in moments:
		if moments[key] and not shots.has(key):
			shots[key] = true
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join(key + ".png"))
			_log("screenshot " + key)


func _jungle_screenshots(p: Pursuer) -> void:
	var stalker_in_view := p.state == Pursuer.State.STALKING and not p.concealed
	var moments := {
		"j1_start": time > 1.5,
		"j2_stalker": stalker_in_view and p._state_time > 0.1,
		"j3_chase_lookback": step == 5 and p.state == Pursuer.State.CHASING and p._state_time > 3.0,
		"j4_roots": player.crouched and step == 7 and player.global_position.z < -118.0,
		"j5_bridge_lookback": step == 11 and p.state == Pursuer.State.CHASING,
		"j6_river": step == 16,
	}
	var look_back := (step == 5 and p.state == Pursuer.State.CHASING) or (step == 11 and not shots.has("j5_bridge_lookback"))
	if look_back:
		Input.action_press("look_back")
	else:
		Input.action_release("look_back")
	# Turn to face the stalker so it gets photographed before it flees.
	if stalker_in_view and not shots.has("j2_stalker"):
		player._yaw = Chase.facing(p.global_position - player.global_position)
	for key in moments:
		if moments[key] and not shots.has(key):
			if key in ["j3_chase_lookback", "j5_bridge_lookback"] and player._look_back_alpha < 0.95:
				continue
			shots[key] = true
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join(key + ".png"))
			_log("screenshot " + key)
