extends Node
## Autoload "Settings". The player's options, saved between runs in
## user://settings.cfg and applied as soon as they change.

const PATH := "user://settings.cfg"

## Multiplies the player's mouse sensitivity.
var look_scale := 1.0
## Master volume, 0..1.
var volume := 0.8
var fullscreen := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		look_scale = cfg.get_value("controls", "look_scale", look_scale)
		volume = cfg.get_value("audio", "volume", volume)
		fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "look_scale", look_scale)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(PATH)
