## A stand-in machine for speaker_tests' amplifier cases: whatever phono outputs the
## case gives it, and a record of every call a sink makes on a source — the same
## duck-typed names RetroSystem answers.
##
## Every field starts at a value no sink would send, so "never told" is visible.
extends Node3D

## Where this machine says its SOUND goes, for TvAudio.carries_sound. Null is a
## machine whose sound reaches nothing, which a set still treats as its own.
var route_sink: Node3D = null

var out_mode: int = -1
var surround_mode: int = -1
var volume: float = -1.0
var channel_mode: int = -1


## What RcaPort.get_device() walks up the tree for.
func on_av_topology_changed(_links: Array) -> void:
	pass


func set_audio_out_mode(mode: int) -> bool:
	out_mode = mode
	return mode == RetroTV.AudioOut.SURROUND


func set_surround_mode(mode: int) -> void:
	surround_mode = mode


func set_audio_volume(v: float) -> void:
	volume = v


func set_audio_channel_mode(mode: int) -> void:
	channel_mode = mode


func audio_route() -> Dictionary:
	return {"tv": route_sink}
