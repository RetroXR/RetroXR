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
const SFX_TURN_DEG := 92.0
## Degrees per second. A slow hand turn hardly excites the hinge or sleeve.
const SFX_TURN_MIN_SPEED := 55.0
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
## The lid against the world: its box, this much smaller all round (what it rests on does not count as in its
## way), is tested where it stands, and something in it turns the lid to the nearest clear angle, either way, as
## far as this in a tick. Never past its stops. A panel is that thick to a fingertip.
const LID_SKIN := 0.0015
const LID_YIELD_DEG := 14.0
## A half resting against the world is asked this far on (deg) whether the world is still there.
const WORLD_REST_PROBE_DEG := 1.5
const PANEL_POKE_T := 0.004
## A grip on an open case nearer its lid than its base, and within this of the lid, has the case by its lid.
const LID_GRIP_REACH := 0.12
## Where a grip takes the manual out (XRToolsSnapZone.reach_box): the booklet itself and this far above it into the
## open case, this far beside it. Never behind it: that is the lid (the owner, 2026-11-22).
const MANUAL_REACH_UP := 0.06
## A fingertip within this of the booklet's face is on the paper: it presses the lid the booklet lies in.
const MANUAL_PRESS_OVER := 0.004
## A hand this far behind the panel a seat is on is not reaching for what is on it.
const SEAT_BEHIND := 0.01
const MANUAL_REACH_SIDE := 0.01
## The rim that lights round the booklet when a grip would take the manual: this far outside it, this wide.
const MANUAL_RIM_GAP := 0.003
const MANUAL_RIM_W := 0.002
const MANUAL_HAPTIC_KEY := &"game_case_manual"
## A flip tray or a flipper is the trigger's this far off its own slab, on a face that is in the open.
const TRAY_TRIGGER_REACH := 0.02
## A case a save puts back has its discs back within this of being made; they are looked at this long after the
## last of them (_adopt_real_layout).
const OLD_LAYOUT_WINDOW_MS := 20000
const OLD_LAYOUT_SETTLE := 0.6
## A manual scanned as two-page spreads (is_spread): its page is wider than tall by this, and this much wider for
## its height than the booklet's own page (two of them side by side are twice; one is once).
const SPREAD_MIN_SHAPE := 1.05
const SPREAD_OVER_SEAT := 1.4
## A jewel case's back, side and front as the scraper files them, each in the folder of its kind
## (ScreenscraperClient.PANEL_MEDIA). The group a case is told through when one lands, and the group it asks
## through (the spawn menu, which owns the scraper).
const PANEL_KINDS := ScreenscraperClient.PANEL_MEDIA
const PANEL_GROUP := &"game_case_art"
const PANEL_LISTENERS := &"case_art_listener"
## Games whose panels a case asked for before anything was there to fetch them: rom path -> system (as
## ArcadeAttract.pending_media). And every game asked for this session, found or not: once each.
static var pending_art: Dictionary = {}
static var _asked_art: Dictionary = {}
## A case let go a little way into what it should lie on is lifted out onto it (HeldObjectPhysics.lift_out): no
## farther than this, and not one moving faster than this (thrown, not put down).
const LIFT_MAX := 0.06
## A pushed back half let go still swinging is given this long to come to rest before the case is a body again.
const BASE_PUSH_SETTLE_MS := 3000
const LIFT_MAX_SPEED := 1.0
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
var _seat_square: Array[float] = []              # per disc seat: the turn at which a disc's label reads upright
var _seat_z: Array[float] = []                   # per disc seat: how far toward the front it lies, the case shut (m)
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
var _lid_probe: BoxShape3D
var _lid_query: PhysicsShapeQueryParameters3D
var _lid_yield := -1.0                           # the way the lid last gave way (+1 opening), for a tie
var _lid_node: Node3D                            # the model's lid (a keep case's cover), and where it lies shut
var _lid_rest := Transform3D()
var _lid_grab: Grab                              # the hand that has the case by its lid ...
var _lid_hand := Transform3D()                   # ... where it is in the lid's own frame
var _base_hinge: CaseHinge                       # the lid's hinge again, by its other half: the base's handle
var _base_probe: BoxShape3D
var _top_grip: CaseHinge                         # which of its two handles a hand last had the lid's hinge by
var _base_push := false                          # nothing holds the case and its BACK is pushed: the lid is the still half ...
var _base_anchor := Transform3D()                # ... where the lid stays, in the world
var _base_unfreeze := false                      # ... the body was loose before, and is again after
var _base_push_until := 0                        # ... when to stop waiting for the back to come to rest (msec)
var _manual_in := -1.0                           # which way is into the case along the manual seat's z
## The manual lies on a tray, not under the lid's tabs (the North American fat case: in the black tray's front
## recess, on its disc). `_manual_on` is that tray's hinge. The lid's own Booklet is then the front sheet, there
## whatever the manual does.
var _manual_loose := false
var _manual_on := -1
## The menu filled this case itself (spawn_contents): its discs are where the real case has them. One a save put
## back is looked at once, after its discs have come back to it (_adopt_real_layout).
var _fresh := false
var _layout_done := false
var _layout_serial := 0
var _born_msec := 0
var _manual_rim: Node3D
var _lid_handle_at := Vector3.ZERO               # the lid's handle in its rig, before _follow_lid moves it
var _hand_rot := Quaternion.IDENTITY
var _hand_has := false
var _hand_turn := 0.0
var _hand_spin := 0.0
static var _sfx_clips: Dictionary = {}           # "<family>_<kind>" -> Array of PackedVector2Array
var _sfx_voices := {}                            # "snap" / "turn" -> PcmOneShot, made at the first sound
var _sfx_ticks := 0
var _sfx_latched := true
var _sfx_lid := 0.0
var _sfx_travel := 0.0
var _sfx_next := SFX_TURN_DEG
var _prev_rot := Quaternion.IDENTITY
var _has_rot := false
var _turn := 0.0
var _spin := 0.0


func _ready() -> void:
	super()
	add_to_group(GROUP)
	add_to_group(PANEL_GROUP)
	_born_msec = Time.get_ticks_msec()
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
	_lid_rest = model.transform * model.lid_transform_at(0.0)
	_build_shapes()
	_build_hinges()
	_build_zones()
	dropped.connect(_on_let_go)
	_has_manual = not manual_path().is_empty()
	_sync_manual()
	_apply_angles()
	if box_image != null:
		_apply_art(box_image)
	elif not rom_path.is_empty():
		_load_art.call_deferred()
	_want_panels.call_deferred()


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
	_fresh = true
	for step: Callable in _content_steps(disc_paths):
		step.call()
	_update_reach()


## The same, a thing a frame: each disc, then the manual. All of them built in the frame the case appeared was a
## long frame on a headset (the owner, 2026-11-23: "the game freezes for a while until it spawns in"); a case's
## lid is shut for the handful of frames it takes.
func spawn_contents_over_frames(disc_paths: PackedStringArray) -> void:
	_fresh = true
	for step: Callable in _content_steps(disc_paths):
		await get_tree().process_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
		step.call()
	_update_reach()


## What fills a new case, one call each: a disc onto its seat for every disc on this device, and the manual.
func _content_steps(disc_paths: PackedStringArray) -> Array[Callable]:
	var steps: Array[Callable] = []
	var umd := systemid == "psp" and _holder_zone != null
	var seats: Array[XRToolsSnapZone] = _zones
	if umd:
		seats = [_holder_zone] as Array[XRToolsSnapZone]
	var order := disc_seat_order(disc_paths.size())
	for i in mini(disc_paths.size(), seats.size()):
		if disc_paths[i].is_empty():
			continue                                     # a disc of the set that is not on this device
		steps.append(_spawn_disc.bind(disc_paths[i], seats[i if umd else order[i]], umd))
	if not manual_path().is_empty() and _manual_zone != null:
		steps.append(_spawn_manual)
	return steps


func _spawn_disc(disc_path: String, seat: XRToolsSnapZone, umd: bool) -> void:
	if not is_instance_valid(seat) or is_instance_valid(seat.picked_up_object):
		return
	var disc := (UMD_SCENE if umd else DISC_SCENE).instantiate() as RetroCartridge
	disc.rom_path = disc_path
	disc.game_label = game_label
	disc.systemid = systemid
	get_parent().add_child(disc)
	disc.add_to_group("spawned")
	disc.global_transform = seat.global_transform
	seat.pick_up_object(disc)


func _spawn_manual() -> void:
	var pdf := manual_path()
	if pdf.is_empty() or _manual_zone == null or is_instance_valid(_manual_zone.picked_up_object):
		return
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.book_height = model.manual_size_m().y
	book.pdf_path = pdf
	get_parent().add_child(book)
	book.add_to_group("spawned")
	book.global_transform = _manual_zone.global_transform
	_manual_zone.pick_up_object(book)


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
	# Where the model draws the lid, not one turn about the hinge line: a keep case's cover turns on its spine's
	# two creases, and by a single turn its hull and its pointer skin stood up to a centimetre off the cover drawn.
	var about := _swing_at(deg)
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
		if which != "open":                              # a tray: anywhere on it, from a face in the open
			hinge.panel_reach = TRAY_TRIGGER_REACH
			hinge.quiet_at = _tray_quiet.bind(idx)
		angle.add_child(hinge)
		# The grab box over the panel's free third, thin through the panel. A flip tray or a flipper is worked from
		# either face, so its box stands a centimetre out of each, about the tray as it is DRAWN (_panel_slab): a
		# jewel case's flip tray turns on the lid's own hinge line and hangs well under it, and laid on that line
		# its handle stood beside the tray, clear of its far face (the owner, 2026-11-22, twice, off the regions
		# probe's pictures). The lid's starts at the lid's own inside face and stands a centimetre out of its
		# outside: reaching 4 mm into the case it stood in FRONT of the manual lying in the lid, and the desktop's
		# click on the booklet's outer half took the lid.
		var grab_y := 0.0
		var grab_t := 0.024
		var slab := Vector2(INF, -INF)
		if which == "open":
			var inside := _lid_box.position.z - pivot.z
			var outside := _lid_box.end.z - pivot.z + 0.010
			grab_y = (inside + outside) * 0.5
			grab_t = outside - inside
		else:
			slab = _panel_slab(("FlipTray%d" if case_family == "jewel" else "Leaf%d") % (idx + 1), slab_from_x(pivot.x, reach))
			if slab.x < slab.y:
				grab_y = (slab.x + slab.y) * 0.5 - pivot.z
				grab_t = (slab.y - slab.x) + 0.020
		hinge.position = Vector3(0.0, grab_y, -reach * 0.8)
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(_closed_box.size.y * 0.85, grab_t, reach * 0.4)
		col.shape = box
		hinge.add_child(col)
		hinge.place_hint(Vector3(0.0, 0.024 - grab_y, -reach * 0.2))
		# A bare fingertip pushes the panel from either face, the whole panel's (the door's rule: pushed, never
		# pulled). A shape for the fingertip's geometry only: disabled, it stops no ray on its way to a disc.
		var to_frame := frame.transform.affine_inverse()
		var mid := Vector3(0.0, 0.0, -reach * 0.5)
		var across := Vector3(_closed_box.size.y * 0.95, PANEL_POKE_T, reach)
		if which == "open":                              # the lid's own box: its outside and its inside
			mid = to_frame * _lid_box.get_center()
			across = Vector3(_lid_box.size.y * 0.95, maxf(_lid_box.size.z, PANEL_POKE_T), _lid_box.size.x)
		elif slab.x < slab.y:                            # a tray's own two faces, its discs on
			mid = Vector3(0.0, grab_y, -reach * 0.5)
			across = Vector3(_closed_box.size.y * 0.95, maxf(slab.y - slab.x, PANEL_POKE_T), reach)
		var panel := CollisionShape3D.new()
		panel.name = "PokePanel"
		var pbox := BoxShape3D.new()
		pbox.size = across
		panel.shape = pbox
		panel.disabled = true
		panel.set_meta(&"poke_surface", true)
		hinge.add_child(panel)
		panel.position = mid - hinge.position
		hinge.poke_torque_faces = VRHinge.FACE_Y_NEG | VRHinge.FACE_Y_POS
		hinge.poke_push_only = true
		_rigs.append([frame, angle, hinge])
		_was_held.append(false)
	sim.configure(levers, open_max_deg(), float(FRICTION.get(case_family, 0.15)),
		float(LATCH_BREAK.get(case_family, 400.0)), float(LATCH_SPEED.get(case_family, 3.5)),
		float(KINETIC.get(case_family, 0.8)))
	if case_family == "keep":
		for i in sim.top():
			sim.set_hinge_friction(i, FLIPPER_FRICTION, 0.8)
		sim.set_living_hinge(KEEP_AJAR_DEG, KEEP_SPRINGBACK_DEG)
		# Its flippers turn like pages, in the sim as in the model: one rule for what is drawn, held and swung.
		sim.set_page_rule(GameCaseModel.LEAF_SPREAD, GameCaseModel.LEAF_STAND)
	_lid_pivot = model.pivot_m("open")
	sim.base_lever = float(levers[levers.size() - 1])
	_lid_node = model.levels[0].find_child("Lid" if case_family == "jewel" else "Cover", true, false) as Node3D \
		if not model.levels.is_empty() else null
	for i in _rigs.size():                               # a flipper under another stops where the sim stops it
		(_rigs[i][2] as CaseHinge).max_deg = rad_to_deg(sim.stop(i))
	var top_rig: Array = _rigs[_rigs.size() - 1]
	(top_rig[2] as CaseHinge).quiet_at = _lid_quiet
	(top_rig[2] as CaseHinge).push_quiet_at = _lid_push_quiet
	(top_rig[2] as CaseHinge).cede_at = _tray_has
	(top_rig[2] as CaseHinge).face_gate = _lid_face_free
	_lid_handle_at = (top_rig[2] as Node3D).position
	# The same hinge from the lid's side, for a case held by its lid (_lid_grab). There the lid is the still half
	# and the base the one that turns, and VRHinge reads a hand in the frame of its target's parent: by the lid's
	# own handle a still fingertip read as moving, every frame, as the base turned under it (the owner,
	# 2026-11-22: pressing the held lid made the other flap creep, and the flap itself could not be pressed).
	# BaseFrame rides the lid, a half turn about its Z; BaseAngle under it turns by the lid's own angle, which
	# brings it back onto the base for good (Rx(t) * Rz(pi) * Rx(t) = Rz(pi)). So this handle's angle IS the
	# hinge's, same sign and range, and the base follows a hand one for one.
	var reach_o := maxf(_closed_box.end.x - _lid_pivot.x, 0.02)
	var half_turn := Transform3D(Basis(Vector3.BACK, PI), Vector3.ZERO)
	var base_frame := Node3D.new()
	base_frame.name = "BaseFrame"
	base_frame.transform = half_turn
	(top_rig[1] as Node3D).add_child(base_frame)
	var base_angle := Node3D.new()
	base_angle.name = "BaseAngle"
	base_frame.add_child(base_angle)
	_base_hinge = CaseHinge.new()
	_base_hinge.name = "BaseHinge"
	_base_hinge.target = base_angle
	_base_hinge.min_deg = 0.0
	_base_hinge.max_deg = rad_to_deg(sim.open_max)
	_base_hinge.engage_radius = 0.05
	_base_hinge.gate = func() -> bool: return _lid_grab != null or _base_free()
	_base_hinge.trigger_gate = func() -> bool: return _lid_grab != null
	_base_hinge.quiet_at = _base_quiet
	_base_hinge.face_gate = _base_face_free
	base_angle.add_child(_base_hinge)
	# In BaseAngle's frame the base lies along -Z from the hinge, as the lid does in its own, +Y out of its back.
	var base_mid := half_turn * ((top_rig[0] as Node3D).transform.affine_inverse() * _base_box.get_center())
	_base_hinge.position = Vector3(0.0, base_mid.y, -reach_o * 0.8)
	# The trigger's box at the base's opening edge. Disabled: VR latches on the reach round the handle and the
	# hint is geometry, and a live box would stand in front of the discs for the desktop ray.
	var base_grab := CollisionShape3D.new()
	base_grab.name = "CollisionShape3D"
	var base_grab_box := BoxShape3D.new()
	base_grab_box.size = Vector3(_closed_box.size.y * 0.85, 0.016, reach_o * 0.4)
	base_grab.shape = base_grab_box
	base_grab.disabled = true
	_base_hinge.add_child(base_grab)
	_base_hinge.place_hint(Vector3(0.0, _base_box.size.z * 0.5 + 0.02, -reach_o * 0.2))
	var base_panel := CollisionShape3D.new()
	base_panel.name = "PokePanel"
	var base_panel_box := BoxShape3D.new()
	base_panel_box.size = Vector3(_base_box.size.y * 0.95, maxf(_base_box.size.z, PANEL_POKE_T), _base_box.size.x)
	base_panel.shape = base_panel_box
	base_panel.disabled = true
	base_panel.set_meta(&"poke_surface", true)
	_base_hinge.add_child(base_panel)
	base_panel.position = base_mid - _base_hinge.position
	_base_hinge.poke_torque_faces = VRHinge.FACE_Y_NEG | VRHinge.FACE_Y_POS
	_base_hinge.poke_push_only = true


## An inner panel's two faces along the case's z, lying shut: its free half as the model draws it (from `from_x`
## out, clear of the arms that reach up to its hinge line) with the discs it carries. (lo, hi); lo > hi when the
## model has no such panel.
func _panel_slab(node_name: String, from_x: float) -> Vector2:
	# The panel's own faces from the baked table; from its mesh only when the table has no such row.
	var own := GameCaseModel.baked_slab(case_family, case_variant, node_name, from_x)
	if own.x > own.y:
		own = _panel_mesh_slab(node_name, from_x)
	var lo := own.x
	var hi := own.y
	for row: Dictionary in model.contract().get("seats", []):
		if str(row.get("parent", row.get("carrier", ""))) != node_name:
			continue
		var z := float((row["center_mm"] as Array)[2]) * 0.001
		lo = minf(lo, z - DISC_HALF_T)
		hi = maxf(hi, z + DISC_HALF_T)
	return Vector2(lo, hi)


## Where an inner panel's free half begins: halfway out from its hinge line.
static func slab_from_x(pivot_x: float, reach: float) -> float:
	return pivot_x + reach * 0.5


## The same faces read off the panel's mesh: what the table is baked from and checked against. Not for a build in
## play (GameCaseModel.PANEL_SLABS says why).
func _panel_mesh_slab(node_name: String, from_x: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var node := model.levels[0].find_child(node_name, true, false) as Node3D if not model.levels.is_empty() else null
	if node != null:
		var parts: Array[MeshInstance3D] = GameCaseModel.meshes(node)
		if node is MeshInstance3D:
			parts.append(node as MeshInstance3D)
		for mi in parts:
			if mi.mesh == null:
				continue
			var at := GameCaseModel._local_to(model.levels[0], mi)
			for s in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					var p := at * v
					if p.x >= from_x:
						lo = minf(lo, p.z)
						hi = maxf(hi, p.z)
	return Vector2(lo, hi)


## Each inner panel of this case: [node name, where its free half begins] (what the table is keyed and baked by).
func inner_panels() -> Array:
	var out: Array = []
	for i in model.inner_count():
		var pivot := model.pivot_m("inner%d" % (i + 1))
		out.append([("FlipTray%d" if case_family == "jewel" else "Leaf%d") % (i + 1),
			slab_from_x(pivot.x, maxf(_closed_box.end.x - pivot.x, 0.02))])
	return out


## How far the lid opens. A jewel case's hinge is near its front, so laid open on a table its lid turns a few degrees
## past flat before it rests on the table beside the back half (else it hangs, and the case tips over onto it).
func open_max_deg() -> float:
	if case_family != "jewel":
		return 180.0
	var pivot := model.pivot_m("open")
	var drop := (pivot.z - _closed_box.position.z) - (_closed_box.end.z - pivot.z)
	var reach := maxf(_closed_box.end.x - pivot.x, 0.02)
	return 180.0 + clampf(rad_to_deg(asin(clampf(drop / reach, 0.0, 0.2))), 0.0, 10.0)


## A hand may take hinge i only when one of its faces is in the open: the panel above stands off it, or it stands
## off the one below (a flip tray under a shut lid may not). The second was missing: a tray turned over onto the
## open lid could not be taken back (a probe, 2026-11-22, after the owner's "I can't easily grab the middle flap").
func _can_take(i: int) -> bool:
	if i >= sim.top():
		return _lid_grab == null                         # held by its lid, the hinge is worked by the base's handle
	var here := sim.angle_deg(i)
	var below := sim.angle_deg(i - 1) if i > 0 else 0.0
	return sim.angle_deg(i + 1) - here >= REACH_DEG or here - below >= REACH_DEG


## A tray is not a hand's from behind whatever lies on it: a point off its upper face with the panel above down on
## it is that panel's, one off its under face with the tray down on what is below is that one's.
func _tray_quiet(at: Vector3, i: int) -> bool:
	var panel := hinge(i).get_node_or_null("PokePanel") as CollisionShape3D
	if panel == null or not panel.shape is BoxShape3D:
		return false
	var y := (panel.global_transform.affine_inverse() * at).y
	var half := (panel.shape as BoxShape3D).size.y * 0.5
	var here := sim.angle_deg(i)
	if y > half:
		return sim.angle_deg(i + 1) - here < REACH_DEG
	if y < -half:
		return here - (sim.angle_deg(i - 1) if i > 0 else 0.0) < REACH_DEG
	return false


## A shut lid's inside is not a fingertip's. A hand passes through the case in VR: a finger come up through the
## base met the lid's inner face from behind and pushed the shut lid open from within (the owner, 2026-11-23).
## The lid's inside (its panel's -Y) is pushed only with the lid far enough off the panel under it for a hand to
## be in there, the angle a tray's under face asks (_tray_quiet). Its outside is pushed at any angle.
func _lid_face_free(face: int) -> bool:
	var top := sim.top()
	return face != VRHinge.FACE_Y_NEG or sim.angle_deg(top) - (sim.angle_deg(top - 1) if top > 0 else 0.0) >= REACH_DEG


## The same for the base of a case held by its lid: its inside, with the panel next to it turned off it.
func _base_face_free(face: int) -> bool:
	return face != VRHinge.FACE_Y_NEG or sim.angle_deg(0) >= REACH_DEG


## Whether a point is on an inner tray a hand may take there: the lid's handle leaves the trigger to it.
func _tray_has(at: Vector3) -> bool:
	for i in sim.top():
		if _can_take(i) and hinge(i).by_panel(at) and not _tray_quiet(at, i):
			return true
	return false


func _layout_soon() -> void:
	_layout_serial += 1
	var mine := _layout_serial
	await get_tree().create_timer(OLD_LAYOUT_SETTLE).timeout
	if mine == _layout_serial and not _fresh and not _layout_done and is_inside_tree():
		_adopt_real_layout()


## A case put back by a save made before the discs went where the real case has them takes the real layout. Until
## 2026-11-22 every case was filled disc 1 on the back and so on up; that day's first builds filled front to back
## with no seat skipped, a disc under the fat case's manual: a three-disc Final Fantasy VII came back to its room
## with disc 2 under its manual and nothing in the rear cover, and stayed so however right a new one was (the
## owner, twice). Only an arrangement that IS one of those two fills is changed: discs a player has moved about
## stay where they were put. Once a case; never on a netplay client (the host's layout is the room's).
func _adopt_real_layout() -> void:
	_layout_done = true
	if _zones.size() < 2 or NetworkManager.is_client():
		return
	var on: Array = []                                   # [disc number, seat, disc]
	var total := 0
	for i in _zones.size():
		var d := _held(_zones[i]) as RetroDisc
		if d == null:
			continue
		var n := MenuIcons.disc_number(d.rom_path.get_file())
		if n < 1 or n > _zones.size():
			return                                       # not a numbered disc of a set: all left alone
		on.append([n, i, d])
		total = maxi(total, n)
	if on.is_empty():
		return
	total = clampi(maxi(total, GameCase.disc_slots(rom_path, GameCase.disc_total_of(systemid, rom_path)).size()), 1, _zones.size())
	var want := disc_seat_order(total)
	var front := disc_seat_order()
	var real := true
	var by_number := true
	var by_front := true
	for row: Array in on:
		var n := int(row[0])
		var seat := int(row[1])
		real = real and seat == want[n - 1]
		by_number = by_number and seat == n - 1
		by_front = by_front and seat == front[n - 1]
	if real or not (by_number or by_front):
		return
	print("[GameCase] %s: discs put back as an older build seated them (%s); moved to the real layout" % [
		rom_path.get_file(), "disc 1 on the back" if by_number else "front to back"])
	for row: Array in on:
		_zones[int(row[1])].drop_object()
	for row: Array in on:
		var zone := _zones[want[int(row[0]) - 1]]
		(row[2] as Node3D).global_transform = zone.global_transform
		zone.pick_up_object(row[2] as Node3D)
	_update_reach()


## The seats in the order a game's discs go on them: disc 1 nearest the front cover, the first met on opening the
## case, and the last on the back (the owner, 2026-11-22: Final Fantasy VII and VIII keep disc 1 in the lid's own
## tray). Seats level with each other (a GameCube case's two on one panel) keep their own order. A game of fewer
## discs than the case has seats keeps disc 1 at the front and packs the rest to the back, leaving the middle's
## front empty (the same day's stills: Final Fantasy VII's three are in the front cover, on the back of the black
## tray and in the rear cover, the manual alone in the tray's front; Metal Gear Solid's two in the two covers).
func disc_seat_order(discs := -1) -> Array[int]:
	var order: Array[int] = []
	for i in _zones.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var d: float = _seat_z[a] - _seat_z[b]
		return d > 0.0005 or (absf(d) <= 0.0005 and a < b))
	if discs > 0 and discs < order.size():
		return order.slice(0, 1) + order.slice(order.size() - (discs - 1))
	return order


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
		# The turn about its hub at which a disc's label reads upright, the case standing on its bottom edge. A
		# seat facing the back is the front-facing one turned over top to bottom in the model, and a disc the case
		# seated there read upside down (the owner, 2026-11-22: Final Fantasy VIII's discs on the lid and under
		# the flip tray): turned over like a page, it does not. A label's top is toward the disc's own -Z.
		var up := (model.transform.basis * GameCaseModel._local_to(model, seat).basis).orthonormalized().inverse() * Vector3.UP
		_seat_square.append(atan2(-up.x, -up.z) if Vector2(up.x, up.z).length() > 0.5 else 0.0)
		_seat_z.append(float((row.get("center_mm", [0.0, 0.0, 0.0]) as Array)[2]) * 0.001)
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
		var where: Dictionary = model.contract().get("manual", {})
		_manual_loose = bool(where.get("front_sheet", false))
		_manual_on = _carrier_of(str(where.get("parent", "")))
		_manual_zone = _zone("ManualZone", _manual_root, "book", 0.06,
			func(obj: Node3D) -> bool: return obj is PDFBook and _manual_open())
		# Which way is into the case from the booklet, along its seat's z: toward the base, the lid being shut now.
		var seat_in_case := model.transform * GameCaseModel._local_to(model, ms)
		var toward_base := (seat_in_case.affine_inverse() * _base_box.get_center()).z
		_manual_in = -1.0 if toward_base < 0.0 else 1.0
		_manual_zone.reach_gate = _clear_of_base
		if _manual_loose:                                # on a tray: the open air is out of its own front
			_manual_in = 1.0
			_manual_zone.reach_gate = _over_manual
		_place_manual_zone(model.manual_size_m().x)
		_manual_zone.has_picked_up.connect(func(what: Node3D) -> void:
			if what is PDFBook and not (what as PDFBook).dimensions_changed.is_connected(_on_book_resized):
				(what as PDFBook).dimensions_changed.connect(_on_book_resized.bind(what))
			if what is PDFBook:
				# A manual goes into its case shut: an open one lay across the spine, hidden, and came out open.
				(what as PDFBook).set_page(PDFBook.BookState.CLOSED, 0)
				_on_book_resized.call_deferred(what)
				# Again once it has finished shutting: its thickness is the closed book's by then.
				get_tree().create_timer(0.6).timeout.connect(_on_book_resized.bind(what))
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
	zone.reach_gate = _over_seat.bind(zone)
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
	if i >= _zones.size() or _popped[i] or not _held(_zones[i]) is RetroDisc or not _seat_reachable(i):
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
		_seat_spin[i] = _seat_square[i]
		# A disc a save has just put back (no hand, the case just made): once they are all back, see whether they
		# sit as an older build seated them.
		if disc is RetroDisc and not _fresh and not _layout_done and not (disc as RetroDisc).released_by_hand_just_now() \
				and Time.get_ticks_msec() - _born_msec < OLD_LAYOUT_WINDOW_MS:
			_layout_soon()
		var d := disc as RetroDisc
		var seat := _zones[i].get_parent() as Node3D
		if d != null and seat != null and d.can_visually_spin() and d.released_by_hand_just_now():
			_seat_spin[i] = RetroDisc.spin_of(Basis.IDENTITY, d.release_basis_in(seat))
		_zones[i].transform = Transform3D(Basis(Vector3.UP, _seat_spin[i]), Vector3.ZERO)
		# The zone had the disc before this ran, on the seat as it stood (square): put it on the turned seat now,
		# not on its driver's next tick. A disc put on at an angle showed square for the frame between (the owner,
		# 2026-11-25).
		var driver := (d._grab_driver if d != null else null) as XRToolsGrabDriver
		if is_instance_valid(driver) and _held(_zones[i]) == d:
			driver.snap_now()
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
		_seated_book.set_pages_locked(false)
		if _seated_book.highlight_updated.is_connected(_on_manual_hover):
			_seated_book.highlight_updated.disconnect(_on_manual_hover)
		_seated_book = null
	if seated != null:
		seated.visible = false
		# Not read in its case: hidden, it still turned a page under a trigger or a click meant to take it out.
		seated.set_pages_locked(true)
		# A grip's hover goes to what the zone holds, the hidden book: its outline never showed. The rim round the
		# booklet the case draws shows it instead.
		if not seated.highlight_updated.is_connected(_on_manual_hover):
			seated.highlight_updated.connect(_on_manual_hover)
		_seated_book = seated
	elif _manual_rim != null:
		_manual_rim.visible = false
	if case_family == "jewel" and _manual_loose:
		# The lid's Booklet is the front sheet: there whatever the manual does, its back plain. The manual itself is
		# the sheet on its tray, below.
		model.show_booklet(true)
		model.set_booklet_back(null)
	elif case_family == "jewel":
		model.show_booklet(seated != null or not _has_manual)
		# Inside the open lid the booklet shows its back: the manual's last page, from the PDF (a spread scan's back
		# cover is its first half page).
		model.set_booklet_back(_manual_page(seated, 0 if seated.half_page_mode else seated._page_count - 1) \
			if seated != null else null)
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
	return _manual_page(book, 1 if book.half_page_mode else 0)


## One page of the seated manual on plain paper of the case's own, or null until it has rendered (and a retry).
## Not the book's own material: its paper shader is written for the book's own sheets (their size, their fold,
## which face is which), and lent to the case's booklet the page came out dark and blue (the owner, 2026-11-22:
## Air Combat's back cover inside its lid, beside the same page bright on the manual held over it).
func _manual_page(book: PDFBook, page: int) -> Material:
	var tex := book._get_page_texture(page)
	if tex != null and book._texture_cache.has(page):
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.roughness = 0.8
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	# (Under a jewel lid its back is toward the seat's front; on a keep case's cover or a tray, behind it.)
	var z := (MANUAL_WALL - half_thick) if case_family == "jewel" and not _manual_loose else (half_thick - MANUAL_WALL)
	_manual_zone.position = Vector3(-book_width * 0.5, 0.0, z)
	# The zone stands at the book's spine; its reach is round the booklet's middle, so a manual offered at either
	# edge of its place is as near.
	var ball := _manual_zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if ball != null:
		ball.position = Vector3(book_width * 0.5, 0.0, -z)
	# Where a grip takes the manual OUT: the booklet itself, from its face against the lid, and the space above it
	# into the open case; a little beside it; nothing behind it, which is the lid (the owner, 2026-11-22). Ranked
	# by the zone's origin alone, the spine edge's middle, only a grip within 6 cm of that took the manual and
	# anywhere else on it took the case.
	var book := manual()
	var tall := model.manual_size_m().y
	var span := Vector2(-half_thick, half_thick)
	if book != null and book.page_size().y > 0.0:
		tall = book.page_size().y
		span = book._drawn_z_span()
	var z0 := span.x if _manual_in > 0.0 else span.x - MANUAL_REACH_UP
	var z1 := span.y + MANUAL_REACH_UP if _manual_in > 0.0 else span.y
	var side := MANUAL_REACH_SIDE
	_manual_zone.reach_box = AABB(Vector3(-side, -tall * 0.5 - side, z0),
		Vector3(book_width + side * 2.0, tall + side * 2.0, z1 - z0))
	# The booklet itself: a grip's nearness to the manual is its distance to this (XRToolsSnapZone.reach_core).
	_manual_zone.reach_core = AABB(Vector3(0.0, -tall * 0.5, span.x), Vector3(book_width, tall, maxf(span.y - span.x, 0.0005)))


func _on_book_resized(book: PDFBook) -> void:
	if not is_instance_valid(book) or _manual_zone == null or _manual_zone.picked_up_object != book \
			or book.page_size().x <= 0.0:
		return
	# A manual scanned as two-page spreads (ScreenScraper has many): read it as single pages, as the book's own
	# Half Pages option does.
	if not book.half_page_mode and is_spread(book.page_size(), model.manual_size_m()):
		book.half_page_mode = true
		return
	var span: Vector2 = book._drawn_z_span()
	_place_manual_zone(book.page_size().x, (span.y - span.x) * 0.5)


## Whether a manual's page is a two-page spread for a booklet of `seat`'s size: by its SHAPE, wider than tall and
## well wider for its height than the booklet's page. Not by its width: a manual put in by hand comes at the size
## it had outside (25 cm tall), wider than any booklet, and every single-page manual had its Half Pages switched on
## (the owner, 2026-11-22; only the manual the case spawned itself came at the booklet's height).
static func is_spread(page: Vector2, seat: Vector2) -> bool:
	if page.x <= 0.0 or page.y <= 0.0 or seat.x <= 0.0 or seat.y <= 0.0:
		return false
	var shape := page.x / page.y
	return shape > SPREAD_MIN_SHAPE and shape > seat.x / seat.y * SPREAD_OVER_SEAT


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


## Whether the manual's place is in the open: under an open lid, or, lying on a tray, with the panel above that
## tray turned off it.
func _manual_open() -> bool:
	if not _manual_loose or _manual_on < 0:
		return _lid_open()
	return sim.angle_deg(_manual_on + 1) - sim.angle_deg(_manual_on) >= REACH_DEG


## A manual lying on a tray is reached from its own front, not through the tray from behind.
func _over_manual(at: Vector3) -> bool:
	return is_instance_valid(_manual_zone) and (_manual_zone.global_transform.affine_inverse() * at).z > -SEAT_BEHIND


## The panel over a seat (the next one up for a hub facing out, the one below for a hub facing back) is turned far
## enough off it for a hand to get at the disc.
func _seat_reachable(seat: int) -> bool:
	var c := _seat_carrier[seat]
	var here := 0.0 if c < 0 else sim.angle_deg(c)
	# The disc under a manual lying on its tray is the manual's to uncover first.
	if _manual_loose and c == _manual_on and not _seat_down[seat] and manual() != null:
		return false
	if _seat_down[seat]:
		var below := 0.0 if c <= 0 else sim.angle_deg(c - 1)
		return here - below >= REACH_DEG
	var above := sim.angle_deg(c + 1) if c + 1 <= sim.top() else 180.0
	return above - here >= REACH_DEG


## Discs (and the manual) under a shut panel cannot be taken, and a seat that cannot be reached takes nothing.
## The zone itself follows its seat's reach too, as a disc tray's does (MediaTray._sync_gates): a grip makes a zone
## let go BEFORE it asks what the zone holds, so with only the disc switched off a grip at a shut case within a
## hub's reach left the hand empty and the disc loose inside the case, to fall through it (a probe, 2026-11-22). A
## zone switched off still holds, and still seats what a spawn or a save puts in it; a grip passes it by and takes
## the case. Set only when it changes: the setter emits.
func _update_reach() -> void:
	for i in _zones.size():
		var ok := _seat_reachable(i)
		if _zones[i].enabled != ok:
			_zones[i].enabled = ok
		var obj: XRToolsPickable = null
		if is_instance_valid(_zones[i].picked_up_object):
			obj = _zones[i].picked_up_object as XRToolsPickable
		if obj != null:
			obj.enabled = ok
		if i < _hub_buttons.size() and _hub_buttons[i].is_inside_tree():
			_hub_buttons[i].set_active(ok and obj is RetroDisc and not _popped[i])
	for z: XRToolsSnapZone in [_holder_zone, _manual_zone, _card_zone]:
		if z == null:
			continue
		var open := _manual_open() if z == _manual_zone else _lid_open()
		if z.enabled != open:
			z.enabled = open
		if is_instance_valid(z.picked_up_object) and z.picked_up_object is XRToolsPickable:
			(z.picked_up_object as XRToolsPickable).enabled = open


# ------------------------------------------------------------------ art
func _load_art() -> void:
	var img: Image = null
	# The case's three panels as ScreenScraper cut them, when the scraper has them; else the one wrap, split by the
	# layout.
	var panels := box_panel_paths(systemid, rom_path)
	if not panels.is_empty():
		img = await decode_panels(get_tree(), panels, case_variant, case_family)
	if img == null and is_inside_tree():
		var path := box_art_path(systemid, rom_path)
		if not path.is_empty():
			img = await decode_image(get_tree(), path)
	if img != null and is_inside_tree():
		_apply_art(img)


## Ask for this game's three panels when it has not got them: a game scraped before its scrape took them. A jewel
## case only (a keep case's wrap keeps its sheet's layout within a few px: Gran Turismo 4's). Through a group: the
## spawn menu owns the scraper, and a case put back by a save is here before it (pending_art). Once a game a
## session, found or not.
func _want_panels() -> void:
	if case_family != "jewel" or rom_path.is_empty() or systemid.is_empty() or not is_inside_tree():
		return
	if _asked_art.has(rom_path) or missing_panels(systemid, rom_path).is_empty():
		return
	_asked_art[rom_path] = true
	pending_art[rom_path] = systemid
	if get_tree().get_nodes_in_group(PANEL_LISTENERS).is_empty():
		return
	get_tree().call_group(PANEL_LISTENERS, &"request_case_art", rom_path, systemid)


## One of a game's panels has landed (the spawn menu, by PANEL_GROUP): with all three there, the art goes on again.
func on_panel_arrived(rom: String) -> void:
	if rom == rom_path and not box_panel_paths(systemid, rom_path).is_empty():
		_load_art()


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


## A game's back, side and front as the scraper filed them ({kind: path}), or {} unless all three are there
## (resolved on the main thread, as box_art_path).
static func box_panel_paths(sys: String, rom: String) -> Dictionary:
	var out := {}
	if sys.is_empty() or rom.is_empty():
		return out
	var base := RomLibrary.content_stem(rom)
	for kind: String in PANEL_KINDS:
		for dir in RomLibrary.rom_dirs_for_system(sys):
			for ext in [".png", ".jpg", ".jpeg", ".webp"]:
				var p := dir.path_join("media").path_join(kind).path_join(base + ext)
				if not out.has(kind) and FileAccess.file_exists(p):
					out[kind] = p
		if not out.has(kind):
			return {}
	return out


## The size a game's box art has as ONE scan (back | spine | front), which is what GameCase.pick tells a long box
## by: the wrap's own, or its three panels' side by side. From the files' headers.
static func box_size(sys: String, rom: String) -> Vector2i:
	var wrap := GameCase.image_size(box_art_path(sys, rom))
	if wrap.x > 0 and wrap.y > 0:
		return wrap
	var panels := box_panel_paths(sys, rom)
	if panels.is_empty():
		return Vector2i.ZERO
	var h := GameCase.image_size(str(panels[PANEL_KINDS[0]])).y
	var w := 0
	for kind: String in PANEL_KINDS:
		var s := GameCase.image_size(str(panels[kind]))
		if s.x <= 0 or s.y <= 0 or h <= 0:
			return Vector2i.ZERO
		w += int(round(float(s.x) * h / float(s.y)))
	return Vector2i(w, h)


## The panel kinds to fetch for a game: all three unless all three are there (they are one region's set).
static func missing_panels(sys: String, rom: String) -> Array:
	return [] if not box_panel_paths(sys, rom).is_empty() else PANEL_KINDS.duplicate()


## Decode a game's three panels and join them for a case of `family` and `variant` (GameCaseModel.join_panels),
## with mipmaps, on a worker thread. Null when one will not load.
static func decode_panels(tree: SceneTree, paths: Dictionary, variant: String, family := "jewel") -> Image:
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void:
		var parts: Array[Image] = []
		for kind: String in PANEL_KINDS:
			var img := Image.new()
			if img.load(str(paths.get(kind, ""))) != OK:
				return
			parts.append(img)
		var joined := GameCaseModel.join_panels(parts[0], parts[1], parts[2], variant, family)
		if joined != null:
			joined.generate_mipmaps()
			out[0] = joined)
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return out[0]


## Decode an image (with its mipmaps) on a worker thread.
static func decode_image(tree: SceneTree, path: String) -> Image:
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void:
		var img := Image.new()
		if img.load(path) == OK:
			GameCaseModel.fit_jewel_scan(img)            # a jewel scan's spine strip, where the layout has it
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
		# The lid's hinge has two handles: its own, and the base's for a case held by its lid.
		var top := i == sim.top() and _base_hinge != null
		var grip := hinge
		if top and _base_hinge.is_held() and not hinge.is_held():
			grip = _base_hinge
		var held := grip.is_held()
		if held:
			var to := grip.get_rotation_deg()
			if top:
				_top_grip = grip
				if grip != _base_hinge:
					_end_base_push()                         # the lid is taken: the back is the still half again
				elif _lid_grab == null:
					if not _base_push:
						_begin_base_push()
					_base_push_until = Time.get_ticks_msec() + BASE_PUSH_SETTLE_MS
					to = _base_clear_toward(sim.angle_deg(i), to)
			sim.set_held(i, true)
			sim.set_held_angle_deg(i, to, delta)
			moved = true
		elif _was_held[i]:
			sim.set_held(i, false, (_top_grip if top and _top_grip != null else hinge).release_speed_deg)
			moved = true
		elif absf(hinge.get_rotation_deg() - sim.angle_deg(i)) > 0.05:
			sim.set_angle_deg(i, hinge.get_rotation_deg())   # a restore or a peer put it there
			if i == sim.top() and hinge.get_rotation_deg() <= 0.05:
				sim.latched = true                           # shut there, it is caught here too
			moved = true
		elif top and absf(_base_hinge.get_rotation_deg() - sim.angle_deg(i)) > 0.05:
			# ... or by its other handle (a peer pressing the base of a case it has by the lid). Asked after the
			# lid's own, and one a tick: a save from before this handle has no record of it, and its 0 must not
			# overrule the lid's.
			sim.set_angle_deg(i, _base_hinge.get_rotation_deg())
			if _base_hinge.get_rotation_deg() <= 0.05:
				sim.latched = true
			moved = true
		_was_held[i] = held
	var spin := _spin if absf(_spin) > SPIN_QUIET else 0.0
	var top_spin := NAN
	if _lid_grab != null:
		top_spin = _hand_spin if absf(_hand_spin) > SPIN_QUIET else 0.0
	elif _base_push:
		top_spin = 0.0                                   # the lid stands still
	if moved or not sim.settled(g, spin, top_spin):
		sim.step(delta, g, spin, top_spin)
		_apply_angles()
	elif _base_push:
		_end_base_push()                                 # the back has come to rest
	if _base_push and not _base_hinge.is_held() and Time.get_ticks_msec() > _base_push_until:
		_end_base_push()
	if _lid_gives_way():
		_apply_angles()
		if _base_push and not _base_hinge.is_held():
			_end_base_push()                             # the back has met the world: the case is a body again
	_hold_by_lid()
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
			_sfx_next = SFX_TURN_DEG * randf_range(0.7, 1.4)
		elif sim.knocked >= SFX_KNOCK:
			_play_sfx("snap", "stop", clampf(sim.knocked / SFX_SLAM, 0.12, 0.8))
		if not sim.latched and sim.latched == _sfx_latched:
			_sfx_travel += absf(lid - _sfx_lid)
			if _sfx_travel >= _sfx_next:
				_sfx_travel = 0.0
				_sfx_next = SFX_TURN_DEG * randf_range(0.7, 1.4)
				var speed := absf(lid - _sfx_lid) / delta
				if speed > SFX_TURN_MIN_SPEED:
					var gain := clampf((speed - SFX_TURN_MIN_SPEED) / 850.0, 0.0, 0.32)
					_play_sfx("turn", str(SFX_TURN.get(case_family, "creak")), gain)
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
# ------------------------------------------------------------------ held by the lid
## The lid in the case's own frame as the model has it now (a keep case's cover turns on its spine's two creases).
func _lid_in_case() -> Transform3D:
	return model.transform * model.lid_transform_at(model.open_deg)


## How the lid has turned from lying shut, in the case's frame.
func _lid_swing() -> Transform3D:
	return _swing_at(model.open_deg)


## The same with the case open `deg`, whatever it is now.
func _swing_at(deg: float) -> Transform3D:
	return model.transform * model.lid_transform_at(deg) * _lid_rest.affine_inverse()


static func _reach_to(box: AABB, p: Vector3) -> float:
	return (p - p.clamp(box.position, box.end)).length()


## Whether a hand at `p` (the case's frame) has the open case by its lid: nearer the lid than the base.
func _on_lid(p: Vector3) -> bool:
	if _lid_node == null or sim.latched or sim.angle_deg(sim.top()) < REACH_DEG:
		return false
	var to_lid := _reach_to(_lid_box, _lid_swing().affine_inverse() * p)
	return to_lid <= LID_GRIP_REACH and to_lid < _reach_to(_base_box, p)


## A grip that lands on the open lid has the case by its lid (the owner, 2026-11-21): the lid stays in that hand
## and the base swings from it, as it does off a real case picked up by its cover. The case's body is its base, so
## each tick the grab is told where the hand now is from the base's side (_hold_by_lid), and the sim swings the
## base instead of the lid (CaseHingeSim.base_swings). Only the hand that carries the case: a second hand, a seat
## or a grab point holds it as before.
func pick_up(by: Node3D) -> void:
	# Where the hand is as it closes: a grip brings the case's own origin into the hand, so afterwards the grab
	# no longer says which half was taken.
	_end_base_push()                                 # before the grip notes whether the body was frozen
	var hand := global_transform.affine_inverse() * by.global_transform if by != null else Transform3D()
	var was_held := is_picked_up()
	super(by)
	if was_held or _lid_grab != null or by == null or by is XRToolsSnapZone or not is_instance_valid(_grab_driver):
		return
	var grab := _grab_driver.get_grab(by)
	if grab == null or grab != _grab_driver.primary or grab.point != null or not _on_lid(hand.origin):
		return
	# By the lid it is held where it was gripped, not drawn in: the lid stays under the fingers.
	grab.transform = hand
	_lid_grab = grab
	_lid_hand = _lid_swing().affine_inverse() * hand
	_hand_has = false
	_hand_spin = 0.0
	sim.base_swings = true
	# The lid's own handle shuts (its gate); a hold on it begun before this grip ends here.
	hinge(sim.top()).drop_hold()


func let_go(by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	super(by, p_linear_velocity, p_angular_velocity)
	if _lid_grab != null and (not is_instance_valid(_grab_driver) or _grab_driver.primary != _lid_grab):
		_free_lid()


func _free_lid() -> void:
	_lid_grab = null
	_hand_has = false
	_hand_spin = 0.0
	sim.base_swings = false
	if _base_hinge != null:
		_base_hinge.drop_hold()


## Over the manual lying in the lid, a hand is reaching for the manual: there the lid's handle takes no trigger and
## shows no open hand (CaseHinge.quiet_at; a fingertip: _lid_push_quiet). The grip's own box, so nothing behind
## the booklet: the lid is still pushed shut from outside, and worked anywhere once the manual is out.
func _lid_quiet(at: Vector3) -> bool:
	if _manual_zone == null or _manual_loose or not is_instance_valid(_manual_zone.picked_up_object) or not _lid_open():
		return false
	return _manual_zone.reach_box.has_point(_manual_zone.global_transform.affine_inverse() * at) and _clear_of_base(at)


## A fingertip ON the booklet presses the lid it lies in, as it would the bare lid. All of _lid_quiet was a
## fingertip's too, and the booklet covers the lid's inside: with a manual in, the lid could not be pressed from
## inside at all (the owner, 2026-11-25). Only a finger still over the paper pushes nothing: that hand is
## reaching for the manual, and a push begun a centimeter early turned the lid away from it.
func _lid_push_quiet(at: Vector3) -> bool:
	if not _lid_quiet(at):
		return false
	var z := (_manual_zone.global_transform.affine_inverse() * at).z
	var paper := _manual_zone.reach_core
	var over := z - paper.end.z if _manual_in > 0.0 else paper.position.z - z
	return over > MANUAL_PRESS_OVER


## A hand behind the panel a seat is on is not reaching for what is on it. A hub's reach is a ball round the hub,
## and it ran through the base: a grip on an open case from underneath took the disc out through its back (a
## probe, 2026-11-22). A zone's +Y is out of its panel (the disc's label side, a card's or a UMD's face).
func _over_seat(at: Vector3, zone: XRToolsSnapZone) -> bool:
	return is_instance_valid(zone) and (zone.global_transform.affine_inverse() * at).y > -SEAT_BEHIND


## Whether a point (world) is in the open air of the case: not inside its base, nor anywhere beneath it. The
## booklet's reach is the space OVER the booklet, and as a plain box it ran on through the base and out of the
## case's back whenever the lid stood short of upright: a hand under the case was reaching for the manual (the
## owner, 2026-11-22, off the regions probe's picture).
func _clear_of_base(at: Vector3) -> bool:
	var p := global_transform.affine_inverse() * at
	var b := _base_box
	# Its outline and a little beside it (the booklet's reach is a centimetre wider than the booklet), but not past
	# the hinge: there the lid itself lies when it is open flat, a little lower than the base's top.
	var beside := MANUAL_REACH_SIDE * 2.0
	return not (p.z < b.end.z and p.x > b.position.x and p.x < b.end.x + beside
		and p.y > b.position.y - beside and p.y < b.end.y + beside)


## Over a disc, a UMD or a card on its seat, a hand is reaching for that, not pressing the base away. From the
## seat's own side only (a zone's +Y is out of its panel): behind the panel, a fingertip at the base's back is
## pressing the base, and its middle is where one presses.
func _base_quiet(at: Vector3) -> bool:
	for z: XRToolsSnapZone in _zones + [_holder_zone, _card_zone]:
		if z == null or not is_instance_valid(z.picked_up_object):
			continue
		var p := z.global_transform.affine_inverse() * at
		if p.y > -0.003 and p.length() <= z.grab_distance:
			return true
	return false


## The seated manual is the nearest thing to a grip, or no longer is: the rim round the booklet, and a tick in the
## hand that would take it.
func _on_manual_hover(_what: Variant, on: bool) -> void:
	var lit := on and manual() != null
	if lit and _manual_rim == null:
		_manual_rim = _build_manual_rim()
	if _manual_rim == null:
		return
	var was := _manual_rim.visible
	if lit:
		_size_manual_rim()
	_manual_rim.visible = lit
	if lit and not was and is_inside_tree():
		for node in XrControllers.all(get_tree()):
			var pickup := node.get_node_or_null("FunctionPickup")
			if pickup != null and pickup.get("closest_object") == _manual_zone:
				Haptics.pulse(node as XRController3D, 0.25, 10, MANUAL_HAPTIC_KEY)


func _build_manual_rim() -> Node3D:
	var root := Node3D.new()
	root.name = "ManualRim"
	model.manual_seat().add_child(root)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1.0, 1.0, 1.0)
	for side: String in ["Top", "Bottom", "Left", "Right"]:
		var strip := MeshInstance3D.new()
		strip.name = side
		strip.mesh = BoxMesh.new()
		strip.material_override = white
		strip.add_to_group("outline_exclude")
		root.add_child(strip)
	root.visible = false
	return root


func _size_manual_rim() -> void:
	var size := model.manual_size_m()
	var book := manual()
	if book != null and book.page_size().x > 0.0:
		size = book.page_size()
	var w := size.x + MANUAL_RIM_GAP * 2.0
	var h := size.y + MANUAL_RIM_GAP * 2.0
	var t := MANUAL_RIM_W
	var deep := MANUAL_T * 2.5
	for row: Array in [["Top", Vector3(w + t * 2.0, t, deep), Vector3(0.0, (h + t) * 0.5, 0.0)],
			["Bottom", Vector3(w + t * 2.0, t, deep), Vector3(0.0, -(h + t) * 0.5, 0.0)],
			["Left", Vector3(t, h, deep), Vector3(-(w + t) * 0.5, 0.0, 0.0)],
			["Right", Vector3(t, h, deep), Vector3((w + t) * 0.5, 0.0, 0.0)]]:
		var strip := _manual_rim.get_node(str(row[0])) as MeshInstance3D
		(strip.mesh as BoxMesh).size = row[1]
		strip.position = row[2]


## Let go a little way into a table (a held thing passes through everything, and a hand sets it down a few
## millimetres too far): lifted out onto it. See HeldObjectPhysics.lift_out for why nothing else does it. A frame
## on, so the escape from the room's own walls and any seat's claim have had their turn.
func _on_let_go(_what: Variant = null) -> void:
	await get_tree().physics_frame
	if not is_inside_tree() or is_picked_up() or freeze or linear_velocity.length() > LIFT_MAX_SPEED:
		return
	HeldObjectPhysics.lift_out(self, _body_shape, original_collision_mask, LIFT_MAX)


func held_by_lid() -> bool:
	return _lid_grab != null


## Whether a fingertip may push the BACK half of the case: nothing holds it (a hand has it by its back, or a seat,
## and the back is going nowhere), nobody has its lid's handle, and this is not a netplay guest (the host stands
## the body). The front has always been pushed; resting on its lid with its back in the air, a case answered a
## finger on the half that was up with nothing (the owner, 2026-11-25).
func _base_free() -> bool:
	return not is_picked_up() and not NetworkManager.is_client() and not hinge(sim.top()).is_held()


## The back is pushed with nothing holding the case: the lid stays where it is in the world and the back turns
## from it, as when a hand has the lid (_lid_grab). The body is the back, so it is frozen and stood by the lid
## each tick (_apply_angles) until the finger has gone and the back has come to rest.
func _begin_base_push() -> void:
	_base_push = true
	sim.clear_world_stop()                           # the other half is the one that meets things now
	_base_anchor = global_transform * _lid_swing()
	_base_unfreeze = not freeze
	freeze = true
	sim.base_swings = true
	_base_push_until = Time.get_ticks_msec() + BASE_PUSH_SETTLE_MS


func _end_base_push() -> void:
	if not _base_push:
		return
	_base_push = false
	sim.clear_world_stop()
	sim.base_swings = _lid_grab != null
	if _base_hinge != null and _lid_grab == null:
		_base_hinge.drop_hold()
	if _base_unfreeze:
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false
		_on_let_go()                                     # out of anything it was left standing in


## How far toward `to` the pushed back may turn from `from` (deg) before it meets the world. It is the body, frozen
## while it is pushed: turned into a table it would shove the table.
func _base_clear_toward(from: float, to: float) -> float:
	if _lid_blocked(from):
		return to                                        # in something already: free to leave it
	var at := from
	while absf(to - at) > 0.01:
		var next := move_toward(at, to, 1.0)
		if _lid_blocked(next):
			break
		at = next
	return at


## The hand keeps the lid: where it is from the base's side, for the lid as it now stands.
func _hold_by_lid() -> void:
	if _lid_grab == null:
		return
	if not is_instance_valid(_grab_driver) or _grab_driver.primary != _lid_grab or not is_instance_valid(_lid_grab.by):
		_free_lid()
		return
	_lid_grab.transform = _lid_swing() * _lid_hand


## Whether the lid, turned `deg`, has something of the world in it: anything the case itself collides with, but
## the case and what it holds.
func _lid_blocked(deg: float) -> bool:
	if _lid_query == null:
		_lid_probe = BoxShape3D.new()
		_lid_probe.size = (_lid_box.size - Vector3.ONE * LID_SKIN * 2.0).max(Vector3.ONE * 0.0005)
		_base_probe = BoxShape3D.new()
		_base_probe.size = (_base_box.size - Vector3.ONE * LID_SKIN * 2.0).max(Vector3.ONE * 0.0005)
		_lid_query = PhysicsShapeQueryParameters3D.new()
		_lid_query.collide_with_areas = false
	if (_lid_grab != null and is_instance_valid(_lid_grab.by)) or _base_push:
		# Held by its lid, or its back pushed with the lid lying still, it is the BASE that turns into things:
		# tested where the case will stand with the hinge at `deg` (the body is re-posed after this in the tick,
		# so its own place is a swing behind).
		_lid_query.shape = _base_probe
		var lid_at := _base_anchor
		if _lid_grab != null:
			lid_at = (_lid_grab.by as Node3D).global_transform * _lid_hand.affine_inverse()
		var body := lid_at * _swing_at(deg).affine_inverse()
		_lid_query.transform = body * Transform3D(Basis.IDENTITY, _base_box.get_center())
	else:
		_lid_query.shape = _lid_probe
		_lid_query.transform = global_transform * _swing_at(deg) * Transform3D(Basis.IDENTITY, _lid_box.get_center())
	# The case's own layers, not what it has now: a held body's mask is 0, and by that the lid of a case in a
	# hand gave way to nothing.
	_lid_query.collision_mask = original_collision_mask
	var skip: Array[RID] = [get_rid()]
	# (An exception outlives its body: a manual or a disc deleted off its seat leaves a null here, and its get_rid
	# stopped the game: the owner, 2026-11-22.)
	for body in get_collision_exceptions():
		if is_instance_valid(body):
			skip.append(body.get_rid())
	_lid_query.exclude = skip
	return not get_world_3d().direct_space_state.intersect_shape(_lid_query, 1).is_empty()


## The lid against the world: a table's edge, a wall, a thing in another hand, a disc left loose under it. What is
## in its way turns it to the nearest angle clear of it, shutting or opening, never past its stops; a lid that
## gravity or its swing carries into something stops against it. A caught lid is shut and gives to nothing, and
## one a hand has goes where the hand takes it. True when it moved.
func _lid_gives_way() -> bool:
	var top := sim.top()
	if sim.latched or top < 0 or sim.held[top] or not is_inside_tree():
		sim.clear_world_stop()
		return false
	# In a seat, or weightless while a save is put back (no holder, no mask): nothing to give way to.
	var by := get_picked_up_by()
	if by is XRToolsSnapZone or (by == null and collision_mask == 0):
		sim.clear_world_stop()
		return false
	var at := sim.angle_deg(top)
	if sim.has_world_stop():
		# Resting against something: there until it swings off by itself, or the thing has gone (the case lifted
		# or tipped, the thing taken away).
		var rest := rad_to_deg(sim.world_lo if sim.world_lo > 0.0 else sim.world_hi)
		var into := -1.0 if sim.world_lo > 0.0 else 1.0
		if absf(at - rest) > 0.2 or not _lid_blocked(at + into * WORLD_REST_PROBE_DEG):
			sim.clear_world_stop()
		return false
	if not _lid_blocked(at):
		return false
	var hi := rad_to_deg(sim.open_max)
	var lo := sim.angle_deg(top - 1) if top > 0 else 0.0
	for k in range(1, int(LID_YIELD_DEG) + 1):
		for way: float in [_lid_yield, -_lid_yield]:
			var to := at + way * float(k)
			if to < lo or to > hi:
				to = clampf(to, lo, hi)
				if absf(to - at) < 0.05:
					continue
			if not _lid_blocked(to):
				_lid_yield = way
				# Where it first clears, to a sixteenth of a degree, and the probe's own skin further: on the thing,
				# not in it. It rests there (the sim's world stop) until the thing has gone.
				var hit := to - way
				for _r in 4:
					var mid := (to + hit) * 0.5
					if _lid_blocked(mid):
						hit = mid
					else:
						to = mid
				to = clampf(to + way * rad_to_deg(LID_SKIN / maxf(_closed_box.size.x, 0.05)), lo, hi)
				sim.push_to_deg(top, to)
				if way > 0.0:
					sim.world_lo = deg_to_rad(to)
				else:
					sim.world_hi = deg_to_rad(to)
				return true
	return false


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
	# Held by its lid, the lid turns with the hand: that turn speeding up is what leaves the base behind.
	if _lid_grab != null and is_instance_valid(_lid_grab.by):
		var hq := (_lid_grab.by as Node3D).global_basis.orthonormalized().get_rotation_quaternion()
		if _hand_has:
			var dq := hq * _hand_rot.inverse()
			if dq.w < 0.0:
				dq = -dq
			var rate := -(Vector3(dq.x, dq.y, dq.z) * 2.0 / delta).dot(global_basis.y.normalized())
			var a_hand := (rate - _hand_turn) / delta
			_hand_turn = rate
			_hand_spin = lerpf(_hand_spin, a_hand if absf(a_hand) < SPIN_CUT else 0.0, 0.35)
		_hand_rot = hq
		_hand_has = true
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
	# The base's handle reads the same angle; writing it is also what keeps its frame on the base.
	if _base_hinge != null and not _base_hinge.is_held():
		_base_hinge.set_angle_quiet(sim.angle_deg(sim.top()))
	if _base_push:
		global_transform = _base_anchor * _lid_swing().affine_inverse()      # the lid stays; the body is the back
	_follow_lid()
	_shape_body(sim.angle_deg(sim.top()))
	_carry_contents()
	_update_reach()


## The lid's handle stands where the model DRAWS the lid. Its rig turns about one line; a keep case's cover turns
## on its spine's two creases, and by the rig alone its grab box, the fingertip's panel and the hint stood up to a
## centimetre off the cover. Moved in its rig, not re-parented: a save finds the handle by its path.
func _follow_lid() -> void:
	if case_family != "keep" or _rigs.is_empty():
		return
	var top_rig: Array = _rigs[_rigs.size() - 1]
	var shut := (top_rig[0] as Node3D).transform
	var deg := sim.angle_deg(sim.top())
	var rig := shut * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(deg)), Vector3.ZERO)
	(top_rig[2] as Node3D).transform = rig.affine_inverse() * _swing_at(deg) * shut \
		* Transform3D(Basis.IDENTITY, _lid_handle_at)


## Whatever the zones hold goes where they now are, at once: a hinge posed outside the physics step (a restore, a
## probe) would otherwise leave it there until the drivers' next tick.
func _carry_contents() -> void:
	for z: XRToolsSnapZone in _zones + [_holder_zone, _card_zone, _manual_zone]:
		if z != null and is_instance_valid(z.picked_up_object) and z.picked_up_object is Node3D and z.is_inside_tree():
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
		if _held(z) is RetroCartridge:
			out.append(_held(z) as RetroCartridge)
	return out


func manual() -> PDFBook:
	return _held(_manual_zone) as PDFBook


## What a seat holds, or null. A thing deleted off its seat (the trash, the menu) stays in its zone as a freed
## reference for a while, and to cast or test one is an error (the owner, 2026-11-22: a manual deleted in its case).
static func _held(zone: XRToolsSnapZone) -> Node3D:
	if zone == null or not is_instance_valid(zone.picked_up_object):
		return null
	return zone.picked_up_object as Node3D


## The memory card holder (PS2, GameCube), or null for a case without one.
func card_zone() -> XRToolsSnapZone:
	return _card_zone


func memory_card() -> MemoryCard:
	return _held(_card_zone) as MemoryCard


func disc_zone(i: int) -> XRToolsSnapZone:
	return _zones[i] if i < _zones.size() else null


func hinge(i: int) -> CaseHinge:
	return _rigs[i][2] as CaseHinge if i < _rigs.size() else null
