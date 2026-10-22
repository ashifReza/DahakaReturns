class_name VentZone
extends ZoneArea
## A crawlspace. Inside it the player is forced to crouch and the pursuer is
## too big to follow; it gives up, vanishes, and ambushes from ambush_point
## when the player crawls out the far end.

@export var ambush_point: Marker3D
@export var ambush_delay := 1.2


func get_ambush() -> Transform3D:
	return ambush_point.global_transform if ambush_point else global_transform


func _player_entered(player: RelentlessPlayer) -> void:
	player.set_forced_crouch(true)
	Chase.player_entered_crawlspace(self)


func _player_exited(player: RelentlessPlayer) -> void:
	player.set_forced_crouch(false)
	Chase.player_exited_crawlspace(self)
