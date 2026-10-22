extends Node
## Command-line version of build_building_level.gd. Runs as a scene (not with
## --script) so the Chase autoload exists while the game scripts load:
##   godot --headless --path Godot res://tools/build_cli.tscn


func _ready() -> void:
	var err: Error = preload("res://tools/build_building_level.gd").save_levels()
	print("Relentless: build ", "OK" if err == OK else "failed (%d)" % err)
	get_tree().quit(0 if err == OK else 1)
