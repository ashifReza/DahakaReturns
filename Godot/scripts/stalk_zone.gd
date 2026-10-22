class_name StalkZone
extends ZoneArea
## Entering it sets the pursuer stalking you: it shows itself at the Marker3D
## children of this node, at a distance, and vanishes when you look at it.
## It stops once a chase starts.

@export_multiline var hint := ""
@export var hint_duration := 5.0

var _started := false


func _player_entered(player: RelentlessPlayer) -> void:
	if _started:
		return
	_started = true
	if hint != "":
		player.show_hint(hint, hint_duration)
	var points: Array[Node3D] = []
	for c in get_children():
		if c is Marker3D:
			points.append(c)
	if is_instance_valid(Chase.pursuer):
		Chase.pursuer.begin_stalk(points)
