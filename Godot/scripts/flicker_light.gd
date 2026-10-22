class_name FlickerLight
extends OmniLight3D
## A failing ceiling light. Sputters on its own, and dies outright when the
## pursuer passes beneath it, so you can watch it coming down a corridor.

@export var energy := 1.0
## 0 = steady, 1 = barely working.
@export_range(0.0, 1.0) var faultiness := 0.3
## The light dies while the pursuer is within this distance.
@export var darken_radius := 7.0

var _seed := 0.0
var _level := 1.0


func _ready() -> void:
	_seed = randf_range(0.0, 1000.0)
	light_energy = energy
	# Far-away lights fade out entirely, which keeps this cheap on weak GPUs.
	distance_fade_enabled = true
	distance_fade_begin = 30.0
	distance_fade_length = 8.0

	var fixture := Greybox.box(Vector3(0.12, 0.05, 0.8), Color.BLACK)
	fixture.material_override = Greybox.material(Color(0.2, 0.2, 0.2), light_color * 0.8)
	fixture.position.y = 0.12
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fixture)


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0 + _seed
	var target := 1.0

	# Random sputters: mostly on, occasionally drops out.
	var n := Chase.perlin(time * 6.0) * 0.5 + 0.5
	if n > 1.0 - faultiness * 0.5:
		target = 0.05

	var p := Chase.pursuer
	if is_instance_valid(p) and p.is_active_threat():
		var dist := p.get_center_position().distance_to(global_position)
		if dist < darken_radius:
			target = 0.0
		elif dist < darken_radius * 1.6:
			# Struggling as it approaches.
			target *= 1.0 if Chase.perlin(time * 25.0) > 0.0 else 0.1

	_level = Chase.finterp(_level, target, delta, 30.0)
	light_energy = energy * _level
