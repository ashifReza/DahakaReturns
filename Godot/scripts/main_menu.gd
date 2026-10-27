extends Control
## The title screen: a treeline against a dying sunset, the jungle at night
## on the speakers, and the way into the story, the chase levels, settings.

const STORY := "res://scenes/story.tscn"
const CHASE := "res://scenes/building.tscn"

var _main: VBoxContainer
var _settings: VBoxContainer
var _title: Label
var _sky: Control
var _trees: Array = []  # [x, width, height, canopy radius]
var _time := 0.0
var _starting := false
var _black: ColorRect


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(PRESET_FULL_RECT)
	theme = MenuUI.theme()

	_sky = Control.new()
	_sky.set_anchors_preset(PRESET_FULL_RECT)
	_sky.mouse_filter = MOUSE_FILTER_IGNORE
	_sky.draw.connect(_draw_backdrop)
	add_child(_sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var x := -0.02
	while x < 1.05:
		_trees.append([x, rng.randf_range(0.004, 0.012), rng.randf_range(0.35, 0.75), rng.randf_range(0.03, 0.06)])
		x += rng.randf_range(0.015, 0.05)

	var grain := ColorRect.new()
	grain.set_anchors_preset(PRESET_FULL_RECT)
	grain.mouse_filter = MOUSE_FILTER_IGNORE
	var post := ShaderMaterial.new()
	post.shader = preload("res://shaders/fear_post.gdshader")
	post.set_shader_parameter("vignette", 0.8)
	post.set_shader_parameter("grain", 0.5)
	post.set_shader_parameter("saturation", 0.85)
	grain.material = post
	add_child(grain)

	var column := VBoxContainer.new()
	column.position = Vector2(110, 0)
	column.anchor_top = 0.16
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_title = MenuUI.label("RELENTLESS", 76)
	column.add_child(_title)
	column.add_child(MenuUI.label("     B L A C K W O O D", 22, MenuUI.ACCENT.lightened(0.25)))
	var gap := Control.new()
	gap.custom_minimum_size.y = 46
	column.add_child(gap)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 4)
	_main.add_child(MenuUI.button("New Game", func() -> void: _start(STORY)))
	_main.add_child(MenuUI.button("Chase Mode", func() -> void: _start(CHASE)))
	_main.add_child(MenuUI.button("Settings", func() -> void: _show_settings(true)))
	_main.add_child(MenuUI.button("Quit", func() -> void: get_tree().quit()))
	column.add_child(_main)

	_settings = MenuUI.settings_panel(func() -> void: _show_settings(false))
	_settings.visible = false
	column.add_child(_settings)

	var help := MenuUI.label("New Game: the story of the search for Daniel Reyes.   Chase Mode: the original Building and Jungle chases.\n[Esc] pauses the game.", 16, MenuUI.DIM)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(110, -70)
	help.grow_vertical = GROW_DIRECTION_BEGIN
	add_child(help)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(PRESET_FULL_RECT)
	_black.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_black)
	create_tween().tween_property(_black, "color:a", 0.0, 1.5)

	for spec in [["res://audio/ambience/jungle.wav", 0.5], ["res://audio/music/chase_drone.wav", 0.35]]:
		var p := AudioStreamPlayer.new()
		p.stream = load(spec[0])
		p.volume_db = linear_to_db(spec[1])
		add_child(p)
		p.play()

	MenuUI.focus_first(_main)


func _show_settings(on: bool) -> void:
	_main.visible = not on
	_settings.visible = on
	MenuUI.focus_first(_settings if on else _main)


func _start(scene: String) -> void:
	if _starting:
		return
	_starting = true
	var t := create_tween()
	t.tween_property(_black, "color:a", 1.0, 0.8)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


func _process(delta: float) -> void:
	_time += delta
	# The title stutters like a failing bulb now and then.
	var n := Chase.perlin(_time * 3.0)
	_title.modulate.a = 0.25 if n > 0.82 else 1.0
	_sky.queue_redraw()


func _draw_backdrop() -> void:
	var size := _sky.size
	var w := size.x
	var h := size.y
	# Sunset sky in bands, from night above to a red glow at the horizon.
	var bands := 48
	var horizon := 0.72
	for i in bands:
		var t := float(i) / bands
		var c := Color(0.02, 0.02, 0.04).lerp(Color(0.16, 0.05, 0.05), pow(t, 2.2)).lerp(Color(0.55, 0.2, 0.08), pow(t, 9.0))
		_sky.draw_rect(Rect2(0, t * h * horizon, w, h * horizon / bands + 1.0), c)
	_sky.draw_rect(Rect2(0, h * horizon, w, h * (1.0 - horizon)), Color(0.012, 0.01, 0.01))
	# A low red sun, mostly gone.
	_sky.draw_circle(Vector2(w * 0.72, h * horizon + h * 0.02), h * 0.07, Color(0.7, 0.22, 0.08))
	# The treeline, swaying a little.
	var tree_color := Color(0.008, 0.006, 0.006)
	for tree in _trees:
		var x: float = tree[0] * w + sin(_time * 0.6 + tree[0] * 20.0) * 1.5
		var tw: float = tree[1] * w
		var th: float = tree[2] * h
		var top := h * horizon + h * 0.08 - th
		_sky.draw_rect(Rect2(x - tw * 0.5, top, tw, h - top), tree_color)
		var r: float = tree[3] * h
		_sky.draw_circle(Vector2(x, top), r, tree_color)
		_sky.draw_circle(Vector2(x - r * 0.7, top + r * 0.4), r * 0.8, tree_color)
		_sky.draw_circle(Vector2(x + r * 0.7, top + r * 0.3), r * 0.75, tree_color)
	_sky.draw_rect(Rect2(0, h * (horizon + 0.06), w, h), tree_color)
