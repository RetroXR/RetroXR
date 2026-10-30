## TVRemote — pickable remote control. While held, it raycasts forward from its
## tip; when pointed at a RetroTV / VCRPlayer / DVDPlayer / CD / Cassette player the
## target is outlined maroon (PickableHighlight.set_remote_target).
##
## By default the handset's OWN keys are the menu: the thumbstick walks a highlight
## (VRButton.set_selected, the laser's hover outline) over the keys in their real
## layout on the face — up/down/left/right to the nearest key that way, skipping keys
## that do nothing on what it is aimed at — and a stick click (or A/X) presses the
## lit key: it sinks while held and does its cell. Desktop: arrow keys walk it, Enter
## presses. With AppPrefs.remote_button_menu on (the remote's own menu, off by
## default) the older floating button GRID pops up above the remote instead,
## billboarded to the camera, with a stable real-remote-style layout per device
## (icons from a Symbols Nerd Font); cells that don't apply right now are greyed and
## skipped rather than removed, and the stick and the arrow keys walk the grid.
class_name TVRemote
extends XRToolsPickable


## Half-angle (degrees) of the acquisition cone: point roughly toward a device and
## the one nearest the cone centre is targeted. Tunable in the inspector.
@export var target_cone_angle_deg: float = 20.0
## Max targeting range in metres (cone radius; also the desktop crosshair reach).
@export var target_max_distance: float = 8.0
## Seconds the ray may leave the target before the menu hides (hand jitter).
const TARGET_GRACE := 0.4

# Grid geometry (metres)
const CELL_W       := 0.05
const CELL_H       := 0.036
const GAP          := 0.006
const GRID_COLS    := 3
const PANEL_PAD    := 0.012
const FLOAT_HEIGHT := 0.16

## Cell glyph sizing. The label is authored at CELL_FONT_MAX and then shrunk per
## cell to fit — see _fit_font_size. A fixed size cannot work here: these icons
## come from three different Nerd Font families and their ink boxes differ by 2x
## at the same point size, so one size that suits the arrows spills the speaker
## pair and the power ring off the tile.
const LABEL_PIXEL_SIZE := 0.0011
const CELL_FONT_MAX := 40
const CELL_FONT_MIN := 8
## Every glyph is normalised to this much of the tile's HEIGHT, which is what
## makes a grid of icons read at one weight rather than at whatever weight each
## font family happened to draw.
const CELL_INK_FRACTION := 0.75
## …and nothing may be wider than this much of its own cell.
const CELL_WIDTH_FRACTION := 0.85
## Outline thickness as a fraction of the font size, so a shrunk glyph doesn't
## keep a halo sized for the big one. 0.15 x CELL_FONT_MAX reproduces the 6 px
## outline these labels were authored with.
const OUTLINE_RATIO := 0.15
## VR only: the grid is authored at desktop size, where it sits in a corner of a
## ~70° screen. Filling that much of a headset's view is overbearing, so shrink it
## for the floating panel.
const VR_MENU_SCALE := 0.6
## Desktop: camera-local menu anchor (right, up, forward) — just above the
## FPS-snapped remote, fixed in screen space so looking around doesn't move it.
const DESKTOP_MENU_OFFSET := Vector3(0.22, -0.03, -0.55)

# Thumbstick step/latch thresholds
const STICK_STEP  := 0.6
const STICK_REARM := 0.3

const COLOR_MAROON          := Color(0.5, 0.0, 0.13, 0.9)
const COLOR_CELL_BG         := Color(0.12, 0.12, 0.16, 0.92)
const COLOR_PANEL_BG        := Color(0.05, 0.05, 0.1, 0.85)
const COLOR_GLYPH           := Color(0.88, 0.90, 0.98)
const COLOR_GLYPH_SELECTED  := Color(1.0, 1.0, 1.0)
const COLOR_GLYPH_DISABLED  := Color(0.42, 0.42, 0.48, 0.55)
const COLOR_GLYPH_ON        := Color(0.30, 1.0, 0.42)   # TV power = on
const COLOR_GLYPH_MUTE      := Color(1.0, 0.35, 0.35)   # TV mute = active
const COLOR_HILITE          := Color(0.62, 0.10, 0.22, 0.7)

# Symbol codepoints live in TransportGlyphs, shared with the front panels of the
# decks this drives. Built into the _glyphs string map in _ready so layouts can
# name glyphs by key.

## Desktop mode: lock to the camera lower-right pointing straight ahead
## (FPS-style, same as the LightGun — read by desktop_pickup.gd). Drop with
## Shift+click while snapped.
var desktop_fps_snap: bool = true

## What its menu (ObjectOptionsPanel) is titled.
var display_name := "TV Remote"

## Height of the drop hint above the remote, in metres. Clear of the button
## grid, which floats at FLOAT_HEIGHT.
const HINT_HEIGHT := 0.26
var _hint: HeldHint = null

# Toggle-hold state (mirrors LightGun)
var _allow_drop := false
var _saved_by: Node3D = null
var _holding_ctrl: XRController3D = null
var _desktop_held: bool = false

## Hides the ray pointer on whichever hand is holding this, so a grab
## gesture cannot also fire the pointer at whatever is behind it.
var _pointer_block := VrPointerBlock.new()

var _locomotion_manager: LocomotionManager = null
var _spawn_menu_ctrl: Node = null
var _left_vr_ctrl: XRController3D = null
var _right_vr_ctrl: XRController3D = null

# Current aim target and lost-ray grace timer.
var _target: Node3D = null
var _lost_time: float = 0.0

## Whether the aimed set had 3D content at the last grid build, so the 3D key can
## be added or dropped when that changes.
var _tv_had_stereo: bool = false

# Selection state
var _selection: int = -1
var _stick_latched := false
var _prev_confirm := false

# Menu nodes (built in code)
var _menu: Node3D = null
var _menu_bg: MeshInstance3D = null
var _hilite: MeshInstance3D = null
# Per-cell state: each is {id, glyph, col, row, span, cx, enabled, face, label}.
var _cells: Array = []
var _nrows: int = 0
# key -> glyph String (built from GLYPH_CODES in _ready)
var _glyphs: Dictionary = {}
# Combined font: project default + the Symbols Nerd Font as a fallback for icons.
var _font: Font = null

@onready var _tip: Marker3D = $Tip
@onready var _pointer_area: StaticBody3D = $PointerArea
@onready var _model: ApplianceModel = $Model
@onready var _keys_root: Node3D = $Keys

## The handset's own keys (RetroXR-models generic/tv-remote), each the grid cell it is
## printed with: pressing one does what that cell does on whatever the remote is aimed
## at, and nothing where the grid would grey the cell or leave it out. PREV/NEXT are the
## chapter keys on a DVD, which names them apart.
const KEY_CELLS := {
	"KeyPower": "power", "KeySource": "source", "KeyVolDown": "vol_down", "KeyMute": "mute",
	"KeyVolUp": "vol_up", "KeyChDown": "ch_down", "KeyChUp": "ch_up", "KeyAudioMode": "audio_mode",
	"KeyStereo3d": "stereo3d", "KeyAspect": "aspect", "KeyAudioOut": "audio_out", "KeyEject": "eject",
	"KeyPrev": "prev", "KeyPlayPause": "playpause", "KeyNext": "next", "KeyRew": "rew", "KeyStop": "stop",
	"KeyFf": "ff", "KeyUp": "up", "KeyDown": "down", "KeyLeft": "left", "KeyRight": "right", "KeyOk": "ok",
	"KeyMenu": "menu", "KeyAudio": "audio", "KeySubtitle": "subtitle",
}
const DVD_CELLS := {"prev": "prev_ch", "next": "next_ch"}
## The keys travel 1.5 mm along their own -Z: the long end of a rubber keypad's 0.8-1.5 mm stroke, so a press is
## seen from arm's length (each stands 2 mm proud). Only the cap moves: VRButton keeps its shape where it is, and a
## fingertip is held by distance and the gate, so the sinking cap cannot slide out from under the finger.
const KEY_TRAVEL := 0.0015
## How long a key stays down when its cell was pressed on the floating grid instead.
const KEY_FLASH := 0.15
## A fingertip presses a key inside its own footprint, this much past it all round, and
## from no higher than KEY_HOVER over its face: the keys are 2-3.5 mm apart.
const KEY_REACH := 0.001
const KEY_HOVER := 0.003
## The four-way ring round OK (the model's params.py): its centre on the face, in the
## remote's frame, and its arcs' radii. The arcs' boxes overlap each other and OK, so a
## fingertip on the ring is told apart by where it is round the centre.
const RING_CENTRE := Vector2(0.0, 0.019)          # x, z
const RING_R_IN := 0.009
const RING_R_OUT := 0.0159
const OK_R := 0.0074
const RING_DIRS := {"KeyRight": 0.0, "KeyUp": 90.0, "KeyLeft": 180.0, "KeyDown": 270.0}

## The battery cover's slot: it comes off whole and goes back, as every battery cover in the room does
## (CoverSlots, which saves and syncs it), and the bay's two AAA seats under it (CellSlots).
const BATTERY_COVER := "tv_remote_battery_cover"
## The cover's outer face in the model's frame: the underside.
const COVER_OUT := Vector3.DOWN
const CELL_SCENE := preload("res://Scenes/Objects/batteries/battery_aaa.tscn")

## The shell's convex hull and triangles, made once per remote (1.4 ms). Not static: a
## shape kept in a static outlives the physics server at quit and crashes the exit.
var _hull: ConvexPolygonShape3D = null
var _shell_faces: ConcavePolygonShape3D = null
## key node name -> VRButton
var _key_buttons: Dictionary = {}

## With the grid off: the key the thumbstick has lit (kept from hold to hold), the one lit now (cleared when
## the remote is let go), and the one a stick click or Enter is holding down, with when it went down.
var _key_sel := "KeyOk"
var _key_lit := ""
var _key_down := ""
var _key_down_ms := 0
## Which way the last frame drew the menu, so a switch is logged once.
var _grid_was: Variant = null
## A key is reached by the stick only this far ahead of the lit one (m), and no farther off to the side than
## KEY_SIDE times that; among those, the nearest with the side distance counted KEY_SIDE_COST times over.
const KEY_AHEAD := 0.002
const KEY_SIDE := 1.5
const KEY_SIDE_COST := 3.0


## The thumbstick drives the on-screen grid while the remote is aimed at a
## device, so the push-out gesture would fight it. Catching one back off the
## laser still works. Queried by function_pickup._handoff_eligible.
func wants_ray_handoff() -> bool:
	return false


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("spawned")
	grabbed.connect(_on_grabbed_signal)
	dropped.connect(_on_dropped_signal)
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)
	for k: String in TransportGlyphs.CODES:
		_glyphs[k] = TransportGlyphs.glyph(k)
	_font = TransportGlyphs.font()
	_build_menu()
	_dress()
	call_deferred("_find_vr_nodes")


# ── The model ─────────────────────────────────────────────────────────────────

## Dress the remote from its model: the tip on the IrTip, a VRButton per key, and the
## body's and the laser's shapes fitted to what it draws. Only the close level is
## outlined — three levels traced over each other would draw it three times.
func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[TVRemote] %s: no model to dress" % name)
		return
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	if _model.part("IrTip") != null:
		_tip.transform = _model.part_transform("IrTip", self)
	else:
		push_warning("[TVRemote] %s: the model has no IrTip; aiming from the scene's Tip" % name)
	_dress_keys()
	_fit_shapes()
	_dress_battery_bay()
	print("[TVRemote] %s: dressed from the model, %d keys, IR at %s" % [name, _key_buttons.size(), _tip.position])


## One VRButton per model key: its cap is the key, its shape the key's own triangles
## (no margin), and it presses along the key's -Z, into the remote.
func _dress_keys() -> void:
	for key_name: String in KEY_CELLS:
		if _model.part(key_name) == null:
			push_warning("[TVRemote] %s: the model has no %s" % [name, key_name])
			continue
		var btn := VRButton.new()
		btn.name = key_name
		btn.monitoring = false
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		btn.add_child(shape)
		# Empty until adopt_button fills it: VRButton looks its cap up as it readies.
		var blank := MeshInstance3D.new()
		blank.name = "ButtonMesh"
		btn.add_child(blank)
		_keys_root.add_child(btn)
		_model.adopt_button(btn, key_name, KEY_TRAVEL)
		var key := _model.part(key_name) as MeshInstance3D
		key.add_to_group("outline_exclude")
		shape.shape = key.mesh.create_trimesh_shape()
		shape.transform = Transform3D.IDENTITY
		var cap := btn.get_node_or_null("ButtonMesh") as MeshInstance3D
		# Touch reaches the farthest corner of the widest key, and the gate keeps it on this one.
		btn.trigger_radius = 0.012
		btn.contact_margin = 0.004
		btn.press_gate = _key_gate.bind(key_name, cap)
		btn.button_pressed.connect(press_key.bind(key_name))
		_key_buttons[key_name] = btn


## Whether a fingertip at `tip` (world) is on `key_name` and on no other: inside the
## key's footprint (grown KEY_REACH) and no higher than KEY_HOVER over its face. The
## ring's arcs and OK go by where the tip is round the ring's centre.
func _key_gate(tip: Vector3, key_name: String, cap: MeshInstance3D) -> bool:
	if cap == null or cap.mesh == null:
		return false
	var p := cap.global_transform.affine_inverse() * tip
	var box := cap.mesh.get_aabb()
	if p.z > KEY_HOVER or p.z < box.position.z:
		return false
	if key_name == "KeyOk" or RING_DIRS.has(key_name):
		var q := global_transform.affine_inverse() * tip
		var d := Vector2(q.x - RING_CENTRE.x, -(q.z - RING_CENTRE.y))
		var r := d.length()
		if key_name == "KeyOk":
			return r <= OK_R + KEY_REACH
		if r < RING_R_IN - KEY_REACH or r > RING_R_OUT + KEY_REACH:
			return false
		var off := wrapf(rad_to_deg(d.angle()) - float(RING_DIRS[key_name]), -180.0, 180.0)
		return absf(off) <= 45.0
	return p.x >= box.position.x - KEY_REACH and p.x <= box.end.x + KEY_REACH \
		and p.y >= box.position.y - KEY_REACH and p.y <= box.end.y + KEY_REACH


## The body's shape is the shell's convex hull (it rests tilted on the battery end and
## the window, as the remote does), the laser's the shell's own triangles: both exactly
## what is drawn, so the keys standing on the face are the ray's, not the body's.
func _fit_shapes() -> void:
	if _hull == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var space := global_transform.affine_inverse()
		for m: MeshInstance3D in _model.levels[0].find_children("*", "MeshInstance3D", true, false):
			# The cover is a thing of its own (its PortCover's shapes): off, the bay is open to the ray.
			if KEY_CELLS.has(String(m.name)) or m.name == "BodyPrint" or m.name == "BatteryCover":
				continue
			for s in m.mesh.get_surface_count():
				st.append_from(m.mesh, s, space * m.global_transform)
		var shell := st.commit()
		_hull = shell.create_convex_shape(true, false) as ConvexPolygonShape3D
		_shell_faces = shell.create_trimesh_shape()
		print("[TVRemote] shell shapes: hull of %d points, %d triangles for the laser"
			% [_hull.points.size(), _shell_faces.get_faces().size() / 3])
	var body := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body:
		body.shape = _hull
		body.transform = Transform3D.IDENTITY
	var laser := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if laser:
		laser.shape = _shell_faces
		laser.transform = Transform3D.IDENTITY


## The battery bay: the model's cover becomes a CoverSlots cover (taken off by hand, laser or mouse, put back,
## saved and synced like a Game Boy's), and the BatteryAAA1/2 markers CellSlots seats. A remote fresh from the
## spawn menu comes with two AAA cells in; a restored one has whatever its save says.
func _dress_battery_bay() -> void:
	var part := _model.part("BatteryCover") as MeshInstance3D
	if part == null:
		push_warning("[TVRemote] %s: the model has no BatteryCover; the bay stays shut" % name)
		return
	# The cover in the slot wears LOD0's part at every distance, so the far levels' copies go.
	for p in _model.parts("BatteryCover"):
		if p != part:
			p.visible = false
	var zone := CoverSlots.shell_cover(part, BATTERY_COVER, COVER_OUT)
	if zone == null:
		push_warning("[TVRemote] %s: no slot for the battery cover (not in an object?)" % name)
		return
	zone.has_picked_up.connect(_on_cover_seated)
	zone.has_dropped.connect(_on_cover_moved)
	var seats := CellSlots.build_seats(_model.levels[0])
	var fresh := not has_meta(CoverSlots.RESTORING)
	print("[TVRemote] %s: battery cover slot built, %d AAA seats, %s" % [name, seats.size(),
		"two cells going in" if fresh else "cells as the save has them"])
	if fresh:
		_seed_cells.call_deferred()


## Two AAA cells into the empty seats of a remote fresh from the spawn menu, as a remote comes in its box.
func _seed_cells() -> void:
	var slots := CellSlots.of(self)
	if slots == null or not is_inside_tree():
		return
	for seat_name: String in slots.seats():
		var zone := slots.slot(seat_name)
		if zone == null or zone.has_snapped_object():
			continue
		var cell := CELL_SCENE.instantiate() as Node3D
		get_tree().current_scene.add_child(cell)
		cell.add_to_group("spawned")
		cell.global_transform = zone.global_transform
		zone.seat_cell(cell, 0.0)
	print("[TVRemote] %s: two AAA cells in the bay" % name)


## The cover went back on: one that nothing has dressed yet (a fresh one, or one made from a save) wears the
## model's own cover.
func _on_cover_seated(what: Node3D) -> void:
	_on_cover_moved()
	var cover := what as PortCover
	var part := _model.part("BatteryCover") as MeshInstance3D
	if cover == null or part == null or cover.has_node("Shell"):
		return
	var copy := part.duplicate() as MeshInstance3D
	part.get_parent().add_child(copy)
	copy.transform = part.transform
	CoverSlots.wear(cover, copy, COVER_OUT)


func _on_cover_moved() -> void:
	var slots := CoverSlots.of(self)
	print("[TVRemote] %s: battery cover %s" % [name, "on" if slots != null and slots.is_on(BATTERY_COVER) else "off"])


## Whether the battery cover is on (a suite asks).
func battery_cover_on() -> bool:
	var slots := CoverSlots.of(self)
	return slots != null and slots.is_on(BATTERY_COVER)


## The VRButton for a model key (a suite presses them), or null.
func key_button(key_name: String) -> VRButton:
	return _key_buttons.get(key_name) as VRButton


## A physical key was pressed: do what its cell does on the device the remote is aimed
## at — the one the grid is showing, or, with no grid up (the remote lying on a table),
## whatever its window points at now. A greyed or absent cell does nothing, as on the grid.
## Returns the cell id that was activated, or "".
func press_key(key_name: String) -> String:
	var target := _target if is_instance_valid(_target) else _scan_for_target()
	if target == null:
		print("[TVRemote] %s: %s pressed, aimed at nothing" % [name, key_name])
		return ""
	var shown := _target
	_target = target
	var id := cell_for_key(key_name)
	var cell := -1
	for i in _cells.size():
		if str(_cells[i]["id"]) == id:
			cell = i
	var on_layout := _on_layout(id)
	if not on_layout or not _cell_enabled(id):
		print("[TVRemote] %s: %s pressed, %s is %s on %s" % [name, key_name, id,
			"greyed" if on_layout else "not a key", target.name])
		_target = shown
		return ""
	print("[TVRemote] %s: %s pressed -> %s on %s" % [name, key_name, id, target.name])
	_activate(id)
	# The grid shows the key that was pressed, as if it had been chosen there.
	if shown == target and cell >= 0:
		_selection = cell
		_refresh_states()
	_target = shown
	return id


func _on_layout(id: String) -> bool:
	for spec: Dictionary in _layout_for_target():
		if str(spec["id"]) == id:
			return true
	return false


## Whether a key does anything on what the remote is aimed at now: its cell is on the device's layout and not
## greyed. Aimed at nothing, every key is as good as another.
func key_live(key_name: String) -> bool:
	if not is_instance_valid(_target):
		return true
	var id := cell_for_key(key_name)
	return _on_layout(id) and _cell_enabled(id)


# ── The keys as the menu (the grid off) ───────────────────────────────────────

## Whether the floating grid shows rather than the keys being lit (the remote's own menu, off by default).
func grid_menu_on() -> bool:
	return AppPrefs.remote_button_menu


## The key the thumbstick has lit.
func selected_key() -> String:
	return _key_sel


## Light `key_name` (VRButton.set_selected, the laser's hover outline) and unlight the one before; "" none.
func _light_key(key_name: String) -> void:
	if key_name == _key_lit:
		return
	var old := key_button(_key_lit)
	if old:
		old.set_selected(false)
	_key_lit = key_name
	var b := key_button(key_name)
	if b:
		b.set_selected(true)


## Where a key sits on the face, in the keypad's own terms: x to the right, y towards the window.
func _key_xy(key_name: String) -> Vector2:
	var b := key_button(key_name)
	if b == null:
		return Vector2.ZERO
	var q := global_transform.affine_inverse() * b.global_position
	return Vector2(q.x, -q.z)


## Walk the light one key in `dir` (x right, y towards the window): the nearest key that way that does
## something on what the remote is aimed at, never wrapping round. On the ring the light goes round the ring
## while another of its keys lies that way (left from the top arc is the left arc, not REW above it), and
## leaves it past the top and bottom arcs. Returns whether it moved.
func move_key(dir: Vector2) -> bool:
	var on_ring := _key_sel == "KeyOk" or RING_DIRS.has(_key_sel)
	var best := _nearest_key(dir, on_ring)
	if best.is_empty() and on_ring:
		best = _nearest_key(dir, false)
	if best.is_empty():
		return false
	_key_sel = best
	if _key_lit != "":
		_light_key(best)
	return true


func _nearest_key(dir: Vector2, ring_only: bool) -> String:
	var here := _key_xy(_key_sel)
	var best := ""
	var best_score := INF
	for key_name: String in _key_buttons:
		if key_name == _key_sel or not key_live(key_name):
			continue
		if ring_only and key_name != "KeyOk" and not RING_DIRS.has(key_name):
			continue
		var d := _key_xy(key_name) - here
		var ahead := d.dot(dir)
		var side := absf(d.cross(dir))
		if ahead < KEY_AHEAD or side > ahead * KEY_SIDE:
			continue
		var score := ahead + side * KEY_SIDE_COST
		if score < best_score:
			best_score = score
			best = key_name
	return best


## The holding hand's stick walks the light, its click (or A/X) holds the lit key down.
func _process_vr_keys() -> void:
	var ctrl := _holding_ctrl
	var v := ctrl.get_vector2("primary")
	if _stick_latched:
		if v.length() < STICK_REARM:
			_stick_latched = false
	elif v.length() > STICK_STEP:
		if absf(v.y) >= absf(v.x):
			move_key(Vector2(0, signf(v.y)))
		else:
			move_key(Vector2(signf(v.x), 0))
		_stick_latched = true
	var confirm := ctrl.get_float("ax_button") > 0.5 or ctrl.get_float("primary_click") > 0.5
	if confirm and not _prev_confirm:
		key_press_down()
	elif not confirm and _prev_confirm:
		key_press_up()
	_prev_confirm = confirm


## A stick click or Enter goes down on the lit key: it sinks, and does its cell (press_key: nothing on a
## device it does not apply to, as on the grid). Returns the cell it did, or "".
func key_press_down() -> String:
	var b := key_button(_key_sel)
	if b == null:
		return ""
	_key_release()
	_key_down = _key_sel
	_key_down_ms = Time.get_ticks_msec()
	if not b.is_held():
		b.set_latched_pressed(true)
	print("[TVRemote] %s: %s pressed with the stick" % [name, _key_sel])
	return press_key(_key_sel)


## ...and comes up: the key stays down for KEY_FLASH at least, so a quick click is seen.
func key_press_up() -> void:
	if _key_down.is_empty():
		return
	var key_name := _key_down
	var left := KEY_FLASH - float(Time.get_ticks_msec() - _key_down_ms) / 1000.0
	if left <= 0.0:
		_key_release()
		return
	get_tree().create_timer(left).timeout.connect(func() -> void:
		if is_instance_valid(self) and _key_down == key_name:
			_key_release())


func _key_release() -> void:
	if _key_down.is_empty():
		return
	var b := key_button(_key_down)
	_key_down = ""
	if b:
		b.set_latched_pressed(false)


## The remote's own menu (ObjectOptionsPanel): whether the floating button grid shows. One setting for every
## remote, kept with the app's preferences: it is how the player likes to drive a remote, not a thing about
## this one, and it is not sent to the other peers in a session.
func options_choices() -> Array:
	return [{"caption": "Floating button menu", "items": ["Off", "On"],
		"selected": 1 if AppPrefs.remote_button_menu else 0}]


func options_choose(row: int, item: int) -> void:
	if row != 0 or item < 0 or item > 1:
		return
	AppPrefs.remote_button_menu = item == 1
	if not AppPrefs.save_prefs():
		push_warning("[TVRemote] the button menu setting was not saved")
	print("[TVRemote] %s: floating button menu %s (from its menu)" % [name, "on" if item == 1 else "off"])


## A cell pressed on the floating grid sinks its key on the remote too, for KEY_FLASH: the press is seen on the
## handset whichever way it was made. A key a finger or the laser is already holding down is left alone.
func _flash_key(id: String) -> void:
	for key_name: String in KEY_CELLS:
		if cell_for_key(key_name) != id:
			continue
		var b := key_button(key_name)
		if b == null or b.is_held():
			return
		b.set_latched_pressed(true)
		get_tree().create_timer(KEY_FLASH).timeout.connect(func() -> void:
			if is_instance_valid(b):
				b.set_latched_pressed(false))
		return


## The grid cell a model key stands for on the current target.
func cell_for_key(key_name: String) -> String:
	var id := str(KEY_CELLS.get(key_name, ""))
	if _target is DVDPlayer and DVD_CELLS.has(id):
		return str(DVD_CELLS[id])
	return id


func _find_vr_nodes() -> void:
	_locomotion_manager = SceneServices.locomotion(self) as LocomotionManager
	_spawn_menu_ctrl = SceneServices.spawn_menu(self)
	for node: Node in get_tree().root.find_children("*", "XRController3D", true, false):
		var ctrl := node as XRController3D
		if ctrl == null:
			continue
		if ctrl.tracker == &"left_hand":
			_left_vr_ctrl = ctrl
		elif ctrl.tracker == &"right_hand":
			_right_vr_ctrl = ctrl
	# The spawn menu hands a fresh object straight to the hand that spawned it, so
	# the grab can land BEFORE this deferred lookup runs — with no manager yet, that
	# grab's block was dropped on the floor and the holding hand kept driving
	# locomotion. Re-apply now that the manager is known.
	_update_locomotion_block()


# ── Toggle-hold (mirrors LightGun) ────────────────────────────────────────────

func _on_grabbed_signal(_pickable: Node3D, by: Node3D) -> void:
	if _hint:
		_hint.on_grabbed(by)
	var pickup := by as XRToolsFunctionPickup
	var ctrl := pickup.get_controller() if pickup else null as XRController3D
	if ctrl == null:
		if by.is_in_group("desktop_hand") and not DesktopPickup.inspecting(self):
			_desktop_held = true
		return
	_saved_by = by
	_holding_ctrl = ctrl
	VrHold.set_model_visible(ctrl, false)
	_update_pointer_block(ctrl, true)
	_update_locomotion_block()


func _on_dropped_signal(_pickable: Node3D) -> void:
	if not _allow_drop and is_instance_valid(_saved_by):
		PokeTip.begin_rehold(_holding_ctrl)
		call_deferred("_rehold")
	else:
		if _hint:
			_hint.on_dropped()
		VrHold.set_model_visible(_holding_ctrl, true)
		_update_pointer_block(_holding_ctrl, false)
		_allow_drop = false
		_saved_by = null
		_holding_ctrl = null
		_desktop_held = false
		_clear_target()
		_update_locomotion_block()


func _rehold() -> void:
	if _allow_drop:
		_allow_drop = false
		return
	if not is_instance_valid(_saved_by):
		VrHold.set_model_visible(_holding_ctrl, true)
		_update_pointer_block(_holding_ctrl, false)
		_saved_by = null
		_holding_ctrl = null
		_update_locomotion_block()
		return
	_saved_by.call("_pick_up_object", self)


## The combo test itself lives on HeldHint so the check and the row advertising
## it cannot disagree. Counting the use here rather than at the drop branch is
## deliberate: a predicate every drop passes through cannot be missed when
## another is added. HeldHint counts once per hold, so testing every frame does
## not inflate it.
func _is_combo_pressed(ctrl: XRController3D) -> bool:
	if not HeldHint.is_combo_pressed(ctrl):
		return false
	if _hint:
		_hint.note_used(&"drop_vr")
	return true


func _drop_all() -> void:
	VrHold.set_model_visible(_holding_ctrl, true)
	_update_pointer_block(_holding_ctrl, false)
	_allow_drop = true
	_holding_ctrl = null
	_clear_target()
	_update_locomotion_block()
	drop()


func _exit_tree() -> void:
	_clear_target()
	_pointer_block.release(_left_vr_ctrl, _right_vr_ctrl)
	if _locomotion_manager != null:
		_locomotion_manager.clear_owner(VrHold.vr_block_owner(self))
		_locomotion_manager.set_block(VrHold.desktop_block_owner(self),
			LocomotionManager.CHANNEL_DESKTOP_MOVE, false)
	_allow_drop = true
	super._exit_tree()


func _update_locomotion_block() -> void:
	var left_held  := is_instance_valid(_holding_ctrl) and _holding_ctrl.tracker == &"left_hand"
	var right_held := is_instance_valid(_holding_ctrl) and _holding_ctrl.tracker == &"right_hand"
	var desktop_claim := _desktop_held
	if _locomotion_manager != null:
		_locomotion_manager.set_block(VrHold.vr_block_owner(self), LocomotionManager.CHANNEL_LEFT,  left_held)
		_locomotion_manager.set_block(VrHold.vr_block_owner(self), LocomotionManager.CHANNEL_RIGHT, right_held)
	# Desktop has no hands, so the tracker tests above never fire there. The
	# desktop providers poll the InputMap, so blocking them is the only way to
	# stop WASD reaching the player while this device is claiming it.
		_locomotion_manager.set_block(VrHold.desktop_block_owner(self),
			LocomotionManager.CHANNEL_DESKTOP_MOVE, desktop_claim)
	if is_instance_valid(_spawn_menu_ctrl) and "disabled" in _spawn_menu_ctrl:
		_spawn_menu_ctrl.set("disabled", left_held)


## Delegates to VrPointerBlock, which owns the shared refcount.
func _update_pointer_block(ctrl: XRController3D, should_block: bool) -> void:
	_pointer_block.set_block(ctrl, should_block)


# ── Aiming / target management ────────────────────────────────────────────────

func _process(delta: float) -> void:
	# VR drop combo (desktop drop is handled by desktop_pickup via left click)
	# A holding hand freed under the remote (a room change) is no hand: its typed call would throw every frame.
	if is_instance_valid(_holding_ctrl) and _is_combo_pressed(_holding_ctrl):
		_drop_all()
		return

	var held := is_instance_valid(_holding_ctrl) or _desktop_held
	if not held:
		if _target != null:
			_clear_target()
		_light_key("")
		_key_release()
		return

	_update_target(delta)
	var grid := grid_menu_on()
	if grid != _grid_was:
		_grid_was = grid
		print("[TVRemote] %s: %s" % [name, "the floating button menu" if grid
			else "the thumbstick lights the remote's own keys"])
	if not grid:
		if _menu.visible:
			_menu.visible = false
		_light_key(_key_sel)
		if is_instance_valid(_holding_ctrl):
			_process_vr_keys()
		return
	_light_key("")
	_update_menu_transform()

	if _target != null:
		if not _menu.visible:
			_menu.visible = true
		# Greying + dynamic glyphs (play/pause, power/mute tint) follow the target's
		# own state every frame — no special poll needed.
		_refresh_states()
		if is_instance_valid(_holding_ctrl):
			_process_vr_selection()


func _update_target(delta: float) -> void:
	var host := _scan_for_target()
	if host == _target and host != null:
		_lost_time = 0.0
		return
	if host != null:
		# New target — switch highlight and rebuild the grid for it.
		_set_target_highlight(_target, false)
		_target = host
		_lost_time = 0.0
		_set_target_highlight(_target, true)
		_rebuild_grid()
		_menu.visible = grid_menu_on()
		return
	# Off-target. VR's cone is already forgiving, so drop it immediately; desktop's
	# thin crosshair keeps the grace period to ride out brief jitter.
	if _target != null:
		if not is_instance_valid(_target):
			_clear_target()
			return
		if not _desktop_held:
			_clear_target()
			return
		_lost_time += delta
		if _lost_time > TARGET_GRACE:
			_clear_target()


## Desktop: a precise crosshair raycast from the camera. VR: a forgiving cone from
## the tip — point in the general direction and the device nearest the cone centre
## (with clear line-of-sight) is targeted.
func _scan_for_target() -> Node3D:
	if _desktop_held:
		var cam := get_viewport().get_camera_3d()
		if not is_instance_valid(cam):
			return null
		return _ray_device(cam.global_position, -cam.global_transform.basis.z)
	return _cone_pick(_tip.global_position, -_tip.global_transform.basis.z)


## Walk a collider up its ancestors to the owning device, or null.
func _walk_to_device(node: Node) -> Node3D:
	while node:
		if node is RetroTV or node is VCRPlayer or node is DVDPlayer or node is RetroAudioPlayer:
			return node as Node3D
		node = node.get_parent()
	return null


## Thin-ray hit on the pointable layer (desktop crosshair), walked to its device.
func _ray_device(from: Vector3, dir: Vector3) -> Node3D:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * target_max_distance)
	q.collision_mask = 1 << 20   # 21: pointable (PointerArea bodies)
	q.exclude = [_pointer_area.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return _walk_to_device(hit["collider"] as Node)


## Pick the pointable device nearest the cone centre (largest dot with `dir`) that
## is within `target_cone_angle_deg` / `target_max_distance` and not occluded by
## world geometry. Mirrors XRToolsFunctionPickup._get_closest_ranged.
func _cone_pick(from: Vector3, dir: Vector3) -> Node3D:
	var shape := SphereShape3D.new()
	shape.radius = target_max_distance
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.collision_mask = 1 << 20   # 21: pointable (PointerArea bodies)
	q.exclude = [_pointer_area.get_rid()]
	var space := get_world_3d().direct_space_state
	var hits := space.intersect_shape(q, 64)

	# Best dot product (cone centre = 1.0) per device, plus a point to sight-check.
	var min_dp := cos(deg_to_rad(target_cone_angle_deg))
	var best_dp: Dictionary = {}   # device -> dp
	var best_pt: Dictionary = {}   # device -> collider world position
	for h in hits:
		var dev := _walk_to_device(h["collider"] as Node)
		if dev == null:
			continue
		var col := h["collider"] as Node3D
		var to: Vector3 = col.global_position - from
		var dist := to.length()
		if dist > target_max_distance or dist < 0.0001:
			continue
		var dp := dir.dot(to / dist)
		if dp < min_dp:
			continue
		if not best_dp.has(dev) or dp > float(best_dp[dev]):
			best_dp[dev] = dp
			best_pt[dev] = col.global_position

	# Closest-to-centre first; return the first with clear line-of-sight.
	var devices: Array = best_dp.keys()
	devices.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return float(best_dp[a]) > float(best_dp[b]))
	for dev: Node3D in devices:
		if not _occluded(from, best_pt[dev]):
			return dev
	return null


## True when world/room geometry (physics layer 1) blocks the straight line from
## `from` to `to`. Devices live on layer 21, so they never self-block.
func _occluded(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 << 0   # world/walls
	q.exclude = [_pointer_area.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _clear_target() -> void:
	_set_target_highlight(_target, false)
	_target = null
	_lost_time = 0.0
	if _menu:
		_menu.visible = false


func _set_target_highlight(target: Node3D, active: bool) -> void:
	if not is_instance_valid(target):
		return
	var hl := target.find_child("PickableHighlight", false, false)
	if hl and hl.has_method("set_remote_target"):
		hl.call("set_remote_target", active)


# ── Layout (per-device cell grid) ─────────────────────────────────────────────

## The static cell specs for the current target: {id, col, row, span} plus a face —
## either `glyph` (a TransportGlyphs key) or `text` (printed literally).
## `enabled` is resolved separately each frame in _refresh_states().
func _layout_for_target() -> Array:
	if _target is RetroTV:
		var tv := _target as RetroTV
		var cells: Array = [
			{"id": "power", "glyph": "power", "col": 0, "row": 0, "span": 3},
			# SOURCE sits directly under power, the way it does on a real handset:
			# it is a whole-set control, not part of the volume cluster.
			{"id": "source", "glyph": "source", "col": 0, "row": 1, "span": 3},
			{"id": "vol_down", "glyph": "vol_down", "col": 0, "row": 2},
			{"id": "mute", "glyph": "mute", "col": 1, "row": 2},
			{"id": "vol_up", "glyph": "vol_up", "col": 2, "row": 2},
		]
		# The channel keys are always on the handset and grey out when the set is not
		# on the tuner (see _cell_enabled). They used to be ADDED only while the tuner
		# was selected, and the grid is rebuilt on a change of TARGET alone — so
		# switching input with the remote still aimed at the same set left the keys
		# missing until you looked away and back.
		var next_row := 3
		cells.append({"id": "ch_down", "glyph": "ch_down", "col": 0, "row": next_row})
		cells.append({"id": "ch_up", "glyph": "ch_up", "col": 2, "row": next_row})
		next_row += 1
		# The speaker switch always; 3D only while there is something 3D to
		# switch, which is how the set's own bezel key behaves. Both take their
		# glyph from the mode they are currently in, so the key reads as a state
		# rather than a label — see _tv_audio_glyph / _tv_stereo_glyph.
		# Picture shape rides with them: also a state key, also always available.
		if tv.has_stereo_source():
			cells.append({"id": "audio_mode", "glyph": _tv_audio_glyph(tv),
				"col": 0, "row": next_row})
			cells.append({"id": "stereo3d", "glyph": _tv_stereo_glyph(tv),
				"col": 1, "row": next_row})
			cells.append({"id": "aspect", "text": _tv_aspect_text(tv),
				"col": 2, "row": next_row})
		else:
			cells.append({"id": "audio_mode", "glyph": _tv_audio_glyph(tv),
				"col": 0, "row": next_row})
			cells.append({"id": "aspect", "text": _tv_aspect_text(tv),
				"col": 2, "row": next_row})
		# Where the sound goes, on a row of its own. One FIXED glyph, unlike the two
		# state keys above: which position it is in is reported by the OSD and by
		# the bezel cap's colour, so there is nothing for the symbol to track and no
		# _live_text or _sizing_faces arm to add. Follows "source", which is the
		# other key built that way.
		next_row += 1
		cells.append({"id": "audio_out", "glyph": "audio_out",
			"col": 0, "row": next_row})
		return cells
	if _target is VCRPlayer:
		# Eject on its own top row, then the transport grid.
		return [
			{"id": "eject", "glyph": "eject", "col": 0, "row": 0, "span": 3},
			{"id": "prev", "glyph": "prev", "col": 0, "row": 1},
			{"id": "playpause", "glyph": "play", "col": 1, "row": 1},
			{"id": "next", "glyph": "next", "col": 2, "row": 1},
			{"id": "rew", "glyph": "rew", "col": 0, "row": 2},
			{"id": "stop", "glyph": "stop", "col": 1, "row": 2},
			{"id": "ff", "glyph": "ff", "col": 2, "row": 2},
		]
	if _target is RetroAudioPlayer:
		# Transport grid: prev/play/next over rew/stop/ff. prev/next greyed unless CD.
		return [
			{"id": "prev", "glyph": "prev", "col": 0, "row": 0},
			{"id": "playpause", "glyph": "play", "col": 1, "row": 0},
			{"id": "next", "glyph": "next", "col": 2, "row": 0},
			{"id": "rew", "glyph": "rew", "col": 0, "row": 1},
			{"id": "stop", "glyph": "stop", "col": 1, "row": 1},
			{"id": "ff", "glyph": "ff", "col": 2, "row": 1},
		]
	if _target is DVDPlayer:
		# Eject on its own top row, then D-pad cluster + chapter/transport + MENU.
		return [
			{"id": "eject", "glyph": "eject", "col": 0, "row": 0, "span": 3},
			{"id": "up", "glyph": "up", "col": 1, "row": 1},
			{"id": "left", "glyph": "left", "col": 0, "row": 2},
			{"id": "ok", "glyph": "ok", "col": 1, "row": 2},
			{"id": "right", "glyph": "right", "col": 2, "row": 2},
			{"id": "down", "glyph": "down", "col": 1, "row": 3},
			{"id": "prev_ch", "glyph": "prev", "col": 0, "row": 4},
			{"id": "playpause", "glyph": "play", "col": 1, "row": 4},
			{"id": "next_ch", "glyph": "next", "col": 2, "row": 4},
			{"id": "rew", "glyph": "rew", "col": 0, "row": 5},
			{"id": "stop", "glyph": "stop", "col": 1, "row": 5},
			{"id": "ff", "glyph": "ff", "col": 2, "row": 5},
			{"id": "menu", "glyph": "menu", "col": 0, "row": 6, "span": 3},
			# Audio-track + subtitle cycle, two half-width cells filling the row.
			{"id": "audio", "glyph": "audio", "col": 0.0, "row": 7, "span": 1.5},
			{"id": "subtitle", "glyph": "subtitle", "col": 1.5, "row": 7, "span": 1.5},
		]
	return []


## Whether a cell id is usable against the current target's state.
## Both of the set's tri-state keys print the mode they are IN rather than a
## label, the same way its bezel caps do.
func _tv_audio_glyph(tv: RetroTV) -> String:
	return "audio_stereo" if tv.audio_mode == SpatialAudioEmitter.ChannelMode.STEREO \
			else "audio_mono"


func _tv_stereo_glyph(tv: RetroTV) -> String:
	return "stereo" if tv.stereo_mode == RetroTV.StereoMode.BOTH else "eye"


## The shape the set is showing NOW, not the one the key would switch to — same
## reading as the audio and 3D keys, where the cell prints the current state.
##
## The words, not the crop glyphs it used to carry: the set's own bezel cap prints
## "16:9" / "4:3" (RetroTV._update_aspect_button) and the handset key for it should
## say what the cap says. Two picture-shape controls with different faces is one
## control too many to learn.
func _tv_aspect_text(tv: RetroTV) -> String:
	return "16:9" if tv.widescreen else "4:3"


## -1 leans left, +1 right, 0 centred — which channel, or which eye. Takes either
## switch: SpatialAudioEmitter.ChannelMode and RetroTV.StereoMode both put the left
## at 1 and the right at 2.
func _tv_side(mode: int) -> float:
	if mode == 1:
		return -1.0
	return 1.0 if mode == 2 else 0.0


## A cell is 50 mm wide against the set's 25 mm cap, so the lean is bigger here.
const CELL_LEAN := 0.009


func _lean(label: Label3D, side: float) -> void:
	if not label.has_meta("home_x"):
		label.set_meta("home_x", label.position.x)
	label.position.x = float(label.get_meta("home_x")) + side * CELL_LEAN


func _cell_enabled(id: String) -> bool:
	if _target is DVDPlayer:
		var in_menu: bool = (_target as DVDPlayer).is_in_menu()
		match id:
			"eject":
				return (_target as DVDPlayer).has_media()   # only with a disc in
			"up", "down", "left", "right", "ok":
				return in_menu       # nav cluster only in a disc menu
			"menu":
				return true          # always usable (return to root menu)
			"audio":
				return not in_menu and (_target as DVDPlayer).has_audio_options()
			"subtitle":
				return not in_menu and (_target as DVDPlayer).has_subtitle_options()
			_:
				return not in_menu   # transport/chapter only during playback
	if _target is VCRPlayer:
		if id == "eject":
			return (_target as VCRPlayer).has_media()   # only with a tape in
		return id != "prev" and id != "next"
	if _target is RetroAudioPlayer:
		if id == "prev" or id == "next":
			return (_target as RetroAudioPlayer).has_track_skip()
		# A turntable has no scan: you move the needle instead. Greyed for the
		# same reason prev/next are greyed on a cassette — the deck cannot do it.
		if id == "rew" or id == "ff":
			return (_target as RetroAudioPlayer).has_scan()
		return true
	if _target is RetroTV:
		# The channel keys are the one TV cell that can be dead: the set may be on
		# the component input, where there is no channel to change. On the aerial
		# input they always have CH3 and CH4 to step between, and an Antenna's
		# channels besides. Every other key on a set works whatever it is showing.
		if id == "ch_up" or id == "ch_down":
			return (_target as RetroTV).can_change_channel()
	return true


# ── Grid widget ───────────────────────────────────────────────────────────────

func _build_menu() -> void:
	_menu = Node3D.new()
	_menu.top_level = true
	_menu.visible = false
	# Repositioned every frame; interpolation would render a visible slide on show.
	_menu.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_menu)

	_menu_bg = MeshInstance3D.new()
	_menu_bg.mesh = QuadMesh.new()
	_menu_bg.material_override = _flat_mat(COLOR_PANEL_BG, 10)
	_menu_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep the menu out of PickableHighlight's outline overlays (a big highlighted
	# quad would draw a huge hull and mask other objects' outlines behind it).
	_menu_bg.add_to_group("outline_exclude")
	_menu.add_child(_menu_bg)

	_hilite = MeshInstance3D.new()
	_hilite.mesh = QuadMesh.new()
	_hilite.material_override = _flat_mat(COLOR_HILITE, 12)
	_hilite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hilite.add_to_group("outline_exclude")
	_hilite.visible = false
	_menu.add_child(_hilite)


## An unshaded, alpha-blended, depth-test-off material at the given render priority.
func _flat_mat(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.no_depth_test = true
	m.render_priority = priority
	return m


## Width of a cell spanning `span` columns.
func _cell_width(span: float) -> float:
	return span * CELL_W + (span - 1.0) * GAP


## What a layout spec prints: its own literal `text` when it carries one (the
## picture-shape key says "16:9"), otherwise the glyph its `glyph` key names.
func _spec_text(spec: Dictionary) -> String:
	if spec.has("text"):
		return str(spec["text"])
	return _glyph(str(spec.get("glyph", "")))


## The text a state key should be printing right now, or "" for a cell whose face
## never changes. One list, so a key that reads as a state cannot be given a live
## face in the layout and then left stale by the per-frame refresh — which is
## exactly what happened to the picture-shape key.
func _live_text(id: String) -> String:
	if id == "playpause":
		return _glyph("pause" if _target_playing() else "play")
	if _target is RetroTV:
		var tv := _target as RetroTV
		match id:
			"audio_mode": return _glyph(_tv_audio_glyph(tv))
			"stereo3d":   return _glyph(_tv_stereo_glyph(tv))
			"aspect":     return _tv_aspect_text(tv)
	return ""


## Print `text` on a cell and size it to that cell.
func _set_cell_text(cell: Dictionary, text: String) -> void:
	var label := cell["label"] as Label3D
	if not is_instance_valid(label):
		return
	label.text = text
	var w := float(cell["width"])
	var size := CELL_FONT_MAX
	for face: String in _sizing_faces(str(cell["id"]), text):
		size = mini(size, _fit_font_size(face, w))
	label.font_size = size
	label.outline_size = maxi(1, roundi(float(size) * OUTLINE_RATIO))


## Every face a key can wear. A state key is sized for the largest of them, so
## toggling it changes what it says and not how big it says it — "4:3" alone fits
## at 22 and "16:9" at 17, and a key that jumps a type size mid-press reads as a
## different key.
func _sizing_faces(id: String, text: String) -> Array:
	match id:
		"playpause":  return [_glyph("play"), _glyph("pause")]
		"audio_mode": return [_glyph("audio_stereo"), _glyph("audio_mono")]
		"stereo3d":   return [_glyph("stereo"), _glyph("eye")]
		"aspect":     return ["16:9", "4:3"]
	return [text]


func _glyph(key: String) -> String:
	return str(_glyphs.get(key, "?"))


## Font size at which `text` fills CELL_INK_FRACTION of the tile's height without
## exceeding CELL_WIDTH_FRACTION of `cell_w`, capped at CELL_FONT_MAX.
##
## Normalising on the INK box rather than the line box is the whole point. This
## font's em box is 60 mm at CELL_FONT_MAX against a 36 mm tile, so on line
## metrics every glyph "overflows" and a global shrink would be the only answer —
## yet the ink of md-video_3d is barely half the height of md-speaker-multiple at
## the same point size. Measure what is actually drawn and every icon lands at one
## weight, which is what a row of keys is supposed to look like.
##
## Memoised: the answer depends on nothing but the string and the cell, and the
## per-frame refresh asks for it whenever a state key changes face.
static var _fit_cache: Dictionary = {}

func _fit_font_size(text: String, cell_w: float) -> int:
	var key := "%s|%.4f" % [text, cell_w]
	if _fit_cache.has(key):
		return int(_fit_cache[key])
	var ink := _ink_extent(text, CELL_FONT_MAX)
	var k := 1.0
	if ink.y > 0.0:
		k = CELL_H * CELL_INK_FRACTION / ink.y
	if ink.x > 0.0:
		k = minf(k, cell_w * CELL_WIDTH_FRACTION / ink.x)
	var size := clampi(roundi(float(CELL_FONT_MAX) * k), CELL_FONT_MIN, CELL_FONT_MAX)
	_fit_cache[key] = size
	return size


## Drawn extent of `text` at `size`, in METRES, outline included.
##
## Height is the tallest glyph's rasterised box — the only honest measure for an
## icon, whose ink sits wherever its family chose to put it inside the em. Width
## is the advance run (right for a word) or the glyph's own box, whichever is
## wider: a single icon is routinely drawn wider than it advances.
func _ink_extent(text: String, size: int) -> Vector2:
	var ts := TextServerManager.get_primary_interface()
	var ink := Vector2.ZERO
	for i in text.length():
		var c := text.unicode_at(i)
		for rid: RID in _font.get_rids():
			var gi := ts.font_get_glyph_index(rid, size, c, 0)
			if gi == 0:
				continue
			var gs: Vector2 = ts.font_get_glyph_size(rid, Vector2i(size, 0), gi)
			ink.x = maxf(ink.x, gs.x)
			ink.y = maxf(ink.y, gs.y)
			break
	ink.x = maxf(ink.x, _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x)
	if ink.y <= 0.0:
		ink.y = _font.get_ascent(size)      # a face with no rasterised box yet
	# The halo is part of what spills off the tile, and it scales with the size
	# this is solving for (see OUTLINE_RATIO).
	var outline := float(size) * OUTLINE_RATIO * 2.0
	return (ink + Vector2(outline, outline)) * LABEL_PIXEL_SIZE


## Local position of a cell's centre (row 0 on top). col/span may be fractional
## (e.g. two 1.5-span cells filling a 3-wide row).
func _cell_center(col: float, row: int, span: float) -> Vector3:
	var cx := col + (span - 1.0) * 0.5
	var x := (cx - float(GRID_COLS - 1) * 0.5) * (CELL_W + GAP)
	var y := (float(_nrows - 1) * 0.5 - float(row)) * (CELL_H + GAP)
	return Vector3(x, y, 0.0)


## Rebuild the grid for the current target: free old cells, create new faces +
## labels from the layout, size the panel, and select the first enabled cell.
func _rebuild_grid() -> void:
	for cell: Dictionary in _cells:
		var f: Node = cell.get("face")
		if is_instance_valid(f):
			f.queue_free()
		var l: Node = cell.get("label")
		if is_instance_valid(l):
			l.queue_free()
	_cells.clear()

	var layout := _layout_for_target()
	_nrows = 0
	for spec: Dictionary in layout:
		_nrows = maxi(_nrows, int(spec["row"]) + 1)

	# Size the background panel to the grid bounds.
	var panel_w := float(GRID_COLS) * CELL_W + float(GRID_COLS - 1) * GAP + PANEL_PAD * 2.0
	var panel_h := float(_nrows) * CELL_H + float(_nrows - 1) * GAP + PANEL_PAD * 2.0
	(_menu_bg.mesh as QuadMesh).size = Vector2(panel_w, panel_h)
	_menu_bg.position = Vector3(0, 0, -0.001)

	for spec: Dictionary in layout:
		var span := float(spec.get("span", 1))
		var col := float(spec["col"])
		var row := int(spec["row"])
		var center := _cell_center(col, row, span)
		var w := _cell_width(span)

		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, CELL_H)
		face.mesh = qm
		face.material_override = _flat_mat(COLOR_CELL_BG, 11)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face.add_to_group("outline_exclude")
		face.position = center + Vector3(0, 0, 0.001)
		_menu.add_child(face)

		var label := Label3D.new()
		label.font = _font
		label.pixel_size = LABEL_PIXEL_SIZE
		label.no_depth_test = true
		label.render_priority = 13
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = center + Vector3(0, 0, 0.004)
		_menu.add_child(label)

		var cell := {
			"id": str(spec["id"]),
			"glyph": str(spec.get("glyph", "")),
			"col": col, "row": row, "span": span, "width": w,
			"cx": float(col) + float(span - 1) * 0.5,
			"enabled": true, "face": face, "label": label,
		}
		_set_cell_text(cell, _spec_text(spec))
		_cells.append(cell)

	_selection = -1
	_refresh_states()


## Recompute each cell's enabled state + dynamic glyph/tint, keep the selection on
## an enabled cell, and move the highlight. Cheap — runs each frame while shown.
func _refresh_states() -> void:
	if not is_instance_valid(_target):
		return
	# 3D content can start or stop while the remote stays aimed at the same set,
	# and the grid is otherwise only built on a target change — so the key would
	# never appear. Rebuilding is cheap and only happens on the flip.
	if _target is RetroTV:
		var has_3d: bool = (_target as RetroTV).has_stereo_source()
		if has_3d != _tv_had_stereo:
			_tv_had_stereo = has_3d
			_rebuild_grid()
			return
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		var id := str(cell["id"])
		var en := _cell_enabled(id)
		cell["enabled"] = en
		var label := cell["label"] as Label3D
		if not is_instance_valid(label):
			continue
		# Keys that print the state they are IN re-read it here; the rest keep what
		# _rebuild_grid gave them. Only written on an actual change, because the fit
		# that follows a write measures the font.
		var live := _live_text(id)
		if not live.is_empty() and live != label.text:
			_set_cell_text(cell, live)
		if _target is RetroTV:
			if id == "audio_mode":
				_lean(label, _tv_side((_target as RetroTV).audio_mode))
			elif id == "stereo3d":
				_lean(label, _tv_side((_target as RetroTV).stereo_mode))
		# Colour: state tints first, then disabled/selected overrides.
		var col := COLOR_GLYPH
		if _target is RetroTV:
			if id == "power" and (_target as RetroTV).is_on():
				col = COLOR_GLYPH_ON
			elif id == "mute" and (_target as RetroTV).is_muted():
				col = COLOR_GLYPH_MUTE
		if not en:
			col = COLOR_GLYPH_DISABLED
		elif i == _selection:
			col = COLOR_GLYPH_SELECTED if col == COLOR_GLYPH else col
		label.modulate = col

	# Keep selection valid (target flipped a group off, or first build).
	if _selection < 0 or _selection >= _cells.size() or not bool(_cells[_selection]["enabled"]):
		_selection = _first_enabled()
	_refresh_highlight()


## True when the target is actively playing (not stopped, not paused).
func _target_playing() -> bool:
	if not is_instance_valid(_target):
		return false
	if not bool(_target.get("is_playing")):
		return false
	if _target.has_method("is_paused"):
		return not bool(_target.call("is_paused"))
	return true


func _first_enabled() -> int:
	for i in _cells.size():
		if bool(_cells[i]["enabled"]):
			return i
	return -1


func _refresh_highlight() -> void:
	if _selection < 0 or _selection >= _cells.size():
		_hilite.visible = false
		return
	var cell: Dictionary = _cells[_selection]
	var span := float(cell["span"])
	(_hilite.mesh as QuadMesh).size = Vector2(_cell_width(span) + 0.005, CELL_H + 0.005)
	_hilite.position = _cell_center(float(cell["col"]), int(cell["row"]), span) + Vector3(0, 0, 0.0016)
	_hilite.visible = true


# ── Selection input ───────────────────────────────────────────────────────────

func _process_vr_selection() -> void:
	var ctrl := _holding_ctrl
	var v := ctrl.get_vector2("primary")
	if _stick_latched:
		if v.length() < STICK_REARM:
			_stick_latched = false
	elif absf(v.y) >= absf(v.x):
		if v.y > STICK_STEP:
			_move_grid(0, -1); _stick_latched = true
		elif v.y < -STICK_STEP:
			_move_grid(0, 1); _stick_latched = true
	else:
		if v.x > STICK_STEP:
			_move_grid(1, 0); _stick_latched = true
		elif v.x < -STICK_STEP:
			_move_grid(-1, 0); _stick_latched = true

	var confirm := ctrl.get_float("ax_button") > 0.5 or ctrl.get_float("primary_click") > 0.5
	if confirm and not _prev_confirm:
		_activate_selected()
	_prev_confirm = confirm


## Move the highlight to the nearest enabled cell in the given grid direction
## (dcol/drow ∈ {-1,0,1}); no-op if there's no enabled cell that way.
func _move_grid(dcol: int, drow: int) -> void:
	if _selection < 0 or _selection >= _cells.size():
		_selection = _first_enabled()
		_refresh_highlight()
		return
	var cur: Dictionary = _cells[_selection]
	var best := -1
	var best_score := INF
	for i in _cells.size():
		if i == _selection or not bool(_cells[i]["enabled"]):
			continue
		var c: Dictionary = _cells[i]
		var ddc := float(c["cx"]) - float(cur["cx"])
		var ddr := float(c["row"]) - float(cur["row"])
		if drow < 0 and ddr >= 0.0: continue
		if drow > 0 and ddr <= 0.0: continue
		if dcol < 0 and ddc >= 0.0: continue
		if dcol > 0 and ddc <= 0.0: continue
		# Left/right never leaves the row. A cell spanning the full width (Menu,
		# Eject) therefore has no horizontal neighbour at all — reach the row below
		# it with down, not by sliding sideways into it.
		if dcol != 0 and not is_zero_approx(ddr):
			continue
		var score := 0.0
		if drow != 0:
			score = absf(ddr) * 10.0 + absf(ddc)   # nearest row, then nearest column
		else:
			score = absf(ddc)
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		_selection = best
		_refresh_highlight()


## Desktop: arrow keys move the highlight, Enter activates (left-click is already
## taken by desktop_pickup's drop).
func _unhandled_input(event: InputEvent) -> void:
	if not _desktop_held:
		return
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	if not grid_menu_on():
		# The keys as the menu: the arrows walk the light, Enter holds the lit key down.
		var moves := {KEY_UP: Vector2(0, 1), KEY_DOWN: Vector2(0, -1), KEY_LEFT: Vector2(-1, 0),
			KEY_RIGHT: Vector2(1, 0)}
		if key.pressed and moves.has(key.physical_keycode):
			move_key(moves[key.physical_keycode])
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
			if key.pressed:
				key_press_down()
			else:
				key_press_up()
			get_viewport().set_input_as_handled()
		return
	if _target == null or not key.pressed:
		return
	match key.physical_keycode:
		KEY_UP:
			_move_grid(0, -1); get_viewport().set_input_as_handled()
		KEY_DOWN:
			_move_grid(0, 1); get_viewport().set_input_as_handled()
		KEY_LEFT:
			_move_grid(-1, 0); get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_move_grid(1, 0); get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_activate_selected(); get_viewport().set_input_as_handled()


func _activate_selected() -> void:
	if _selection < 0 or _selection >= _cells.size() or not is_instance_valid(_target):
		return
	var cell: Dictionary = _cells[_selection]
	if not bool(cell["enabled"]):
		return
	_activate(str(cell["id"]))
	_flash_key(str(cell["id"]))
	# Power/mute/play-pause state may have changed — refresh glyphs/tints.
	_refresh_states()


## A single Play/Pause cell: pause if actively playing, else (re)start playback.
func _toggle_playpause(player: Node) -> void:
	if _target_playing():
		player.call("remote_pause")
	else:
		player.call("remote_play")


func _activate(id: String) -> void:
	if _target is RetroTV:
		var tv := _target as RetroTV
		# The same line the bezel prints, so a key pressed from across the room
		# shows up in the log beside one pressed on the set.
		print("[TVRemote] %s: pressed %s" % [tv.name, id])
		match id:
			"power": tv.remote_power_toggle()
			"vol_up": tv.remote_volume_up()
			"vol_down": tv.remote_volume_down()
			"mute": tv.remote_mute_toggle()
			"audio_mode": tv.set_audio_mode(tv.next_audio_mode())
			# Not a modulo here: the set skips a position that would sound identical
			# to the one it is on, which this file cannot know about.
			"audio_out": tv.remote_audio_out_cycle()
			"stereo3d": tv.set_stereo_mode(tv.next_stereo_mode())
			"aspect": tv.toggle_aspect()
			"source": tv.remote_source_cycle()
			"ch_up": tv.remote_channel_up()
			"ch_down": tv.remote_channel_down()
	elif _target is VCRPlayer:
		var vcr := _target as VCRPlayer
		match id:
			"eject": vcr.remote_eject()
			"playpause": _toggle_playpause(vcr)
			"stop": vcr.remote_stop()
			"rew": vcr.remote_rewind()
			"ff": vcr.remote_ff()
	elif _target is RetroAudioPlayer:
		var ap := _target as RetroAudioPlayer
		match id:
			"playpause": _toggle_playpause(ap)
			"stop": ap.remote_stop()
			"rew": ap.remote_rewind()
			"ff": ap.remote_ff()
			"prev": ap.remote_prev()
			"next": ap.remote_next()
	elif _target is DVDPlayer:
		var dvd := _target as DVDPlayer
		match id:
			"eject": dvd.remote_eject()
			"up": dvd.dvd_menu_up()
			"down": dvd.dvd_menu_down()
			"left": dvd.dvd_menu_left()
			"right": dvd.dvd_menu_right()
			"ok": dvd.dvd_ok()
			"menu": dvd.dvd_root_menu()
			"prev_ch": dvd.dvd_prev_chapter()
			"next_ch": dvd.dvd_next_chapter()
			"playpause": _toggle_playpause(dvd)
			"rew": dvd.remote_rewind()
			"ff": dvd.remote_ff()
			"stop": dvd.remote_stop()
			"audio": dvd.dvd_cycle_audio()
			"subtitle": dvd.dvd_cycle_subtitle()


# ── Menu transform ────────────────────────────────────────────────────────────

## Position the menu. VR: float above the remote and billboard to the camera.
## Desktop: fixed camera-local anchor (the remote is FPS-snapped to the camera, so
## anchoring to it would make the menu wander as the player looks around).
func _update_menu_transform() -> void:
	if _menu == null or not _menu.visible:
		return
	var cam := get_viewport().get_camera_3d()

	if _desktop_held:
		if is_instance_valid(cam):
			_menu.global_transform = Transform3D(
				cam.global_transform.basis,
				cam.global_transform * DESKTOP_MENU_OFFSET)
		return

	_menu.global_position = global_position + Vector3(0, FLOAT_HEIGHT, 0)
	_menu.scale = Vector3.ONE * VR_MENU_SCALE
	if is_instance_valid(cam):
		var to_cam := cam.global_position - _menu.global_position
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.0001:
			_menu.look_at(cam.global_position, Vector3.UP)
			_menu.rotate_object_local(Vector3.UP, PI)


