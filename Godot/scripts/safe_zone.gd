class_name SafeZone
extends ZoneArea
## Somewhere it can't follow. Ends the chase; optionally loads the next level.

@export_multiline var message := ""
## Leave empty to stay in this level.
@export_file("*.tscn") var next_level := ""
@export var next_level_delay := 5.0

var _reached := false


func _player_entered(player: RelentlessPlayer) -> void:
	if _reached or player.dead:
		return
	_reached = true
	Chase.end_chase()
	if message != "":
		player.show_hint(message, 5.0)
	if next_level != "":
		get_tree().create_timer(next_level_delay).timeout.connect(func() -> void:
			get_tree().change_scene_to_file(next_level)
		)
