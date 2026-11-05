## pocketstation_play_probe — a PocketStation out of the slot, running its own card on a
## real pokket core: the BIOS menu, an app a PlayStation game downloaded, and what the app
## writes going back to the card.
##
## The card is a copy of --image (e.g. one pocketstation_dock_probe left with --keep) put
## on a fixture unit; the unit is switched on through its own power_on, its buttons pressed
## through its own set_input, and its LCD saved (32 x 32, enlarged) where asked. After
## power-off the card is listed again, so the carry-back is read off the card itself.
##
##     "$godot" --headless --path RetroXR res://Tools/cores/pocketstation_play_probe.tscn -- \
##         --root=<scratch libretro root: cores/pokket_libretro.dll, system/pokket/pocketstation.bin> \
##         --image=<a PS1 card .mcr> --out=<dir> --every=16 \
##         --steps="200-202:down,240-242:action,280-282:right,320-322:action"
##
## --steps: `from-to:buttons`, buttons joined by `+` from up down left right action, held
## over the CORE's frames (Pokket runs 32 a second) from..to. The Pokket README's route to
## an app: wait out the HELLO animation, Down then Action past the date/time screen, Right
## to the app, Action to start it. A real press is ~40 ms: hold 2-3 frames.
extends Node

const BITS := {"up": ControllerBindings.JOYPAD_UP, "down": ControllerBindings.JOYPAD_DOWN,
	"left": ControllerBindings.JOYPAD_LEFT, "right": ControllerBindings.JOYPAD_RIGHT,
	"action": ControllerBindings.JOYPAD_A}
const CARD_ID := "__PSPLAY_PROBE"
const SCALE := 10

var root_dir := ""
var image_path := ""
## A library app to switch the unit on with instead of its card (the Games tab's other rows).
var app_path := ""
var out_dir := ""
var every := 0
var keep := false
var _steps: Array = []
var _shots: Array[int] = []
var _ps: PocketStation = null
var _sent := -1


func _ready() -> void:
	var steps_arg := ""
	var shots_arg := ""
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--image="):
			image_path = a.trim_prefix("--image=").replace("\\", "/")
		elif a.begins_with("--app="):
			app_path = a.trim_prefix("--app=").replace("\\", "/")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
		elif a.begins_with("--steps="):
			steps_arg = a.trim_prefix("--steps=")
		elif a.begins_with("--shots="):
			shots_arg = a.trim_prefix("--shots=")
		elif a.begins_with("--every="):
			every = int(a.trim_prefix("--every="))
		elif a == "--keep":
			keep = true
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[psplay] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if root_dir.is_empty() or out_dir.is_empty() or not FileAccess.file_exists(image_path):
		print("[psplay] need --root=, --out= and --image=")
		get_tree().quit(1)
		return
	for s in steps_arg.split(",", false):
		var parts := s.split(":")
		var span := parts[0].split("-")
		var mask := 0
		for b in parts[1].split("+", false):
			if not BITS.has(b):
				print("[psplay] unknown button %s" % b)
			mask |= 1 << int(BITS.get(b, 0))
		_steps.append({"from": int(span[0]), "to": int(span[1]), "mask": mask})
	for f in shots_arg.split(",", false):
		_shots.append(int(f))
	await _run()


func _run() -> void:
	var card := FileAccess.get_file_as_bytes(image_path)
	var path := SramPaths.card_save_path("playstation", CARD_ID)
	if not AtomicFile.write_bytes(path, card, "pocketstation_play_probe"):
		print("[psplay] could not write the fixture card")
		get_tree().quit(1)
		return
	_report("before", card)
	_ps = (load("res://Scenes/Objects/peripherals/pocketstation.tscn") as PackedScene).instantiate() as PocketStation
	_ps.card_id = CARD_ID
	_ps.card_label = CARD_ID
	_ps.core_directory = root_dir
	add_child(_ps)
	_ps.freeze = true
	await get_tree().process_frame
	print("[psplay] blocker '%s'" % _ps.standalone_blocker())
	var start := app_path if not app_path.is_empty() else _ps.image_path()
	if not _ps.power_on(start, "probe"):
		print("[psplay] FAIL power_on refused")
		await _finish(1)
		return
	var lib: Object = _ps.get("_lib")
	var deadline := Time.get_ticks_msec() + 30000
	while (lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ident: Dictionary = lib.GetCoreIdentity()
	if ident.is_empty():
		print("[psplay] FAIL the core never came up")
		await _finish(1)
		return
	print("[psplay] core %s %s, running '%s'" % [ident.get("library_name", "?"),
		ident.get("library_version", "?"), _ps.playing_title()])
	var last := every
	for f: int in _shots:
		last = maxi(last, f)
	for st: Dictionary in _steps:
		last = maxi(last, int(st["to"]) + 1)
	var sorted_shots := _shots.duplicate()
	sorted_shots.sort()
	var shot_i := 0
	var next_every := every
	while true:
		var frame := int(lib.GetFrameCount())
		_drive(frame)
		while shot_i < sorted_shots.size() and frame >= sorted_shots[shot_i]:
			_shot(lib, sorted_shots[shot_i])
			shot_i += 1
		if every > 0 and frame >= next_every:
			_shot(lib, frame)
			next_every += every
		if frame > last:
			break
		await get_tree().process_frame
	_ps.power_off()
	# The final flush lands as the core unloads; the unit carries it back then.
	for i in 180:
		await get_tree().process_frame
	_report("after", FileAccess.get_file_as_bytes(path))
	await _finish(0)


func _drive(frame: int) -> void:
	var mask := 0
	for st: Dictionary in _steps:
		if frame >= int(st["from"]) and frame <= int(st["to"]):
			mask |= int(st["mask"])
	if mask == _sent:
		return
	_sent = mask
	_ps.set_input(mask)


func _shot(lib: Object, frame: int) -> void:
	var img: Image = lib.call("GetVideoImage")
	if img == null or img.is_empty():
		print("[psplay] frame %d: no image" % frame)
		return
	img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	var p := out_dir.path_join("lcd_%05d.png" % frame)
	img.save_png(p)
	print("[psplay] frame %d -> %s" % [frame, p])


func _report(when: String, data: PackedByteArray) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(data)
	var saves := PS1Card.list_saves(data, false)
	print("[psplay] card %s: md5 %s, %d save(s)" % [when, ctx.finish().hex_encode(), saves.size()])
	for s: Dictionary in saves:
		print("[psplay]   %-22s %d block(s)%s" % [s["name"], int(s["blocks"]),
			"  [PocketStation app]" if bool(s.get("pocketstation", false)) else ""])


func _finish(code: int) -> void:
	if not keep:
		for p: String in [SramPaths.card_save_path("playstation", CARD_ID),
				PocketStation.PLAY_DIR.path_join("%s.mcr" % CARD_ID)]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("[psplay] done")
	get_tree().quit(code)
