class_name StoryZone
extends ZoneArea
## A box the story director listens to: walking in moves the story on
## (a thought, a door slamming behind you).

signal entered(zone: StoryZone)

## Only reacts while armed. The director arms zones as the story reaches them.
@export var armed := true
@export var once := true

var _fired := false


func _player_entered(player: RelentlessPlayer) -> void:
	if not armed or player.dead or (once and _fired):
		return
	_fired = true
	entered.emit(self)


## True while the player is inside, armed or not.
func has_player() -> bool:
	for body in get_overlapping_bodies():
		if body is RelentlessPlayer:
			return true
	return false
