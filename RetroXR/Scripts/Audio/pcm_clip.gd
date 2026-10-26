## Decodes an imported .wav into interleaved stereo frames at the DEVICE mix rate.
##
## SpatialAudioEmitter is PCM-push only — `frames_wanted()` / `push_stereo()`, with
## no "play this AudioStream" entry point — so anything that wants Meta XR Audio
## spatialisation has to arrive as frames. This turns a WAV resource into those
## frames once, at load.
##
## The resample is not optional. `project.godot` asks for 48000, but the Quest
## reports 44100 regardless, so a 48 kHz asset played back frame-for-frame would
## run ~9% fast and a hair sharp. Everything here keys off
## AudioServer.get_mix_rate() rather than the config file.
##
## Decoding is done ONCE and the result cached per path, because it is a
## per-sample GDScript loop — the same reason SpatialAudioEmitter downmixes stereo
## in C++ rather than in script. A 4 s 48 kHz clip is ~192k samples; that is fine
## behind the loading screen and unthinkable per frame.
class_name PcmClip
extends RefCounted


static var _cache: Dictionary = {}


## Interleaved stereo frames for `path`, resampled to the device rate.
## Mono sources are duplicated to both channels — a hum or a click is a point
## source, and the emitter spatialises it anyway.
static func load_frames(path: String) -> PackedVector2Array:
	var rate := AudioServer.get_mix_rate()
	var key := "%s@%d" % [path, int(rate)]
	if _cache.has(key):
		return _cache[key]

	var stream := load(path) as AudioStreamWAV
	if stream == null:
		push_warning("[PcmClip] %s is not an AudioStreamWAV" % path)
		return PackedVector2Array()

	var mono := _decode(stream)
	if mono.is_empty():
		return PackedVector2Array()
	var frames := _resample(mono, float(stream.mix_rate), rate)
	_cache[key] = frames
	return frames


## Decode to float samples in -1..1. Handles the 8- and 16-bit PCM formats the
## importer produces; IMA-ADPCM and QOA are compressed and would need the engine's
## own decoder, so they are refused loudly rather than silently played as noise.
static func _decode(stream: AudioStreamWAV) -> PackedVector2Array:
	var data := stream.data
	var out: PackedVector2Array = []
	match stream.format:
		AudioStreamWAV.FORMAT_16_BITS:
			var step := 4 if stream.stereo else 2
			@warning_ignore("integer_division")
			var count := data.size() / step
			out.resize(count)
			for i in count:
				var l := float(data.decode_s16(i * step)) / 32768.0
				var r := float(data.decode_s16(i * step + 2)) / 32768.0 if stream.stereo else l
				out[i] = Vector2(l, r)
		AudioStreamWAV.FORMAT_8_BITS:
			var step8 := 2 if stream.stereo else 1
			@warning_ignore("integer_division")
			var count8 := data.size() / step8
			out.resize(count8)
			for i in count8:
				var l8 := (float(data.decode_s8(i * step8)) / 128.0)
				var r8 := (float(data.decode_s8(i * step8 + 1)) / 128.0) if stream.stereo else l8
				out[i] = Vector2(l8, r8)
		_:
			push_warning("[PcmClip] %s is compressed (format %d); import it as " %
					[stream.resource_path, stream.format] + "uncompressed PCM")
	return out


## Linear resample. Good enough here: the only content near Nyquist is the CRT's
## 15734 Hz whine, which sits well below 44100/2, so there is nothing to alias.
static func _resample(src: PackedVector2Array, from_rate: float, to_rate: float) -> PackedVector2Array:
	if src.is_empty() or is_equal_approx(from_rate, to_rate) or from_rate <= 0.0:
		return src
	var ratio := from_rate / to_rate
	var count := int(float(src.size()) / ratio)
	var out: PackedVector2Array = []
	out.resize(count)
	var last := src.size() - 1
	for i in count:
		var pos := float(i) * ratio
		var a := int(pos)
		var f := pos - float(a)
		var b := mini(a + 1, last)
		out[i] = src[a].lerp(src[b], f)
	return out
