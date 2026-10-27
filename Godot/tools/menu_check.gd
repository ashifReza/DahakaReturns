extends Node
## Clicks through the menus and saves a screenshot of each, for checking
## the layout without playing:
##   godot --path Godot res://tools/menu_check.tscn -- <folder>

var shot_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	shot_dir = args[0] if not args.is_empty() else OS.get_user_data_dir()
	_run.call_deferred()


func _run() -> void:
	# Step out of the way, then put the title screen in our place.
	reparent(get_tree().root)
	var menu: Node = load(MenuUI.MAIN_MENU).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _wait(2.2)
	await _shot("m1_title")
	_press(menu, "Settings")
	await _wait(0.4)
	await _shot("m2_settings")
	_press(menu, "Back")
	await _wait(0.3)
	_press(menu, "New Game")
	await _wait(3.5)
	await _shot("m3_story_intro")
	PauseMenu.open()
	await _wait(0.5)
	await _shot("m4_paused")
	_press(PauseMenu, "Settings")
	await _wait(0.4)
	await _shot("m5_pause_settings")
	_press(PauseMenu, "Back")
	_press(PauseMenu, "Main Menu")
	await _wait(2.0)
	print("menu check: back on ", get_tree().current_scene.name if get_tree().current_scene else "nothing", ", paused=", get_tree().paused)
	await _shot("m6_back_to_title")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _press(root: Node, text: String) -> void:
	for b in root.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree():
			b.pressed.emit()
			print("menu check: pressed ", text)
			return
	print("menu check: NO BUTTON ", text)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(name + ".png"))
	print("menu check: screenshot ", name)
