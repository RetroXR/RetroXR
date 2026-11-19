## Probe: the device output end to end, with no core.
##
## One decoded channel at a time is played as a tone through SurroundAudio's
## output, with the matrix SystemAudio builds for the device, and the Master bus's
## own peak meter is read on every speaker pair. So what lights up says which
## decoded channel reached which of the device's speakers, and at what level,
## through the real bus, effect and pair numbering.
##
## The meters, not a recording: in 4.7.2 the movie writer's multichannel WAV is
## scrambled before it is written (AudioDriverDummy keeps the channel count it was
## initialised with, and its table gives 5.1 eight channels), whatever it is fed.
## The movie writer is still what puts the dummy driver into 3.1, 5.1 or 7.1, which
## can only come from project settings -- Tools/surround_output_check.py writes
## them and runs this. Windowed, never --headless.
extends Node

const LEVEL := 0.2
const TONE_HZ := 440.0
## Frames a channel plays before it is measured: the ramp in and the cushion out.
const SETTLE := 20
const MEASURE := 20
const NAMES := ["FL", "FR", "C", "LFE", "SL", "SR"]
const OUT_NAMES := ["FL", "FR", "C", "LFE", "BL", "BR", "SL", "SR"]

var _out: Object = null
var _m := PackedFloat32Array()
var _rate := 48000.0
var _pairs := 1
var _input := 0
var _frame := 0
var _phase := 0.0
var _peaks := PackedFloat32Array()
var _failures := 0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_rate = AudioServer.get_mix_rate()
	if not Engine.has_singleton("SurroundAudio"):
		print("[probe] FAIL no SurroundAudio")
		get_tree().quit(1)
		return
	_out = Engine.get_singleton("SurroundAudio").create_output()
	if _out == null:
		print("[probe] FAIL no output")
		get_tree().quit(1)
		return
	var targets: Array = []
	for ch in 6:
		targets.append(PackedInt32Array([ch]))
	_m = SystemAudio.discrete_matrix(targets, PackedFloat32Array([1, 1, 1, 1, 1, 1]),
		AudioServer.get_speaker_mode())
	if _m.is_empty():
		print("[probe] FAIL the device is stereo; run through Tools/surround_output_check.py")
		get_tree().quit(1)
		return
	_out.set_matrix(_m)
	_peaks.resize(8)


func _process(delta: float) -> void:
	if _out == null or _m.is_empty():
		return
	# The bus is re-made at the first mix, once the driver's real channel count is
	# known, so the pair count is read here rather than in _ready.
	_pairs = AudioServer.get_bus_channels(0)
	_push(int(round(_rate * delta)) + (int(_rate * 0.05) if _frame == 0 else 0))
	_frame += 1
	if _frame > SETTLE:
		for k in _pairs:
			_peaks[k * 2] = maxf(_peaks[k * 2], db_to_linear(AudioServer.get_bus_peak_volume_left_db(0, k)))
			_peaks[k * 2 + 1] = maxf(_peaks[k * 2 + 1], db_to_linear(AudioServer.get_bus_peak_volume_right_db(0, k)))
	if _frame < SETTLE + MEASURE:
		return
	_report()
	_input += 1
	_frame = 0
	_peaks.fill(0.0)
	_out.flush()
	if _input >= 6:
		print("[probe] %d pair(s), %s" % [_pairs, "PASS" if _failures == 0 else "FAIL (%d)" % _failures])
		get_tree().quit(0 if _failures == 0 else 1)


func _report() -> void:
	var row := ""
	for out in _pairs * 2:
		var want := LEVEL * _m[_input * 8 + out]
		var got := _peaks[out]
		row += " %s=%6.1f" % [OUT_NAMES[out], linear_to_db(got) if got > 1e-9 else -200.0]
		var bad := false
		if want > 0.0:
			bad = absf(linear_to_db(maxf(got, 1e-9)) - linear_to_db(want)) > 0.5
		else:
			bad = got > LEVEL * 0.001
		if bad:
			_failures += 1
			row += "(!)"
	print("[probe] %-3s ->%s" % [NAMES[_input], row])


func _push(frames: int) -> void:
	var planes: Array = []
	var w := TAU * TONE_HZ / _rate
	for ch in 6:
		var p := PackedFloat32Array()
		p.resize(frames)
		if ch == _input:
			for i in frames:
				p[i] = LEVEL * sin(_phase + w * i)
		else:
			p.fill(0.0)
		planes.append(p)
	_phase = fmod(_phase + w * frames, TAU)
	_out.push(planes)
