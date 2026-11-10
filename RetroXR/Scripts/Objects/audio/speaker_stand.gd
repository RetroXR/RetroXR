## A floor stand for a surround loudspeaker: a cast base, a column, and a plate a
## cabinet seats on.
##
## ── Why the seat needs no grab point ─────────────────────────────────────────
## XRToolsSnapZone puts a snapped object's GRAB POINT on the zone, or its origin
## when it carries none — which is the case ExpansionPort needed a foot for. A
## loudspeaker is baked with its origin at the BASE CENTRE, so a zone whose origin
## is the plate's top face lands the cabinet standing on the plate with no offset
## anywhere. That is also why the height in a stand's name is measured to that
## face: a satellite on the 1.2 m stand has its base at 1.2 m.
##
## ── Why there is no audio code here ─────────────────────────────────────────
## A stand carries no signal and publishes no cone. The cabinet on it goes on
## answering get_speaker_positions() from wherever it is standing, and a source
## reads that every frame rather than latching it — so raising a cabinet onto a
## stand moves its sound with no code here and none in the source.
##
## ── The model ────────────────────────────────────────────────────────────────
## The stand wears the RETRO XR model (RetroXR-models generic/speaker-stand) through
## an ApplianceModel child, `Model`. The model's SpeakerSeat empty is the top of the
## plate's pads at exactly the stand's height; the scene's zone is put on it (they
## agree; a model that disagreed is logged). Its base, both pillars and its plate are
## their own nodes, so the body takes one exact box per part: CollisionShape3D the base,
## ColumnShape and ColumnShape2 the two pillars (one box over both would fill the gap
## between them), TopShape the plate and its pads.
class_name SpeakerStand
extends XRToolsPickable

## Every stand joins this, so a sweep can find them without testing the class.
const GROUP := "speaker_stand"

@onready var _seat: XRToolsSnapZone = $SpeakerSeat
@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

## The model's parts, and the body's shape each one takes.
const PART_SHAPES := {"StandBase": "CollisionShape3D", "PillarL": "ColumnShape", "PillarR": "ColumnShape2",
	"Plate": "TopShape"}


func _ready() -> void:
	super()
	add_to_group("spawned")
	add_to_group(GROUP)
	_dress()


func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[SpeakerStand] %s: no model to dress the stand from" % name)
		return
	for mouth in _model.parts("SpeakerSeat"):
		mouth.name = "SpeakerSeatMouth"
	var mouth := _model.part("SpeakerSeatMouth")
	if mouth != null:
		var at := _model.part_transform("SpeakerSeatMouth", self).origin
		if at.distance_to(_seat.position) > 0.0005:
			push_warning("[SpeakerStand] %s: the model's seat is at %s, the scene's at %s; the model's is used"
				% [name, at, _seat.position])
		_seat.position = at
	else:
		push_warning("[SpeakerStand] %s: the model has no SpeakerSeat; the plate stays at %s" % [name, _seat.position])
	var fitted: Array[String] = []
	for part: String in PART_SHAPES:
		var node := _model.part(part)
		var shape_name: String = PART_SHAPES[part]
		var shape := get_node_or_null(shape_name) as CollisionShape3D
		if shape == null:
			shape = CollisionShape3D.new()
			shape.name = shape_name
			add_child(shape)
		if node == null:
			push_warning("[SpeakerStand] %s: the model has no %s; %s left as it was" % [name, part, shape_name])
			continue
		var box := ApplianceModel.node_bounds(node, self)
		ApplianceModel.fit_box(shape, box)
		fitted.append("%s %s" % [part, (box.size * 1000.0).snapped(Vector3.ONE * 0.1)])
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	print("[SpeakerStand] %s: dressed from the model (%d levels), seat at %.3f m; boxes: %s"
		% [name, _model.levels.size(), _seat.position.y, ", ".join(fitted)])


## The plate's snap zone, so a restore can seat a cabinet back on it.
func seat() -> XRToolsSnapZone:
	return _seat


## The cabinet standing on this stand, or null.
func seated_speaker() -> Loudspeaker:
	if _seat == null or not is_instance_valid(_seat.picked_up_object):
		return null
	return _seat.picked_up_object as Loudspeaker


## Put a cabinet back on the plate after a restore.
##
## The STAND records what is on it rather than the cabinet recording the stand:
## the zone is the stand's, and it keeps Loudspeaker ignorant of stands, which is
## the same reason it does not know which channel it carries.
func restore_seat(speaker: Loudspeaker) -> void:
	if _seat == null or speaker == null:
		return
	_seat.pick_up_object(speaker)


## Drop whatever is on the plate and free the stand. Looked for BY NAME by
## clear_scene and StorageBox, so the signature matters more than the body.
##
## The cabinet is dropped rather than freed with the stand: it is a separate prop
## the player owns, and a stand put away should not take a speaker with it.
func drop_and_free() -> void:
	if _seat != null and is_instance_valid(_seat.picked_up_object):
		_seat.drop_object()
	queue_free()
