extends Node
## Automated run of the whole story, for checking it still plays through:
##   godot --headless --path Godot --fixed-fps 60 res://tools/story_playtest.tscn
## Dialogue and fades are cut short. It walks to the car's trunk, picks up
## every clue, reads the note, grabs the gun, shoots, forces the back door
## and runs for the road. A folder after "--" also saves screenshots (needs
## a window, not --headless).

const Builder := preload("res://tools/story_builder.gd")

var level: Node
var director: StoryDirector
var player: RelentlessPlayer
var steps := []
var step := 0
var time := 0.0
var deaths := 0
var dead_wait := false
var last_phase := -1
var last_pursuer_state := -1
var last_concealed := true
var shots_fired := 0
var hits := 0
var shot_dir := ""
var shots := {}
var _wait_time := 0.0
var _stuck := 0.0
var _pressed := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--") and DisplayServer.get_name() != "headless":
		shot_dir = args[0]
	StoryDirector.fast_mode = true
	seed(7)  # the scares are random: keep runs repeatable
	level = load("res://scenes/story.tscn").instantiate()
	add_child(level)
	director = level.get_node("Director")
	player = Chase.player
	Chase.chase_started.connect(func(): _log("chase started"))
	Chase.chase_ended.connect(func(): _log("chase ended"))
	Chase.chase_reset.connect(func(): _log("chase reset to checkpoint"))
	director.scared.connect(func(kind: String): _log("SCARE: %s at %s" % [kind, player.global_position.snapped(Vector3.ONE)]))
	_plan()


func _plan() -> void:
	steps = [["phase", StoryDirector.Phase.STREET], ["go", 7.8, 21.0], ["go", 0.5, 7.2], ["phase", StoryDirector.Phase.FLASHLIGHT],
		["go", 4.0, 20.0], ["go", 4.6, 25.2], ["use", "Street/Car/Trunk"], ["go", 3.0, 20.0], ["go", 0.0, 6.0]]
	# Into the jungle, then from clue to clue, always to the nearest one left.
	steps += [["go", 0.0, -14.0]]
	var at := Vector2(0, -14)
	var left := []
	for clue in level.get_node("Clues").get_children():
		left.append(clue)
	while not left.is_empty():
		left.sort_custom(func(a, b): return at.distance_to(Vector2(a.global_position.x, a.global_position.z)) < at.distance_to(Vector2(b.global_position.x, b.global_position.z)))
		var next: Node3D = left.pop_front()
		steps.append(["use", "Clues/" + next.name])
		at = Vector2(next.global_position.x, next.global_position.z)
	steps.append(["phase", StoryDirector.Phase.TRAIL])
	steps.append(["go", 10.0, -118.0])
	for v in Builder.HOUSE_TRAIL:
		steps.append(["go", v.x, v.y])
	var h := Builder.HOUSE
	steps += [
		["go", 0, -160], ["go", 0, h.z + 4.0], ["go", 0, h.z - 2.5], ["phase", StoryDirector.Phase.HOUSE],
		["go", 3.0, h.z - 4.5], ["go", 5.0, h.z - 6.2], ["go", 5.0, h.z - 8.0], ["go", 4.0, h.z - 10.5],
		["go", 5.0, h.z - 12.2], ["go", 5.0, h.z - 14.2], ["go", -3.0, h.z - 16.0], ["use", "House/Note"],
		["phase", StoryDirector.Phase.CHASE], ["wait", 0.6],
		["go", -5.0, h.z - 14.0], ["go", -5.0, h.z - 11.6], ["slam", "House/KitchenDoor"], ["use", "House/Gun"],
		["shoot", 2], ["go", -7.5, h.z - 10.0], ["force", "House/BackDoor"], ["go", -12.0, h.z - 10.0],
	]
	for v in Builder.ESCAPE:
		steps.append(["go", v.x, v.y])
	steps += [["phase", StoryDirector.Phase.ENDED], ["done"]]


func _log(msg: String) -> void:
	print("[%6.2fs] %s" % [time, msg])


func _physics_process(delta: float) -> void:
	time += delta
	if DisplayServer.get_name() != "headless" and int(time / 5.0) != int((time - delta) / 5.0):
		_log("fps %d" % Engine.get_frames_per_second())
	if director.phase != last_phase:
		last_phase = director.phase
		_log("PHASE -> %s (clues %d)" % [StoryDirector.Phase.keys()[director.phase], director.clues_found])
	var p := Chase.pursuer
	if p.state != last_pursuer_state or p.concealed != last_concealed:
		last_pursuer_state = p.state
		last_concealed = p.concealed
		_log("pursuer -> %s%s at %s (gap %.1fm, danger %.2f)" % [Pursuer.State.keys()[p.state], " (hidden)" if p.concealed else "", p.global_position.snapped(Vector3.ONE * 0.1), p.trail_gap, Chase.danger])
	if int(time * 2.0) != int((time - delta) * 2.0) and p.state == Pursuer.State.CHASING and director.phase == StoryDirector.Phase.CHASE:
		_log("  pursuer at %s trail %d/%d gap %.1f speed %.1f" % [p.global_position.snapped(Vector3.ONE * 0.1), p._trail_index, p._trail.size(), p.trail_gap, Vector2(p.velocity.x, p.velocity.z).length()])
		for i in p.get_slide_collision_count():
			var c := p.get_slide_collision(i)
			if absf(c.get_normal().y) < 0.7:
				_log("    blocked by %s normal %s" % [c.get_collider().get_path(), c.get_normal().snapped(Vector3.ONE * 0.01)])
	if time > 400.0:
		_log("TIMEOUT at step %d %s" % [step, steps[step]])
		get_tree().quit(1)
		return

	if player.dead:
		if not dead_wait:
			dead_wait = true
			deaths += 1
			_log("player CAUGHT at %s (death %d)" % [player.global_position.snapped(Vector3.ONE * 0.1), deaths])
			if deaths >= 4:
				get_tree().quit(1)
		_release()
		return
	if dead_wait:
		dead_wait = false
		_log("respawned at %s" % player.global_position.snapped(Vector3.ONE * 0.1))
		step = _nearest_go_step()

	_screenshots()
	var s: Array = steps[step]
	match s[0]:
		"phase":
			_release()
			if director.phase == s[1]:
				_next()
		"go":
			var target := Vector3(s[1], 0, s[2])
			var to := target - player.global_position
			to.y = 0.0
			if to.length() < 0.6:
				_next()
				return
			_walk(to)
			_report_if_stuck(delta)
		"use":
			var item: StoryInteractable = level.get_node(s[1])
			if not item.available:
				if _pressed:
					player._interact_released()
					_pressed = false
					_log("used %s" % s[1])
				_next()  # or already had it from before a respawn
				return
			var to := item.global_position - player.global_position
			to.y = 0.0
			if to.length() > 1.1:
				_walk(to)
				_report_if_stuck(delta)
				return
			_release()
			var look := item.global_position - player.camera.global_position
			player._yaw = Chase.facing(look)
			player._pitch = atan2(look.y, Vector2(look.x, look.z).length())
			if player._focused == item and not _pressed:
				player._interact_pressed()
				_pressed = true
			elif _pressed:
				player._interact_released()
				_pressed = false
		"shoot":
			_release()
			_wait_time += delta
			# Wait for it to come through the door, then put a couple of rounds in it.
			if p.is_active_threat() and p.state == Pursuer.State.CHASING and _in_sight(p):
				var look := p.get_center_position() + Vector3.UP * 0.3 - player.camera.global_position
				player._yaw = Chase.facing(look)
				player._pitch = atan2(look.y, Vector2(look.x, look.z).length())
				if player._shot_cooldown_left <= 0.0 and player._view.distance_to(Vector3(player._pitch, player._yaw, 0)) < 0.05:
					var before := p._slow_left
					player._shoot()
					shots_fired += 1
					if p._slow_left > before:
						hits += 1
					_log("shot %d: %s (ammo %d)" % [shots_fired, "HIT, it's slowed" if p._slow_left > before else "miss", player.ammo])
			# Don't stand there once it's close: run.
			var close := p.is_active_threat() and p.global_position.distance_to(player.global_position) < 4.5
			if shots_fired >= s[1] or _wait_time > 6.0 or close:
				_wait_time = 0.0
				_next()
		"slam":
			_release()
			var door: ChaseDoor = level.get_node(s[1])
			var to: Vector3 = door._panel.global_position - player.camera.global_position
			player._yaw = Chase.facing(to)
			player._pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if player._focused == door and player._interacting == null:
				player._interact_pressed()
				_log("slam: '%s'" % door.get_interact_prompt())
			if door.state != ChaseDoor.DoorState.OPEN:
				player._interact_released()
				_next()
		"force":
			_release()
			var door: ChaseDoor = level.get_node(s[1])
			var to: Vector3 = door._panel.global_position - player.camera.global_position
			player._yaw = Chase.facing(to)
			player._pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if player._focused == door and player._interacting == null:
				player._interact_pressed()
				_log("force: '%s'" % door.get_interact_prompt())
			if door.state == ChaseDoor.DoorState.OPEN:
				player._interact_released()
				_log("back door forced open")
				_next()
		"wait":
			_release()
			_wait_time += delta
			if _wait_time >= s[1]:
				_wait_time = 0.0
				_next()
		"done":
			_log("STORY COMPLETE. deaths=%d clues=%d shots=%d hits=%d battery=%.0f ammo=%d" % [deaths, director.clues_found, shots_fired, hits, player.battery, player.ammo])
			get_tree().quit(0)


func _in_sight(p: Pursuer) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, p.get_center_position(), Chase.LAYER_WORLD)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


var _blocked := 0.0
var _sidestep := 0.0
var _sidestep_dir := 1.0


func _walk(to: Vector3) -> void:
	player._yaw = Chase.facing(to)
	player._pitch = 0.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	if player.is_on_floor() and player.is_on_wall() and not player.crouched:
		player.velocity.y = player.jump_velocity
	# Walked into a tree: step sideways round it for a moment.
	var dt := get_physics_process_delta_time()
	if _sidestep > 0.0:
		_sidestep -= dt
		var strafe := ("move_right" if _sidestep_dir > 0.0 else "move_left")
		Input.action_press(strafe)
		if _sidestep <= 0.0:
			Input.action_release("move_right")
			Input.action_release("move_left")
		return
	if Vector2(player.velocity.x, player.velocity.z).length() < 1.0 and not player.controls_locked:
		_blocked += dt
		if _blocked > 0.25:
			_blocked = 0.0
			_sidestep = 0.7
			_sidestep_dir = -_sidestep_dir
	else:
		_blocked = 0.0


func _report_if_stuck(delta: float) -> void:
	if player.controls_locked or Vector2(player.velocity.x, player.velocity.z).length() > 0.5:
		_stuck = 0.0
		return
	_stuck += delta
	if _stuck > 1.0:
		_stuck = -100.0
		_log("STUCK at %s going for step %d %s" % [player.global_position.snapped(Vector3.ONE * 0.1), step, steps[step]])
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			_log("  against %s normal %s" % [c.get_collider().get_path(), c.get_normal().snapped(Vector3.ONE * 0.01)])


func _next() -> void:
	step += 1
	_stuck = 0.0
	if step < steps.size():
		_log("step %d -> %s" % [step, steps[step]])


func _release() -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("move_right")
	Input.action_release("move_left")
	_sidestep = 0.0


func _nearest_go_step() -> int:
	var best := step
	var best_d := INF
	# Once the chase is on, never go back to before it.
	var first := _step_of("use", "House/Note") + 1 if director.phase == StoryDirector.Phase.CHASE else 0
	for i in range(maxi(step - 12, first), mini(step + 4, steps.size())):
		if steps[i][0] != "go":
			continue
		var d := Vector3(steps[i][1], 0, steps[i][2]).distance_to(player.global_position * Vector3(1, 0, 1))
		if d < best_d:
			best_d = d
			best = i
	return best


## Saves a few frames at moments worth looking at.
func _screenshots() -> void:
	if shot_dir == "":
		return
	var p := Chase.pursuer
	var phase := director.phase
	var moments := {
		"01_car": phase == StoryDirector.Phase.CAR and time > 0.5,
		"02_street": phase == StoryDirector.Phase.STREET and time > 1.0 and step == 2,
		"03_trunk": phase == StoryDirector.Phase.SEARCH and step <= 9,
		"04_sunset_trail": director.clues_found == 2,
		"05_shadow_figure": director.figure.visible and director.figure._watch_left < 0.6,
		"06_night_trail": director.clues_found == 7 and phase == StoryDirector.Phase.TRAIL,
		"07_house": phase == StoryDirector.Phase.TRAIL and player.global_position.z < Builder.HOUSE.z + 7.0,
		"08_house_dark": phase == StoryDirector.Phase.HOUSE and player._dark_left > 1.0,
		"09_living_room": phase == StoryDirector.Phase.HOUSE and player._dark_left <= 0.0 and player.global_position.z < Builder.HOUSE.z - 4.0,
		"10_bedroom": phase == StoryDirector.Phase.HOUSE and player.global_position.z < Builder.HOUSE.z - 15.0,
		"11_cryptid": phase == StoryDirector.Phase.CHASE and not p.concealed and step <= _step_of("use", "House/Note") + 3,
		"12_shooting": shots_fired >= 1,
		"13_escape": phase == StoryDirector.Phase.CHASE and player.global_position.x < -40.0,
		"14_road": phase == StoryDirector.Phase.ENDED,
	}
	# Face the cryptid for its shot.
	if moments["11_cryptid"] and not shots.has("11_cryptid"):
		var look := p.get_head_position() - player.camera.global_position
		player._yaw = Chase.facing(look)
		player._pitch = atan2(look.y, Vector2(look.x, look.z).length())
		if player._view.distance_to(Vector3(player._pitch, player._yaw, 0)) > 0.05:
			return
	for key in moments:
		if moments[key] and not shots.has(key):
			shots[key] = true
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join(key + ".png"))
			_log("screenshot " + key)


func _step_of(kind: String, what: String) -> int:
	for i in steps.size():
		if steps[i][0] == kind and steps[i].size() > 1 and str(steps[i][1]) == what:
			return i
	return -1
