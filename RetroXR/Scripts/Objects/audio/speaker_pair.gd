## A pair of powered desktop speakers: two cabinets, independently pickable, joined
## by a permanent wire, with the line-in socket and the volume knob on the right one.
##
## ── Why there is almost no audio code here ───────────────────────────────────
## Because a television has none either. RetroTV never plays anything: it is two
## Marker3Ds and a volume number. The SOURCE owns its voices and walks them onto
## whatever get_speaker_positions() hands back, every frame (see
## SystemAudio.update_position). So publishing this pair's two cabinet
## positions is the whole of being a loudspeaker — and because it is read per frame
## rather than latched, carrying a box across the room carries its channel with it.
##
## The one thing that did have to change elsewhere: RetroSystem used to cast the
## sink to RetroTV and drop anything else on the floor. It now asks whether the sink
## has get_speaker_positions, which a set and a speaker pair both answer.
##
## ── The sink contract, as the sources actually use it ────────────────────────
## Duck-typed throughout; there is no base class to inherit. Provide:
##   on_av_topology_changed  — mandatory, it is what RcaPort.get_device() looks for
##   get_speaker_positions   — the two cabinets, LEFT FIRST
##   on_av_source_found/lost — so the source learns who is carrying its sound
##   show_osd_timed/hide_osd — the DVD and VCR call these UNGUARDED
##   get_screen_mesh         — null; nothing routes a picture here
## get_screen_normal is deliberately NOT provided. It is guarded by has_method, and
## leaving it out keeps the source omnidirectional — which is the honest answer for
## two boxes pointing in whatever directions the player left them in, where a single
## forward vector would have to lie about one of them.
##
## ── The model ────────────────────────────────────────────────────────────────
## Each box wears its RETRO XR model (RetroXR-models generic/computer-speakers, a left
## and a right GLB) through an ApplianceModel child, `Model`. _dress() puts each box's
## CableBoss on the model's grommet tip (so the wire leaves through the grommet), its
## ConeFront on the driver, the right box's LineIn on the model's 3.5 mm socket and the
## model's knob cap under the VolumeKnob's KnobPivot, and fits each box's body and laser
## boxes to what its model draws (the knob is the VRKnob's own box). The old primitive
## meshes keep their nodes, hidden. No speaker-wire clips: the wire and LINE IN are the
## only connections the pair has.
##
## ── The power LED ────────────────────────────────────────────────────────────
## The volume knob is a click-off pot, as on most desktop speakers: at the bottom of its
## travel (LED_OFF_BELOW) the amplifier is off, and the green LED beside the knob is lit
## whenever it is above that. The pair has no mains cord in the game, so the knob's
## click is the whole of its power state.
class_name SpeakerPair
extends Node3D

## Which cabinet is which, and the order get_speaker_positions reports them in.
enum Side { LEFT, RIGHT }

@onready var _boxes: Array[SpeakerBox] = [$SpeakerL, $SpeakerR]
@onready var _rope: VerletRope = $VerletRope
@onready var _line_in: TrsPort = $SpeakerR/LineIn
@onready var _knob: VRKnob = $SpeakerR/VolumeKnob

## The knob's click: below this the amplifier is off and the LED dark.
const LED_OFF_BELOW := 0.02
const LED_ON := Color8(60, 235, 110)
const LED_DARK := Color8(14, 44, 20)
## The old primitive meshes, hidden once a model dresses the box (the nodes are kept).
const OLD_MESHES: Array[String] = ["Cabinet", "Baffle", "Cone", "DustCap", "Port", "BackLabel"]
## The model's empties, renamed `<name>Mouth` so a recursive find meets the scene's node.
const MOUTHS: Array[String] = ["CableBoss", "LineIn", "DriverCentre"]

var _led_mat: StandardMaterial3D = null
var _led_on: Variant = null

## The device currently feeding these speakers, or null.
var _source: Node3D = null

## 0..1, the knob's position. Pushed at the source whenever either changes.
var _volume: float = 0.75

# The rope is built a frame after _ready (see there). Until it is, its particles are
# a default cord around the origin and the tether must not read them.
var _rope_built := false


func _ready() -> void:
	add_to_group("spawned")
	_dress()
	_volume = _knob.value
	_knob.value_changed.connect(_on_volume)
	_update_led()
	# The SOCKET announces seating, not the plug — a plug taken straight out of one
	# socket into another leaves the first empty without ever reporting it.
	_line_in.has_picked_up.connect(func(_w: Node3D) -> void: _push_volume())
	# Deferred, NOT called straight through. VerletRope is top_level and its
	# particles are world-space, so _init_points bakes them around wherever the
	# cabinets stand at the time — and the spawn menu positions what it spawned on
	# the line AFTER add_child returns (spawn_menu_controller::_place_spawned).
	# Building here would pin the wire to the world origin and the tether below
	# would then haul both boxes back to it.
	call_deferred("_build_rope")


# ── dressing ─────────────────────────────────────────────────────────────────

func _dress() -> void:
	for box: SpeakerBox in _boxes:
		var model := box.get_node_or_null("Model") as ApplianceModel
		if model == null or model.levels.is_empty():
			push_warning("[Speaker] %s/%s: no model to dress the box from" % [name, box.name])
			continue
		for n: String in MOUTHS:
			for mouth in model.parts(n):
				mouth.name = n + "Mouth"
		var boss := box.get_node_or_null("CableBoss") as Node3D
		if boss != null and model.part("CableBossMouth") != null:
			boss.transform = model.part_transform("CableBossMouth", box)
		else:
			push_warning("[Speaker] %s/%s: no CableBoss on the model or the scene" % [name, box.name])
		var cone := box.get_node_or_null("ConeFront") as Node3D
		if cone != null and model.part("DriverCentreMouth") != null:
			cone.transform = Transform3D(Basis.IDENTITY, model.part_transform("DriverCentreMouth", box).origin)
		for n: String in OLD_MESHES:
			var old := box.get_node_or_null(n) as Node3D
			if old != null:
				old.visible = false
		if box == _boxes[Side.RIGHT]:
			_dress_right(box, model)
		for i in range(1, model.levels.size()):
			for m in model.levels[i].find_children("*", "MeshInstance3D", true, false):
				m.add_to_group("outline_exclude")
		# The knob is hung under the VRKnob by now (_dress_right), so the box is the cabinet as drawn.
		model.fit_shapes([box.get_node_or_null("CollisionShape3D") as CollisionShape3D,
			box.get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D])
		print("[Speaker] %s/%s: dressed from the model (%d levels), wire at %s" % [name, box.name, model.levels.size(),
			boss.position.snapped(Vector3.ONE * 0.0001) if boss != null else "nowhere"])


## The right box: LINE IN on the model's socket, the model's knob cap under the VolumeKnob's pivot (fitted with the
## pivot at rest, as DeckFace.dress_phones does), and the LED's own material on every level.
func _dress_right(box: SpeakerBox, model: ApplianceModel) -> void:
	if model.part("LineInMouth") != null:
		DeckFace.seat_port(model, _line_in, "LineInMouth")
	else:
		push_warning("[Speaker] %s: the model has no LINE IN socket" % name)
	var cap := model.part("VolumeKnob")
	if cap != null:
		var ab := ApplianceModel.node_bounds(cap, box)
		var axis := model.part_transform("VolumeKnob", box).origin
		_knob.position = Vector3(axis.x, axis.y, ab.position.z)
		var pivot := _knob.get_node("KnobPivot") as Node3D
		var turned := pivot.rotation
		pivot.rotation = Vector3.ZERO
		model.attach_part("VolumeKnob", pivot)
		var level := 0
		for part in pivot.get_children():
			if part.name == "KnobCap" or part.name == "KnobPointer":
				(part as Node3D).visible = false
				continue
			part.name = "ModelLevel%d" % level
			pivot.move_child(part, level)          # the model's caps first: the knob IS the close level's cap
			level += 1
		var first := pivot.get_node_or_null("ModelLevel0")
		if first != null:
			ApplianceModel.fit_box(_knob.get_node_or_null("CollisionShape3D") as CollisionShape3D,
				ApplianceModel.node_bounds(first, _knob))
		pivot.rotation = turned
	else:
		push_warning("[Speaker] %s: the model has no VolumeKnob; the primitive cap stays" % name)
	_led_mat = StandardMaterial3D.new()
	var leds := model.parts("PowerLed")
	for led in leds:
		(led as MeshInstance3D).material_override = _led_mat
	if leds.is_empty():
		push_warning("[Speaker] %s: the model has no PowerLed" % name)


## The LED lit while the knob is off its click.
func _update_led() -> void:
	if _led_mat == null:
		return
	var on := _volume >= LED_OFF_BELOW
	if on == _led_on:
		return
	_led_on = on
	_led_mat.albedo_color = LED_ON if on else LED_DARK
	_led_mat.emission_enabled = on
	_led_mat.emission = LED_ON
	_led_mat.emission_energy_multiplier = 2.0
	print("[Speaker] %s: power LED %s (volume %.2f)" % [name, "lit" if on else "dark: the knob is on its click", _volume])


## Whether the power LED is lit (for tests and probes).
func led_lit() -> bool:
	return _led_on == true


## Wire the two cabinets together. One cord, both ends anchored — the same shape as
## CompositeCable's single-cord lead, minus the plugs.
##
## Anchored at the cable BOSSES, not at the cabinets. The marker is what makes the
## difference: VerletRope reads a RigidBody3D anchor that is neither held nor frozen
## as a free PLUG and couples it to the cord (end_align_stiffness,
## VerletRope::CouplePlug) — the cord leaves along its -Z and pushes back on it. It
## used to TURN it there, 70% a tick, and anchored at the boxes a spawned pair rolled
## flat on its side within a second and then crept across the floor forever, chasing a
## tangent its own turning kept moving. A cabinet is still not a plug. A plain Node3D
## anchor is read as a host attach point instead — a device end, which is what these
## are — exactly as every controller and peripheral cable here anchors its machine end.
## The cabinet still owns the anchor: RefreshExclusions walks up to the first
## CollisionObject3D, so the cord is still excluded from the box it leaves.
func _build_rope() -> void:
	if not is_inside_tree():
		return
	_rope.start_node = $SpeakerL/CableBoss
	_rope.end_node = $SpeakerR/CableBoss
	_rope.start_anchor_offset = Vector3.ZERO
	_rope.end_anchor_offset = Vector3.ZERO
	_rope._init_points()
	_rope_built = true


## Keep the two cabinets within the wire's length of each other.
##
## A pinned rope particle has inverse mass zero, so a box drives the rope and the
## rope can never drive a box: without this, carrying one speaker away leaves the
## other exactly where it was while the wire stretches without limit. Only the box
## that is NOT held moves — something else owns a held one's transform, and fighting
## it just jitters the thing in your hand.
##
## HAULED rather than moved, through CableHaul, which is where that whole argument
## lives: the wire leaves this cabinet at a boss 45 mm below its centre of mass and off
## to one side, so a box lifted by the one in your hand turns and hangs from the taut
## wire instead of sailing along upright. Same call the RF switch's box makes.
func _physics_process(_delta: float) -> void:
	if not _rope_built or _rope == null:
		return
	var a: SpeakerBox = _boxes[Side.LEFT]
	var b: SpeakerBox = _boxes[Side.RIGHT]
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	if _is_held(a) and _is_held(b):
		return          # both in hands: the wire is simply taut, as it would be
	var fixed: SpeakerBox = a
	var loose: SpeakerBox = b
	if _is_held(b):
		fixed = b
		loose = a
	var reach: float = float(_rope.segment_count) * _rope.segment_length
	# Boss to boss, not origin to origin: that is the span the wire actually has.
	loose.global_position += CableHaul.haul(loose, _boss(loose), _boss(fixed), reach)


## Where the wire leaves a cabinet, in world space.
func _boss(box: SpeakerBox) -> Vector3:
	return box.global_transform * (box.get_node("CableBoss") as Node3D).position


## True while a hand, a laser or a snap zone owns this cabinet's pose.
##
## `freeze`, for the reason RcaPlug.is_held gives: a ray grab never calls pick_up(), so
## is_picked_up() reads false for the whole hold. A beam-held box read as loose is the
## worse half of the bug — an impulse does nothing to a frozen body, so the wire would
## couple neither way and the far cabinet would sit still while the near one flew off.
func _is_held(box: SpeakerBox) -> bool:
	return box.freeze


# ── the sink contract ────────────────────────────────────────────────────────

## Nothing to do here: speakers are a sink, and every routing decision is the
## source's. It exists so RcaPort.get_device() recognises this pair as a device at
## all — that is the whole of the interface, exactly as it is on a television.
func on_av_topology_changed(_links: Array) -> void:
	pass


## Where the sound comes from, LEFT FIRST. Read every frame by whatever is feeding
## us, so moving a cabinet moves its channel with it.
func get_speaker_positions() -> PackedVector3Array:
	return PackedVector3Array([
		($SpeakerL/ConeFront as Node3D).global_position,
		($SpeakerR/ConeFront as Node3D).global_position,
	])


func on_av_source_found(source: Node3D) -> void:
	_source = source
	_push_volume()


func on_av_source_lost(source: Node3D) -> void:
	if _source != source:
		return          # already replaced by another source
	_source = null


## No screen here, and nothing should ever route a picture to a loudspeaker. Present
## because the DVD player reads it without guarding.
func get_screen_mesh() -> MeshInstance3D:
	return null


## The decks call these on whatever they are plugged into, unguarded. A speaker has
## nowhere to put a message, so they are no-ops rather than absent.
func show_osd_timed(_text: String, _seconds: float = 2.0) -> void:
	pass


func hide_osd() -> void:
	pass


# ── volume ───────────────────────────────────────────────────────────────────

func _on_volume(v: float) -> void:
	_volume = v
	_push_volume()
	_update_led()


## The same contract every volume control in the project speaks: the sink holds a
## 0..1 level and hands it to the source, which owns the actual voices.
##
## A television on these through its headphone jack is the exception. It owns no
## voices either — it pushes ITS level at the machines it shows — so it is told the
## knob moved and folds the knob into that (RetroTV.on_line_out_level_changed).
func _push_volume() -> void:
	if not is_instance_valid(_source):
		return
	if _source.has_method("on_line_out_level_changed"):
		_source.on_line_out_level_changed()
	else:
		AvSourceContract.push_volume(_source, _volume)


func get_volume() -> float:
	return _volume


## Set the knob and the level together — used by save/restore, which has no hand to
## turn it with.
func set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	if _knob != null:
		_knob.set_value_no_signal(_volume)
	_push_volume()
	_update_led()


# ── save / restore ───────────────────────────────────────────────────────────
#
# The two cabinets move independently, so the ROOT's transform says nothing about
# where either of them is — this cannot be a pose-only object.


func box_poses() -> Array:
	var out: Array = []
	# Variant first: binding a freed box to a typed loop variable throws before any
	# validity test could run. A cabinet freed on its own (SpeakerBox.drop_and_free
	# forwards to the pair now) must not take an autosave down with it.
	for entry: Variant in _boxes:
		if not is_instance_valid(entry) or not (entry as Node3D).is_inside_tree():
			push_warning("[SpeakerPair] '%s' has a freed cabinet; saving no box poses" % name)
			return []
		var box: SpeakerBox = entry
		var p := box.global_position
		var r := box.global_rotation_degrees
		out.append({"position": [p.x, p.y, p.z], "rotation": [r.x, r.y, r.z]})
	return out


func restore_box_poses(poses: Array) -> void:
	for i in mini(poses.size(), _boxes.size()):
		var rec: Dictionary = poses[i]
		if not is_instance_valid(_boxes[i]):
			push_warning("[SpeakerPair] '%s' cabinet %d is freed; pose not restored" % [name, i])
			continue
		var box: SpeakerBox = _boxes[i]
		var pos: Array = rec.get("position", [])
		var rot: Array = rec.get("rotation", [])
		if pos.size() == 3:
			box.global_position = Vector3(pos[0], pos[1], pos[2])
		if rot.size() == 3:
			box.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	# The wire was baked around wherever the cabinets stood a frame ago; rebuild it
	# now they have been put back.
	call_deferred("_build_rope")


## Release the seated lead before this pair is freed.
##
## ScenePersistence.clear_scene looks for this by name. Without it the socket is left
## holding a freed pickable and XRToolsPickable._exit_tree walks a dangling grab
## driver — the same trap CompositeCable.drop_and_free records.
func drop_and_free() -> void:
	if is_instance_valid(_line_in):
		_line_in.drop_object()
	Vanish.free_node(self)
