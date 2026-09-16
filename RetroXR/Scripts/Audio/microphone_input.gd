## Microphone — the one reader of the host microphone.
##
## AudioServer keeps a single read cursor for the whole process, so capture has
## exactly one owner. Each frame this finds the running machines whose core has
## a microphone switched on, keeps the device open only while there is one and
## the player allows it, and hands the same frames to every one of them, scaled
## by how far that machine's microphone is from the player's head.
##
## Two kinds of listener, not one. A core with a handle open is handed the frames
## themselves; a peripheral that only needs to know how LOUD the room is -- a
## Famicom's Controller II, whose microphone reaches the console as one bit of
## player 2's pad -- is handed a level measured once for all of them.
extends Node

## Full level inside this distance from the head, 1/d beyond it.
const MIC_UNIT_SIZE := 0.5

## () -> {frames: PackedVector2Array, rate: float}, empty when nothing arrived.
var frame_source: Callable = _read_audio_server
## () -> Array of machines to feed.
var consumer_source: Callable = _running_machines
## (on: bool) -> bool, true when the device took the change.
var device_switch: Callable = _switch_audio_server
## () -> Vector3.
var head_source: Callable = _camera_position

var _device_active := false


static func gain_for(mic_position: Vector3, head_position: Vector3, max_distance: float) -> float:
	return SpatialAudioEmitter.distance_gain(mic_position, head_position, MIC_UNIT_SIZE, max_distance)


static func should_capture(enabled: bool, consumers: Array) -> bool:
	return enabled and not consumers.is_empty()


func is_capturing() -> bool:
	return _device_active


func _ready() -> void:
	if not ClassDB.class_has_method("Libretro", "IsMicrophoneActive"):
		print("[Microphone] the libretro extension has no microphone support; capture disabled")
		set_process(false)


func _process(_delta: float) -> void:
	tick()


## One frame of work, callable directly by a test.
func tick() -> void:
	var consumers: Array = consumer_source.call()
	var wanted := should_capture(AppPrefs.microphone_enabled, consumers)
	if wanted != _device_active:
		var took: bool = device_switch.call(wanted)
		_device_active = wanted
		if not wanted:
			print("[Microphone] capture off")
		elif took:
			print("[Microphone] capture on for %d machine(s)" % consumers.size())
		else:
			print("[Microphone] capture requested for %d machine(s); the device refused" % consumers.size())
	if not _device_active:
		return

	var capture: Dictionary = frame_source.call()
	var frames: PackedVector2Array = capture.get("frames", PackedVector2Array())
	if frames.is_empty():
		return
	var rate := float(capture.get("rate", 0.0))
	var head: Vector3 = head_source.call()
	# Measured at most once, and only if somebody wants it. rms and peak are both
	# linear in the gain -- MicrophoneLevel.hpp's cases pin that -- so one
	# measurement at unity serves every listener, which is the same one-reader
	# rule that makes this service the only thing draining AudioServer.
	var level := Vector2.ZERO
	var measured := false
	for machine in consumers:
		var gain := gain_for(machine.microphone_position(), head, float(machine.audio_max_distance))
		machine.get_libretro_node().PushMicrophoneFrames(frames, rate, gain)
		if machine.hears_microphone_level():
			if not measured:
				level = Libretro.MeasureMicrophoneLevel(frames, rate)
				measured = true
			machine.push_microphone_level(level * gain)


func _read_audio_server() -> Dictionary:
	var available := AudioServer.get_input_frames_available()
	if available <= 0:
		return {}
	return {
		"frames": AudioServer.get_input_frames(available),
		"rate": AudioServer.get_input_mix_rate(),
	}


func _running_machines() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("retro_system"):
		var machine := node as RetroSystem
		if machine == null or not machine.is_powered_on:
			continue
		# Not IsMicrophoneActive() directly: a Famicom's Controller II wants the
		# device open although fceumm never opens a microphone of its own.
		if machine.hears_microphone():
			out.append(machine)
	return out


func _switch_audio_server(on: bool) -> bool:
	return AudioServer.set_input_device_active(on) == OK


func _camera_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO
