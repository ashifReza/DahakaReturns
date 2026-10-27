class_name MusicDirector
extends Node
## Adaptive score. Each layer fades in with the chase's danger value; the
## ambience drops away as it closes in, so silence means it's near.

## e.g. drone (0-0.2), percussion (0.2-0.5), strings (0.4-0.7), choir (0.7-0.95)
@export var layers: Array[MusicLayer] = []
@export var ambience: AudioStream
@export var heartbeat: AudioStream
## The ambience falls silent while the pursuer is in the open this close, even
## before a chase: in the jungle, the insects stop.
@export var ambience_cut_distance := 25.0

var _layer_players: Array[AudioStreamPlayer] = []
var _ambience_player: AudioStreamPlayer
var _heartbeat_player: AudioStreamPlayer
var _ambience_cut := 1.0


func _ready() -> void:
	for layer in layers:
		_layer_players.append(_start_loop(layer.stream if layer else null))
	_ambience_player = _start_loop(ambience)
	_heartbeat_player = _start_loop(heartbeat)


func _start_loop(stream: AudioStream) -> AudioStreamPlayer:
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(0.001)
	add_child(p)
	p.play()
	return p


## Swaps the ambience bed, e.g. on walking indoors.
func set_ambience(stream: AudioStream) -> void:
	ambience = stream
	if _ambience_player:
		_ambience_player.stream = stream
		_ambience_player.play()
	else:
		_ambience_player = _start_loop(stream)


func _process(delta: float) -> void:
	var danger := Chase.danger
	var pursuer := Chase.pursuer
	var near := is_instance_valid(pursuer) and not pursuer.concealed and is_instance_valid(Chase.player) \
		and pursuer.global_position.distance_to(Chase.player.global_position) < ambience_cut_distance
	# Cuts out fast, creeps back slowly.
	_ambience_cut = Chase.finterp(_ambience_cut, 0.04 if near else 1.0, delta, 3.0 if near else 0.4)
	for i in mini(layers.size(), _layer_players.size()):
		var p := _layer_players[i]
		if p == null:
			continue
		var layer := layers[i]
		var span := maxf(layer.fade_in_end - layer.fade_in_start, 0.01)
		var t := clampf((danger - layer.fade_in_start) / span, 0.0, 1.0)
		p.volume_db = linear_to_db(maxf(0.001, smoothstep(0.0, 1.0, t) * layer.max_volume))
	if _ambience_player:
		_ambience_player.volume_db = linear_to_db(maxf(0.001, (1.0 - danger * 0.95) * _ambience_cut))
	if _heartbeat_player:
		_heartbeat_player.volume_db = linear_to_db(maxf(0.001, (danger - 0.3) / 0.7))
		_heartbeat_player.pitch_scale = lerpf(0.9, 1.5, danger)
