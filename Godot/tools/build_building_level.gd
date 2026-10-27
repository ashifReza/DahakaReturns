@tool
extends EditorScript
## Rebuilds the level scenes from their builders:
##   tools/building_builder.gd -> scenes/building.tscn
##   tools/jungle_builder.gd   -> scenes/jungle.tscn
##   tools/story_builder.gd    -> scenes/story.tscn
## In the editor: open this file in the Script tab, then File > Run (Ctrl+Shift+X).
## Re-running overwrites the scenes, so make layout changes in the builders.

const LEVELS := {
	"res://scenes/building.tscn": "res://tools/building_builder.gd",
	"res://scenes/jungle.tscn": "res://tools/jungle_builder.gd",
	"res://scenes/story.tscn": "res://tools/story_builder.gd",
}


func _run() -> void:
	var err := save_levels()
	if err == OK:
		print("Relentless: levels built")
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Relentless: could not save a level (error %d)" % err)


## `only` limits it to the levels whose scene path contains that text.
static func save_levels(only := "") -> Error:
	for output in LEVELS:
		if only != "" and not only in output:
			continue
		var builder = load(LEVELS[output])
		if builder == null or not builder.can_instantiate():
			return FAILED
		var root: Node3D = builder.new().build()
		var scene := PackedScene.new()
		var err := scene.pack(root)
		if err == OK:
			err = ResourceSaver.save(scene, output)
		root.free()
		if err != OK:
			return err
		print("Relentless: saved ", output)
	return OK
