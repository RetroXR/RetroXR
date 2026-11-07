## The loudspeaker cabinets a SOURCE's own line out reaches, as one sink.
##
## A lead from a deck's (or a console's) L / R straight into two `Loudspeaker`s plays
## out of them, as a pair of powered speakers would (2026-11-07: it used to be silent,
## the cabinets answering only a set's or the amplifier's speaker outputs). The cabinets
## are separate objects, one cone each, and every source expects ONE sink answering
## get_speaker_positions() with a left and a right -- so this node is that sink: a child
## of the source, reused across re-resolves, its two positions the cones the L and R
## cords reach.
##
## Made by AvSource.resolve only for a device that is not itself a sink: a set's or the
## amplifier's speaker outputs are the same channels, and those already drive their
## cabinets through audio_dest (SpeakerRig).
##
## The sink contract (see SpeakerPair): get_speaker_positions, on_av_source_found/lost,
## show_osd_timed / hide_osd / get_screen_mesh (the decks call those unguarded). No
## get_screen_normal, so the source is omnidirectional. No knob: the cabinets play at
## full level and the source's own level (a deck's LEVEL knob) applies.
class_name LineOutCabinets
extends Node3D

const NODE_NAME := "LineOutCabinets"

## The cabinet each channel's cord reaches, or null.
var left: Node3D = null
var right: Node3D = null
var _source: Node3D = null


## The one belonging to `dev`, made on first use, with its cabinets set.
static func for_device(dev: Node3D, l_cab: Node3D, r_cab: Node3D) -> LineOutCabinets:
	var sink := dev.get_node_or_null(NODE_NAME) as LineOutCabinets
	if sink == null:
		sink = LineOutCabinets.new()
		sink.name = NODE_NAME
		# Deferred while the device is still building its children (a restore seats
		# leads from _ready); nothing here needs the tree but the fallback position.
		if dev.is_node_ready():
			dev.add_child(sink)
		else:
			dev.add_child.call_deferred(sink)
	sink._set_cabinets(dev, l_cab, r_cab)
	return sink


func _set_cabinets(dev: Node3D, l_cab: Node3D, r_cab: Node3D) -> void:
	if l_cab == left and r_cab == right:
		return
	var before: Array = [left, right]
	left = l_cab
	right = r_cab
	print("[Speaker] %s: line out -> L %s, R %s" % [dev.name, _cab_name(left), _cab_name(right)])
	# Cabinets that joined or left while a source is already being carried.
	if is_instance_valid(_source):
		for cab in before:
			if is_instance_valid(cab) and cab != left and cab != right and cab.has_method("on_av_source_lost"):
				cab.on_av_source_lost(_source)
		for cab in [left, right]:
			if is_instance_valid(cab) and not before.has(cab) and cab.has_method("on_av_source_found"):
				cab.on_av_source_found(_source)


static func _cab_name(cab: Node3D) -> String:
	return String(cab.name) if is_instance_valid(cab) else "nothing"


## LEFT FIRST. A channel whose cord reaches nothing takes the other's cone; the source
## silences that channel itself (its index is -1), so the position is never heard.
func get_speaker_positions() -> PackedVector3Array:
	var l := _cone(left)
	var r := _cone(right)
	if l.is_empty() and r.is_empty():
		var here := global_position if is_inside_tree() else Vector3.ZERO
		return PackedVector3Array([here, here])
	return PackedVector3Array([(l if not l.is_empty() else r)[0], (r if not r.is_empty() else l)[0]])


## A cabinet's cone, as a one-entry array, or empty.
static func _cone(cab: Node3D) -> PackedVector3Array:
	if not is_instance_valid(cab) or not cab.is_inside_tree() or not cab.has_method("get_speaker_positions"):
		return PackedVector3Array()
	var sp: PackedVector3Array = cab.get_speaker_positions()
	return PackedVector3Array([sp[0]]) if not sp.is_empty() else PackedVector3Array()


func on_av_source_found(source: Node3D) -> void:
	_source = source
	for cab in _cabinets():
		if cab.has_method("on_av_source_found"):
			cab.on_av_source_found(source)
	# No knob on a cabinet: full level, the source's own level on top.
	AvSourceContract.push_volume(source, 1.0)


func on_av_source_lost(source: Node3D) -> void:
	if _source != source:
		return
	_source = null
	for cab in _cabinets():
		if cab.has_method("on_av_source_lost"):
			cab.on_av_source_lost(source)


func _cabinets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for cab in [left, right]:
		if is_instance_valid(cab) and not out.has(cab):
			out.append(cab)
	return out


func get_screen_mesh() -> MeshInstance3D:
	return null


func show_osd_timed(_text: String, _seconds: float = 2.0) -> void:
	pass


func hide_osd() -> void:
	pass
