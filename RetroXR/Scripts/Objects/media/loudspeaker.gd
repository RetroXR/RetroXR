## One surround loudspeaker: a cabinet you carry anywhere, with a phono input on
## the back and one cone.
##
## ── Why there is no audio code here ──────────────────────────────────────────
## Same reason a television has none. The SOURCE owns its voices and walks them
## onto whatever get_speaker_positions() hands back, every frame — so publishing
## this cabinet's cone is the whole of being a loudspeaker, and because it is read
## per frame rather than latched, carrying the cabinet carries its channel.
##
## ── Which channel it carries ─────────────────────────────────────────────────
## Not this object's business. A phono jack is generic: the input is
## RcaPort.Channel.AUDIO_SPEAKER, and AvSource files the cabinet under whichever
## of the television's six speaker outputs the lead's far end is sitting in.
##
## ── The sink contract, as the sources use it ─────────────────────────────────
## Duck-typed throughout; there is no base class. Provide:
##   on_av_topology_changed  — mandatory, it is what RcaPort.get_device() finds
##   get_speaker_positions   — the cone, as a one-entry array
##   on_av_source_found/lost — so the source learns who carries its sound
##   show_osd_timed/hide_osd — the decks call these UNGUARDED
##   get_screen_mesh         — null; nothing routes a picture here
## get_screen_normal is deliberately NOT provided. It is guarded by has_method,
## and leaving it out keeps the source omnidirectional — the honest answer for a
## cabinet left pointing wherever a hand put it.
class_name Loudspeaker
extends XRToolsPickable

## Scene-authored so the satellite and the subwoofer share this script.
@export var speaker_label: String = "SURROUND"

@onready var _cone: Node3D = $ConeFront
@onready var _input: RcaPort = $SpeakerIn

## The device currently feeding this cabinet, or null.
var _source: Node3D = null


func _ready() -> void:
	super()
	add_to_group("spawned")


# ── the sink contract ────────────────────────────────────────────────────────

## Nothing to do: a loudspeaker is a sink and every routing decision is the
## source's. It exists so RcaPort.get_device() recognises this cabinet as a
## device at all.
func on_av_topology_changed(_links: Array) -> void:
	pass


## Where the sound comes from. One cone, so one entry — and the source indexes
## this array with the 0 that AvSource files a cabinet under.
func get_speaker_positions() -> PackedVector3Array:
	return PackedVector3Array([_cone.global_position])


func on_av_source_found(source: Node3D) -> void:
	_source = source


func on_av_source_lost(source: Node3D) -> void:
	if _source != source:
		return          # already replaced by another source
	_source = null


## No screen here. Present because the DVD player reads it without guarding.
func get_screen_mesh() -> MeshInstance3D:
	return null


func show_osd_timed(_text: String, _seconds: float = 2.0) -> void:
	pass


func hide_osd() -> void:
	pass


## Release the seated lead before this cabinet is freed.
##
## ScenePersistence.clear_scene and StorageBox look for this by name. Without it
## the socket is left holding a freed pickable and XRToolsPickable._exit_tree
## walks a dangling grab driver — the trap CompositeCable.drop_and_free records.
func drop_and_free() -> void:
	if is_instance_valid(_input):
		_input.drop_object()
	Vanish.free_node(self)
