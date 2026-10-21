## GbPrinter — the Game Boy Printer (MGB-007), the object you can pick up.
##
## A machine of its own the way a standalone VMU is: it grows a Libretro node and
## runs a core, `gbprinter`, which is RetroXR's own (RetroXR/gbprinter-libretro).
## That core has no CPU and loads nothing. It joins the frontend's link bus on the
## "gb-sio-1" wire the Game Boy cores already speak, and answers a Game Boy the way
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
## How far the strip leans back from upright, toward the roll cover.
const PAPER_LEAN_DEG := 8.0

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

## Read by LinkCable._watch, like RetroSystem's.
var is_powered_on := false
## Why net_prepare_boot last refused, in words the session shows the player.
var net_boot_failure: String = ""

var _lib: Node = null
var _mask := -1
var _alx := -1
var _tear_frames := 0
var _tear_lines := 0
var _shown_tex: Texture2D = null
var _shown_lines := -1
var _paper_mat: ShaderMaterial = null
var _paper_quad: QuadMesh = null
var _paper_box: BoxShape3D = null
var _toast: AchievementToast = null
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

	# Each printer its own mesh, shape and material: the strip's length is per
	# printer, and a shared QuadMesh would grow on every printer in the room.
	_paper_quad = QuadMesh.new()
	_paper_mesh.mesh = _paper_quad
	_paper_box = BoxShape3D.new()
	_paper_shape.shape = _paper_box
	_paper_mat = ShaderMaterial.new()
	_paper_mat.shader = PAPER_SHADER
	_paper_mat.set_shader_parameter("dots_frac", GbPrinterPaper.DOTS * DOT_PITCH / PAPER_WIDTH)
	_paper_mesh.set_surface_override_material(0, _paper_mat)
	# Leaning back off the slot a little, as paper does once it has some length.
	# Set here rather than written into the scene as a matrix (CLAUDE.md's row/
	# column trap); a positive pitch would lean it over the front instead.
	($PaperPivot as Node3D).rotation.x = -deg_to_rad(PAPER_LEAN_DEG)
	_lay_paper(null, 0)
	_show_power()
	set_process(false)


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
	_tear_frames = 0
	_shown_tex = null
	_shown_lines = -1
	_show_power()
	set_process(true)
	_rejoin_lead()


func _stopped() -> void:
	if _lib != null:
		_lib.StopContent()
	is_powered_on = false
	_show_power()
	_lay_paper(null, 0)
	set_process(false)
	_rejoin_lead()


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

func _process(_delta: float) -> void:
	if not is_powered_on or _lib == null:
		return
	var mask := 0
	var alx := 0
	if _feed.is_held():
		mask |= BTN_A
	if _tear_frames > 0:
		_tear_frames -= 1
		mask |= BTN_B
		alx = _tear_lines
	if mask != _mask or alx != _alx:
		_push_input(mask, alx)

	var tex: Texture2D = _lib.GetVideoTexture()
	var lines := 0
	if tex != null and tex.get_width() == GbPrinterPaper.DOTS:
		lines = tex.get_height()
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
## through it and every peer's printer sees it on the same frame.
func _push_input(mask: int, alx: int) -> void:
	_mask = mask
	_alx = alx
	if not NetworkManager.netplay_route(self, 0, {"btn": mask, "alx": alx}):
		_lib.SetJoypadState(0, mask, alx, 0, 0, 0)


## Size the strip to `lines` of paper and show `tex` on it. The pivot sits at the
## slot and the strip rises from it, so the newest line is always at the head.
func _lay_paper(tex: Texture2D, lines: int) -> void:
	if tex == _shown_tex and lines == _shown_lines:
		return
	_shown_tex = tex
	_shown_lines = lines
	var length := maxf(STUB_LENGTH, lines * DOT_PITCH)
	_paper_quad.size = Vector2(PAPER_WIDTH, length)
	_paper_box.size = Vector3(PAPER_WIDTH, length, 0.003)
	# The AREA moves, not its mesh: VRButton puts its ButtonMesh back where it
	# found it every frame it animates, so an offset on the mesh would not last.
	_paper.position = Vector3(0.0, length * 0.5, 0.0)
	_paper_mat.set_shader_parameter("print_tex", tex)


## Tear the paper off at the serrated edge.
##
## The picture comes from what this printer can see NOW, and the press that tells
## the core to let it go carries how many lines that was -- so a line burned in
## the frame or two before the core hears about it stays on the roll instead of
## going into the bin unseen.
func tear() -> void:
	if not is_powered_on or _lib == null or _tear_frames > 0:
		return
	var img: Image = _lib.GetVideoImage()
	if img == null or img.is_empty() or img.get_width() != GbPrinterPaper.DOTS:
		return
	var lines := img.get_height()
	var path := GbPrinterPaper.save_print(img, DataPaths.media_root(PRINTS_DIR))
	if path.is_empty():
		push_warning("[GbPrinter] could not write the print")
	else:
		_hand_over(_spawn_printout(path, lines))
	_tear_lines = lines
	_tear_frames = TEAR_FRAMES
	if _mask >= 0:
		_push_input(_mask | BTN_B, lines)


## A Poster the size of the paper, carrying the print. Placed at the top of the
## strip it came from.
func _spawn_printout(path: String, lines: int) -> Poster:
	var poster := POSTER_SCENE.instantiate() as Poster
	var long_edge := maxf(PAPER_WIDTH, lines * DOT_PITCH)
	# Before image_path: the setter loads the picture and sizes the sheet from
	# size_scale as it stands.
	poster.size_scale = long_edge / Poster.BASE_LONG_EDGE
	poster.image_path = path
	var scene := get_tree().current_scene
	scene.add_child(poster)
	poster.add_to_group("spawned")
	var top := _paper.global_transform * Vector3(0.0, _paper_quad.size.y * 0.5, 0.0)
	poster.global_transform = Transform3D(_paper.global_transform.basis.orthonormalized(),
		top + Vector3.UP * 0.02)
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
