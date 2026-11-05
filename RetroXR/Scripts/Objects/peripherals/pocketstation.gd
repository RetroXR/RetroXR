## PocketStation — Sony's SCPH-4000, the PlayStation memory card that is also a handheld.
##
## Two identities at once, the VMU's arrangement (VmuCard) on a PlayStation card:
##
##   * a MEMORY CARD. It IS a MemoryCard of the "playstation" family, so a PS1's card
##     slot takes it, its image is save/memcards/playstation/<card_id>.mcr, and the
##     shelf, the panel, renames and RomM serve it unchanged. Seated, the console
##     reads and writes it as it does any card.
##   * a HANDHELD. Out of the slot it runs the `pokket` core on its own card: the
##     PocketStation's BIOS menu, the apps a PlayStation game put on it, its clock.
##     The card panel's Play buttons (an app on the card, a library app, or the card
##     itself on the Games tab) are how it is switched on.
##
## What it does NOT do yet: answer the PlayStation as a PocketStation. A game sees a
## plain card, so it offers no download; that is the pcsx_rearmed half of the plan
## (docs/dev/pocketstation.md), and an app reaches the card from a library file or
## another card meanwhile.
##
## Whatever the device writes goes into a SCRATCH copy of the card, never the card
## file: the core's save RAM IS the card (Pokket's flash, byte for byte a .mcr), and it
## comes back through CardSaveOps.write_card once the core has let go of it, unless a
## powered console holds the card by then (it waits, as a VMU's progress does).
class_name PocketStation
extends MemoryCard

const STANDALONE_CORE := "pokket"
## The BIOS the core opens from its system folder, and refuses to start without.
const BIOS_FILE := "pocketstation.bin"
## The library folder the panel's Games tab lists, roms/<this>.
const LIBRARY_SYSTEMID := "pocketstation"
## What Pokket loads, identified by its bytes (a card, a single save, a title sector, a
## DexDrive dump). A firmware dump kept beside them is a .bin too, and is not a game.
const LIBRARY_EXTENSIONS: Array[String] = ["mcs", "pss", "gme", "mcr", "mcd", "bin"]
const DEFAULT_LABEL := "POCKETSTATION"
## Scratch images: <card_id>.mcr for the card itself, apps/<md5>.mcr for a library app,
## whose own progress is kept there between plays and never reaches the card.
const PLAY_DIR := "user://pocketstation_play"
const HINT_HEIGHT := 0.10
## The speaker's distance law, a handheld's.
const STANDALONE_AUDIO_UNIT_SIZE := 3.0
const STANDALONE_AUDIO_MAX_DISTANCE := 15.0
## How far a button sinks: they stand 1.2 mm proud of the base.
const PRESS_DEPTH := 0.0009
const ANIM_WEIGHT := 0.4
const IDLE_FRAMES_TO_STOP := 24

## [node under Model, RetroPad bit]: Pokket reads the d-pad as the four buttons and A
## as the action button (frontends/libretro/libretro.c, read_buttons).
const _CONTROLS: Array = [
	["ButtonUp", ControllerBindings.JOYPAD_UP],
	["ButtonDown", ControllerBindings.JOYPAD_DOWN],
	["ButtonLeft", ControllerBindings.JOYPAD_LEFT],
	["ButtonRight", ControllerBindings.JOYPAD_RIGHT],
	["ButtonAction", ControllerBindings.JOYPAD_A],
]

## A libretro root to run from instead of the player's (its cores/, system/pokket/ and
## core_options/), as RetroSystem.core_directory: for the probes, which must not install a
## core into the player's folders. Empty in the room.
@export var core_directory := ""

var _hint: HeldHint = null
var _lib: Node = null
var _running := false
var _game_title := ""
## The scratch the running core reads and writes, and whether it is this card's own
## (whose writes go back to the card) or a library app's (whose stay with the app).
var _scratch := ""
var _scratch_is_card := false
## Set at power-off until the core has unloaded and the scratch can be read back.
var _carry_pending := false
var _opt_defs: Dictionary = {}
var _opt_values: Dictionary = {}
## The snap zone holding this card (a console's slot, a multitap's), or null.
var _seat: Node = null
var _input: VmuInput = null
var _anim: ControlAnimator = null
var _poke: ControlPoke = null
var _btn := 0
var _idle_frames := 0
var _screen: MeshInstance3D = null
var _screen_off_mat: Material = null
var _screen_mat: ShaderMaterial = null
var _last_tex: Texture2D = null
var _own_voices := PackedInt32Array()
var _own_gain := -1.0
var _mx: Object = null
var _listener: Node = null


func _ready() -> void:
	# Numbered as plain cards are, from its own default, before MemoryCard mints the id.
	if card_label == DEFAULT_LABEL:
		var units := get_tree().get_nodes_in_group("memory_card").filter(
			func(n: Node) -> bool: return n is PocketStation)
		card_label = "%s %d" % [DEFAULT_LABEL, units.size()]
	super._ready()
	add_to_group("spawned")
	add_to_group("pocketstation")
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)
	_screen = get_node_or_null("Model/LidHinge/Screen") as MeshInstance3D
	if _screen != null:
		_screen_off_mat = _screen.get_surface_override_material(0)
	_bind_controls()
	# The VMU's hand driver: A is the action button, the stick the four direction
	# buttons, which is the map Pokket reads (_CONTROLS).
	_input = VmuInput.attach(self)
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)
	set_process(false)
	# Progress a run left in the scratch when the app last closed.
	_carry_back.call_deferred()


# --- The controls -------------------------------------------------------------

func _bind_controls() -> void:
	_anim = ControlAnimator.new()
	for spec: Array in _CONTROLS:
		var m := get_node_or_null(NodePath("Model/" + str(spec[0]))) as MeshInstance3D
		if m == null:
			push_warning("[PocketStation] no %s on the model" % spec[0])
			continue
		# Into the face is -Y in the model's frame, which the object's 180 degree turn
		# about Y leaves alone.
		_anim.buttons.append({
			"node": m, "rest": m.transform, "bit": int(spec[1]),
			"depth": PRESS_DEPTH, "dir": Vector3(0, -1, 0),
		})
	_poke = ControlPoke.new(self)
	_poke.add_animator(_anim)


## The buttons a fingertip is pressing this frame, as a RetroPad mask (VmuInput ORs it in).
func poke_mask() -> int:
	return int(_poke.poll()["btn"]) if _poke != null else 0


## What the buttons should show and, while it runs, what the core reads: one entry
## point, so a press can never animate without reaching the core or the other way round.
func set_input(btn: int) -> void:
	_btn = btn
	if _running and _lib != null:
		_lib.SetJoypadState(0, btn, 0, 0, 0, 0)
	if btn != 0:
		_idle_frames = 0
		set_process(true)


func input_mask() -> int:
	return _btn


# --- Seated or loose ----------------------------------------------------------

func _on_grabbed(_pickable: Node3D, by: Node3D) -> void:
	if by is XRToolsSnapZone:
		# Pushed into a slot it is a memory card: its buttons are inside the console,
		# and a game running on it stops, as a VMU's does in a controller.
		_seat = by
		print("[PocketStation] %s seated in %s" % [card_label, by.get_path()])
		power_off()


func _on_released(_pickable: Node3D, by: Node3D) -> void:
	if by == _seat:
		_seat = null
		print("[PocketStation] %s out of its slot" % card_label)
		# Refused while a console held the card; free to go back now.
		_carry_back()


func is_seated() -> bool:
	return is_instance_valid(_seat)


# --- Standalone ---------------------------------------------------------------

## Whether it can run right now: "" when ok, else why, in words the panel shows.
func standalone_blocker() -> String:
	if is_seated():
		return "seated in a slot — pull it out first"
	# The last run's core still unloading: its final flush has yet to land in the
	# scratch, and a new run writing that same scratch would race it.
	if _carry_pending and not _core_unloaded():
		return "still switching off"
	if not _core_installed():
		return "the Pokket core is not installed (PlayStation BIOS / Extras)"
	if not FileAccess.file_exists(bios_path()):
		return "%s is not in Pokket's BIOS folder" % BIOS_FILE
	return ""


func bios_path() -> String:
	return _core_root().path_join("system").path_join(STANDALONE_CORE).path_join(BIOS_FILE)


func _core_root() -> String:
	return core_directory if not core_directory.is_empty() else CoreDownloadManager.default_core_root()


func _core_installed() -> bool:
	if core_directory.is_empty():
		return not CoreDownloadManager.installed_core_lib(STANDALONE_CORE).is_empty()
	for f: String in DirAccess.get_files_at(core_directory.path_join("cores")):
		if f.begins_with(STANDALONE_CORE + "_libretro."):
			return true
	return false


## Where this card's image lives on disk, found or to be made.
func image_path() -> String:
	var found := SramPaths.find_card(card_id, family)
	return found if not found.is_empty() else SramPaths.card_save_path(family, card_id)


## Switch it on with `path`: this card's own image (the Games tab's first row), or a
## library app. Returns false with the reason logged when it will not start.
func power_on(path: String, title := "") -> bool:
	if _running:
		return true
	var why := standalone_blocker()
	if not why.is_empty():
		push_warning("[PocketStation] cannot run %s: %s" % [title, why])
		return false
	# Whatever the last run on this card left in its scratch goes back first, before
	# a new scratch is written over it.
	_carry_pending = false
	_carry_back()
	if path == image_path() or path.is_empty():
		return _boot_card(title)
	if not FileAccess.file_exists(path):
		push_warning("[PocketStation] no such app: %s" % path)
		return false
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAY_DIR.path_join("apps")))
	# The app's own progress, kept between plays: Pokket's save RAM is the card it
	# builds round the app, and the frontend loads it over that card at the next start.
	var scratch := PLAY_DIR.path_join("apps").path_join("%s.mcr" % _md5(bytes))
	var name := title if not title.is_empty() else path.get_file().get_basename()
	return _boot(path, scratch, false, name)


## A PocketStation app on the card: the device boots its whole card and its own menu
## lists the app (Pokket cannot jump past the BIOS), so this is switching it on.
func play_save(_block: int, title := "") -> bool:
	return power_on(image_path(), title)


func _boot_card(title: String) -> bool:
	if not CardSaveOps.in_use_reason(get_tree(), card_id).is_empty():
		push_warning("[PocketStation] %s is in use by a console" % card_label)
		return false
	var path := image_path()
	var card := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	if card.is_empty():
		if not minted:
			# A card restored or spawned from the shelf is supposed to have an image;
			# a silent blank would read as its saves being wiped.
			push_warning("[PocketStation] %s has no image at %s" % [card_label, path])
			return false
		card = PS1Card.blank_image()
		if not CardSaveOps.write_card(get_tree(), CardFormats.for_family(family), path, card_id, card):
			return false
		print("[PocketStation] %s: a new formatted card at %s" % [card_label, path])
	if not PS1Card.is_card_image(card):
		push_warning("[PocketStation] %s's image is not a PlayStation card" % card_label)
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAY_DIR))
	var scratch := PLAY_DIR.path_join("%s.mcr" % card_id)
	if not AtomicFile.write_bytes(scratch, card, "PocketStation"):
		return false
	return _boot(scratch, scratch, true, title if not title.is_empty() else card_label)


## Start the core on `content`, its save RAM backed by `scratch`.
func _boot(content: String, scratch: String, is_card: bool, title: String) -> bool:
	if not _ensure_lib():
		return false
	_scratch = scratch
	_scratch_is_card = is_card
	_lib.SetSramPath(ProjectSettings.globalize_path(scratch))
	_lib.StartContent(_core_root(), STANDALONE_CORE,
		ProjectSettings.globalize_path(content))
	_running = true
	_game_title = title
	_last_tex = null
	set_process(true)
	if _hint != null:
		_hint.add_row(&"pocketstation_a", HeldHint.PLATFORM_VR,
			["quest_button_a_outline"], "Action — stick is the four buttons")
	print("[PocketStation] %s running %s (%s, scratch %s)" % [card_label, title,
		"its own card" if is_card else content.get_file(), scratch])
	return true


## Made once and KEPT, as a VMU's is: freeing a Libretro node whose emulation thread is
## still unwinding ends in an access violation.
func _ensure_lib() -> bool:
	if _lib != null:
		return true
	var lib: Object = ClassDB.instantiate("Libretro")
	_lib = lib as Node
	if _lib == null:
		push_warning("[PocketStation] could not instantiate a Libretro node")
		return false
	_lib.name = "PocketStationLibretro"
	add_child(_lib)
	_lib.connect("options_ready", _on_options_ready)
	return true


func power_off() -> void:
	if not _running:
		return
	_running = false
	_opt_defs = {}
	_opt_values = {}
	if _lib != null and _lib.has_method("StopContent"):
		_lib.StopContent()
	# The final save-RAM flush lands as the core unloads; _process reads it back then.
	_carry_pending = _scratch_is_card
	_btn = 0
	print("[PocketStation] %s off (%s)" % [card_label, _game_title])
	_game_title = ""
	if _hint != null:
		_hint.remove_row(&"pocketstation_a")
	set_process(_carry_pending)
	_show_off()


func is_running_standalone() -> bool:
	return _running


func playing_title() -> String:
	return _game_title if _running else ""


func _core_unloaded() -> bool:
	if _lib == null:
		return true
	var identity: Dictionary = _lib.call("GetCoreIdentity")
	return identity.is_empty()


## Put what the device wrote back on the card: the whole image, since the device's
## flash IS the card. Waits while a powered console holds the card.
func _carry_back() -> void:
	if not is_inside_tree() or _running or card_id.is_empty():
		return
	var scratch := PLAY_DIR.path_join("%s.mcr" % card_id)
	if not FileAccess.file_exists(scratch):
		return
	var why := CardSaveOps.in_use_reason(get_tree(), card_id)
	if not why.is_empty():
		print("[PocketStation] %s: progress waits in %s (%s)" % [card_label, scratch, why])
		return
	var data := FileAccess.get_file_as_bytes(scratch)
	var path := image_path()
	if not PS1Card.is_card_image(data):
		push_warning("[PocketStation] %s: the scratch is not a card image, left where it is" % card_label)
		return
	var old := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	if old == data:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
		return
	if not CardSaveOps.write_card(get_tree(), CardFormats.for_family(family), path, card_id, data):
		push_warning("[PocketStation] %s did not verify; progress stays in %s" % [card_label, scratch])
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	print("[PocketStation] carried %s's progress back to %s" % [card_label, path])


# --- The panel's other questions ------------------------------------------------

## The Games tab: this card itself first, then the apps in roms/pocketstation/.
func library_games() -> Array[Dictionary]:
	var games: Array[Dictionary] = [{"path": image_path(), "label": "%s (its own card)" % card_label,
		"tag": "this card"}]
	for g: Dictionary in RomLibrary.scan_roms(LIBRARY_SYSTEMID, LIBRARY_EXTENSIONS):
		if str(g["path"]).get_file().to_lower().contains("bios") \
				or str(g["path"]).get_file().to_lower() == BIOS_FILE:
			continue
		games.append(g)
	return games


func library_systemid() -> String:
	return LIBRARY_SYSTEMID


func _on_options_ready(_categories: Dictionary, definitions: Dictionary, values: Dictionary) -> void:
	_opt_defs = definitions
	_opt_values = values


func core_options() -> Dictionary:
	var out := {"definitions": {}, "values": {}, "forced": {}, "note": ""}
	if _running and not _opt_defs.is_empty():
		out["definitions"] = _opt_defs
		out["values"] = _opt_values
		return out
	if not _core_installed():
		out["note"] = "The Pokket core is not installed."
		return out
	var root := _core_root()
	var peeked := CoreOptionsStore.peek(root, STANDALONE_CORE)
	if peeked.is_empty():
		out["note"] = CoreOptionsStore.peek_failure_reason(root, STANDALONE_CORE)
		return out
	out["definitions"] = peeked["definitions"]
	out["values"] = CoreOptionsStore.effective_values(peeked,
		CoreOptionsStore.load_values(root, STANDALONE_CORE))
	return out


func set_core_option(key: String, value: String) -> void:
	if _running and _lib != null:
		_lib.call("SetCoreOption", key, value)
		_opt_values[key] = value
	else:
		CoreOptionsStore.set_value(_core_root(), STANDALONE_CORE, key, value)


## The screen for the desktop fullscreen overlay, as a handheld lists its own.
func fullscreen_panels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _screen == null:
		return out
	out.append({
		"mesh": _screen,
		"texture_fn": func() -> Texture2D:
			return _lib.GetVideoTexture() as Texture2D if _running and _lib != null else null,
		"region": Rect2(0, 0, 1, 1),
		"aspect_fn": func() -> float: return 1.0,
		"fit_fn": func() -> Vector2: return Vector2.ONE,
		"flip_h": false,
		"flip_v": false,
	})
	return out


# --- Every frame while it runs ---------------------------------------------------

func _process(_delta: float) -> void:
	if _carry_pending and not _running and _core_unloaded():
		_carry_pending = false
		_carry_back()
	if _running and _lib != null:
		_update_audio()
		show_picture(_lib.GetVideoTexture() as Texture2D)
	if _anim != null and not _anim.is_empty():
		_anim.animate(_btn, Vector2.ZERO, Vector2.ZERO, ANIM_WEIGHT)
	if not _running and not _carry_pending and _btn == 0:
		_idle_frames += 1
		if _idle_frames > IDLE_FRAMES_TO_STOP:
			set_process(false)
	else:
		_idle_frames = 0


## Put `tex` on the LCD, through the same window shader a handheld's screen uses. Public
## so a probe can check which way up a picture lands without a core.
func show_picture(tex: Texture2D) -> void:
	if _screen == null:
		return
	if tex == null:
		_show_off()
		return
	if _screen_mat == null:
		_screen_mat = ShaderMaterial.new()
		_screen_mat.shader = RetroTV.window_shader()
		_screen_mat.set_shader_parameter("source_rect", Vector4(0.0, 0.0, 1.0, 1.0))
	if tex != _last_tex:
		_last_tex = tex
		_screen_mat.set_shader_parameter("source_tex", tex)
	if _screen.get_surface_override_material(0) != _screen_mat:
		_screen.set_surface_override_material(0, _screen_mat)


func _show_off() -> void:
	if _screen != null and _screen.get_surface_override_material(0) != _screen_off_mat:
		_screen.set_surface_override_material(0, _screen_off_mat)
	_last_tex = null


## Meta XR Audio mixes a voice only once its owner has posed it, and this is not a
## RetroSystem, so the speaker is posed here (the VMU's _update_standalone_audio).
func _update_audio() -> void:
	var voices: PackedInt32Array = _lib.GetAudioVoiceIds()
	if voices != _own_voices:
		_own_voices = voices
		_own_gain = -1.0
		if _mx == null and Engine.has_singleton("MetaXRAudio"):
			_mx = Engine.get_singleton("MetaXRAudio")
		if _mx != null:
			for v in voices:
				_mx.set_voice_directivity(v, SpatialAudioEmitter.SPEAKER_DIRECTIVITY)
	if voices.is_empty() or _mx == null:
		return
	if not is_instance_valid(_listener):
		_listener = get_node_or_null("/root/SpatialAudioListener")
		if _listener == null:
			return
	var listener_pos: Vector3 = _listener.get_listener_position()
	var pos := global_position
	var b := global_transform.basis
	var at := SpatialAudioEmitter.hold_off_head(pos, listener_pos)
	for v in voices:
		# The grille is on the back.
		_mx.set_voice_pose(v, at, -b.y.normalized(), b.z.normalized())
	var gain := SpatialAudioEmitter.distance_gain(pos, listener_pos,
		STANDALONE_AUDIO_UNIT_SIZE, STANDALONE_AUDIO_MAX_DISTANCE)
	if not is_equal_approx(gain, _own_gain):
		_own_gain = gain
		for v in voices:
			_mx.set_voice_gain(v, gain)


static func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
