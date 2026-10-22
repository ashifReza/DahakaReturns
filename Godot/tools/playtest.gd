extends Node
## Automated run of the Building route, for checking the chase logic without
## playing it by hand. Steers the player along waypoints and logs what happens:
##   godot --headless --path Godot --fixed-fps 60 res://tools/playtest.tscn

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
var _wait_time := 0.0
var shot_dir := ""
var shots := {}


func _ready() -> void:
	# Pass a folder after "--" to also save screenshots (needs a window, not --headless).
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--") and DisplayServer.get_name() != "headless":
		shot_dir = args[0]
	level = load("res://scenes/building.tscn").instantiate()
	add_child(level)
	# Perf experiments: "--no-volumetric" and/or "--no-light-shadows" after "--".
	var user_args := OS.get_cmdline_user_args()
	if "--no-volumetric" in user_args:
		level.get_node("Environment/WorldEnvironment").environment.volumetric_fog_enabled = false
	if "--no-light-shadows" in user_args:
		for l in level.get_node("Lights").get_children():
			l.shadow_enabled = false
	player = Chase.player
	Chase.chase_started.connect(func(): _log("chase started"))
	Chase.chase_ended.connect(func(): _log("chase ended"))
	Chase.chase_reset.connect(func(): _log("chase reset to checkpoint"))
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
	if p.state != last_pursuer_state:
		last_pursuer_state = p.state
		_log("pursuer -> %s (gap %.1fm, danger %.2f)" % [Pursuer.State.keys()[p.state], p.trail_gap, Chase.danger])
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
		"go":
			var target := Builder.ue(s[1], s[2], 0)
			var to := target - player.global_position
			to.y = 0.0
			if to.length() < 0.5:
				_next()
				return
			player._yaw = Chase.facing(to)
			Input.action_press("move_forward")
			Input.action_press("sprint")
			_report_if_stuck(delta)
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
		if steps[i][0] != "go":
			continue
		var d := Builder.ue(steps[i][1], steps[i][2], 0).distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


## Saves a few frames at moments worth looking at.
func _screenshots() -> void:
	if shot_dir == "":
		return
	var p := Chase.pursuer
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
