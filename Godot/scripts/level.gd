extends Node3D
## Root of a level. Resets the chase manager before anything in it registers.


func _enter_tree() -> void:
	Chase.begin_level()
