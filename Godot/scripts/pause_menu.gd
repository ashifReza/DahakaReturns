extends CanvasLayer
## Autoload "PauseMenu". [Esc] in any level pauses the game and offers
## resume, restart, settings, the main menu, and quit.

var _root: Control
var _main: VBoxContainer
var _settings: VBoxContainer
var _dim: ColorRect
## The level's own overlays (HUD, subtitles), hidden while paused.
var _hidden: Array[CanvasLayer] = []


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = MenuUI.theme()
	_root.visible = false
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)

	var column := VBoxContainer.new()
	column.position = Vector2(110, 0)
	column.anchor_top = 0.22
	column.add_theme_constant_override("separation", 6)
	_root.add_child(column)
	column.add_child(MenuUI.label("PAUSED", 56))
	var gap := Control.new()
	gap.custom_minimum_size.y = 30
	column.add_child(gap)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 4)
	_main.add_child(MenuUI.button("Resume", close))
	_main.add_child(MenuUI.button("Restart Level", func() -> void:
		close()
		get_tree().reload_current_scene()
	))
	_main.add_child(MenuUI.button("Settings", func() -> void: _show_settings(true)))
	_main.add_child(MenuUI.button("Main Menu", func() -> void:
		close()
		get_tree().change_scene_to_file(MenuUI.MAIN_MENU)
	))
	_main.add_child(MenuUI.button("Quit Game", func() -> void: get_tree().quit()))
	column.add_child(_main)

	_settings = MenuUI.settings_panel(func() -> void: _show_settings(false))
	_settings.visible = false
	column.add_child(_settings)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("release_mouse"):
		return
	if _root.visible:
		if _settings.visible:
			_show_settings(false)
		else:
			close()
		get_viewport().set_input_as_handled()
	elif _in_level():
		open()
		get_viewport().set_input_as_handled()


## Only in a level with a player: not on the title screen.
func _in_level() -> bool:
	return is_instance_valid(Chase.player) and Chase.player.is_inside_tree()


func open() -> void:
	get_tree().paused = true
	_root.visible = true
	_hidden.clear()
	_dim.color.a = 0.72
	for layer in get_tree().current_scene.find_children("*", "CanvasLayer", true, false):
		# Keep a black screen black (a title card): don't give the scene away.
		if layer.has_method("blackout"):
			_dim.color.a = maxf(_dim.color.a, layer.blackout())
		if layer.visible:
			layer.visible = false
			_hidden.append(layer)
	_show_settings(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	get_tree().paused = false
	_root.visible = false
	for layer in _hidden:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden.clear()
	if _in_level():
		Chase.player._grab_mouse()


func is_open() -> bool:
	return _root.visible


func _show_settings(on: bool) -> void:
	_main.visible = not on
	_settings.visible = on
	MenuUI.focus_first(_settings if on else _main)
