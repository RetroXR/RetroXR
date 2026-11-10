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
##
## ── The model ────────────────────────────────────────────────────────────────
## Both cabinets wear a RETRO XR model (RetroXR-models generic/satellite-speaker,
## generic/subwoofer) through an ApplianceModel child, `Model`. The scene keeps every
## node name; _dress() seats SpeakerIn on the model's jack mouth, moves ConeFront onto
## the model's DriverCentre (the cloth, over the driver) and fits the body's and the
## laser's boxes to what the model draws, no margin. The model prints the back panel,
## so the old BackLabel is hidden. A subwoofer has more on its back (Subwoofer).
##
## is_sounding() is the one thing a cabinet can say about its sound: SpeakerRig plays a
## channel that reaches a cabinet that is not sounding at level 0, and folds nothing
## onto it. A passive satellite always is.
class_name Loudspeaker
extends XRToolsPickable

## Every cabinet joins this, and a speaker stand's plate names it as its
## snap_require. Load-bearing rather than tidy: XRToolsSnapZone.can_preview
## refuses to draw the snap ghost for a zone with no snap_require, so without the
## group a cabinet could still be dropped on a stand but never previewed onto one.
const GROUP := "loudspeaker"

## Scene-authored so the satellite and the subwoofer share this script.
@export var speaker_label: String = "SURROUND"

@onready var _cone: Node3D = $ConeFront
@onready var _input: RcaPort = $SpeakerIn
@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

## The model's empties, renamed `<name>Mouth` so a recursive find on the cabinet meets
## the scene's node and never the model's.
const MOUTHS: Array[String] = ["SpeakerIn", "DriverCentre"]

## The device currently feeding this cabinet, or null.
var _source: Node3D = null


func _ready() -> void:
	super()
	add_to_group("spawned")
	add_to_group(GROUP)
	_dress()


## Whether this cabinet makes a sound when a channel reaches it. A passive cabinet
## always does; Subwoofer answers its switch and its supply.
func is_sounding() -> bool:
	return true


# ── dressing ─────────────────────────────────────────────────────────────────

func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[Speaker] %s: no model to dress the cabinet from" % name)
		return
	for n: String in MOUTHS:
		for mouth in _model.parts(n):
			mouth.name = n + "Mouth"
	if _model.part("SpeakerInMouth") != null:
		DeckFace.seat_port(_model, _input, "SpeakerInMouth")
	else:
		push_warning("[Speaker] %s: the model has no SpeakerIn mouth; the jack stays where the scene put it" % name)
	var driver := _model.part("DriverCentreMouth")
	if driver != null:
		_cone.transform = Transform3D(Basis.IDENTITY, _model.part_transform("DriverCentreMouth", self).origin)
	else:
		push_warning("[Speaker] %s: the model has no DriverCentre; the cone stays where the scene put it" % name)
	var label := get_node_or_null("BackLabel") as Node3D
	if label != null:
		label.visible = false          # the model prints its own back panel
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	_fit_collision()
	print("[Speaker] %s: dressed from the model (%d levels): jack at %s, cone at %s" % [name, _model.levels.size(),
		_input.position.snapped(Vector3.ONE * 0.0001), _cone.position.snapped(Vector3.ONE * 0.0001)])


## The body's and the laser's boxes are what the model draws, no margin.
func _fit_collision() -> void:
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D])


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
