## The minimum a source-side resolve needs from a sink, for speaker_tests'
## stand-in television: RcaPort.get_device() walks up the parent chain for
## on_av_topology_changed, and AvSource only files a target that can say where its
## speakers are.
extends Node3D

func on_av_topology_changed(_links: Array) -> void:
	pass


func get_speaker_positions() -> PackedVector3Array:
	return PackedVector3Array([global_position])
