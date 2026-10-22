class_name KillZone
extends ZoneArea
## Falling into this (a chasm) kills you; you restart from the checkpoint.


func _player_entered(player: RelentlessPlayer) -> void:
	if not player.dead:
		player.caught(null)
