## GbPrinter — the Game Boy Printer (MGB-007), the object you can pick up.
##
## A machine of its own the way a standalone VMU is: it grows a Libretro node and
## runs a core, `gbprinter`, which is RetroXR's own (RetroXR/gbprinter-libretro).
## That core has no CPU and loads nothing. It joins the frontend's link bus on the
## "gb-sio" wire the Game Boy cores already speak, and answers a Game Boy the way
## the printer does -- so cabling this to a Game Boy with the ordinary link lead
## is all it takes for a game to print, on gambatte or mGBA alike, and neither of
## them knows the far end is not another Game Boy.
##
## The paper is the core's video frame: 160 dots a line, oldest line at the top,
## the newest at the head. It is drawn on a strip standing out of the slot, as
## long as the paper the core has fed, and torn off onto a printout -- a Poster,
## because the real paper is sticker-backed and a print is for sticking on things.
##
## Deliberately NOT a RetroSystem, for VmuCard's reason: none of that machinery
## (televisions, cartridges, pads) has anything to say about a printer. What it
## shares with one is the duck-typed surface a link lead and a netplay session
## walk: get_libretro_node(), is_powered_on, and the net_* methods.
##
## Shaped after the real unit: 135 x 70 x 60 mm, six AA cells underneath, one
## EXT.IN socket for the link cable, a POWER switch and a FEED button, and the
## paper coming up out of a slot across the top with a serrated edge to tear it on.
## The size is the Science Museum's (object co8184142); where the controls sit
## along the top is from descriptions, not measured off a unit.
class_name GbPrinter
extends XRToolsPickable

## The spawn menu's token and the save file's type.
const SPAWN_ID := "gb_printer"
const CORE := "gbprinter"

## One dot, and one line of paper, in metres: the printed picture is 22 mm wide
## on 38 mm paper (Wikipedia, "Game Boy Printer"), so 160 dots make 0.1375 mm a
## dot. Lines are taken to be as far apart as dots, which keeps a Camera picture
## its own shape on the paper.
const DOT_PITCH := 0.0001375
const PAPER_WIDTH := 0.038
## What stands out of the slot with nothing printed: the end of the roll.
const STUB_LENGTH := 0.004
## How far the slot sends the paper back from upright, toward the roll cover.
## From there it bends as paper does (GbPrinterStrip).
const PAPER_LEAN_DEG := 8.0
## The strip's mesh is laid again once a point of it has moved this far, meters.
const PAPER_REDRAW := 0.00005
## The tear trigger is at least this thick, so a strip standing edge-on to the
## pointer can still be pointed at.
const PAPER_HIT_THICKNESS := 0.003
## How wide the highlight round the paper is, meters (GbPaperRim).
const PAPER_RIM := 0.0015
## How often the room round the paper is looked for, seconds, and how far down
## under the printer.
const FLOOR_EVERY := 0.2
const FLOOR_REACH := 1.5
## Down from every ROOM_SAMPLE of paper, from ROOM_LIFT above it to ROOM_DROP
## below, meters; and each patch found reaches PATCH_REACH each way along it,
## a little over half the spacing so neighbors meet. No further: a patch found
## at a table's edge reaches past it into the air, and at 4 cm a long print's end
## lay out on nothing beyond the edge instead of hanging over it.
const ROOM_SAMPLE := 0.02
const ROOM_LIFT := 0.01
const ROOM_DROP := 0.15
const PATCH_REACH := 0.012
## The gear's turn, as the core keeps it (gbprinter-libretro src/sound.c: keep
## these and its TURN_S and TURN_OFFSET_S the same): 1.1407 s a turn, each a
## little longer or shorter by a fixed pattern, starting at the knock when the
## motor starts. The room cannot hear the core, so it counts the same turns
## from the same start and jolts the paper as each knocks. The motor runs on a
## line and a half after the last (the core's MOTOR_TAIL).
const TURN_S := 1.1407
const TURN_OFFSET_S: Array[float] = [0.004, -0.009, 0.002, 0.011, -0.005, -0.001, 0.008, -0.010]
const MOTOR_TAIL_S := 1.5 * 240000.0 / 8388608.0
## The knock's kick to the paper's swing, rad/s; the stub's flick back as the
## print tears off it.
const KNOCK_JOLT := 1.2
const TEAR_FLICK := -2.5
## A fingertip, as the paper meets it: round, this radius, meters; and only
## within FINGER_NEAR of the slot.
const FINGER_RADIUS := 0.009
const FINGER_NEAR := 0.5

## Libretro joypad ids, as bits of the mask: the core's FEED and TEAR.
const BTN_B := 1 << 0
const BTN_A := 1 << 8
## How long TEAR is held down, in frames. The core acts on the press, so this
## only has to outlast one of its frames whatever the window's rate.
const TEAR_FRAMES := 6

## The sound's distance law: a handheld's, as VmuCard's standalone buzzer uses.
const AUDIO_UNIT_SIZE := 3.0
const AUDIO_MAX_DISTANCE := 15.0

## Where prints are written, under the data root.
const PRINTS_DIR := "prints"
const POSTER_SCENE := preload("res://Scenes/Objects/media/poster.tscn")
const PAPER_SHADER := preload("res://Shaders/gb_printer_paper.gdshader")

## What its menu (ObjectOptionsPanel) is titled.
var display_name := "Game Boy Printer"
## Read by LinkCable._watch, like RetroSystem's.
var is_powered_on := false
## Why net_prepare_boot last refused, in words the session shows the player.
var net_boot_failure: String = ""
## The roll it is loaded with, an id of GbPrinterPaper.ROLLS; saved with the room.
## The strip on it shows the roll at once. A print already torn off keeps the
## roll it came off: its colors are in its file.
var paper_roll: String = GbPrinterPaper.ROLLS[0]["id"]:
	set(value):
		paper_roll = str(GbPrinterPaper.roll(value)["id"])
		_show_roll()

var _lib: Node = null
var _mask := -1
var _alx := -1
var _aly := -1
var _tear_frames := 0
var _tear_lines := 0
var _tear_code := 0
var _shown_tex: Texture2D = null
var _shown_lines := -1
## The strip as the room keeps it, from a core sending windows of it
## (GbPaperLines); `_windowed` once one has. A core from before sends the
## whole strip, shown straight off its frame.
var _paper_lines := GbPaperLines.new()
var _windowed := false
var _end_seen := 0
var _paper_mat: ShaderMaterial = null
var _paper_arrays: ArrayMesh = null
## The highlight round the paper (GbPaperRim), shown as the tear trigger's
## outline would be, and its material.
var _paper_rim: MeshInstance3D = null
var _paper_rim_mat: StandardMaterial3D = null
var _paper_box: BoxShape3D = null
## The paper's bend, and the points its mesh was last laid from.
var _strip := GbPrinterStrip.new()
var _drawn := PackedVector2Array()
## The slot as it was last frame, for its acceleration and turn.
var _motion := GbPaperMotion.new()
## The gear's turn (TURN_S): how far round, how many since the motor started,
## how long this one takes, and how long the motor runs on.
var _turn := 0.0
var _turns := 0
var _turn_s := TURN_S
var _motor_left := 0.0
var _lines_seen := 0
## The hands whose fingertips push the paper (XRController3D, found once).
var _controllers: Array[XRController3D] = []
var _floor_wait := 0.0
## What the last looks round the paper found, in the room: [position, normal].
var _room_hits: Array = []
@onready var _pivot: Node3D = $PaperPivot
var _toast: AchievementToast = null
## Said once per press, not every frame it is held.
var _feed_refused := false
var _voices := PackedInt32Array()
var _gain := -1.0
var _mx: Object = null
var _listener: Node = null
## The plug seated in the socket, so pulling it can undo the collision exception
## the seating made (ILinkHub's reason).
var _held_plug: PhysicsBody3D = null

@onready var _port: LinkPort = $LinkPort
@onready var _power: VRButton = $PowerSwitch
@onready var _feed: VRButton = $FeedButton
@onready var _led: MeshInstance3D = $PowerLed
@onready var _paper: VRButton = $PaperPivot/Paper
@onready var _paper_mesh: MeshInstance3D = $PaperPivot/Paper/ButtonMesh
@onready var _paper_shape: CollisionShape3D = $PaperPivot/Paper/CollisionShape3D


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group("gb_printer")
	_power.button_pressed.connect(toggle_power)
	_paper.button_pressed.connect(tear)
	_port.has_picked_up.connect(_on_plug_seated)
	_port.has_dropped.connect(_on_plug_pulled)

	# Each printer its own mesh, shape and material: the strip's length and bend
	# are per printer.
	_paper_arrays = ArrayMesh.new()
	_paper_mesh.mesh = _paper_arrays
	_paper_box = BoxShape3D.new()
	_paper_shape.shape = _paper_box
	_paper_mat = ShaderMaterial.new()
	_paper_mat.shader = PAPER_SHADER
	_paper_mat.set_shader_parameter("dots_frac", GbPrinterPaper.DOTS * DOT_PITCH / PAPER_WIDTH)
	_paper_mesh.material_override = _paper_mat
	# Its outline round it, not over it (GbPaperRim): the tear trigger's own
	# inflated hull covered the strip in its color.
	_paper.builtin_outline = false
	_paper_rim = MeshInstance3D.new()
	_paper_rim.name = "PaperRim"
	_paper_rim.add_to_group("outline_exclude")
	_paper_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_paper_rim.visible = false
	_paper_rim_mat = GbPaperRim.material(WidgetOutline.HOVER_COLOR)
	_paper_rim.material_override = _paper_rim_mat
	_paper.add_child(_paper_rim)
	_show_roll()
	# Leaning back off the slot a little, the way the slot sends it. Set here
	# rather than written into the scene as a matrix (CLAUDE.md's row/column
	# trap); a positive pitch would lean it over the front instead.
	_pivot.rotation.x = -deg_to_rad(PAPER_LEAN_DEG)
	_lay_paper(null, 0)
	_show_power()
	# Always processing: the paper swings and settles whether or not the printer
	# is on. Off, it is the roll's end, and costs next to nothing.
	set_process(true)
	# Controllers arrive a frame after the room does (VRButton's reason).
	_find_controllers.call_deferred()


func _exit_tree() -> void:
	if is_powered_on and _lib != null:
		_lib.StopContent()
	is_powered_on = false
	super._exit_tree()


# --- Power ----------------------------------------------------------------------

func toggle_power() -> void:
	if is_powered_on:
		power_off()
	else:
		power_on()


## Switch on: start the core and put it on whatever lead is in the socket.
## False when the core is not installed, which is said to the player.
func power_on() -> bool:
	if is_powered_on:
		return true
	var why := standalone_blocker()
	if not why.is_empty():
		_notice("Printer core missing", why)
		return false
	if not _ensure_lib():
		return false
	_ask_for_windows()
	_lib.StartContent(CoreDownloadManager.default_core_root(), CORE, "")
	_started()
	return true


func power_off() -> void:
	if not is_powered_on:
		return
	# A printer in a session stops on every peer; the session calls net_stop_core.
	if NetworkManager.netplay_running() and NetworkManager.netplay_covers(self) \
			and not NetworkManager.is_event_applying():
		NetworkManager.netplay_stop("Game Boy Printer switched off")
		if not is_powered_on:
			return
	# Paper still hanging out of the slot comes away with the power, rather than
	# going down with the core: tearing it off is what a player would do first.
	tear()
	_stopped()


## Why the printer cannot be switched on, or "" when it can.
func standalone_blocker() -> String:
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		return "Download it in OPTIONS > Cores > BIOS / Extras > Game Boy."
	return ""


func _started() -> void:
	is_powered_on = true
	_mask = -1
	_alx = -1
	_aly = -1
	_tear_frames = 0
	_shown_tex = null
	_shown_lines = -1
	_paper_lines.clear()
	_windowed = false
	_end_seen = 0
	_show_power()
	_rejoin_lead()


func _stopped() -> void:
	if _lib != null:
		_lib.StopContent()
	is_powered_on = false
	_show_power()
	_lay_paper(null, 0)
	_rejoin_lead()


## The strip a window at a time, kept here (GbPaperLines): set before the core
## starts, held until it says what it understands. A core from before has no
## such option and sends the whole strip as it always did.
func _ask_for_windows() -> void:
	_lib.SetCoreOption(GbPaperLines.OPTION, GbPaperLines.WINDOWS)


## Made once and KEPT, as VmuCard's is: freeing a Libretro node whose emulation
## thread is still unwinding takes the process down.
func _ensure_lib() -> bool:
	if _lib != null:
		return true
	var lib: Object = ClassDB.instantiate("Libretro")
	_lib = lib as Node
	if _lib == null:
		push_warning("[GbPrinter] could not instantiate a Libretro node")
		return false
	_lib.name = "PrinterLibretro"
	add_child(_lib)
	return true


## Re-state the lead in the socket. Stopping or starting a core changes what is
## on the bus without moving a plug, and only a moving plug makes a lead look
## again -- RetroSystem.net_refresh_link_cables, for one socket.
func _rejoin_lead() -> void:
	var plug := _port.picked_up_object
	if plug == null:
		return
	var cable: Object = plug.get("cable")
	if cable != null and is_instance_valid(cable) and cable.has_method("rejoin"):
		cable.call("rejoin")


func _show_power() -> void:
	_power.set_latched_pressed(is_powered_on)
	var mat := _led.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		mat.emission_enabled = is_powered_on
		mat.albedo_color = Color(0.9, 0.12, 0.1) if is_powered_on else Color(0.25, 0.05, 0.05)


func _notice(title: String, text: String) -> void:
	if not is_instance_valid(_toast):
		_toast = AchievementToast.attach_to_machine(self)
	if _toast != null:
		_toast.show_notice("Game Boy Printer", title, text)


# --- Buttons and paper ------------------------------------------------------------

func _process(delta: float) -> void:
	if is_powered_on and _lib != null:
		_drive_core()
	_move_paper(delta)


## FEED and TEAR into the core, and the paper and sound out of it.
func _drive_core() -> void:
	var mask := 0
	var alx := 0
	var aly := 0
	if _feed.is_held():
		if _presses_count():
			mask |= BTN_A
		elif not _feed_refused:
			_feed_refused = true
			_notice("Printer", "Pick the printer up to feed paper during a session.")
	else:
		_feed_refused = false
	if _tear_frames > 0:
		_tear_frames -= 1
		mask |= BTN_B
		alx = _tear_lines
		aly = _tear_code
	if mask != _mask or alx != _alx or aly != _aly:
		_push_input(mask, alx, aly)

	var took := _paper_lines.take(_lib.GetVideoImage())
	if took >= 0:
		_windowed = true
		if _paper_lines.end > _end_seen:
			motor_ran()
		_end_seen = _paper_lines.end
		if took > 0:
			_lay_lines()
	else:
		var tex: Texture2D = _lib.GetVideoTexture()
		var lines := 0
		if tex != null and tex.get_width() == GbPrinterPaper.DOTS:
			lines = tex.get_height()
		if lines > _lines_seen:
			motor_ran()
		_lines_seen = lines
		_lay_paper(tex if lines > 0 else null, lines)
	_update_audio()


## Pose the core's voices on the printer: its motor and head are the core's sound,
## and Meta XR Audio mixes a voice only once its owner has posed it. VmuCard's
## standalone buzzer, for the same reason -- a RetroSystem is what poses a
## machine's voices, and this is not one. Empty on the fallback player, which is
## already a child of the printer.
func _update_audio() -> void:
	var voices: PackedInt32Array = _lib.GetAudioVoiceIds()
	if voices != _voices:
		_voices = voices
		_gain = -1.0
		if _mx == null and Engine.has_singleton("MetaXRAudio"):
			_mx = Engine.get_singleton("MetaXRAudio")
		if _mx != null:
			for v in voices:
				_mx.set_voice_directivity(v, SpatialAudioEmitter.SPEAKER_DIRECTIVITY)
	if voices.is_empty() or _mx == null:
		return
	if _listener == null or not is_instance_valid(_listener):
		_listener = get_node_or_null("/root/SpatialAudioListener")
		if _listener == null:
			return
	var listener_pos: Vector3 = _listener.get_listener_position()
	var pos := global_position
	var at := SpatialAudioEmitter.hold_off_head(pos, listener_pos)
	for v in voices:
		_mx.set_voice_pose(v, at, global_transform.basis.y.normalized(),
			global_transform.basis.z.normalized())
	var gain := SpatialAudioEmitter.distance_gain(pos, listener_pos,
		AUDIO_UNIT_SIZE, AUDIO_MAX_DISTANCE)
	if not is_equal_approx(gain, _gain):
		_gain = gain
		for v in voices:
			_mx.set_voice_gain(v, gain)


## What reaches the core. In a session the port is the session's, so a press goes
## through it and every peer's printer sees it on the same frame -- and NEVER
## straight into this peer's core, even when the session swallows it because
## another peer drives the port: a press only one peer's printer saw is paper
## only one peer has.
func _push_input(mask: int, alx: int, aly := 0) -> void:
	_mask = mask
	_alx = alx
	_aly = aly
	if _in_session():
		NetworkManager.netplay_route(self, 0, {"btn": mask, "alx": alx, "aly": aly})
		return
	_lib.SetJoypadState(0, mask, alx, aly, 0, 0)


func _in_session() -> bool:
	return NetworkManager.netplay_running() and NetworkManager.netplay_covers(self)


## Whether a press here reaches the printer: always alone, and in a session only
## for the peer that drives its port -- whoever is holding it.
func _presses_count() -> bool:
	return not _in_session() or NetworkManager.netplay_owns_port(self, 0)


## Size the strip to `lines` of paper and show `tex` on it. The pivot sits at the
## slot and the strip comes out of it, so the newest line is always at the head.
## How it bends is _move_paper's.
func _lay_paper(tex: Texture2D, lines: int) -> void:
	if tex == _shown_tex and lines == _shown_lines:
		return
	_shown_tex = tex
	_shown_lines = lines
	_strip.set_length(maxf(STUB_LENGTH, lines * DOT_PITCH))
	_paper_mat.set_shader_parameter("layered", false)
	_paper_mat.set_shader_parameter("print_tex", tex)
	_draw_paper()


## The strip the room keeps (GbPaperLines) onto the paper: the chunks a frame
## touched uploaded, and the paper as long as the lines out.
func _lay_lines() -> void:
	if _paper_lines.upload():
		_paper_mat.set_shader_parameter("print_layers", _paper_lines.texture)
	var lines := _paper_lines.lines()
	_paper_mat.set_shader_parameter("layered", true)
	_paper_mat.set_shader_parameter("layer_count", _paper_lines.layers)
	_paper_mat.set_shader_parameter("line_first", _paper_lines.first)
	_paper_mat.set_shader_parameter("line_count", lines)
	_shown_tex = null
	if lines == _shown_lines:
		return
	_shown_lines = lines
	_strip.set_length(maxf(STUB_LENGTH, lines * DOT_PITCH))
	_draw_paper()


## The length of paper out of the slot, meters.
func paper_length() -> float:
	return _strip.length


## The roll's colors onto the strip.
func _show_roll() -> void:
	if _paper_mat == null:
		return
	var r := GbPrinterPaper.roll(paper_roll)
	var paper: Color = r["paper"]
	var ink: Color = r["ink"]
	_paper_mat.set_shader_parameter("paper_color", Vector3(paper.r, paper.g, paper.b))
	_paper_mat.set_shader_parameter("ink_color", Vector3(ink.r, ink.g, ink.b))


## What the generic object menu offers to choose (ObjectOptionsPanel): the roll.
func options_choices() -> Array:
	var names: Array = []
	var at := 0
	for i in GbPrinterPaper.ROLLS.size():
		names.append(GbPrinterPaper.ROLLS[i]["name"])
		if GbPrinterPaper.ROLLS[i]["id"] == paper_roll:
			at = i
	return [{"caption": "Paper roll", "items": names, "selected": at}]


func options_choose(row: int, item: int) -> void:
	if row == 0 and item >= 0 and item < GbPrinterPaper.ROLLS.size():
		paper_roll = GbPrinterPaper.ROLLS[item]["id"]


## Step the paper's bend: gravity as the printer is turned, less the slot's own
## acceleration so a shaken printer shakes it, the printer's turn about the
## paper's hinge line so the paper lags it, and what is in its way. Drawn again
## only once it has visibly moved.
func _move_paper(delta: float) -> void:
	if delta <= 0.0:
		return
	# How the printer is moving (GbPaperMotion: off the pose it is drawn at, and
	# smoothed), at the slot.
	var xf := get_global_transform_interpolated()
	_motion.update(xf, _pivot.position, delta)
	var g := _motion.gravity
	_floor_wait -= delta
	if _floor_wait <= 0.0:
		_floor_wait = FLOOR_EVERY
		_find_obstacles()
	# The room is where it is: placed against the printer every frame, so a
	# printer tipping over it never meets it a fifth of a second late.
	_place_room(xf)
	_aim_strip()
	turn_gear(delta)
	_show_paper_rim()
	_place_fingers(xf)
	var shove := _motion.shove
	_strip.step(delta, Vector2(g.y, g.z), _motion.spin_accel, Vector2(shove.y, shove.z))
	_draw_paper()


## The rim round the paper, as the tear trigger's outline would show: green
## armed or aimed at, amber with the trigger down.
func _show_paper_rim() -> void:
	if _paper_rim == null:
		return
	var c := _paper.outline_color()
	_paper_rim.visible = c.a > 0.0
	if _paper_rim.visible:
		_paper_rim_mat.albedo_color = c


## Paper came out: the motor runs on for MOTOR_TAIL_S, and if it had stopped,
## it starts at the knock, as the core's does.
func motor_ran() -> void:
	if _motor_left <= 0.0:
		_turn = 0.0
		_turns = 0
		_turn_s = TURN_S + TURN_OFFSET_S[0]
	_motor_left = MOTOR_TAIL_S


## Turn the gear `delta` seconds while the motor runs; true when it knocked,
## and the paper is jolted.
func turn_gear(delta: float) -> bool:
	if _motor_left <= 0.0:
		return false
	_motor_left -= delta
	_turn += delta / _turn_s
	if _turn < 1.0:
		return false
	_turn -= 1.0
	_turns += 1
	_turn_s = TURN_S + TURN_OFFSET_S[_turns % TURN_OFFSET_S.size()]
	_strip.jolt(KNOCK_JOLT)
	return true


func _find_controllers() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("*", "XRController3D", true, false):
		_controllers.append(node as XRController3D)


## The fingertips across the paper's width, near the slot, as round obstacles
## in the printer's (Y, Z), placed against the printer drawn at `xf`.
func _place_fingers(xf: Transform3D) -> void:
	_strip.fingers.clear()
	var inv := xf.affine_inverse()
	for ctrl in _controllers:
		if not is_instance_valid(ctrl):
			continue
		var tip := inv * PokeTip.tip_of(ctrl)
		if absf(tip.x - _pivot.position.x) > PAPER_WIDTH * 0.5 + FINGER_RADIUS:
			continue
		if tip.distance_to(_pivot.position) > FINGER_NEAR:
			continue
		_strip.fingers.append([Vector2(tip.y, tip.z), FINGER_RADIUS])


## Where the slot is and which way it points the paper, in the printer's (Y, Z).
## The pivot only ever turns about X.
func _aim_strip() -> void:
	var up := _pivot.transform.basis.y
	_strip.place(Vector2(_pivot.position.y, _pivot.position.z), atan2(-up.z, up.y))


## What the paper meets: the printer's own boxes (the scene's, or the ones a
## shell fitted round itself), and the room, as patches of surface found by short
## rays and kept as they are in the room (_place_room puts them against the
## printer each frame):
##   under the printer's back, its slot and its front, straight down, for what it
##   stands on;
##   down from every few centimeters of the paper, for what the paper hangs over
##   (a table's top, or nothing past its edge);
##   from each of those points of the paper to the next, for what it runs into
##   (a wall, the Game Boy beside it).
## One whole surface under the slot was the paper's only room: it could not hang
## over a table's edge, and went through everything else.
func _find_obstacles() -> void:
	_strip.boxes.clear()
	var z_lo := INF
	var z_hi := -INF
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			continue
		var size := (shape.shape as BoxShape3D).size
		var c := shape.position
		_strip.boxes.append(Rect2(Vector2(c.y - size.y * 0.5, c.z - size.z * 0.5), Vector2(size.y, size.z)))
		z_lo = minf(z_lo, c.z - size.z * 0.5)
		z_hi = maxf(z_hi, c.z + size.z * 0.5)
	_room_hits.clear()
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	# Not the printer, nor its own bodies (its pointer target is a StaticBody3D
	# round the deck, which the paper would otherwise lie on in the air).
	var own: Array[RID] = [get_rid()]
	for body in find_children("*", "CollisionObject3D", true, false):
		own.append((body as CollisionObject3D).get_rid())
	var cast := func(from: Vector3, to: Vector3) -> void:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = own
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			_room_hits.append([hit["position"], hit["normal"]])
	var feet: Array[float] = [_pivot.position.z]
	if z_lo < z_hi:
		feet = [z_lo, _pivot.position.z, z_hi]
	for z: float in feet:
		var from := to_global(Vector3(_pivot.position.x, _pivot.position.y, z))
		cast.call(from, from + Vector3.DOWN * FLOOR_REACH)
	var down := (ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) as Vector3).normalized()
	var pts := _strip.points
	var every := maxi(1, ceili(ROOM_SAMPLE / (_strip.length / maxi(_strip.segments, 1))))
	var last := Vector3.INF
	for i in range(every, pts.size(), every):
		var at := to_global(Vector3(_pivot.position.x, pts[i].x, pts[i].y))
		cast.call(at - down * ROOM_LIFT, at + down * ROOM_DROP)
		if last != Vector3.INF:
			cast.call(last, at)
		last = at


## The room's patches (_find_obstacles), in the frame of the printer drawn at
## `xf` this frame, across the middle of the paper.
func _place_room(xf: Transform3D) -> void:
	_strip.planes.clear()
	_strip.patches.clear()
	var inv := xf.affine_inverse()
	var turn := xf.basis.orthonormalized().inverse()
	for hit: Array in _room_hits:
		var n: Vector3 = turn * (hit[1] as Vector3)
		var at: Vector3 = inv * (hit[0] as Vector3)
		var n2 := Vector2(n.y, n.z)
		# A surface the paper's plane is not across: the printer on its side.
		if n2.length() < 0.3:
			continue
		var offset := n.dot(at) - n.x * _pivot.position.x
		_strip.patches.append([n2 / n2.length(), offset / n2.length(), Vector2(at.y, at.z), PATCH_REACH])


## Lay the strip's mesh, the tear trigger and its box from the bend, once some
## point of it has moved. In the pivot's frame, as the pivot holds them: each
## point is (across, Y, Z) in the printer's, then into the pivot's.
func _draw_paper() -> void:
	if _paper_arrays == null:
		return
	_aim_strip()
	var pts := _strip.points
	if pts.size() == _drawn.size():
		var moved := false
		for i in pts.size():
			if pts[i].distance_squared_to(_drawn[i]) > PAPER_REDRAW * PAPER_REDRAW:
				moved = true
				break
		if not moved:
			return
	_drawn = pts.duplicate()
	var n := pts.size()
	var dirs := _strip.directions()
	var to_pivot := _pivot.transform.affine_inverse()
	var x := _pivot.position.x
	var half := PAPER_WIDTH * 0.5
	var mid := PackedVector3Array()
	mid.resize(n)
	var box := AABB()
	for i in n:
		mid[i] = to_pivot * Vector3(x, pts[i].x, pts[i].y)
		var row := AABB(mid[i] - Vector3(half, 0, 0), Vector3(PAPER_WIDTH, 0, 0))
		box = row if i == 0 else box.merge(row)
	var thick := Vector3(0.0, maxf(0.0, PAPER_HIT_THICKNESS - box.size.y),
		maxf(0.0, PAPER_HIT_THICKNESS - box.size.z))
	box = AABB(box.position - thick * 0.5, box.size + thick)
	# The AREA moves, not its mesh: VRButton puts its ButtonMesh back where it
	# found it every frame it animates, so an offset on the mesh would not last.
	var center := box.get_center()
	_paper.position = center
	_paper_box.size = box.size

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	verts.resize(n * 2)
	normals.resize(n * 2)
	uvs.resize(n * 2)
	for i in n:
		var t := dirs[i]
		# The printed face: the paper's +Z when it stands straight up out of the slot.
		var face := (to_pivot.basis * Vector3(0.0, -t.y, t.x)).normalized()
		var p := mid[i] - center
		var v := 1.0 - float(i) / float(n - 1)
		# Right then left, as QuadMesh lays a row: clockwise seen from the face.
		verts[i * 2] = p + Vector3(half, 0, 0)
		verts[i * 2 + 1] = p - Vector3(half, 0, 0)
		normals[i * 2] = face
		normals[i * 2 + 1] = face
		uvs[i * 2] = Vector2(1.0, v)
		uvs[i * 2 + 1] = Vector2(0.0, v)
	for i in n - 1:
		var r := i * 2
		index.append_array([r, r + 1, r + 2, r + 1, r + 3, r + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	_paper_arrays.clear_surfaces()
	_paper_arrays.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_paper.mesh_changed()
	if _paper_rim != null:
		var centers := PackedVector3Array()
		var along := PackedVector3Array()
		var vs := PackedFloat32Array()
		for i in n:
			centers.append(mid[i] - center)
			along.append((to_pivot.basis * Vector3(0.0, dirs[i].x, dirs[i].y)).normalized())
			vs.append(1.0 - float(i) / float(n - 1))
		_paper_rim.mesh = GbPaperRim.build(centers, along, Vector3.RIGHT, half, PAPER_RIM, vs)


## Tear the paper off at the serrated edge.
##
## The picture comes from what this printer can see NOW, and the press that tells
## the core to let it go carries how many lines that was -- so a line burned in
## the frame or two before the core hears about it stays on the roll instead of
## going into the bin unseen.
func tear() -> void:
	if not is_powered_on or _lib == null or _tear_frames > 0:
		return
	if not _presses_count():
		_notice("Printer", "Pick the printer up to tear the paper off during a session.")
		return
	var img: Image = _paper_lines.image() if _windowed else _lib.GetVideoImage()
	if img == null or img.is_empty() or img.get_width() != GbPrinterPaper.DOTS:
		return
	var lines := img.get_height()
	var r := GbPrinterPaper.roll(paper_roll)
	var path := GbPrinterPaper.save_print(img, DataPaths.media_root(PRINTS_DIR),
		r["paper"], r["ink"])
	if path.is_empty():
		push_warning("[GbPrinter] could not write the print")
	else:
		_hand_over(_spawn_printout(path, lines))
	# A count (LX) for a core that sends the whole strip; where the strip ended
	# (LY) for one sending windows, the count no longer fitting an axis.
	_tear_lines = mini(lines, 32767)
	_tear_code = _paper_lines.tear_code() if _windowed else 0
	_tear_frames = TEAR_FRAMES
	# What is left in the slot flicks back as the print comes away.
	_strip.jolt(TEAR_FLICK)
	if _mask >= 0:
		_push_input(_mask | BTN_B, _tear_lines, _tear_code)


## A Poster the size of the paper, carrying the print. Placed at the free end of
## the strip it came from, facing as that end did.
func _spawn_printout(path: String, lines: int) -> Poster:
	var poster := POSTER_SCENE.instantiate() as Poster
	var long_edge := maxf(PAPER_WIDTH, lines * DOT_PITCH)
	# Before image_path: the setter loads the picture and sizes the sheet from
	# size_scale as it stands.
	poster.size_scale = long_edge / Poster.BASE_LONG_EDGE
	# Paper, not a board: it bends in the hand (GbPrintoutFlop), starting as bent
	# as the strip it came off.
	poster.printout = true
	poster.set_meta(GbPrintoutFlop.BEND_META, _strip.mean_curvature())
	poster.image_path = path
	var scene := get_tree().current_scene
	scene.add_child(poster)
	poster.add_to_group("spawned")
	var tip := _strip.points[_strip.points.size() - 1]
	var dirs := _strip.directions()
	var along := dirs[dirs.size() - 1]
	var basis := global_transform.basis.orthonormalized()
	var x := basis.x
	var y := (basis * Vector3(0.0, along.x, along.y)).normalized()
	var top := to_global(Vector3(_pivot.position.x, tip.x, tip.y))
	poster.global_transform = Transform3D(Basis(x, y, x.cross(y)), top + Vector3.UP * 0.02)
	NetworkManager.on_local_spawn(poster)
	return poster


## Into the hand that tore it, when one is free; otherwise it stays where it was
## torn, standing above the printer.
func _hand_over(poster: Poster) -> void:
	if poster == null or not is_instance_valid(poster) or NetworkManager.is_client():
		return
	var controller := _paper.held_by()
	if controller != null:
		var pickup := XRToolsFunctionPickup.find_instance(controller)
		if pickup != null and pickup.picked_up_object == null:
			pickup.call("_pick_up_object", poster)
		return
	var hand := get_tree().get_first_node_in_group("desktop_hand")
	if hand != null and hand.has_method("owner_pickup"):
		var grabber: Node = hand.call("owner_pickup")
		if grabber != null and grabber.has_method("grab_spawned") \
				and not bool(grabber.call("is_holding")):
			grabber.call("grab_spawned", poster)


# --- The socket -----------------------------------------------------------------

## So RcaPort.get_device() finds an owner for the socket, which is what a save
## records a seated plug against. Nothing about picture or sound passes here.
func on_av_topology_changed(_links: Array) -> void:
	pass


func _on_plug_seated(what: Node) -> void:
	var body := what as PhysicsBody3D
	if body == null:
		return
	add_collision_exception_with(body)
	_held_plug = body


func _on_plug_pulled() -> void:
	if is_instance_valid(_held_plug):
		remove_collision_exception_with(_held_plug)
	_held_plug = null


# --- Netplay ----------------------------------------------------------------------
#
# A printer joins a session as a member of the Game Boy's group, found through the
# lead (LinkCable.linked_machines), never as the anchor. Every peer runs its own
# printer beside its own copy of the Game Boy, and the two step in LOCKSTEP: the
# core's frames are exactly the Game Boy's, so the bus never has one waiting on the
# other. Nobody needs to hold it; whoever does drives FEED and TEAR through the
# session.

func get_libretro_node() -> Node:
	return _lib


func resolve_core_name() -> String:
	return CORE


func port_holders() -> Array:
	return [self]


func net_rom_md5() -> String:
	return ""


func net_boot_spec(_core: String) -> Dictionary:
	return {"mode": "no_content"}


func net_prepare_boot(_spec: Dictionary) -> bool:
	net_boot_failure = standalone_blocker()
	if not net_boot_failure.is_empty():
		net_boot_failure = "the Game Boy Printer core is not installed"
		return false
	return true


func net_sram_file_bytes() -> PackedByteArray:
	return PackedByteArray()


func net_set_sram(_path: String, _data: PackedByteArray) -> void:
	pass


func net_start_core(_core: String, port_mask: int, start_frame: int,
		_options: Dictionary) -> Node:
	if is_powered_on:
		_stopped()
	if not _ensure_lib():
		return null
	# The gate before StartContent, so the core holds at the start frame until
	# inputs post -- as RetroSystem.net_start_core does.
	_lib.SetNetplayMode(true, port_mask, start_frame)
	_ask_for_windows()
	_lib.StartContent(CoreDownloadManager.default_core_root(), CORE, "")
	_started()
	return _lib


func net_stop_core() -> void:
	if _lib != null:
		_lib.SetNetplayMode(false, 1, 0)
	if is_powered_on:
		_stopped()


func net_play_reset() -> void:
	pass
