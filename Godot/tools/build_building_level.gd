@tool
extends EditorScript
## Rebuilds res://scenes/building.tscn from tools/building_builder.gd.
## In the editor: open this file in the Script tab, then File > Run (Ctrl+Shift+X).
## Re-running overwrites the scene, so make layout changes in the builder.

const OUTPUT := "res://scenes/building.tscn"


func _run() -> void:
	var err := save_level()
	if err == OK:
		print("Relentless: Building level built and saved to ", OUTPUT)
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Relentless: could not save the level (error %d)" % err)


static func save_level() -> Error:
	var root: Node3D = preload("res://tools/building_builder.gd").new().build()
	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err == OK:
		err = ResourceSaver.save(scene, OUTPUT)
	root.free()
	return err
