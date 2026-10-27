class_name StoryDirector
extends Node
## Runs the story level from start to finish, like a script:
##
##   title cards -> in the car (dispatch, his thoughts) -> out, across the
##   road -> no flashlight: get it from the trunk -> into the jungle to find
##   Daniel's 7 belongings while the sun goes down (noises, a shadow figure
##   between the trees) -> the drag marks lead through the brush -> a house
##   in the dark -> the door slams, the lights come on -> blood, drag marks,
##   chains -> Daniel's note -> it's behind you -> a revolver in the kitchen
##   (shots slow it) -> force the back door -> run for the road -> safe.
##
## Lives at the level root as "Director"; finds everything by name.

enum Phase { INTRO, CAR, STREET, FLASHLIGHT, SEARCH, TRAIL, HOUSE, CHASE, ENDED }

const CLUE_COUNT := 7

const INTRO_CARDS := [
	"October 24th.  6:40 PM.",
	"Daniel Reyes, 34, has been missing for four days.",
	"The last camera to see him was on Route 9, at the edge of the city.\nHe was on foot, walking toward Blackwood Forest. Alone.",
	"The search teams went home at noon.\n\nOfficer Hale didn't.",
	"R E L E N T L E S S",
]

const CAR_LINES := [
	["Dispatch", "Unit 14, be advised: the Reyes search is suspended for the night. Come on back in."],
	["Hale", "Copy, Dispatch. Just checking one last thing on Route 9."],
	["", "Four days. His car was still in his driveway. Phone off. Wallet gone."],
	["", "And the last camera caught him walking out here, at dusk, into the woods."],
	["", "Nobody walks into Blackwood at dusk."],
	["", "The trail starts right across the road. One quick look before the light goes."],
]

const NOTE_TEXT := "If anyone finds this, my name is Daniel Reyes.\n\n" \
	+ "I don't know how many days it's been. It keeps me in here. It brings me water and scraps so I stay alive. " \
	+ "I understand now. It's keeping me fresh.\n\n" \
	+ "It is taller than the doorway. It walks like a man, but it is not a man. " \
	+ "It stands in the corner and watches me eat. When it thinks I'm asleep, it smiles.\n\n" \
	+ "I got the chain off tonight. I'm going for the door.\n\n" \
	+ "If you're reading this, I didn't make it.\n\n" \
	+ "GET OUT. IT KNOWS WHEN SOMEONE IS IN THE HOUSE.\nIT IS ALREADY COMING BACK."

const ENDING_CARDS := [
	"Officer Hale made it out of Blackwood Forest at 9:52 PM.",
	"At dawn, twelve officers went back in with him.\nThey found the house. The chains. The note.",
	"They never found Daniel Reyes.",
	"And they never found the thing that lived there.",
	"THE END",
]

## Playtests turn this on before loading the level: every wait is a blink.
static var fast_mode := false

@export_group("Sounds")
@export var car_door_sound: AudioStream
@export var branch_sound: AudioStream
@export var whoosh_sound: AudioStream
@export var screech_sound: AudioStream
@export var creak_sound: AudioStream
@export var stinger_sound: AudioStream
@export var click_sound: AudioStream
@export var house_ambience: AudioStream
@export var jungle_ambience: AudioStream

var phase := Phase.INTRO
var clues_found := 0
var ui: StoryUI

var player: RelentlessPlayer
var music: MusicDirector
var figure: ShadowFigure

var _night := 0.0
var _night_target := 0.0
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _lamps: Array[Light3D] = []
var _kitchen_hinted := false


func _ready() -> void:
	ui = StoryUI.new()
	ui.fast = fast_mode
	add_child(ui)
	player = _node("Gameplay/Player")
	music = _node("Gameplay/MusicDirector")
	figure = _node("Gameplay/ShadowFigure")
	_env = (_node("Environment/WorldEnvironment") as WorldEnvironment).environment
	_sky = _env.sky.sky_material
	_sun = _node("Environment/Sun")
	_moon = _node("Environment/Moon")
	for l in _node("Street/Lamps").get_children():
		if l is Light3D:
			_lamps.append(l)

	_zone("Entrance").entered.connect(func(_z): _on_entrance())
	_zone("JungleIn").entered.connect(func(_z): _on_jungle_in())
	_zone("Thicket").entered.connect(func(_z): _on_thicket())
	_zone("Clearing").entered.connect(func(_z): _on_clearing())
	_zone("HouseInside").entered.connect(func(_z): _on_enter_house())
	_zone("LivingRoom").entered.connect(func(_z): _think_once(Phase.HOUSE, [
		["", "Blood. On the floor, on the walls... a lot of it."],
		["", "There was a fight in here. Somebody fought hard."]]))
	_zone("Study").entered.connect(func(_z): _think_once(Phase.HOUSE, [
		["", "Drag marks. Someone was pulled through here."],
		["", "Into the back."]]))
	_zone("Bedroom").entered.connect(func(_z): _think_once(Phase.HOUSE, [
		["", "Chains. Bolted to the bed frame."],
		["", "Oh God. He was kept here."]]))
	_zone("Kitchen").entered.connect(func(_z): _on_kitchen())
	_zone("Outside").entered.connect(func(_z): _on_outside())
	for clue in _node("Clues").get_children():
		(clue as StoryInteractable).used.connect(_on_clue)
	(_node("Street/Car/Trunk") as StoryInteractable).used.connect(func(_i): _on_trunk())
	(_node("House/Note") as StoryInteractable).used.connect(func(_i): _on_note())
	(_node("House/Gun") as StoryInteractable).used.connect(func(_i): _on_gun())
	Chase.chase_ended.connect(_on_chase_ended)

	_apply_night()
	_run.call_deferred()


func _node(path: String) -> Node:
	return get_parent().get_node(path)


func _zone(zone_name: String) -> StoryZone:
	return _node("Zones/" + zone_name)


func _process(delta: float) -> void:
	if not is_equal_approx(_night, _night_target):
		_night = move_toward(_night, _night_target, delta * (1.0 if fast_mode else 0.06))
		_apply_night()


# ---------------------------------------------------------------------------
# The story, in order
# ---------------------------------------------------------------------------

func _run() -> void:
	var seat: Marker3D = _node("Street/Car/Seat")
	player.frozen = true
	player.controls_locked = true
	player.global_position = seat.global_position
	player.look_toward(-seat.global_basis.z)

	for text in INTRO_CARDS:
		await ui.card(text)

	phase = Phase.CAR
	await ui.fade(0.0, 2.5)
	await ui.lines(CAR_LINES)

	await ui.fade(1.0, 0.8)
	Chase.play_2d(car_door_sound)
	var out: Marker3D = _node("Street/Car/ExitPoint")
	player.frozen = false
	player.global_position = out.global_position
	player.look_toward(-out.global_basis.z)
	await ui.wait(0.8, false)
	ui.fade(0.0, 1.2)
	player.controls_locked = false
	phase = Phase.STREET
	ui.set_objective("Cross the road to the forest trail.")
	player.show_hint("[WASD] Move   [Mouse] Look   [Shift] Run", 5.0)


func _on_entrance() -> void:
	if phase != Phase.STREET:
		return
	phase = Phase.FLASHLIGHT
	(_node("Street/Car/Trunk") as StoryInteractable).set_available(true)
	ui.set_objective("Get your flashlight from the car's trunk.")
	await ui.lines([
		["", "It'll be dark soon. I'm not going in there without a light."],
		["", "Flashlight's in the trunk."]])


func _on_trunk() -> void:
	player.give_flashlight()
	var barrier: CollisionObject3D = _node("Street/EntranceBarrier")
	barrier.collision_layer = 0
	phase = Phase.SEARCH
	ui.set_objective("Search the forest for any sign of Daniel. (0/%d)" % CLUE_COUNT)
	player.show_hint("[F] Flashlight   [Right mouse] Focus the beam", 5.0)
	await ui.line("", "Got it. Okay. Let's find you, Daniel.")


func _on_jungle_in() -> void:
	await ui.lines([
		["Hale", "Daniel? DANIEL REYES! Police!"],
		["", "Nothing. Not even birds."],
		["", "If he came this way, he might have dropped something."]])


func _on_clue(item: StoryInteractable) -> void:
	clues_found += 1
	var n := clues_found
	_night_target = 0.9 * float(n) / CLUE_COUNT
	ui.set_objective("Search the forest for any sign of Daniel. (%d/%d)" % [n, CLUE_COUNT])
	await ui.line("", item.thought)
	if n == CLUE_COUNT:
		await _all_clues_found()
	else:
		await _scare(n)


func _all_clues_found() -> void:
	phase = Phase.TRAIL
	var thicket: Node3D = _node("Jungle/Thicket")
	thicket.visible = false
	(_node("Jungle/ThicketBarrier") as CollisionObject3D).collision_layer = 0
	ui.set_objective("Follow the drag marks.")
	await ui.wait(1.0, false)
	await ui.lines([
		["", "Drag marks in the dirt. Something heavy was pulled through the brush up ahead."],
		["", "That's a trail. A real one."],
		["", "It's dark. I should call this in."],
		["", "...and say what? I found a shoe? Keep going."]])


## Something after each find, so the forest never feels empty.
func _scare(n: int) -> void:
	await ui.wait(1.2 if n % 2 == 0 else 2.5, false)
	match n:
		2:
			_sound_behind(branch_sound, 1.0)
			await ui.line("", "...A branch. Just an animal.")
		3:
			_figure()
			await ui.wait(1.2, false)
			await ui.line("Hale", "Hey! HEY! Police! Stop right there!")
			await ui.line("", "Gone. Was that... Daniel?")
		4:
			_sound_behind(whoosh_sound, 0.8)
			await ui.line("Hale", "Who's there?!")
		5:
			_figure()
			Chase.play_2d(stinger_sound, 0.45)
			await ui.wait(1.0, false)
			await ui.line("", "It's following me. Keeping its distance. Watching.")
		6:
			_sound_behind(screech_sound, 0.25)
			await ui.line("", "What the hell was that? That's no animal I know.")


func _on_thicket() -> void:
	if phase == Phase.SEARCH and clues_found < CLUE_COUNT:
		player.show_hint("The brush is too thick here.\nI haven't searched everywhere yet. (%d/%d)" % [clues_found, CLUE_COUNT], 4.0)


func _on_clearing() -> void:
	if phase != Phase.TRAIL:
		return
	_night_target = 1.0
	ui.set_objective("Search the house.")
	await ui.lines([
		["", "A house? Out here? There's no road for miles."],
		["", "No lights. No car. The drag marks go right up the steps."]])


func _on_enter_house() -> void:
	if phase != Phase.TRAIL:
		return
	phase = Phase.HOUSE
	ui.set_objective("")
	var door: ChaseDoor = _node("House/FrontDoor")
	door.slam_shut()
	player.force_dark(3.2)
	music.set_ambience(house_ambience)
	await ui.line("", "What the—")
	await ui.wait(1.8, false)
	for light in _node("House/Lights").get_children():
		if light is FlickerLight:
			light.powered = true
			Chase.play_at(click_sound, light.global_position, 0.7)
			await ui.wait(0.25, false)
	await ui.lines([
		["Hale", "Hello? Police! Is anybody in here?"],
		["", "Lights don't switch themselves on."],
		["", "And the door's jammed. Fine. There's got to be another way out."]])
	ui.set_objective("Find out what happened to Daniel.")


func _think_once(needs: Phase, entries: Array) -> void:
	if phase == needs:
		await ui.lines(entries)


func _on_note() -> void:
	player.controls_locked = true
	ui.set_objective("")
	await ui.read_note(NOTE_TEXT)
	await ui.line("", "Kept alive. As food.")
	var trigger: ChaseTrigger = _node("Gameplay/Chase_House")
	Chase.play_at(creak_sound, trigger.get_pursuer_start().origin, 1.0)
	await ui.wait(1.4, false)
	await ui.line("", "...There's something behind me.", 1.6)

	phase = Phase.CHASE
	player.controls_locked = false
	trigger.fire(player)
	Chase.pursuer.show_dormant()
	Chase.play_2d(stinger_sound)
	(_node("House/Gun") as StoryInteractable).set_available(true)
	(_node("House/BackDoor") as ChaseDoor).locked = false
	ui.set_objective("Get out of the house!")
	player.show_hint("RUN.", 2.5)


func _on_gun() -> void:
	player.give_gun(6)
	player.show_hint("[Left mouse] Shoot. It won't kill it, but it slows it down.", 5.0)
	await ui.line("", "A revolver. Six rounds. Daniel's? Didn't do him much good.")


func _on_kitchen() -> void:
	if phase == Phase.CHASE and not _kitchen_hinted:
		_kitchen_hinted = true
		player.show_hint("The back door! Hold [E] to force it open.", 4.0)


func _on_outside() -> void:
	if phase != Phase.CHASE:
		return
	music.set_ambience(jungle_ambience)
	ui.set_objective("Run! Get back to the road!")


func _on_chase_ended() -> void:
	if phase != Phase.CHASE:
		return
	phase = Phase.ENDED
	ui.set_objective("")
	await ui.lines([
		["Hale", "Dispatch, Unit 14! Shots fired, I need units on Route 9, now!"],
		["Dispatch", "Unit 14, units are already on scene. Look up, Hale. We heard the shots."],
		["", "It stopped at the tree line. It didn't follow me out."],
		["", "...I'm out. I'm alive."]])
	player.controls_locked = true
	await ui.fade(1.0, 3.0)
	for text in ENDING_CARDS:
		await ui.card(text)
	if fast_mode:
		return  # A playtest: it reads the ending itself.
	await ui.card("Press any key to play again.", 600.0)
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Scares
# ---------------------------------------------------------------------------

func _sound_behind(stream: AudioStream, volume: float) -> void:
	var forward := -player.camera.global_basis.z
	forward.y = 0.0
	var right := forward.normalized().cross(Vector3.UP)
	var at := player.global_position - forward.normalized() * 7.0 + right * randf_range(-3.0, 3.0) + Vector3.UP
	Chase.play_at(stream, at, volume)


## A shadow between the trees ahead and to one side, that bolts out of sight.
func _figure() -> void:
	if figure.is_busy():
		return
	var forward := -player.camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var side := -1.0 if randf() < 0.5 else 1.0
	var from := player.global_position + forward * 13.0 + right * side * 4.5
	from.y = 0.0
	var to := from + right * side * 13.0 + forward * 3.0
	figure.scare(from, to, 1.1)
	Chase.play_at(whoosh_sound, from + Vector3.UP, 0.5)


# ---------------------------------------------------------------------------
# Sunset to night
# ---------------------------------------------------------------------------

func _apply_night() -> void:
	var n := _night
	# The sun slides under the horizon by about two thirds of the way.
	var elevation := lerpf(7.0, -14.0, n)
	_sun.rotation_degrees = Vector3(-elevation, 200.0, 0.0)
	_sun.light_energy = lerpf(1.25, 0.0, smoothstep(0.0, 0.7, n))
	_sun.light_color = Color(1.0, 0.62, 0.36).lerp(Color(0.9, 0.3, 0.2), n)
	_sun.visible = n < 0.75
	_moon.light_energy = lerpf(0.0, 0.2, smoothstep(0.5, 1.0, n))
	_moon.visible = n > 0.4

	_sky.sky_top_color = Color(0.22, 0.3, 0.5).lerp(Color(0.003, 0.005, 0.012), n)
	_sky.sky_horizon_color = Color(0.98, 0.56, 0.3).lerp(Color(0.01, 0.012, 0.02), smoothstep(0.0, 0.85, n))
	_sky.ground_horizon_color = Color(0.4, 0.25, 0.18).lerp(Color(0.006, 0.006, 0.01), n)
	_sky.ground_bottom_color = Color(0.06, 0.05, 0.05).lerp(Color(0.0, 0.0, 0.0), n)
	_sky.energy_multiplier = lerpf(1.0, 0.4, n)

	_env.ambient_light_color = Color(0.45, 0.36, 0.34).lerp(Color(0.02, 0.03, 0.035), n)
	_env.ambient_light_energy = lerpf(0.55, 0.35, n)
	_env.fog_light_color = Color(0.55, 0.35, 0.25).lerp(Color(0.004, 0.006, 0.008), smoothstep(0.0, 0.8, n))
	_env.fog_density = lerpf(0.006, 0.028, n)
	_env.volumetric_fog_density = lerpf(0.004, 0.012, n)

	for lamp in _lamps:
		lamp.light_energy = lerpf(0.3, 3.0, smoothstep(0.0, 0.35, n))
