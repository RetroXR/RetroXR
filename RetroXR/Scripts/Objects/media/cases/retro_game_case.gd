## RetroGameCase — a disc game's case: the jewel or keep case it was sold in (GameCase picks it), its ScreenScraper
## box-texture on the paper, its discs on their hubs and its manual under the lid.
##
## The case is one pickable body; its lid (and a fat case's flip tray, a keep case's flippers) swing by
## CaseHingeSim under the gravity the case feels where it is held, and snap shut. A hand works them through
## CaseHinge (the trigger in VR, the reticle on the desktop), as any hinged lid in the game.
##
## Each disc seat and the manual's place is an XRToolsSnapZone in ScenePersistence.MOD_ZONE_GROUP: a save records
## what is in it as attached, as the NAOMI GD-ROM drive's spindle does, so the case comes back with its contents.
## Only spawn_contents() (the spawn menu's case button) makes discs and a manual; a restored case gets its own back.
class_name RetroGameCase
extends XRToolsPickable

const GROUP := &"game_case"
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")
const UMD_SCENE := preload("res://Scenes/Objects/media/umd_disc.tscn")
const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
## A seat a hand can reach: the panel over it turned this far off it.
const REACH_DEG := 25.0
const MASS := {"jewel": 0.075, "keep": 0.11}
## How freely each family's hinge turns (CaseHingeSim friction, a share of gravity's pull): a jewel case's knuckles
## let the lid fall as the case is tilted or waved; a keep case's polypropylene hinge is stiffer than gravity, so
## its cover holds where it is put unless the case is shaken (the owner, 2026-11-20). At 1.3 a 0.3 g move of the
## hand swung it 45 degrees; at 2.5 it takes 2 g.
const FRICTION := {"jewel": 0.12, "keep": 2.5}
## Sliding friction as a share of that: a living hinge does not slip once it moves.
const KINETIC := {"jewel": 0.8, "keep": 1.0}
## A keep case's flippers are trays clipped on pins: free, like a jewel case's flip tray.
const FLIPPER_FRICTION := 0.12
## Its cover's living hinge was molded lying open: unlatched it rests about this far off shut, and let go by a hand
## it eases this far back the way it came [E: no case measured].
const KEEP_AJAR_DEG := 4.0
const KEEP_SPRINGBACK_DEG := 4.0
## The case's sounds (Tools/gen/gen_case_sounds.py): <family>_open and _close as the latch lets go and catches, and
## as the lid turns a jewel case's pins creak, a keep case's hinge and sleeve rustle, once in about this much travel.
const SFX_DIR := "res://Audio/cases/"
const SFX_TURN := {"jewel": "creak", "keep": "hinge"}
const SFX_TURN_DEG := 60.0
## <family>_stop: the lid against its open stop, or home without catching, from this speed (rad/s) up; full at
## SFX_SLAM. A keep case's cover has no such sound: it never swings.
const SFX_KNOCK := 2.0
const SFX_SLAM := 16.0
## A restore's first poses are not a hand's: no sound for this many physics ticks.
const SFX_QUIET_TICKS := 45
## The case's turn about its spine: speeding up faster than this (rad/s^2) is a teleport or a grab's first frame;
## slower than SPIN_QUIET, the tracking's tremor.
const SPIN_CUT := 800.0
const SPIN_QUIET := 12.0
## The jolt that springs a caught latch (rad/s^2), and how fast a free swing must come home to catch it (rad/s):
## a lid that drifts shut rests there unlatched; a hand or a poke pushing it home catches it.
const LATCH_BREAK := {"jewel": 400.0, "keep": 900.0}
## A jewel lid dropped from upright reaches about 18 rad/s at the bottom, so gravity alone never catches it from less
## than about 100 degrees open; a flick of the wrist does.
const LATCH_SPEED := {"jewel": 20.0, "keep": 15.0}
const KEEP_COVER_T := 0.002
const LATCH_HAPTIC_KEY := &"game_case_latch"
## A popped disc rides this far up off its hub, tilted this much, loose on the catches.
const POP_LIFT := 0.004
const POP_TILT_DEG := 4.0
## The hub button's reach: its cap, inside the disc's hole (7.5 mm).
const HUB_BUTTON_R := 0.0045
## The body's hull is rebuilt when the lid has turned this far since the last one.
const SHAPE_STEP_DEG := 2.0
## The panel a manual sits under, from the manual seat's centre (the seat is the paper's mid-plane).
const MANUAL_WALL := 0.0006
## A seated manual as the case draws it: the room under the clips (keep_params MANUAL_T).
const MANUAL_T := 0.0012
## The cases with a memory-card holder, and the card family (MemoryCard.family) each takes.
## Open past this, the pointer target leaves the case's inside clear; the lid's skin is this thick; a disc is
## 1.2 mm.
const POINTER_OPEN_DEG := 15.0
const POINTER_SKIN := 0.0015
const DISC_HALF_T := 0.0006
const CARD_FAMILIES := {"ps2": "playstation2", "gc": "gamecube", "gc_jp": "gamecube", "gc_double": "gamecube",
	"gc_double_pal": "gamecube", "gc_jp_double": "gamecube"}
## How a card lies in its holder (seat frame: +X across, +Y up the case, +Z out of the panel). The PS2 holder is
## landscape: the card lies along it, label out, its +Z end toward the opening edge (gauntlet/refs/trayrefs/ps2/
## ps2_case_inside_memory_card_holder_commons.jpg; the owner, 2026-11-21: turned 180 from the first try). The
## GameCube holder is portrait: the card upright, label out, reading the right way up (the default below; the owner).
const CARD_BASIS := {"ps2": Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))}

@export var rom_path := ""
@export var game_label := ""
@export var systemid := ""
## Which case: set before _ready (GameCase.pick, or a save); empty picks from the game with no box art to measure.
@export var case_family := ""
@export var case_variant := ""
@export var case_color := ""
## The decoded box-texture, handed in by whoever already loaded it; else the case loads its own.
var box_image: Image

var model: GameCaseModel
var sim := CaseHingeSim.new()
## One per sim hinge, from the back: [frame Node3D, angle Node3D, CaseHinge].
var _rigs: Array = []
var _was_held: Array[bool] = []
var _zones: Array[XRToolsSnapZone] = []          # disc seats, in seat order (index 0 is DiscSeat1)
var _seat_carrier: Array[int] = []               # per disc seat: -1 the back, else a sim hinge
var _seat_down: Array[bool] = []                 # per disc seat: its hub faces the back
var _popped: Array[bool] = []                    # per disc seat: its hub button has popped the disc up
var _seat_spin: Array[float] = []                # per disc seat: the turn about the hub its disc was put on at (rad)
var _hub_buttons: Array[VRButton] = []
var _manual_zone: XRToolsSnapZone
var _manual_root: Node3D
var _holder_zone: XRToolsSnapZone                # the UMD's holder
var _card_zone: XRToolsSnapZone                  # a PS2 or GameCube memory card's holder
var _body_shape: CollisionShape3D
var _shape_deg := -1.0
var _lid_box := AABB()
var _base_box := AABB()
var _pointer_base: CollisionShape3D
var _pointer_lid: CollisionShape3D
var _pointer_floor := AABB()
var _pointer_skin := AABB()
var _pointer_open := false
var _closed_box := AABB()
var _has_manual := false
var _seated_book: PDFBook
var _manual_proxy: Node3D
var _front_tries := 0
var _pos_hist: Array[Vector3] = []
var _accel := Vector3.ZERO
var _lid_pivot := Vector3.ZERO
static var _sfx_clips: Dictionary = {}           # "<family>_<kind>" -> Array of PackedVector2Array
var _sfx_voices := {}                            # "snap" / "turn" -> PcmOneShot, made at the first sound
var _sfx_ticks := 0
var _sfx_latched := true
var _sfx_lid := 0.0
var _sfx_travel := 0.0
var _sfx_next := 15.0
var _prev_rot := Quaternion.IDENTITY
var _has_rot := false
var _turn := 0.0
var _spin := 0.0


func _ready() -> void:
	super()
	add_to_group(GROUP)
	# The desktop ray meets the case by its PointerArea only (shaped to leave an open case's inside clear), not by its
	# body's hull: that fills an open case to the brim, and every click on a disc took the case (the owner, 2026-11-21).
	set_meta(InteractionResolver.POINTER_BY_AREA, true)
	# Before the grab drivers (a zone's at -70, a hand's at -80): the trays turn first, then whatever they hold follows
	# them in the same frame. At the default 0 the discs were placed where their trays had been, a frame behind
	# (the owner, 2026-11-21: "the disk lags behind slightly").
	process_physics_priority = -100
	if case_variant.is_empty():
		var pick := GameCase.pick(systemid, GameCase.market_of(systemid, rom_path),
			GameCase.discs_of(rom_path).size(), Vector2i.ZERO, GameCase.release_of(systemid, rom_path))
		case_family = str(pick["family"])
		case_variant = str(pick["variant"])
		if case_color.is_empty():
			case_color = str(pick["color"])
	model = GameCaseModel.new()
	model.name = "Model"
	add_child(model)
	if not model.build(case_family, case_variant):
		case_family = "jewel"
		case_variant = "single"
		model.build(case_family, case_variant)
	if not case_color.is_empty():
		model.set_color(case_color)
	mass = float(MASS.get(case_family, 0.08))
	_closed_box = _model_box()
	_build_shapes()
	_build_hinges()
	_build_zones()
	_has_manual = not manual_path().is_empty()
	_sync_manual()
	_apply_angles()
	if box_image != null:
		_apply_art(box_image)
	elif not rom_path.is_empty():
		_load_art.call_deferred()


## The scraped manual for this game, or "".
func manual_path() -> String:
	if rom_path.is_empty() or systemid.is_empty():
		return ""
	var base := RomLibrary.content_stem(rom_path)
	for dir in RomLibrary.rom_dirs_for_system(systemid):
		var p := dir.path_join("media").path_join("manual").path_join(base + ".pdf")
		if FileAccess.file_exists(p):
			return p
	return ""


## Fill a new case: a disc on each hub for every disc of the game (as many as it holds), and the manual. The case
## must be in the tree; the contents join the room it is in as objects of their own ("spawned").
func spawn_contents(disc_paths: PackedStringArray) -> void:
	var room := get_parent()
	var umd := systemid == "psp" and _holder_zone != null
	var seats: Array[XRToolsSnapZone] = _zones
	if umd:
		seats = [_holder_zone] as Array[XRToolsSnapZone]
	for i in mini(disc_paths.size(), seats.size()):
		if disc_paths[i].is_empty():
			continue                                     # a disc of the set that is not on this device
		var disc := (UMD_SCENE if umd else DISC_SCENE).instantiate() as RetroCartridge
		disc.rom_path = disc_paths[i]
		disc.game_label = game_label
		disc.systemid = systemid
		room.add_child(disc)
		disc.add_to_group("spawned")
		disc.global_transform = seats[i].global_transform
		seats[i].pick_up_object(disc)
	var pdf := manual_path()
	if not pdf.is_empty() and _manual_zone != null:
		var book := BOOK_SCENE.instantiate() as PDFBook
		book.book_height = model.manual_size_m().y
		book.pdf_path = pdf
		room.add_child(book)
		book.add_to_group("spawned")
		book.global_transform = _manual_zone.global_transform
		_manual_zone.pick_up_object(book)
	_update_reach()


# ------------------------------------------------------------------ build
func _model_box() -> AABB:
	var ab := AABB()
	var first := true
	for mi in GameCaseModel.meshes(model.levels[0]):
		var box: AABB = GameCaseModel._local_to(model.levels[0], mi) * mi.get_aabb()
		ab = box if first else ab.merge(box)
		first = false
	return ab


## The body is ONE convex shape at every angle: the back half's box and the lid's (or keep cover's) box at its
## angle, hulled together. Shut it is the case's box; open flat, a slab across both halves; part open, the wedge
## between them. Two boxes in one body lost their contacts with the table (Jolt drops contacts it takes for a
## compound's internal edges): a dropped case sank its back half into the table, an open one tipped onto its lid
## and sank 10 mm (DevTools/cases/case_drop_probe). One hull rests flat every time.
func _build_shapes() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var pivot := model.pivot_m("open")
	var b := _closed_box
	var split := pivot.z if case_family == "jewel" else b.end.z - KEEP_COVER_T
	split = clampf(split, b.position.z + 0.002, b.end.z - 0.001)
	_base_box = AABB(b.position, Vector3(b.size.x, b.size.y, split - b.position.z))
	_lid_box = AABB(Vector3(b.position.x, b.position.y, split), Vector3(b.size.x, b.size.y, b.end.z - split))
	_body_shape = CollisionShape3D.new()
	_body_shape.name = "BodyShape"
	_body_shape.shape = ConvexPolygonShape3D.new()
	add_child(_body_shape)
	_shape_deg = -1.0
	_shape_body(0.0)
	# The desktop ray's target. Shut, the whole case. Open, only the back panel under everything seated on it and a
	# skin on the lid's outside, so the ray reaches a disc, the manual or a card: as one box round the shut case it
	# stopped every ray above them (the owner, 2026-11-21: no disc could be taken with the desktop ray).
	var floor_top := b.end.z
	var c := model.contract()
	for row: Dictionary in c.get("seats", []):
		var parent := str(row.get("parent", row.get("carrier", "")))
		if parent.is_empty() or parent == "<null>" or parent == "Body":
			floor_top = minf(floor_top, float((row["center_mm"] as Array)[2]) * 0.001 - DISC_HALF_T - 0.0005)
	for key in ["card_seat"]:
		var h: Variant = c.get(key)
		if h is Dictionary and str((h as Dictionary).get("parent", "")) in ["", "<null>"]:
			var t := float(((h as Dictionary).get("size_mm", [0, 0, 4.0]) as Array)[2]) * 0.001
			floor_top = minf(floor_top, float(((h as Dictionary)["center_mm"] as Array)[2]) * 0.001 - t * 0.5 - 0.0005)
	floor_top = clampf(floor_top, b.position.z + 0.001, split)
	_pointer_floor = AABB(b.position, Vector3(b.size.x, b.size.y, floor_top - b.position.z))
	_pointer_skin = AABB(Vector3(b.position.x, b.position.y, b.end.z - POINTER_SKIN), Vector3(b.size.x, b.size.y, POINTER_SKIN))
	_pointer_base = get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if _pointer_base != null:
		_pointer_base.shape = BoxShape3D.new()
		_pointer_lid = CollisionShape3D.new()
		_pointer_lid.name = "LidSkin"
		_pointer_lid.shape = BoxShape3D.new()
		(_pointer_lid.shape as BoxShape3D).size = _pointer_skin.size
		_pointer_base.get_parent().add_child(_pointer_lid)
	_pointer_open = true
	_shape_pointer(false, Transform3D.IDENTITY)


## The hull for the lid at `deg`: the back half's eight corners and the lid box's eight, turned about the hinge.
## Rebuilt only when the lid has moved SHAPE_STEP_DEG since the last one.
func _shape_body(deg: float) -> void:
	if _shape_deg >= 0.0 and absf(deg - _shape_deg) < SHAPE_STEP_DEG and (deg > 0.0) == (_shape_deg > 0.0):
		return
	_shape_deg = deg
	var pivot := model.pivot_m("open")
	var turn := Transform3D(Basis(Vector3.UP, -deg_to_rad(deg)), Vector3.ZERO)
	var about := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
	var pts := PackedVector3Array()
	for k in 8:
		pts.append(_base_box.get_endpoint(k))
		pts.append(about * _lid_box.get_endpoint(k))
	(_body_shape.shape as ConvexPolygonShape3D).points = pts
	_shape_pointer(deg > POINTER_OPEN_DEG, about)


## The pointer target: the shut case's box, or open, the back panel under the seats and the lid's outer skin.
func _shape_pointer(open: bool, about: Transform3D) -> void:
	if _pointer_base == null:
		return
	if open != _pointer_open:
		_pointer_open = open
		var box := _pointer_floor if open else _closed_box
		(_pointer_base.shape as BoxShape3D).size = box.size
		_pointer_base.position = box.get_center()
		_pointer_lid.disabled = not open
	if open:
		_pointer_lid.transform = about * Transform3D(Basis.IDENTITY, _pointer_skin.get_center())


## A frame at each hinge's pivot whose local X is the hinge line, so a CaseHinge's angle (rotation.x of its
## target) is the hinge's opening: its -Z the panel lying shut (case +x), its +Y the way it opens (case +z).
func _build_hinges() -> void:
	var levers: Array = []
	var names: Array[String] = []
	for i in model.inner_count():
		names.append("inner%d" % (i + 1))
	names.append("open")
	for which in names:
		var pivot := model.pivot_m(which)
		var reach := maxf(_closed_box.end.x - pivot.x, 0.02)
		levers.append(reach * 0.5)
		var frame := Node3D.new()
		frame.name = "Hinge_%s" % which
		add_child(frame)
		frame.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)), pivot)
		var angle := Node3D.new()
		angle.name = "Angle"
		frame.add_child(angle)
		var hinge := CaseHinge.new()
		hinge.name = "CaseHinge"
		hinge.target = angle
		hinge.min_deg = 0.0
		hinge.max_deg = 180.0
		hinge.engage_radius = 0.05
		var idx := names.find(which)
		hinge.gate = _can_take.bind(idx)
		angle.add_child(hinge)
		# The grab box over the panel's free third, thin through the panel.
		hinge.position = Vector3(0.0, 0.004, -reach * 0.8)
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(_closed_box.size.y * 0.85, 0.016, reach * 0.4)
		col.shape = box
		hinge.add_child(col)
		hinge.place_hint(Vector3(0.0, 0.02, -reach * 0.2))
		_rigs.append([frame, angle, hinge])
		_was_held.append(false)
	sim.configure(levers, open_max_deg(), float(FRICTION.get(case_family, 0.15)),
		float(LATCH_BREAK.get(case_family, 400.0)), float(LATCH_SPEED.get(case_family, 3.5)),
		float(KINETIC.get(case_family, 0.8)))
	if case_family == "keep":
		for i in sim.top():
			sim.set_hinge_friction(i, FLIPPER_FRICTION, 0.8)
		sim.set_living_hinge(KEEP_AJAR_DEG, KEEP_SPRINGBACK_DEG)
	_lid_pivot = model.pivot_m("open")
	for r in _rigs:
		(r[2] as CaseHinge).max_deg = rad_to_deg(sim.open_max)


## How far the lid opens. A jewel case's hinge is near its front, so laid open on a table its lid turns a few degrees
## past flat before it rests on the table beside the back half (else it hangs, and the case tips over onto it).
func open_max_deg() -> float:
	if case_family != "jewel":
		return 180.0
	var pivot := model.pivot_m("open")
	var drop := (pivot.z - _closed_box.position.z) - (_closed_box.end.z - pivot.z)
	var reach := maxf(_closed_box.end.x - pivot.x, 0.02)
	return 180.0 + clampf(rad_to_deg(asin(clampf(drop / reach, 0.0, 0.2))), 0.0, 10.0)


## A hand may take hinge i only when the one above it is open off it (a flip tray under a shut lid may not).
func _can_take(i: int) -> bool:
	if i >= sim.top():
		return true
	return sim.angle_deg(i + 1) - sim.angle_deg(i) >= REACH_DEG


func _build_zones() -> void:
	var c := model.contract()
	var seats: Array = c.get("seats", [])
	for i in model.disc_seat_count():
		var seat := model.disc_seat(i + 1)
		var row: Dictionary = seats[i] if i < seats.size() else {}
		var zone := _zone("DiscZone%d" % (i + 1), seat, "disc", 0.05, _accepts_disc.bind(i))
		_zones.append(zone)
		_popped.append(false)
		_seat_spin.append(0.0)
		zone.has_dropped.connect(_seat_disc.bind(i))
		zone.has_picked_up.connect(func(d: Node3D) -> void: _seat_disc(i, d))
		_build_hub_button(seat, i)
		_seat_carrier.append(_carrier_of(str(row.get("parent", row.get("carrier", "")))))
		var axis: Array = row.get("hub_axis", [0, 0, 1])
		_seat_down.append(float(axis[2]) < 0.0)
	# The PS2 and GameCube cases' molded holder takes that console's memory card (the owner, 2026-11-21): flat on the
	# panel, its label out and reading upright (a card's label is on its +Y face and reads toward its -Z end).
	var card_family := str(CARD_FAMILIES.get(case_variant, ""))
	if model.card_seat() != null and not card_family.is_empty():
		_card_zone = _zone("CardZone", model.card_seat(), "memory_card", 0.05,
			func(obj: Node3D) -> bool: return obj is MemoryCard and (obj as MemoryCard).family == card_family \
				and _lid_open())
		_card_zone.basis = CARD_BASIS.get(case_variant, Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)))
	if model.umd_seat() != null:
		_holder_zone = _zone("UmdZone", model.umd_seat(), "cartridge", 0.05,
			func(obj: Node3D) -> bool: return obj is RetroUMD and _lid_open())
		# Flat in its holder, label out and upright (the seat's +Z is out of the panel; a UMD is thin along its Y):
		# it stood on its edge (the owner, 2026-11-21; trayrefs/psp_umd/open_with_umd_wheelersndealers.jpg).
		_holder_zone.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	# A cover that carries a disc (the five-disc case) has no room for a manual (round 8 F02): its set's paper goes
	# in the outer sleeve.
	var ms := model.manual_seat()
	var cover_disc := seats.any(func(row: Dictionary) -> bool: return str(row.get("parent", "")) == "Cover")
	if ms != null and not cover_disc:
		_manual_root = Node3D.new()
		_manual_root.name = "ManualAnchor"
		ms.add_child(_manual_root)
		_manual_zone = _zone("ManualZone", _manual_root, "book", 0.06,
			func(obj: Node3D) -> bool: return obj is PDFBook and _lid_open())
		_place_manual_zone(model.manual_size_m().x)
		_manual_zone.has_picked_up.connect(func(what: Node3D) -> void:
			if what is PDFBook and not (what as PDFBook).dimensions_changed.is_connected(_on_book_resized):
				(what as PDFBook).dimensions_changed.connect(_on_book_resized.bind(what))
			if what is PDFBook:
				_on_book_resized.call_deferred(what)
				if not (what as PDFBook).dimensions_changed.is_connected(_sync_manual):
					(what as PDFBook).dimensions_changed.connect(_sync_manual)
			_sync_manual.call_deferred())
		_manual_zone.has_dropped.connect(_sync_manual.call_deferred)


func _zone(n: String, parent: Node3D, group: String, reach: float, filter: Callable) -> XRToolsSnapZone:
	var zone := (load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene).instantiate() as XRToolsSnapZone
	zone.name = n
	zone.add_to_group(ScenePersistence.MOD_ZONE_GROUP)
	zone.grab_distance = reach
	zone.snap_require = group
	zone.snap_filter = filter
	parent.add_child(zone)
	zone.has_picked_up.connect(func(what: Node3D) -> void:
		if what is PhysicsBody3D:
			add_collision_exception_with(what)
		_update_reach.call_deferred())
	zone.has_dropped.connect(_update_reach.call_deferred)
	return zone


## The hub's centre is a button (a keep case's PUSH, a jewel case's rosette): pressed through the disc's hole, by a
## fingertip or the desktop pointer, it pops the disc up off the catches (the owner, 2026-11-20). Only with the
## seat open to the hand.
func _build_hub_button(seat: Node3D, i: int) -> void:
	# The hub's cap only (inside the disc's 15 mm hole), and live only while there is a disc on it to pop: as a 7 mm
	# ball it took every desktop click near a disc's middle (InteractionResolver prefers a control just behind what
	# the ray met), so a click meant to lift the disc popped it, and the next did nothing (the owner, 2026-11-21).
	var b := VRButton.new()
	b.name = "HubButton%d" % (i + 1)
	b.state_tint = false
	b.depress_depth = 0.0
	b.trigger_radius = 0.008
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HUB_BUTTON_R
	shape.shape = sphere
	b.add_child(shape)
	seat.add_child(b)
	b.position = Vector3(0.0, 0.0015, 0.0)
	b.button_pressed.connect(pop_disc.bind(i))
	_hub_buttons.append(b)


## Pop the disc on seat i up off its hub: it rides up and tilts on its zone, loose for a hand to lift out.
func pop_disc(i: int) -> bool:
	if i >= _zones.size() or _popped[i] or not _zones[i].picked_up_object is RetroDisc or not _seat_reachable(i):
		return false
	_popped[i] = true
	_zones[i].transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(POP_TILT_DEG)) * Basis(Vector3.UP, _seat_spin[i]),
		Vector3(0.0, POP_LIFT, 0.0))
	_update_reach.call_deferred()
	var ctrl := get_picked_up_by_controller()
	if ctrl != null:
		Haptics.pulse(ctrl, 0.3, 10, LATCH_HAPTIC_KEY)
	return true


func is_popped(i: int) -> bool:
	return i < _popped.size() and _popped[i]


## A disc taken off seat i, or one put on it: back down on the hub. One a hand has just put there keeps the turn
## it was offered at, as the snap preview drew it and as a console's tray seats it (RetroDisc.spin_of); a disc
## the case was spawned or restored with sits square.
func _seat_disc(i: int, disc: Node3D = null) -> void:
	if i < _zones.size():
		_popped[i] = false
		_seat_spin[i] = 0.0
		var d := disc as RetroDisc
		var seat := _zones[i].get_parent() as Node3D
		if d != null and seat != null and d.can_visually_spin() and d.released_by_hand_just_now():
			_seat_spin[i] = RetroDisc.spin_of(Basis.IDENTITY, d.release_basis_in(seat))
		_zones[i].transform = Transform3D(Basis(Vector3.UP, _seat_spin[i]), Vector3.ZERO)
		_update_reach.call_deferred()


## What the case shows of its manual. Seated, a booklet as thin as a real one (MANUAL_T) lies under the clips or the
## lid's tabs: the jewel case's own printed Booklet, or for a keep case a sheet the manual's size wearing the PDF's
## cover. The PDFBook itself is hidden there: drawn as a book (a gap outside each cover, 0.1 mm a page) it was 4-5 mm
## thick and swallowed the clips that hold a real manual in (the owner, 2026-11-21). It stays in its zone, and a hand
## or the desktop ray still takes it; out of the case it shows again and the stand-in goes.
func _sync_manual() -> void:
	if model == null:
		return
	var seated := manual()
	if is_instance_valid(_seated_book) and _seated_book != seated:
		_seated_book.visible = true
		_seated_book = null
	if seated != null:
		seated.visible = false
		_seated_book = seated
	if case_family == "jewel":
		model.show_booklet(seated != null or not _has_manual)
		# Inside the open lid the booklet shows its back: the manual's last page, from the PDF.
		var back := seated.get_node_or_null("BackCover") as MeshInstance3D if seated != null else null
		model.set_booklet_back(back.get_active_material(0) if back != null else null)
		return
	if seated == null:
		if _manual_proxy != null:
			_manual_proxy.visible = false
		return
	if _manual_proxy == null:
		_manual_proxy = _build_manual_proxy()
	_manual_proxy.visible = true
	(_manual_proxy.get_node("Front") as MeshInstance3D).material_override = _manual_front(seated)


## The manual's front cover, out of the case (the owner, 2026-11-21: "the manual needs to have the front face out").
## A manual scanned as two-page spreads opens on its cover sheet, back cover on the left and front on the right: read
## in half pages, its first is the back, so the front is its second. Otherwise the book's own cover. Until that page
## has rendered, the paper, and a retry.
func _manual_front(book: PDFBook) -> Material:
	if not book.half_page_mode:
		var cover := book.get_node_or_null("Cover") as MeshInstance3D
		return cover.get_active_material(0) if cover != null else null
	var tex := book._get_page_texture(1)
	if book._texture_cache.has(1):
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.roughness = 0.8
		return m
	if _front_tries < 40 and is_inside_tree():
		_front_tries += 1
		get_tree().create_timer(0.25).timeout.connect(_sync_manual)
	return null


## A keep case's seated manual: a sheet MANUAL_T thick on the manual seat, its front (the seat's +Z, into the case)
## a quad for the cover page.
func _build_manual_proxy() -> Node3D:
	var size := model.manual_size_m()
	var root := Node3D.new()
	root.name = "ManualProxy"
	model.manual_seat().add_child(root)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.92, 0.89)
	paper.roughness = 0.85
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, MANUAL_T)
	sheet.mesh = box
	sheet.material_override = paper
	root.add_child(sheet)
	var front := MeshInstance3D.new()
	front.name = "Front"
	var quad := QuadMesh.new()
	quad.size = size
	front.mesh = quad
	front.material_override = paper
	front.position = Vector3(0.0, 0.0, MANUAL_T * 0.5 + 0.0001)
	root.add_child(front)
	for mi: MeshInstance3D in [sheet, front]:
		mi.add_to_group("outline_exclude")
	return root


## A closed book's origin is its spine; its cover lies to +x. The zone sits half the book's width toward the seat's
## spine side so the cover lands on the seat, and the book's back lies flat against the panel it sits under (the
## jewel lid, out of the seat's front; the keep case's cover, behind it): drawn thicker than a real booklet (its
## pages plus a gap outside each cover), a book centred on the seat poked out through the front (the owner,
## 2026-11-21). Its extra thickness goes into the case, where the shut case hides it.
func _place_manual_zone(book_width: float, half_thick := 0.0) -> void:
	if _manual_zone == null:
		return
	var z := (MANUAL_WALL - half_thick) if case_family == "jewel" else (half_thick - MANUAL_WALL)
	_manual_zone.position = Vector3(-book_width * 0.5, 0.0, z)


func _on_book_resized(book: PDFBook) -> void:
	if not is_instance_valid(book) or _manual_zone == null or _manual_zone.picked_up_object != book \
			or book.page_size().x <= 0.0:
		return
	# A manual scanned as two-page spreads (ScreenScraper has many) is twice the booklet's width: read it as single
	# pages, as the book's own Half Pages option does.
	if not book.half_page_mode and book.page_size().x > model.manual_size_m().x * 1.4:
		book.half_page_mode = true
		return
	var span: Vector2 = book._drawn_z_span()
	_place_manual_zone(book.page_size().x, (span.y - span.x) * 0.5)


func _carrier_of(parent: String) -> int:
	if parent.is_empty() or parent == "<null>" or parent == "Body":
		return -1
	if parent == "Lid" or parent == "Cover":
		return sim.top()
	var n := parent.trim_prefix("FlipTray").trim_prefix("Leaf")
	return int(n) - 1 if n.is_valid_int() else -1


func _accepts_disc(obj: Node3D, seat: int) -> bool:
	return obj is RetroDisc and not obj is RetroUMD and _seat_reachable(seat)


func _lid_open() -> bool:
	return sim.angle_deg(sim.top()) >= REACH_DEG


## The panel over a seat (the next one up for a hub facing out, the one below for a hub facing back) is turned far
## enough off it for a hand to get at the disc.
func _seat_reachable(seat: int) -> bool:
	var c := _seat_carrier[seat]
	var here := 0.0 if c < 0 else sim.angle_deg(c)
	if _seat_down[seat]:
		var below := 0.0 if c <= 0 else sim.angle_deg(c - 1)
		return here - below >= REACH_DEG
	var above := sim.angle_deg(c + 1) if c + 1 <= sim.top() else 180.0
	return above - here >= REACH_DEG


## Discs (and the manual) under a shut panel cannot be taken, and a seat that cannot be reached takes nothing.
func _update_reach() -> void:
	for i in _zones.size():
		var ok := _seat_reachable(i)
		var obj := _zones[i].picked_up_object as XRToolsPickable
		if obj != null:
			obj.enabled = ok
		if i < _hub_buttons.size() and _hub_buttons[i].is_inside_tree():
			_hub_buttons[i].set_active(ok and obj is RetroDisc and not _popped[i])
	var open := _lid_open()
	for z: XRToolsSnapZone in [_holder_zone, _manual_zone, _card_zone]:
		if z != null and z.picked_up_object is XRToolsPickable:
			(z.picked_up_object as XRToolsPickable).enabled = open


# ------------------------------------------------------------------ art
func _load_art() -> void:
	var path := box_art_path(systemid, rom_path)
	if path.is_empty():
		return
	var img := await decode_image(get_tree(), path)
	if img != null and is_inside_tree():
		_apply_art(img)


func _apply_art(img: Image) -> void:
	if not img.has_mipmaps():
		img.generate_mipmaps()
	model.apply_box_texture(ImageTexture.create_from_image(img))


## The box-texture file for a game, or "" (resolved on the main thread: RomLibrary's folders are not threadsafe).
static func box_art_path(sys: String, rom: String) -> String:
	if sys.is_empty() or rom.is_empty():
		return ""
	var base := RomLibrary.content_stem(rom)
	for dir in RomLibrary.rom_dirs_for_system(sys):
		for ext in [".png", ".jpg", ".jpeg", ".webp"]:
			var p := dir.path_join("media").path_join("box").path_join(base + ext)
			if FileAccess.file_exists(p):
				return p
	return ""


## Decode an image (with its mipmaps) on a worker thread.
static func decode_image(tree: SceneTree, path: String) -> Image:
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void:
		var img := Image.new()
		if img.load(path) == OK:
			img.generate_mipmaps()
			out[0] = img)
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return out[0]


# ------------------------------------------------------------------ hinges
func _physics_process(delta: float) -> void:
	if delta <= 0.0 or model == null:
		return
	_track_accel(delta)
	var g_world := Vector3(0.0, -CaseHingeSim.G, 0.0) - _accel
	var g := global_basis.orthonormalized().inverse() * g_world
	var moved := false
	for i in _rigs.size():
		var hinge := _rigs[i][2] as CaseHinge
		var held := hinge.is_held()
		if held:
			sim.set_held(i, true)
			sim.set_held_angle_deg(i, hinge.get_rotation_deg(), delta)
			moved = true
		elif _was_held[i]:
			sim.set_held(i, false, hinge.release_speed_deg)
			moved = true
		elif absf(hinge.get_rotation_deg() - sim.angle_deg(i)) > 0.05:
			sim.set_angle_deg(i, hinge.get_rotation_deg())   # a restore or a peer put it there
			if i == sim.top() and hinge.get_rotation_deg() <= 0.05:
				sim.latched = true                           # shut there, it is caught here too
			moved = true
		_was_held[i] = held
	var spin := _spin if absf(_spin) > SPIN_QUIET else 0.0
	if moved or not sim.settled(g, spin):
		sim.step(delta, g, spin)
		_apply_angles()
	if sim.clicked:
		sim.clicked = false
		var ctrl := get_picked_up_by_controller()
		if ctrl != null:
			Haptics.pulse(ctrl, 0.45, 12, LATCH_HAPTIC_KEY)
	_sound(delta)


## The latch's snap as it catches or lets go, and the hinge's creak as the lid travels.
func _sound(delta: float) -> void:
	_sfx_ticks += 1
	var lid := sim.angle_deg(sim.top())
	if _sfx_ticks > SFX_QUIET_TICKS:
		if sim.latched != _sfx_latched:
			_play_sfx("snap", "close" if sim.latched else "open", 0.6)
			_sfx_travel = 0.0
			_sfx_next = 15.0
		elif sim.knocked >= SFX_KNOCK:
			_play_sfx("snap", "stop", clampf(sim.knocked / SFX_SLAM, 0.12, 0.8))
		if not sim.latched and sim.latched == _sfx_latched:
			_sfx_travel += absf(lid - _sfx_lid)
			if _sfx_travel >= _sfx_next:
				_sfx_travel = 0.0
				_sfx_next = SFX_TURN_DEG * randf_range(0.7, 1.4)
				var speed := absf(lid - _sfx_lid) / delta
				_play_sfx("turn", str(SFX_TURN.get(case_family, "creak")), clampf(speed / 600.0, 0.2, 0.45))
	sim.knocked = 0.0
	_sfx_latched = sim.latched
	_sfx_lid = lid


func _play_sfx(voice: String, kind: String, volume: float) -> void:
	var key := "%s_%s" % [case_family, kind]
	if not _sfx_clips.has(key):
		var found: Array = []
		var n := 1
		while ResourceLoader.exists("%s%s_%02d.wav" % [SFX_DIR, key, n]):
			var frames := PcmClip.load_frames("%s%s_%02d.wav" % [SFX_DIR, key, n])
			if not frames.is_empty():
				found.append(frames)
			n += 1
		_sfx_clips[key] = found
	var clips: Array = _sfx_clips[key]
	if clips.is_empty():
		return
	var v := _sfx_voices.get(voice) as PcmOneShot
	if v == null:
		v = PcmOneShot.new()
		v.name = "Sfx_%s" % voice
		v.unit_size = 0.6
		v.max_distance = 3.0
		add_child(v)
		_sfx_voices[voice] = v
	v.volume = volume
	v.play(clips[randi() % clips.size()])


## What the lid feels of the case's own motion: the hinge line's acceleration (so a turn about the spine adds no
## false pull), and that turn speeding up.
func _track_accel(delta: float) -> void:
	var rot := global_basis.orthonormalized().get_rotation_quaternion()
	if _has_rot:
		var d := _prev_rot.inverse() * rot
		var turn := 2.0 * d.y * signf(d.w) / delta       # about the case's +y, the hinge line
		var a_turn := (turn - _turn) / delta
		_turn = turn
		_spin = lerpf(_spin, a_turn if absf(a_turn) < SPIN_CUT else 0.0, 0.35)
	_prev_rot = rot
	_has_rot = true
	_pos_hist.push_front(global_transform * _lid_pivot)
	if _pos_hist.size() > 3:
		_pos_hist.resize(3)
	if _pos_hist.size() < 3:
		return
	var a := (_pos_hist[0] - 2.0 * _pos_hist[1] + _pos_hist[2]) / (delta * delta)
	# A grab driver's first frame, a teleport, a restore: not a jolt the lid should feel.
	if a.length() > 60.0:
		a = Vector3.ZERO
	_accel = _accel.lerp(a, 0.35)


func _apply_angles() -> void:
	var inner: Array = []
	for i in sim.count - 1:
		inner.append(sim.angle_deg(i))
	model.set_angles(sim.angle_deg(sim.top()), inner)
	for i in _rigs.size():
		var hinge := _rigs[i][2] as CaseHinge
		if not hinge.is_held():
			hinge.set_angle_quiet(sim.angle_deg(i))
	_shape_body(sim.angle_deg(sim.top()))
	_carry_contents()
	_update_reach()


## Whatever the zones hold goes where they now are, at once: a hinge posed outside the physics step (a restore, a
## probe) would otherwise leave it there until the drivers' next tick.
func _carry_contents() -> void:
	for z: XRToolsSnapZone in _zones + [_holder_zone, _card_zone, _manual_zone]:
		if z != null and z.picked_up_object is Node3D and z.is_inside_tree():
			(z.picked_up_object as Node3D).global_transform = z.global_transform


# ------------------------------------------------------------------ state
func lid_deg() -> float:
	return sim.angle_deg(sim.top())


func is_latched() -> bool:
	return sim.latched


## The discs in the case, in seat order (empty seats left out).
func discs() -> Array[RetroCartridge]:
	var out: Array[RetroCartridge] = []
	for z: XRToolsSnapZone in _zones + ([_holder_zone] if _holder_zone else []):
		if z != null and z.picked_up_object is RetroCartridge:
			out.append(z.picked_up_object as RetroCartridge)
	return out


func manual() -> PDFBook:
	return _manual_zone.picked_up_object as PDFBook if _manual_zone != null else null


## The memory card holder (PS2, GameCube), or null for a case without one.
func card_zone() -> XRToolsSnapZone:
	return _card_zone


func memory_card() -> MemoryCard:
	return _card_zone.picked_up_object as MemoryCard if _card_zone != null else null


func disc_zone(i: int) -> XRToolsSnapZone:
	return _zones[i] if i < _zones.size() else null


func hinge(i: int) -> CaseHinge:
	return _rigs[i][2] as CaseHinge if i < _rigs.size() else null
