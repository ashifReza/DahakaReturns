extends Node3D
## Renders the creature in a lit studio and saves screenshots of a few poses:
##   godot --path Godot res://tools/creature_preview.tscn -- <output folder>

var body: CreatureBody
var shots := [
	["front_run", Pursuer.State.CHASING, 6.0, Vector3(0, 1.7, -4.2)],
	["side_run", Pursuer.State.CHASING, 6.0, Vector3(4.2, 1.6, -0.5)],
	["front_stalk", Pursuer.State.STALKING, 0.0, Vector3(0.6, 1.8, -3.2)],
	["stunned", Pursuer.State.STUNNED, 0.0, Vector3(1.5, 1.8, -3.5)],
	["bashing", Pursuer.State.BASHING, 0.0, Vector3(-2.5, 1.8, -3.0)],
	["dark_flashlight", Pursuer.State.CHASING, 5.0, Vector3(0, 1.6, -6.0)],
]
var index := 0
var time := 0.0
var camera: Camera3D
var key: DirectionalLight3D
var flashlight: SpotLight3D
var out_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if not args.is_empty() else OS.get_user_data_dir()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 150, 0)
	key.light_energy = 1.2
	add_child(key)
	var ground := CSGBox3D.new()
	ground.size = Vector3(20, 0.2, 20)
	ground.position.y = -0.1
	add_child(ground)
	body = CreatureBody.new()
	add_child(body)
	camera = Camera3D.new()
	add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.light_energy = 6.0
	flashlight.spot_range = 26.0
	flashlight.spot_angle = 28.0
	flashlight.shadow_enabled = true
	flashlight.visible = false
	camera.add_child(flashlight)


func _process(delta: float) -> void:
	if index >= shots.size():
		get_tree().quit()
		return
	var shot: Array = shots[index]
	time += delta
	body.animate(delta, shot[1], time, shot[2])
	camera.position = shot[3]
	camera.look_at(Vector3(0, 1.5, 0))
	var dark: bool = shot[0] == "dark_flashlight"
	key.visible = not dark
	flashlight.visible = dark
	(get_node("WorldEnvironment") if has_node("WorldEnvironment") else get_child(0)).environment.ambient_light_energy = 0.05 if dark else 1.0
	if time > 1.3:
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("creature_%s.png" % shot[0]))
		index += 1
		time = 0.0
