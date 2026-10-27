extends Node
## Command-line version of build_building_level.gd. Runs as a scene (not with
## --script) so the Chase autoload exists while the game scripts load:
##   godot --headless --path Godot res://tools/build_cli.tscn
## Add "-- story" (or building, jungle) to rebuild just that level.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var err: Error = preload("res://tools/build_building_level.gd").save_levels(args[0] if not args.is_empty() else "")
	print("Relentless: build ", "OK" if err == OK else "failed (%d)" % err)
	get_tree().quit(0 if err == OK else 1)
