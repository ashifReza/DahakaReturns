class_name StoryInteractable
extends StaticBody3D
## Something the story wants you to pick up or use: a clue, the note, the
## trunk, the gun. Look at it and press E. It sits on the interact layer, so
## the interact ray finds it but nothing bumps into it. Build its look from
## child meshes; this only adds the collider and a faint glint.

signal used(item: StoryInteractable)

@export var prompt := "[E] Pick up"
## Shown in thoughts and the objective ("Daniel's wallet").
@export var label := ""
## What the policeman thinks when he picks it up.
@export_multiline var thought := ""
@export var available := true
## Hide it once used (a pickup). Off for things that stay, like the trunk.
@export var consume := true
@export var radius := 0.4
## A pale glint so it can be spotted in the undergrowth.
@export var glint := true
@export var glint_color := Color(1.0, 0.95, 0.8)
@export var use_sound: AudioStream

var _glint: OmniLight3D
var _time := 0.0


func _ready() -> void:
	collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = radius
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	if glint:
		_glint = OmniLight3D.new()
		_glint.light_color = glint_color
		_glint.omni_range = 1.4
		_glint.position.y = 0.35
		_glint.shadow_enabled = false
		add_child(_glint)
	_time = randf() * TAU
	set_available(available)


func _process(delta: float) -> void:
	if _glint:
		_time += delta
		_glint.light_energy = (0.25 + 0.2 * sin(_time * 2.5)) if available else 0.0


func set_available(on: bool) -> void:
	available = on
	visible = on or not consume
	collision_layer = Chase.LAYER_INTERACT if on else 0


# --- Interaction (called by the player) ------------------------------------

func can_interact() -> bool:
	return available


func get_interact_prompt() -> String:
	return prompt if available else ""


func begin_interact(_by: RelentlessPlayer) -> void:
	if not available:
		return
	Chase.play_at(use_sound, global_position)
	set_available(false)
	used.emit(self)


func end_interact(_by: RelentlessPlayer) -> void:
	pass


func get_interact_progress() -> float:
	return -1.0
