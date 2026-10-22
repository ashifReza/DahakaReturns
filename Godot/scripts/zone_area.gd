class_name ZoneArea
extends Area3D
## Base for the trigger boxes: an Area3D that sizes its own box from `extent`
## and only reacts to the player.

## Half-size of the box, in metres.
@export var extent := Vector3(1.0, 1.75, 1.5)


func _ready() -> void:
	collision_layer = 0
	collision_mask = Chase.LAYER_PLAYER
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = extent * 2.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	body_entered.connect(func(body: Node3D) -> void:
		if body is RelentlessPlayer:
			_player_entered(body)
	)
	body_exited.connect(func(body: Node3D) -> void:
		if body is RelentlessPlayer:
			_player_exited(body)
	)


func _player_entered(_player: RelentlessPlayer) -> void:
	pass


func _player_exited(_player: RelentlessPlayer) -> void:
	pass
