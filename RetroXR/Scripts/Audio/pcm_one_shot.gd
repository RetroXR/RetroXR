## Plays a short clip once, spatialised, through SpatialAudioEmitter.
##
## The emitter is PCM-push only — there is no "play this AudioStream" entry point
## — so a one-shot cannot be an AudioStreamPlayer3D. It has to be pushed as frames
## like everything else, which is what this wraps up so each caller does not
## rewrite the push loop. CrtHum does the same thing for a looping source.
##
## Retriggering restarts from the beginning rather than layering. For a switch
## click that is right: the mechanism cannot be in two states at once, and two
## overlapping copies of the same transient comb-filter into something metallic.
class_name PcmOneShot
extends Node3D


## Full-gain distance. Small by default — these are close-range object sounds, not
## room audio; the console feed uses 3.0 by comparison.
@export var unit_size: float = 0.8
## Hard cut. Inverse-distance attenuation only loses 6 dB per doubling, so without
## this a click would still be faintly audible across the room.
@export var max_distance: float = 4.0
@export var volume: float = 0.5

var _emitter: SpatialAudioEmitter = null
var _frames: PackedVector2Array = []
var _read := -1                               # -1 = idle


func _ready() -> void:
	_emitter = SpatialAudioEmitter.new()
	_emitter.name = "OneShotEmitter"
	_emitter.unit_size = unit_size
	_emitter.max_distance = max_distance
	add_child(_emitter)
	_emitter.set_volume(0.0)
	set_process(true)


func play(frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	# Always clear first, so a voice reused after a play_from() does not keep
	# emitting from a point the next sound has nothing to do with.
	_emitter.clear_emit_position()
	_frames = frames
	_read = 0
	_emitter.set_volume(volume)


## Play from somewhere other than this node.
##
## For a sound whose SOURCE is not the object that owns the clip: a controller's
## plug goes into a socket on the console, so it belongs at that socket, not at
## the pad — which may be lying on a table on the other side of the room.
func play_from(frames: PackedVector2Array, at: Vector3) -> void:
	play(frames)
	if not frames.is_empty():
		_emitter.set_emit_position(at)


func is_playing() -> bool:
	return _read >= 0


func _process(_delta: float) -> void:
	if _emitter == null or _read < 0:
		return
	var want := _emitter.frames_wanted()
	if want <= 0:
		return
	var out: PackedVector2Array = []
	out.resize(want)
	for i in want:
		if _read < _frames.size():
			out[i] = _frames[_read]
			_read += 1
		else:
			out[i] = Vector2.ZERO       # pad the rest of the buffer with silence
	_emitter.push_stereo(out)
	if _read >= _frames.size():
		# The mixer still has queued frames to play at this gain.
		_read = -1
