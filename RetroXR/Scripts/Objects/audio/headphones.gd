## The RETRO XR portable headphones: a headset with a captive 1.2 m cord to a 3.5 mm plug, for any headphone jack in
## the room (a handheld's PhonesOut, a television's).
##
## ── Why it IS a CompositeCable ───────────────────────────────────────────────
## For the reasons the Antenna gives: binning, saving and the netplay seat events all key on `is CompositeCable`.
## Unlike the aerial's, this lead's captive end has a plug: PlugA0 sits for good in the headset's own hidden IN jack
## (Body/LineIn), so the jack's lead resolves to the headset as a SINK exactly as a 3.5 mm cable into SpeakerPair's
## line-in does — AvSource.resolve walks OUT jack -> lead -> LineIn -> get_device() == this node. Nothing in the
## routing is new: the host cuts its own speaker because its jack's lead reaches a sink (phones_carry_sound), and it
## places its two voices where get_speaker_positions() says, every frame.
##
## ── How it sounds ────────────────────────────────────────────────────────────
## The host owns the voices (Meta XR Audio, two of them): its LEFT channel at the left cup, its RIGHT at the right.
## Dry: no room is ever set on the SDK (MetaXRAudioServer.set_room is not called by the game), so no voice has a
## reverb or early reflections to send. Worn, the cups ARE at the ears, so it sounds like headphones by position
## alone; lying on a desk the same two voices are a small source there. One level, LEVEL, and one distance law with a
## near-ear reference, UNIT_SIZE: full level within 12 cm of the head, falling as 1/d past it — worn, the cups'
## middle is the head's middle (gain 1); on a desk a metre off the same pair is 0.12, about 18 dB down, which is what
## open foam headphones leak. hold_off_head still keeps each voice 25 cm out from the listener along its own
## direction, so worn they are hard left and hard right without the HRTF's near field muffling them.
##
## ── Worn ────────────────────────────────────────────────────────────────────
## Only a placement: the headset rides the wearer's camera, its ear axis on the head's (WORN_OFFSET). It changes no
## routing. VR: let go of it within WEAR_REACH of the headset's view point; take it off by grabbing it. Desktop: "On
## your head" in its menu (the headset's, or its plug's, which stays in the room while the camera is inside the band).
## Saved; not sent to other players — a worn flag on the wire would put the headset on THEIR heads. They see it
## wherever the body's synced pose is.
class_name Headphones
extends CompositeCable

## The one level the headphones play the host at (the host's volume, pushed as a SpeakerPair's knob is).
const LEVEL := 0.7
## Full level within this of the listener, 1/d past it (SystemAudio / media_transport read get_audio_unit_size).
const UNIT_SIZE := 0.12
## VR: let go of the headset within this of the view point and it goes on the head.
const WEAR_REACH := 0.28
## The headset's frame on the camera's: the ear axis 9 cm behind the eyes and 2 cm under them.
const WORN_OFFSET := Transform3D(Basis(), Vector3(0.0, -0.02, 0.09))
## How far each ear piece comes down at the band's three sizes (the model's EXTEND, 16 mm).
const EXTEND_M := 0.016
const BAND_LABELS := ["Small", "Medium", "Large"]
## The pads' middles, from the model: inner face 66 mm out, 11 mm thick.
const PAD_X := 0.0715
## The rig (headphones_contract.json): pivot, arch and parts, glTF meters in the body's frame.
const PIVOT := Vector3(0.0835, 0.025, 0.0)
const ARCH_Z0 := 0.056
const ARCH_TOP := 0.1358            # the band's centerline at its apex (inner 135 + half the 1.6 strip)
const BAND_T := 0.0016
const BAND_W := 0.010
const PAD_T := 0.005
const PAD_W := 0.013
const PAD_DEG := 52.0
const ARCH_SEGMENTS := 14

@onready var _body: HeadphonesBody = $Body
@onready var _model: ApplianceModel = $Body/Model
@onready var _line_in: TrsPort = $Body/LineIn
@onready var _band: VRSlider = $Body/BandSize

var worn := false
var _wearer: Node3D = null
var _source: Node3D = null
var _ext := 0.0
var _rest := {}


func _init() -> void:
	cord_colors = PackedColorArray([Color(0.06, 0.06, 0.065)])


func _ready() -> void:
	super._ready()
	var captive := $PlugA0 as RcaPlug
	# The captive end: seated in the headset's own jack for good, and nothing else can take it or reach it.
	_line_in.pick_up_object(captive)
	captive.enabled = false
	captive.visible = false
	captive.collision_layer = 0
	captive.collision_mask = 0
	# The cord leaves the cup at the relief's tip, which is where the captive plug's mating face sits: a hidden plug's
	# handle would otherwise start the rope 30 mm under the cup, in the air.
	captive.cable_anchor = Vector3.ZERO
	_line_in.enabled = false
	_line_in.collision_layer = 0
	_line_in.visible = false
	for plug: RcaPlug in _end_plugs(End.B):
		plug.add_collision_exception_with(_body)
	# The band's size is carried by a hidden slider so the room save and netplay restore and send it as every
	# articulated control (the record player's SpeedSwitch does the same for its speed).
	_band.visible = false
	_band.collision_layer = 0
	_band.process_mode = Node.PROCESS_MODE_DISABLED
	_band.value_changed.connect(_on_band)
	_body.dropped.connect(_on_body_dropped.unbind(1))
	_body.grabbed.connect(_on_body_grabbed.unbind(2))
	_build_shapes()
	_apply_band(_band.value)
	print("[Headphones] %s: ready, band %s, %d levels" % [name, BAND_LABELS[_band_index()], _model.levels.size()])


func _process(_delta: float) -> void:
	if worn:
		if not is_instance_valid(_wearer):
			take_off()
			return
		_body.global_transform = _wearer.global_transform * _worn_offset()


# ── the sink contract (SpeakerPair's, read by SystemAudio, media_transport and RetroTV) ──────────────────────

func on_av_topology_changed(_links: Array) -> void:
	pass


## Left cup first, then right: where the host's two channels play.
func get_speaker_positions() -> PackedVector3Array:
	var y := -EXTEND_M * _ext
	return PackedVector3Array([
		_body.global_transform * Vector3(-PAD_X, y, 0.0),
		_body.global_transform * Vector3(PAD_X, y, 0.0),
	])


func get_audio_unit_size() -> float:
	return UNIT_SIZE


func get_volume() -> float:
	return LEVEL


func on_av_source_found(source: Node3D) -> void:
	_source = source
	print("[Headphones] %s: carrying %s" % [name, source.name])
	_push_level()


func on_av_source_lost(source: Node3D) -> void:
	if _source != source:
		return
	_source = null
	print("[Headphones] %s: %s no longer plays through them" % [name, source.name])


func get_screen_mesh() -> MeshInstance3D:
	return null


func show_osd_timed(_text: String, _seconds: float = 2.0) -> void:
	pass


func hide_osd() -> void:
	pass


func _push_level() -> void:
	if not is_instance_valid(_source):
		return
	if _source.has_method("on_line_out_level_changed"):
		_source.on_line_out_level_changed()       # a set folds get_volume() into its own level
	else:
		AvSourceContract.push_volume(_source, LEVEL)


## Who is playing through them, or null.
func source() -> Node3D:
	return _source if is_instance_valid(_source) else null


# ── wearing ──────────────────────────────────────────────────────────────────

## Put the headset on `camera`'s head (its ear axis on the head's).
func put_on(camera: Node3D) -> void:
	if camera == null:
		push_warning("[Headphones] %s: no camera to put them on" % name)
		return
	if _body.is_picked_up():
		_body.drop()
	worn = true
	_wearer = camera
	_body.freeze = true
	_body.global_transform = camera.global_transform * _worn_offset()
	call_deferred("_build_rope")
	print("[Headphones] %s: put on (%s)" % [name, camera.name])


## The headset on the head: its ear axis on the head's, lifted by however far the band lets the cups down, so the
## cups are on the ears at every size.
func _worn_offset() -> Transform3D:
	return WORN_OFFSET * Transform3D(Basis(), Vector3(0.0, EXTEND_M * _ext, 0.0))


func take_off() -> void:
	if not worn:
		return
	worn = false
	var cam := _wearer
	_wearer = null
	if not _body.is_picked_up():
		_body.freeze = false
		if is_instance_valid(cam):
			# Down in front of the face, where a hand would put them.
			_body.global_transform = Transform3D(cam.global_basis.orthonormalized(),
				cam.global_position - cam.global_basis.z * 0.35 + Vector3(0, -0.15, 0))
	print("[Headphones] %s: taken off" % name)


func _view_camera() -> Node3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _on_body_dropped() -> void:
	if worn:
		return
	var cam := _view_camera()
	if cam == null or not get_viewport().use_xr:
		return
	var d := _body.global_position.distance_to(cam.global_position)
	if d <= WEAR_REACH:
		put_on(cam)


func _on_body_grabbed() -> void:
	if worn:
		take_off()


# ── the band ─────────────────────────────────────────────────────────────────

func _band_index() -> int:
	return clampi(roundi(_band.value * 2.0), 0, 2)


func set_band(index: int) -> void:
	_band.set_value(clampf(index / 2.0, 0.0, 1.0))


func _on_band(v: float) -> void:
	_apply_band(v)
	print("[Headphones] %s: band %s" % [name, BAND_LABELS[_band_index()]])


## Pull each ear piece down out of its slider, on every level, with the cord's exit and the shapes that ride it.
func _apply_band(v: float) -> void:
	_ext = clampf(v, 0.0, 1.0)
	for side: String in ["L", "R"]:
		for part: String in ["Yoke", "Cup"]:
			for n in _model.parts(part + side):
				if not _rest.has(n):
					_rest[n] = n.position
				n.position = (_rest[n] as Vector3) + Vector3(0.0, -EXTEND_M * _ext, 0.0)
	_place_line_in()
	_place_moving_shapes()


## The hidden jack stands on the left cup's CordExit, facing out along the cord (a socket's +Z is its mouth; the
## cord leaves the exit along its -Z).
func _place_line_in() -> void:
	var exit := _model.part("CordExit")
	if exit == null:
		push_warning("[Headphones] %s: the model has no CordExit" % name)
		return
	var t := exit.global_transform.orthonormalized()
	_line_in.global_transform = Transform3D(t.basis * Basis(Vector3.UP, PI), t.origin)


# ── collision: what the model draws, no margin ───────────────────────────────

## The body and its PointerArea get the same shapes: the band as boxes along its arch (the padded strip in them where
## it runs), the two sliders, and per side the pivot block, the steel strip, the cup and the pad as cylinders. A dynamic
## body cannot take the drawn triangles, and one box round an arch would be a solid block over the head.
func _build_shapes() -> void:
	var ptr := _body.get_node("PointerArea") as StaticBody3D
	for owner_node: Node3D in [_body, ptr]:
		for c in owner_node.get_children():
			if c is CollisionShape3D:
				owner_node.remove_child(c)
				c.queue_free()
	var fixed: Array = []
	var a := PIVOT.x
	var b := ARCH_TOP - ARCH_Z0
	for i in ARCH_SEGMENTS:
		var t0 := deg_to_rad(-90.0 + 180.0 * i / ARCH_SEGMENTS)
		var t1 := deg_to_rad(-90.0 + 180.0 * (i + 1) / ARCH_SEGMENTS)
		var p0 := Vector3(a * sin(t0), ARCH_Z0 + b * cos(t0), 0.0)
		var p1 := Vector3(a * sin(t1), ARCH_Z0 + b * cos(t1), 0.0)
		var tan := (p1 - p0).normalized()
		var inward := Vector3(-tan.y, tan.x, 0.0)
		if inward.dot(Vector3(0, ARCH_Z0, 0) - (p0 + p1) * 0.5) < 0.0:
			inward = -inward
		var mid_deg := rad_to_deg((t0 + t1) * 0.5)
		var padded := absf(mid_deg) < PAD_DEG
		var thick := BAND_T + (PAD_T if padded else 0.0)
		var centre := (p0 + p1) * 0.5 + inward * ((thick - BAND_T) * 0.5)
		var basis := Basis(tan, inward, Vector3.BACK)
		fixed.append([Vector3((p1 - p0).length(), thick, PAD_W if padded else BAND_W), Transform3D(basis, centre)])
	for s: float in [-1.0, 1.0]:
		fixed.append([Vector3(0.0075, 0.022, 0.014), Transform3D(Basis(), Vector3(s * a, 0.051, 0.0))])
		fixed.append([Vector3(BAND_T, ARCH_Z0 - 0.044, BAND_W), Transform3D(Basis(), Vector3(s * a, (0.044 + ARCH_Z0) * 0.5, 0.0))])
	for owner_node: Node3D in [_body, ptr]:
		var k := 0
		for f: Array in fixed:
			var cs := CollisionShape3D.new()
			cs.name = "Fixed%d" % k
			var box := BoxShape3D.new()
			box.size = f[0]
			cs.shape = box
			cs.transform = f[1]
			owner_node.add_child(cs)
			k += 1
		for side: String in ["L", "R"]:
			for part: String in ["Pivot", "Strip", "Cup", "Pad"]:
				var cs := CollisionShape3D.new()
				cs.name = part + side
				if part == "Cup" or part == "Pad":
					var cyl := CylinderShape3D.new()
					cyl.radius = 0.022 if part == "Cup" else 0.025
					cyl.height = 0.013 if part == "Cup" else 0.011
					cs.shape = cyl
				else:
					var box := BoxShape3D.new()
					box.size = Vector3(0.006, 0.008, 0.009) if part == "Pivot" else Vector3(0.0014, 0.012, 0.009)
					cs.shape = box
				owner_node.add_child(cs)


## The ear pieces' shapes at the band's current size: the cup and pad round the cup's axis, the pivot block on its
## top, the strip between it and the slider.
func _place_moving_shapes() -> void:
	var dy := -EXTEND_M * _ext
	var ptr := _body.get_node("PointerArea") as StaticBody3D
	for owner_node: Node3D in [_body, ptr]:
		for side: String in ["L", "R"]:
			var s := -1.0 if side == "L" else 1.0
			var at := {
				"Pivot": Transform3D(Basis(), Vector3(s * PIVOT.x, 0.025 + dy, 0.0)),
				"Strip": Transform3D(Basis(), Vector3(s * PIVOT.x, 0.035 + dy, 0.0)),
				"Cup": Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(s * 0.0835, dy, 0.0)),
				"Pad": Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(s * PAD_X, dy, 0.0)),
			}
			for part: String in at:
				var cs := owner_node.get_node_or_null(part + side) as CollisionShape3D
				if cs:
					cs.transform = at[part]


# ── its menu (ObjectOptionsPanel, through the body or the plug) ──────────────

func options_choices() -> Array:
	return [{"caption": "On your head", "items": ["Off", "On"], "selected": 1 if worn else 0},
		{"caption": "Band", "items": BAND_LABELS, "selected": _band_index()}]


func options_choose(row: int, item: int) -> void:
	match row:
		0:
			if item == 1 and not worn:
				put_on(_view_camera())
			elif item == 0 and worn:
				take_off()
		1:
			set_band(item)


# ── save / restore ───────────────────────────────────────────────────────────

func carried_body_pose() -> Dictionary:
	if not is_instance_valid(_body):
		return {}
	var p := _body.global_position
	var r := _body.global_rotation_degrees
	return {"position": [p.x, p.y, p.z], "rotation": [r.x, r.y, r.z], "worn": worn}


func restore_carried_body(data: Dictionary) -> void:
	if not is_instance_valid(_body) or data.is_empty():
		return
	var pos: Array = data.get("position", [])
	var rot: Array = data.get("rotation", [])
	if pos.size() == 3:
		_body.global_position = Vector3(pos[0], pos[1], pos[2])
	if rot.size() == 3:
		_body.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	call_deferred("_build_rope")
	if bool(data.get("worn", false)):
		call_deferred("_restore_worn")


func _restore_worn() -> void:
	var cam := _view_camera()
	if cam != null:
		put_on(cam)
	else:
		print("[Headphones] %s: saved worn, but there is no camera to put them on" % name)
