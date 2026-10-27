class_name Siren
extends Node3D
## A police light bar. Flashes red and blue while active; dark otherwise.

@export var active := true
@export var energy := 3.0

var _red: OmniLight3D
var _blue: OmniLight3D
var _red_mat: StandardMaterial3D
var _blue_mat: StandardMaterial3D


func _ready() -> void:
	_red_mat = _lamp(Vector3(-0.32, 0, 0), Color(1, 0.05, 0.05))
	_blue_mat = _lamp(Vector3(0.32, 0, 0), Color(0.1, 0.25, 1))
	var bar := Greybox.box(Vector3(1.2, 0.08, 0.28), Color(0.08, 0.08, 0.08))
	bar.position.y = -0.08
	add_child(bar)
	_red = _light(Vector3(-0.5, 0.2, 0), Color(1, 0.1, 0.1))
	_blue = _light(Vector3(0.5, 0.2, 0), Color(0.15, 0.3, 1))


func _lamp(at: Vector3, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.3
	m.emission_enabled = true
	m.emission = color
	var mi := Greybox.box(Vector3(0.5, 0.12, 0.26), color)
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return m


func _light(at: Vector3, color: Color) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = 14.0
	l.position = at
	add_child(l)
	return l


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# Quick double flashes, alternating sides.
	var cycle := fmod(t * 1.6, 1.0)
	var red_on := active and (cycle < 0.12 or (cycle > 0.2 and cycle < 0.32))
	var blue_on := active and ((cycle > 0.5 and cycle < 0.62) or (cycle > 0.7 and cycle < 0.82))
	_red.light_energy = energy if red_on else 0.0
	_blue.light_energy = energy if blue_on else 0.0
	_red_mat.emission_energy_multiplier = 4.0 if red_on else 0.05
	_blue_mat.emission_energy_multiplier = 4.0 if blue_on else 0.05
