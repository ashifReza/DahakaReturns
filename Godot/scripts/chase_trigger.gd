class_name ChaseTrigger
extends ZoneArea
## Walk into it once. With starts_chase it begins the chase, or, if one is
## already running, becomes the new checkpoint. Without it, it just shows a hint.

@export var starts_chase := true
## Where the pursuer appears. Move the marker in the viewport.
@export var pursuer_start: Marker3D
## Where the player comes back after dying past this point.
@export var player_respawn: Marker3D
@export var activation_delay := 0.4
@export_multiline var hint := ""
@export var hint_duration := 4.0
@export var stinger: AudioStream

var _triggered := false


func get_pursuer_start() -> Transform3D:
	return pursuer_start.global_transform if pursuer_start else global_transform


func get_player_respawn() -> Transform3D:
	return player_respawn.global_transform if player_respawn else global_transform


func _player_entered(player: RelentlessPlayer) -> void:
	if _triggered or player.dead:
		return
	_triggered = true
	if hint != "":
		player.show_hint(hint, hint_duration)
	Chase.play_2d(stinger)
	if starts_chase:
		Chase.start_chase(self)
