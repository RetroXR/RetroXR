## VmuCard — a Dreamcast Visual Memory Unit, the object you can pick up.
##
## Two identities at once, the way a Controller Pak is both an N64Pak and a card:
##
##   * a CONTROLLER accessory. It seats in one of the two expansion slots on a
##     Dreamcast pad, so it joins "controller_plug" narrowed by a systemid
##     sentinel, exactly as N64Pak does. dreamcast.tres declares no card_family
##     and RetroSystem's own console-slot machinery stays out of this entirely.
##   * a MEMORY CARD. Its image lives at save/memcards/vmu/<card_id>.vmu and the
##     same shelf, panel, rename and delete serve it.
##
## Not a subclass of N64Pak, and not yet a shared base with it. The two have the
## seat in common and little else — a pak answers a per-port core option, a VMU
## answers a per-SLOT one and also carries a screen — so the common surface is
## not yet obvious enough to name. Extracting one once both exist is the cheap
## direction; guessing it now is not.
##
## Dimensions are the real unit's: 47 x 80 x 16 mm, 45 g, and an LCD of 48 x 32
## dots measuring 37 x 26 mm. Referenced rather than guessed — an earlier draft
## of this had it 8 mm thick.
class_name VmuCard
extends XRToolsPickable

## Read by the slot this is offered to. The sentinel that narrows a socket which
## would otherwise take any cable plug in the room.
const PLUG_SYSTEMID := "dreamcast_vmu"

## The card family: the folder under save/memcards/ and the byte format. Fixed —
## there is only one kind of VMU — but named `family` like every other card so
## CardFormats, SramPaths and MemoryCardPanel take it with no special case.
const FAMILY := "vmu"

const OPTIONS_PANEL_SCENE := preload("res://Scenes/UI/memory_card_panel.tscn")

## Height of the drop hint above the card, in metres. A VMU is a small object and
## the default 18 cm floats clear of it.
const HINT_HEIGHT := 0.10

## Read by everything that treats this as a card. See FAMILY.
var family: String = FAMILY

## Read by any slot this is offered to; see PLUG_SYSTEMID.
var systemid: String = PLUG_SYSTEMID

## Persistent identity, and literally the file name this card's saves live in
## (`<card_id>.vmu`).
@export var card_id: String = ""

## Display label on the card's back, and its filename on disk — see card_id.
@export var card_label: String = "VMU":
	set(v):
		card_label = v
		_update_label()

## True only for a card this session invented — the id was not handed in. Only
## such a card may have its image created; one restored from a saved room or
## spawned from the shelf is supposed to have an image already, and answering a
## card whose saves have gone missing with a silent blank reads exactly like the
## saves were wiped.
var minted := false

const SCREEN_WINDOW_SHADER := preload("res://Shaders/screen_window.gdshader")

var _options_panel: MemoryCardPanel = null
var _hint: HeldHint = null

# --- The screen ---------------------------------------------------------------
#
# flycast burns the VMU's 48 x 32 LCD into a corner of the main framebuffer, so
# the card's face shows that corner cropped back out with screen_window — the
# same mechanism the 3DS bottom screen uses on a composite frame. The rect and
# the options that put it there live on VmuStorage.
#
# Only SLOT 1 lights up. That is the hardware (only the front slot has a window
# in the controller's shell) and the core agrees: its screen options are indexed
# per port and gate on the slot-1 device alone.

## Which slot this card is seated in, or -1 when it is loose. Set by VmuPort.
var _slot := -1
## The pad it is seated in, for reaching the machine on the other end.
var _pad: Node = null

var _lcd: MeshInstance3D = null
var _lcd_off_mat: Material = null
var _lcd_mat: ShaderMaterial = null
## The voice a seated card's beep plays on, posed on the card each frame.
var _beep_voice := -1
var _beep_gain := -1.0
var _mx: Object = null
var _listener: Node = null
var _last_tex: Texture2D = null
var _last_frame := Vector2i.ZERO

# --- The controls -------------------------------------------------------------
#
# ControlAnimator, the same engine every pad and handheld face in the project
# runs on. A VMU has four buttons and a d-pad, and the d-pad rocks as one piece
# because on the real unit it is a disc with a cross moulded into it.
#
# The buttons map onto the RetroPad the way vemulator reads them: A and B are A
# and B, and MODE and SLEEP take START and SELECT — the VMU has no other pair to
# put them on.

## How far a cap sinks. The caps stand ~2 mm proud of a 16 mm body, and a cap
## driven flush reads as a hole rather than a press.
const PRESS_DEPTH := 0.0011

## Per-frame lerp weight toward the pressed pose.
const ANIM_WEIGHT := 0.4

## [node name, RetroPad bit]. Every one of these sits on the +Z face.
const _CONTROLS: Array = [
	["ButtonA", ControllerBindings.JOYPAD_A],
	["ButtonB", ControllerBindings.JOYPAD_B],
	["ModeButton", ControllerBindings.JOYPAD_START],
	["SleepButton", ControllerBindings.JOYPAD_SELECT],
]

var _anim: ControlAnimator = null
## The button mask last pushed in, which is what the controls animate from.
var _btn := 0
## Frames since anything needed driving. A released control lerps back to rest
## over a few frames, so the drive cannot stop the moment the mask clears — and a
## card doing nothing should not tick forever either, with eight of them in a
## room.
var _idle_frames := 0

## How long to keep driving after the last input, in frames. ANIM_WEIGHT 0.4
## settles well inside this.
const IDLE_FRAMES_TO_STOP := 24

# --- Standalone ---------------------------------------------------------------
#
# A VMU is a handheld in its own right: its own CPU, its own screen, its own
# buttons and two coin cells. Out of a controller it can run a downloaded
# minigame on the `vemulator` core, which is a whole machine in a 282 KB core.
#
# Deliberately NOT a RetroSystem. HandheldInput and the rest of that machinery
# hang off one, and a VMU is a card first — it has to keep being a card while it
# is seated. What it grows instead is a Libretro node of its own.

const STANDALONE_CORE := "vemulator"
## The library folder the card's Games tab lists, roms/<this>.
const LIBRARY_SYSTEMID := "vmu"
## What vemulator loads: a minigame, a game with its directory entry, or a card.
const LIBRARY_EXTENSIONS: Array[String] = ["vms", "dci", "bin"]
## path -> {mtime, icons}, for library_games.
static var _icon_cache := {}
## Pinned for every standalone run: see _boot() for why writing must be on.
const FORCED_OPTIONS := {"enable_flash_write": "enabled"}

## Where a game lifted off a card is written for the core to boot from.
const PLAY_DIR := "user://vmu_play"

var _lib: Node = null
var _running := false
## What the running game is called, for the panel's "playing" row. Empty when
## nothing runs.
var _game_title := ""
## What the running core published through options_ready, for the card menu.
var _opt_defs: Dictionary = {}
var _opt_values: Dictionary = {}
## Set on power-off until the core has unloaded and closed its scratch image.
var _carry_pending := false
## The hand's buttons reaching the core — see VmuInput.
var _input: VmuInput = null

## Netplay: the flash image the session is about to boot on every peer, what to
## call it, and where it came from ({mode: "rom"|"card", rom_md5, ...}). Set by
## the host when a game is offered to a session, and by a client from the host's
## spec. Empty outside a session.
var _net_image := PackedByteArray()
var _net_title := ""
var _net_source: Dictionary = {}
## Why net_prepare_boot last refused, in words the session shows the player.
var net_boot_failure: String = ""


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	# The slot requires this group, the same one every cable plug joins. Being in
	# it is what makes a cable-less accessory seatable at all; the systemid is
	# what then narrows the socket to this one thing.
	add_to_group("controller_plug")
	add_to_group("vmu")
	# What the SLOT filters on. A Jump Pack is in it too, because the two
	# compete for the same two sockets -- see VmuPort.SLOT_GROUP.
	add_to_group(VmuPort.SLOT_GROUP)
	# Numbering and the in-use check both sweep this group, and a VMU held by a
	# controller is exactly as much "in use" as a card in a console.
	add_to_group("memory_card")

	if card_label == "VMU":
		card_label = "VMU %d" % get_tree().get_nodes_in_group("vmu").size()
	if card_id.is_empty():
		card_id = SramPaths.unique_card_id(card_label)
		card_label = card_id
		minted = true
	_update_label()
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)

	_lcd = get_node_or_null("Lcd") as MeshInstance3D
	if _lcd != null:
		# The authored dark panel is what a VMU shows with nothing driving it, and
		# is kept rather than rebuilt so an unseated card looks the same as it
		# does on a shelf.
		_lcd_off_mat = _lcd.get_surface_override_material(0)
	_bind_controls()
	_input = VmuInput.attach(self)
	grabbed.connect(_on_hand_grab_changed)
	released.connect(_on_hand_grab_changed)
	set_process(false)
	# Progress left by a game that was still running when the app last closed.
	_carry_progress_back.call_deferred()


# --- The controls -------------------------------------------------------------

func _bind_controls() -> void:
	_anim = ControlAnimator.new()
	# The pad's UP is its -Z arm in the pivot's frame, and a positive pitch about
	# X LIFTS what lies on -Z — so the sign flips for UP to depress it. Same
	# reason handheld_model's stand-in pass sets it.
	_anim.dpad_pitch_sign = -1.0
	_anim.dpad_tilt_deg = 6.0
	for spec: Array in _CONTROLS:
		var m := get_node_or_null(NodePath(str(spec[0]))) as MeshInstance3D
		if m == null:
			continue
		# `dir` is in the mesh PARENT's frame — the card's — where into the face
		# is -Z. The caps carry their own rotation to stand a cylinder up, and
		# that has no bearing on which way they travel.
		_anim.buttons.append({
			"node": m, "rest": m.transform, "bit": int(spec[1]),
			"depth": PRESS_DEPTH, "dir": Vector3(0, 0, -1),
		})
	# The animated node is the PIVOT, which is identity; the turn that puts the
	# face normal on +Y lives on the MOUNT above it, because the animator rotates
	# in the animated node's parent space. See the scene's own note.
	var pivot := get_node_or_null("DpadMount/DpadPivot") as Node3D
	if pivot != null:
		_anim.dpad = {"node": pivot, "rest": pivot.transform, "pivot": Vector3.ZERO}


## Push the button state this card's controls should show, and — while it is
## running standalone — what its core should read.
##
## One entry point for both, so a press can never animate without reaching the
## core or vice versa.
func set_input(btn: int) -> void:
	_btn = btn
	# In a session the port is the session's: a remote holder's presses arrive
	# through the gate, and under rollback a local one still comes straight here.
	if _running and _lib != null \
			and not NetworkManager.netplay_route(self, 0, {"btn": btn}):
		_lib.SetJoypadState(0, btn, 0, 0, 0, 0)
	# Wake the per-frame drive. The controls have to move whether or not this card
	# has a screen to fill — the animation gate and the picture gate are separate
	# questions, and conflating them left every button frozen while the animator
	# sat there correctly configured and never ticked.
	if btn != 0:
		_idle_frames = 0
		set_process(true)


## The mask currently held down. Read by the probes.
func input_mask() -> int:
	return _btn


# --- Seating ------------------------------------------------------------------

## Told by VmuPort which slot took this card, and on which pad.
func seated_in(pad: Node, slot: int) -> void:
	# A card in a controller is a memory card, not a handheld: its own buttons are
	# inside the pad and unreachable. Pushing it into a slot ends a standalone
	# game, which is what putting one in a Dreamcast does.
	power_off()
	_pad = pad
	_slot = slot
	# Only slot 1 has a window in the shell, so only it drives a screen. A card in
	# either slot can beep.
	set_process(true)
	if _slot != 0:
		_show_off()


func unseated() -> void:
	_pad = null
	_slot = -1
	if not _running:
		set_process(false)
		_show_off()
	# Refused while a console held the card; free to go back now.
	_carry_progress_back()


## The machine this card is plugged into, through the pad holding it, or null.
func host_system() -> Node:
	if not is_instance_valid(_pad) or not _pad.has_method("get_connected_system"):
		return null
	var sys: Node = _pad.call("get_connected_system")
	return sys if is_instance_valid(sys) else null


# --- The screen ---------------------------------------------------------------

func _show_off() -> void:
	if _lcd != null and _lcd.get_surface_override_material(0) != _lcd_off_mat:
		_lcd.set_surface_override_material(0, _lcd_off_mat)
	_last_tex = null
	_last_frame = Vector2i.ZERO


# --- Standalone ---------------------------------------------------------------

## Power the card up as its own machine, running one minigame.
##
## `vms_path` is a .vms, .dci or .bin — the file a Dreamcast game downloaded into
## the card, or one out of a library. `title` is what to call it while it runs;
## the file name stands in when none is given. Returns false when the core is
## not installed, the file is missing or the card is seated, which is the
## difference between "nothing happened" and "it silently played nothing".
func power_on(vms_path: String, title := "") -> bool:
	if _running:
		return true
	if vms_path.is_empty() or not FileAccess.file_exists(vms_path):
		push_warning("[VmuCard] no such minigame: %s" % vms_path)
		return false
	var image := _flash_image_for(FileAccess.get_file_as_bytes(vms_path), vms_path)
	if image.is_empty():
		push_warning("[VmuCard] %s is not a VMU game, save or card" % vms_path.get_file())
		return false
	var name := title if not title.is_empty() else vms_path.get_file().get_basename()
	var sums := NetFileTransfer.checksums_of(vms_path)
	if _net_offer(image, name, {"mode": "rom", "rom_md5": NetFileTransfer.hash_of(vms_path),
			"rom_size": int(sums.get("size", 0)), "rom_label": vms_path.get_file().get_basename()}):
		return true
	return _boot(image, name)


## The 128 KiB flash image the core is handed, whatever the file was.
##
## A card image is taken as it is. A .dci or a .vms is put at block 0 of a
## blank card — where a game must sit, since with no BIOS the core runs the
## flash from its first byte.
func _flash_image_for(bytes: PackedByteArray, path: String) -> PackedByteArray:
	if VMUCard.is_card_image(bytes):
		return bytes
	var dci := bytes
	if not VMUCard.is_dci(dci):
		var stem := path.get_file().get_basename().to_upper()
		dci = VMUCard.dci_from_vms(bytes, stem if not stem.is_empty() else "GAME")
	if dci.is_empty():
		return PackedByteArray()
	return VMUCard.insert_save(VMUCard.blank_image(), dci)


## Boot the core on a flash image written to this card's scratch file.
##
## ALWAYS a .bin, never the .vms or .dci the game arrived as, and the reason
## is a crash in the core rather than a preference. vemulator's flash object
## opens a file handle only for a .bin with enable_flash_write on, and its
## destructor closes that handle unconditionally — but the member is never
## initialised, so on a .vms or .dci the handle is garbage and reset() dies in
## rfclose the moment the game is unloaded. Read at source (flash.cpp,
## flash.h, main.cpp) after the stop button took the process down with it. A
## .bin with writing on gives it a real handle to close, and the writes land
## in this scratch copy, never in the card. (The .dci path is also simply
## broken: a real one runs zero frames.)
func _boot(image: PackedByteArray, title: String, net := {}) -> bool:
	var why := standalone_blocker()
	if not why.is_empty():
		push_warning("[VmuCard] cannot run %s: %s" % [title, why])
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAY_DIR))
	# The scratch image is about to be replaced, so anything a previous game on
	# this card left in it goes back first.
	_carry_pending = false
	_carry_progress_back()
	_remove_play_note()
	var scratch := play_scratch_path()
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	if f == null:
		push_warning("[VmuCard] could not write %s" % scratch)
		return false
	f.store_buffer(image)
	f.close()
	var root := CoreDownloadManager.default_core_root()
	CoreOptionsStore.merge_values(root, STANDALONE_CORE, FORCED_OPTIONS)
	if not _ensure_lib():
		return false
	# A session's pins go through the store the core reads at load, as in
	# RetroSystem.net_start_core, and the gate is set BEFORE StartContent so the
	# core holds at the start frame until inputs post.
	if not net.is_empty():
		CoreOptionsStore.merge_values(root, STANDALONE_CORE, net.get("options", {}))
		_lib.SetNetplayMode(true, int(net.get("mask", 1)), int(net.get("start_frame", 0)))
	_lib.StartContent(root, STANDALONE_CORE, ProjectSettings.globalize_path(scratch))
	_running = true
	_game_title = title
	# Its own screen now, not a window into a Dreamcast's frame.
	_last_tex = null
	_last_frame = Vector2i.ZERO
	set_process(true)
	if _hint != null:
		_hint.add_row(&"vmu_ab", HeldHint.PLATFORM_VR,
			["quest_button_a_outline", "quest_button_b_outline"], "A and B — stick is the d-pad")
		_hint.add_row(&"vmu_mode", HeldHint.PLATFORM_VR,
			["quest_stick_{s}_press"], "MODE")
	print("[VmuCard] %s running %s" % [card_label, title])
	return true


## Run one of this card's own game entries, the loop the hardware is remembered
## for: a Dreamcast game put it there, and the card plays it on its own.
##
## The entry is lifted off as a .dci — the form that carries its directory
## entry — and put at block 0 of a fresh image for the core, one scratch per
## card, overwritten each time. The card's own image is never touched, and
## nothing comes back to it: whatever the game writes lands in the scratch.
## `block` is the entry's first block, as list_saves reports it.
func play_save(block: int, title := "") -> bool:
	var path := SramPaths.find_card(card_id, FAMILY)
	if path.is_empty():
		push_warning("[VmuCard] %s has no image to play from" % card_label)
		return false
	var dci := VMUCard.extract_save(FileAccess.get_file_as_bytes(path), block)
	if dci.is_empty():
		push_warning("[VmuCard] no game at block %d on %s" % [block, card_label])
		return false
	var image := VMUCard.insert_save(VMUCard.blank_image(), dci)
	if image.is_empty():
		push_warning("[VmuCard] the game at block %d would not go onto a blank card" % block)
		return false
	# A game off a card is the player's save, so a session ships it like SRAM.
	if _net_offer(image, title, {"mode": "card"}):
		return true
	if not _boot(image, title):
		return false
	JsonStore.write_dict(_play_note_path(), {"card_id": card_id}, "VmuCard")
	return true


## Where the image the core boots from is written. A .bin, see _boot.
func play_scratch_path() -> String:
	return PLAY_DIR.path_join("%s.bin" % card_id)


## Beside the scratch image: marks it as a game played from this card, whose
## writes belong back on the card.
func _play_note_path() -> String:
	return PLAY_DIR.path_join("%s.json" % card_id)


func _remove_play_note() -> void:
	if FileAccess.file_exists(_play_note_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_play_note_path()))


## Made once and KEPT. Freeing a Libretro node whose emulation thread is still
## unwinding is how a clean run ends in an access violation on the way out —
## the same hazard as a GDExtension audio playback that outlives its extension.
## Powering off stops the content and leaves the node in place for the next game.
func _ensure_lib() -> bool:
	if _lib != null:
		return true
	var lib: Object = ClassDB.instantiate("Libretro")
	_lib = lib as Node
	if _lib == null:
		push_warning("[VmuCard] could not instantiate a Libretro node")
		return false
	_lib.name = "VmuLibretro"
	add_child(_lib)
	_lib.connect("options_ready", _on_options_ready)
	return true


## Whether the core has unloaded, which is when vemulator closes the scratch image.
func _core_unloaded() -> bool:
	if _lib == null:
		return true
	var identity: Dictionary = _lib.call("GetCoreIdentity")
	return identity.is_empty()


## Put what a minigame played from this card wrote back onto the card. Each file
## in the scratch image replaces the card's copy of the same name, or is added;
## one that no longer fits leaves the card's copy. Left pending, note and all,
## while a console holds the card.
func _carry_progress_back() -> void:
	if not is_inside_tree() or _running or card_id.is_empty() \
			or not FileAccess.file_exists(_play_note_path()):
		return
	var path := SramPaths.find_card(card_id, FAMILY)
	var scratch := FileAccess.get_file_as_bytes(play_scratch_path())
	if path.is_empty() or not VMUCard.is_card_image(scratch):
		_remove_play_note()
		return
	if not CardSaveOps.in_use_reason(get_tree(), card_id).is_empty():
		return
	var out := FileAccess.get_file_as_bytes(path)
	var carried: Array[String] = []
	for s: Dictionary in VMUCard.list_saves(scratch, false):
		var file_name := str(s["name"])
		var file := VMUCard.extract_save(scratch, int(s["block"]))
		if file.is_empty():
			continue
		var base := out
		var at := VMUCard.block_of(out, file_name)
		if at >= 0:
			# Past the 32-byte directory entry, whose first-block field differs
			# between the two images whatever the game did.
			if VMUCard.extract_save(out, at).slice(32) == file.slice(32):
				continue
			base = VMUCard.delete_save(out, at)
		var merged := VMUCard.insert_save(base, file) if not base.is_empty() \
			else PackedByteArray()
		if merged.is_empty():
			push_warning("[VmuCard] %s did not fit back on %s; the card keeps its copy"
				% [file_name, card_label])
			continue
		out = merged
		carried.append(file_name)
	if not carried.is_empty():
		if not CardSaveOps.write_card(get_tree(), CardFormats.for_family(FAMILY), path,
				card_id, out):
			push_warning("[VmuCard] %s did not verify; progress stays in %s"
				% [card_label, play_scratch_path()])
			return
		print("[VmuCard] carried %s back to %s" % [", ".join(carried), card_label])
	_remove_play_note()


## The minigames in the library's VMU folder, as [{path, label, icons}] sorted by
## label, `icons` being the file's own frames as Images. A firmware dump kept
## beside them is a .bin too, and is not a game.
func library_games() -> Array[Dictionary]:
	var games: Array[Dictionary] = []
	for g: Dictionary in RomLibrary.scan_roms(LIBRARY_SYSTEMID, LIBRARY_EXTENSIONS):
		var path := str(g["path"])
		if path.get_file().to_lower().contains("bios"):
			continue
		g["icons"] = _library_icons(path)
		games.append(g)
	return games


## A file's icon frames, decoded once per change to the file. Every card shares
## the cache, so opening a second card's menu reads nothing.
static func _library_icons(path: String) -> Array:
	var mtime := FileAccess.get_modified_time(path)
	var hit: Dictionary = _icon_cache.get(path, {})
	if hit.get("mtime", -1) == mtime:
		return hit["icons"]
	var icons := VMUCard.icons_of_file(FileAccess.get_file_as_bytes(path))
	_icon_cache[path] = {"mtime": mtime, "icons": icons}
	return icons


## The systemid those games are filed under, locally and on a RomM server.
func library_systemid() -> String:
	return LIBRARY_SYSTEMID


## A VR hand taking or letting go of the card re-anchors every hand still on it.
## Only a hand: a snap zone's pick-up emits grabbed too, and re-anchoring that
## would pin the card where it was instead of seating it.
func _on_hand_grab_changed(_pickable: Node3D, by: Node3D) -> void:
	if by is XRToolsFunctionPickup:
		GripAnchor.refresh(self, self)


## Where a VR hand grips the card, in card space: the authored HandLeft/HandRight
## nodes, which place the drawn hands too. See GripAnchor.
func grip_anchor(is_left: bool) -> Variant:
	var hand := get_node_or_null(^"HandLeft" if is_left else ^"HandRight") as Node3D
	return hand.transform if hand != null else null


## Why this card cannot run a minigame right now, or "" when it can.
func standalone_blocker() -> String:
	if _slot >= 0:
		return "seated in a controller — pull it out first"
	if CoreDownloadManager.installed_core_lib(STANDALONE_CORE).is_empty():
		return "the %s core is not installed" % STANDALONE_CORE
	return ""


## The running game's name, or "" when the card is not running one.
func playing_title() -> String:
	return _game_title if _running else ""


func power_off() -> void:
	if not _running:
		return
	# A game in a session stops on every peer; the session calls net_stop_core.
	if NetworkManager.netplay_running() and NetworkManager.netplay_covers(self) \
			and not NetworkManager.is_event_applying():
		NetworkManager.netplay_stop("VMU powered off")
		if not _running:
			return
	_power_off_local()


func _power_off_local() -> void:
	if not _running:
		return
	_running = false
	_opt_defs = {}
	_opt_values = {}
	# StopContent, and the node is KEPT rather than freed.
	#
	# Measured, both ways round. Freeing it here crashes the process with an
	# access violation before the caller's next print — StopContent is
	# non-blocking, so the emulation thread is still unwinding through a node
	# that has just been queued for deletion. Keeping it costs one idle node per
	# card and is reused by the next power_on.
	#
	# That is a DIFFERENT crash from the audio-teardown race, which fires on
	# QUIT rather than on free and is fixed with frames on the caller's side.
	if _lib != null and _lib.has_method("StopContent"):
		_lib.StopContent()
	_carry_pending = FileAccess.file_exists(_play_note_path())
	_btn = 0
	_game_title = ""
	if _hint != null:
		_hint.remove_row(&"vmu_ab")
		_hint.remove_row(&"vmu_mode")
	set_process(_slot == 0 or _carry_pending)
	_show_off()


func is_running_standalone() -> bool:
	return _running


## This card's screen for the desktop fullscreen overlay, in the panel shape
## TvFullscreen.panels_for builds for a handheld. Empty while the screen is dark.
## A seated card sits upside down in its pad, so its picture is turned half round
## to read the right way up.
func fullscreen_panels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pic := _picture()
	if _lcd == null or pic.is_empty():
		return out
	out.append({
		"mesh": _lcd,
		"texture_fn": func() -> Texture2D:
			var now := _picture()
			return now["tex"] as Texture2D if not now.is_empty() else null,
		"region": Rect2(0, 0, 1, 1),
		"aspect_fn": func() -> float: return 48.0 / 32.0,
		"fit_fn": func() -> Vector2: return Vector2.ONE,
		"flip_h": _slot >= 0,
		"flip_v": _slot >= 0,
	})
	return out


func _on_options_ready(_categories: Dictionary, definitions: Dictionary,
		values: Dictionary) -> void:
	_opt_defs = definitions
	_opt_values = values


## vemulator's options for the card menu: {definitions, values, forced, note}.
## From the running core when there is one, otherwise read from the core without
## starting it.
func core_options() -> Dictionary:
	var out := {"definitions": {}, "values": {}, "forced": FORCED_OPTIONS, "note": ""}
	if _running and not _opt_defs.is_empty():
		out["definitions"] = _opt_defs
		out["values"] = _opt_values
		return out
	if CoreDownloadManager.installed_core_lib(STANDALONE_CORE).is_empty():
		out["note"] = "The %s core is not installed." % STANDALONE_CORE
		return out
	var root := CoreDownloadManager.default_core_root()
	var peeked := CoreOptionsStore.peek(root, STANDALONE_CORE)
	if peeked.is_empty():
		out["note"] = CoreOptionsStore.peek_failure_reason(root, STANDALONE_CORE)
		return out
	out["definitions"] = peeked["definitions"]
	out["values"] = CoreOptionsStore.effective_values(peeked,
		CoreOptionsStore.load_values(root, STANDALONE_CORE))
	return out


## Change one vemulator option: live while a game runs, otherwise in the option
## file the core reads at start. Pinned keys are refused.
func set_core_option(key: String, value: String) -> void:
	if FORCED_OPTIONS.has(key):
		return
	if _running and _lib != null:
		_lib.call("SetCoreOption", key, value)
		_opt_values[key] = value
	else:
		CoreOptionsStore.set_value(CoreDownloadManager.default_core_root(),
			STANDALONE_CORE, key, value)


## Whichever picture belongs on this card's face, and the window into it.
##
## Two sources, and both are whole. Standalone, the core IS a VMU and its frame
## is the entire 48 x 32 screen. Seated, the Dreamcast core hands that port's
## panel over as a texture of its own.
##
## There is no third. A core that cannot hand panels over leaves this card dark,
## which is the honest picture: the overlay it would otherwise be cropped from
## is pinned off on every port, so that corner of the frame holds nothing but
## the game.
func _picture() -> Dictionary:
	if _running and _lib != null:
		var own: Texture2D = _lib.GetVideoTexture()
		if own != null:
			return {"tex": own, "whole": true}
		return {}
	var sys := host_system()
	if _slot != 0 or sys == null or not sys.has_method("vmu_screen_texture"):
		return {}
	# The core's own panel, or nothing. There is no second source any more: the
	# overlay that used to be cropped out of the television's picture is pinned
	# OFF on every port, because a Dreamcast never draws a VMU onto the TV and
	# neither does this room. With it off there is nothing in that corner but the
	# game, so cropping would put the game on the card.
	var panel: Texture2D = sys.call("vmu_screen_texture", _pad, _slot)
	return {"tex": panel, "whole": true} if panel != null else {}


func _process(_delta: float) -> void:
	if _carry_pending and not _running and _core_unloaded():
		_carry_pending = false
		_carry_progress_back()
	if _slot >= 0:
		_update_beep()

	if _anim != null and not _anim.is_empty():
		_anim.animate(_btn, Vector2.ZERO, Vector2.ZERO, ANIM_WEIGHT)

	# Stop ticking once there is nothing left to do: no screen to fill, nothing
	# held, a carry-back not waiting, and the controls given long enough to settle.
	var wants_screen := _running or _slot >= 0 or _carry_pending
	if not wants_screen and _btn == 0:
		_idle_frames += 1
		if _idle_frames > IDLE_FRAMES_TO_STOP:
			set_process(false)
	else:
		_idle_frames = 0

	if _lcd == null:
		return
	var pic := _picture()
	if pic.is_empty():
		_show_off()
		return
	var tex: Texture2D = pic["tex"]

	if _lcd_mat == null:
		_lcd_mat = ShaderMaterial.new()
		_lcd_mat.shader = SCREEN_WINDOW_SHADER

	# The texture is a NEW object whenever the core changes resolution, so it is
	# read every frame and only pushed when it differs.
	if tex != _last_tex:
		_last_tex = tex
		_lcd_mat.set_shader_parameter("source_tex", tex)
	var frame := tex.get_size()
	var frame_i := Vector2i(int(frame.x), int(frame.y))
	# The WHOLE texture, always. Both sources are a 48 x 32 panel in their own
	# right now — the core's own frame when this card is the machine, and the
	# handed-over panel when it is seated — so there is no window to work out.
	# This used to crop a rect out of the television's picture, which is gone with
	# the overlay it cropped.
	if frame_i != _last_frame:
		_last_frame = frame_i
		_lcd_mat.set_shader_parameter("source_rect", Vector4(0.0, 0.0, 1.0, 1.0))

	if _lcd.get_surface_override_material(0) != _lcd_mat:
		_lcd.set_surface_override_material(0, _lcd_mat)


## Pose a seated card's beep on the card. Loudness is the distance law alone: a
## game sets the buzzer itself.
func _update_beep() -> void:
	var sys := host_system()
	var voice := -1
	if sys != null and sys.has_method("vmu_beep_voice"):
		voice = int(sys.call("vmu_beep_voice", _pad, _slot))
	if voice != _beep_voice:
		_beep_voice = voice
		_beep_gain = -1.0
		if voice >= 0:
			if _mx == null and Engine.has_singleton("MetaXRAudio"):
				_mx = Engine.get_singleton("MetaXRAudio")
			if _mx != null:
				_mx.set_voice_directivity(voice, SpatialAudioEmitter.SPEAKER_DIRECTIVITY)
	if voice < 0 or _mx == null:
		return
	if _listener == null or not is_instance_valid(_listener):
		_listener = get_node_or_null("/root/SpatialAudioListener")
		if _listener == null:
			return
	var listener_pos: Vector3 = _listener.get_listener_position()
	var pos := global_position
	var basis := global_transform.basis
	_mx.set_voice_pose(voice, SpatialAudioEmitter.hold_off_head(pos, listener_pos),
		basis.y.normalized(), basis.z.normalized())
	var gain := SpatialAudioEmitter.distance_gain(pos, listener_pos,
		float(sys.get("audio_unit_size")), float(sys.get("audio_max_distance")))
	if not is_equal_approx(gain, _beep_gain):
		_beep_gain = gain
		_mx.set_voice_gain(voice, gain)


## What flycast's per-slot device option should be set to while this is seated.
## The core's own vocabulary, because it is the core being told.
func slot_option_value() -> String:
	return "VMU"


## What to call this in a menu or a refusal.
func accessory_label() -> String:
	return "Visual Memory Unit"


## Where this card's saves live, or "" when the family is somehow unregistered.
func image_path() -> String:
	return SramPaths.card_save_path(FAMILY, card_id)


func _update_label() -> void:
	var lbl := get_node_or_null("CardLabel") as Label3D
	if lbl:
		lbl.text = card_label


## Open/close the save list, the same panel a memory card uses.
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		_options_panel = OPTIONS_PANEL_SCENE.instantiate()
		add_child(_options_panel)
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


# --- Netplay ------------------------------------------------------------------
#
# A standalone VMU is a one-port machine of its own to NetplaySession, through
# the same duck-typed seam RetroSystem answers. The card is its own controller,
# so port 0 belongs to whoever holds it (ObjectSync hands it over on a grab).
# The image the core boots comes from one of two places: a library minigame is
# found by hash on every peer and never sent, like any ROM, and a game lifted
# off a card is the player's save, so it travels in the spec's SRAM field.

## Host: hand a game about to start to the running session. True when the
## session took it — it boots the core on every peer, this one included.
func _net_offer(image: PackedByteArray, title: String, source: Dictionary) -> bool:
	if not NetworkManager.is_active() or not NetworkManager.is_host() \
			or NetworkManager.is_event_applying() \
			or not NetworkManager.netplay_capable(STANDALONE_CORE):
		return false
	_net_image = image
	_net_title = title
	_net_source = source
	if source.get("mode") == "card":
		_net_source["rom_md5"] = _md5(image)
	if NetworkManager.netplay_start_host(self, STANDALONE_CORE, str(_net_source["rom_md5"])):
		return true
	_net_clear()
	return false


func _net_clear() -> void:
	_net_image = PackedByteArray()
	_net_title = ""
	_net_source = {}


static func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func get_libretro_node() -> Node:
	return _lib if _ensure_lib() else null


func resolve_core_name() -> String:
	return STANDALONE_CORE


func net_rom_md5() -> String:
	return str(_net_source.get("rom_md5", ""))


## The card is its own pad.
func port_holders() -> Array:
	return [self]


func net_boot_spec(_core: String) -> Dictionary:
	if _net_source.is_empty() or _net_image.is_empty():
		return {}
	var spec := _net_source.duplicate()
	spec["vmu_title"] = _net_title
	if spec.get("mode") == "card":
		# The session knows three boot modes; this is a ROM whose bytes happen to
		# come in the SRAM field, and net_prepare_boot reads the flag.
		spec["mode"] = "rom"
		spec["vmu_card"] = true
	else:
		spec["systemid"] = LIBRARY_SYSTEMID
	return spec


func net_prepare_boot(spec: Dictionary) -> bool:
	net_boot_failure = ""
	var why := standalone_blocker()
	if not why.is_empty():
		net_boot_failure = "the VMU is %s" % why if _slot >= 0 else why
		return false
	var md5 := str(spec.get("rom_md5", ""))
	_net_title = str(spec.get("vmu_title", "VMU game"))
	if bool(spec.get("vmu_card", false)):
		# The image arrives in net_set_sram, which the session calls next.
		if str(_net_source.get("rom_md5", "")) != md5:
			_net_image = PackedByteArray()
		_net_source = {"mode": "card", "rom_md5": md5}
		return true
	if not _net_image.is_empty() and str(_net_source.get("rom_md5", "")) == md5:
		return true   # the host, which built it
	var path := NetFileTransfer.resolve_by_md5(md5, "rom", int(spec.get("rom_size", 0)), "",
		[RomLibrary.rom_dir_for_system(LIBRARY_SYSTEMID)])
	if path.is_empty():
		net_boot_failure = "you do not have the VMU game %s" % str(spec.get("rom_label", ""))
		return false
	_net_image = _flash_image_for(FileAccess.get_file_as_bytes(path), path)
	_net_source = {"mode": "rom", "rom_md5": md5}
	return not _net_image.is_empty()


## Host: the image of a game played off a card, for every peer to boot. Empty
## for a library game, which each peer finds by hash.
func net_sram_file_bytes() -> PackedByteArray:
	return _net_image if _net_source.get("mode") == "card" else PackedByteArray()


func net_set_sram(_path: String, data: PackedByteArray) -> void:
	if _net_source.get("mode") != "card":
		return
	if _md5(data) != str(_net_source.get("rom_md5", "")):
		push_warning("[VmuCard] netplay: the card game that arrived does not match its hash")
		_net_image = PackedByteArray()
		return
	_net_image = data


func net_start_core(_core: String, port_mask: int, start_frame: int,
		options: Dictionary) -> Node:
	if _net_image.is_empty():
		push_warning("[VmuCard] netplay start — no game prepared")
		return null
	_power_off_local()
	var host_card: bool = _net_source.get("mode") == "card" and NetworkManager.is_host()
	if not _boot(_net_image, _net_title,
			{"options": options, "mask": port_mask, "start_frame": start_frame}):
		return null
	# Progress goes back to the host's card, whose game it was. A client only
	# ever played a copy.
	if host_card:
		JsonStore.write_dict(_play_note_path(), {"card_id": card_id}, "VmuCard")
	return _lib


func net_stop_core() -> void:
	if _lib != null:
		_lib.SetNetplayMode(false, 1, 0)
	_power_off_local()
	_net_clear()


func net_play_reset() -> void:
	pass
