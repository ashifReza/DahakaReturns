extends RefCounted
## Hooks the synthesised music and sounds (tools/synth_audio.py) into a level
## as it's built.

const MusicLayerScript := preload("res://scripts/music_layer.gd")


static func setup_music(music: Node, ambience: String) -> void:
	var layers: Array[MusicLayer] = []
	for spec in [
		["chase_drone", 0.0, 0.2, 0.7],
		["chase_percussion", 0.2, 0.5, 0.8],
		["chase_riff", 0.4, 0.7, 0.75],
		["chase_choir", 0.7, 0.95, 0.7],
	]:
		var layer: MusicLayer = MusicLayerScript.new()
		layer.stream = load("res://audio/music/%s.wav" % spec[0])
		layer.fade_in_start = spec[1]
		layer.fade_in_end = spec[2]
		layer.max_volume = spec[3]
		layers.append(layer)
	music.set("layers", layers)
	music.set("ambience", load("res://audio/ambience/%s.wav" % ambience))
	music.set("heartbeat", load("res://audio/music/heartbeat.wav"))


static func setup_pursuer(pursuer: Node) -> void:
	pursuer.set("roar_sound", sfx("roar"))
	pursuer.set("footstep_sound", sfx("footstep"))
	pursuer.set("bash_sound", sfx("bash"))
	pursuer.set("screech_sound", sfx("screech"))
	pursuer.set("vanish_sound", sfx("whoosh"))


static func setup_player(player: Node) -> void:
	player.set("flashlight_click_sound", sfx("click"))
	player.set("death_sound", sfx("death"))


static func sfx(name: String) -> AudioStream:
	return load("res://audio/sfx/%s.wav" % name)
