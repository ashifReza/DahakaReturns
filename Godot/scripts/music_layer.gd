class_name MusicLayer
extends Resource
## One stem of the adaptive score.

## Should loop, with every layer the same length and tempo.
@export var stream: AudioStream
## Danger at which this layer starts fading in, and is fully in.
@export_range(0.0, 1.0) var fade_in_start := 0.0
@export_range(0.0, 1.0) var fade_in_end := 0.3
@export var max_volume := 1.0
