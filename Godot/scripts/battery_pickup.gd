class_name BatteryPickup
extends Area3D
## Placed just off the escape route: worth the detour, if you dare.

@export var amount := 40.0
@export var pickup_sound: AudioStream

var _mesh: MeshInstance3D
var _glow: OmniLight3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Chase.LAYER_PLAYER
	monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

	_mesh = Greybox.cylinder(0.06, 0.25, Color(0.1, 0.5, 0.15))
	add_child(_mesh)

	# A faint glow so it can be spotted in the dark.
	_glow = OmniLight3D.new()
	_glow.light_color = Color8(120, 255, 140)
	_glow.omni_range = 1.2
	_glow.light_energy = 0.4
	add_child(_glow)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_mesh.rotate_y(deg_to_rad(60.0) * delta)
	_glow.light_energy = 0.4 + sin(Time.get_ticks_msec() / 1000.0 * 3.0) * 0.2


func _on_body_entered(body: Node3D) -> void:
	if body is RelentlessPlayer:
		body.add_battery(amount)
		Chase.play_at(pickup_sound, global_position)
		queue_free()
