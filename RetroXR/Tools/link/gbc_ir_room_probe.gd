## Mystery Gift across a room: two Game Boy Colors, a cartridge in each, pointed
## at each other.
##
##     python Tools/gs_save.py <a Gold or Silver save> --unlock a.srm
##     python Tools/gs_save.py <a Gold or Silver save> --unlock b.srm --id 12345 --name PROBE
##     USERPROFILE=<a scratch home holding probe_home.txt> \
##     "$godot" --headless --path RetroXR res://Tools/link/gbc_ir_room_probe.tscn -- \
##         "--rom=<Pokemon Gold or Silver>" --save=a.srm --save2=b.srm
##     ... -- ... --apart     # control: the same two machines a metre and a half apart
##     ... -- ... --away      # control: 30 cm apart, one looking the other way
##     ... -- ... --wall      # control: face to face with a wall between them
##     ... -- ... --cabled    # control: a link cable goes in, and the port goes deaf
##     ... -- ... --core=mgba [--core2=gambatte]
##
## gbc_ir_probe drives the bus directly: it calls LinkConnect on port 1 and
## proves two cores can trade a gift over it. This drives what a PLAYER does,
## which is to switch two machines on and hold them up to each other, and which
## runs through a window on a model, a sight line, a dwell, and IrBus before it
## reaches any of that. It is where an integration fault lives: a window that
## looks back into its own shell, a pair that links and never lights, a machine
## carried away and still joined.
##
## Every leg starts the same way -- both machines on, a metre and a half apart,
## no link -- and only then does what its name says. So the gift in the main
## leg crossed a link the ROOM made, after the cores were already running.
##
## Windowed (never --headless for this part) it also photographs the window lit
## and dark, into --out: `--resolution 640x480 --position 20,20`.
##
## The saves are WRITTEN, and so is the data root: the machines keep their
## batteries there. So this refuses to run unless the data root holds a file
## named probe_home.txt, which a player's never does. Point USERPROFILE (HOME on
## Linux) at a scratch folder with `retroxr/probe_home.txt` and
## `retroxr/libretro/cores/` in it.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CART_SCENE := "res://Scenes/Objects/media/cartridge.tscn"
const CABLE_SCENE := "res://Scenes/Objects/cables/gb_link_cable.tscn"
const MARKER := "probe_home.txt"

const BTN_B := 1 << 0
const BTN_START := 1 << 3
const BTN_DOWN := 1 << 5
const BTN_A := 1 << 8

## pokegold's addresses (pret/pokegold, symbols branch); see gbc_ir_probe.
const RP := 0xFF56
const W_TILEMAP := 0xC3A0
const TILEMAP_SIZE := 360
const S_PARTNER_COUNT := 0xABE5
const S_PARTNER_IDS := 0xABE6
const S_PARTNER_NAME := 0xABFE
const FILE_TRAINER := 0x2009
const NAME_LENGTH := 11

const IR_PORT := 1
const CABLE_PORT := 0
const MAX_PRESSES := 5

var _cores: Array[String] = ["gambatte", "gambatte"]
var _roms: Array[String] = ["", ""]
var _saves: Array[String] = ["", ""]
var _out := "res://probe_out/gbc_ir_room"
var _leg := ""

var _pass := 0
var _fail := 0
var _sys: Array[RetroSystem] = []
var _lib: Array[Libretro] = []
var _port: Array[IrPort] = []
var _window: Array[MeshInstance3D] = []
var _dark: Array[Material] = []
var _camera: Camera3D = null
var _shots := 0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[ir-room] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			_cores = [arg.substr(7), arg.substr(7)]
		elif arg.begins_with("--core2="):
			_cores[1] = arg.substr(8)
		elif arg.begins_with("--rom="):
			_roms = [arg.substr(6), arg.substr(6)]
		elif arg.begins_with("--rom2="):
			_roms[1] = arg.substr(7)
		elif arg.begins_with("--save="):
			_saves[0] = arg.substr(7)
		elif arg.begins_with("--save2="):
			_saves[1] = arg.substr(8)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg in ["--apart", "--away", "--wall", "--cabled"]:
			_leg = arg.substr(2)

	if not FileAccess.file_exists(DataPaths.media_root(MARKER)):
		print("[ir-room] SKIP  %s has no %s: this writes saves, so it runs in a scratch home only"
			% [DataPaths.media_root(), MARKER])
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	for i in range(2):
		if _roms[i].is_empty() or not FileAccess.file_exists(_roms[i]):
			print("[ir-room] SKIP  pass --rom=<Pokemon Gold or Silver>")
			get_tree().quit(0)
			return
		if _saves[i].is_empty() or not FileAccess.file_exists(_saves[i]):
			print("[ir-room] SKIP  pass --save= and --save2=, scratch copies made by Tools/gs_save.py")
			get_tree().quit(0)
			return
		if not FileAccess.file_exists("%s/cores/%s_libretro.dll" % [root, _cores[i]]) \
				and not FileAccess.file_exists("%s/cores/%s_libretro.so" % [root, _cores[i]]):
			print("[ir-room] SKIP  no %s core under %s" % [_cores[i], root])
			get_tree().quit(0)
			return
	print("[ir-room] cores %s and %s, leg: %s" % [_cores[0], _cores[1],
		_leg if not _leg.is_empty() else "face to face"])
	if _leg == "cabled":
		# The cable only reaches a core that was started with it switched on.
		for core: String in _cores:
			_write_link_option(root, core)

	var trainers: Array[PackedByteArray] = [_trainer_of(_saves[0]), _trainer_of(_saves[1])]
	_ok("the two cartridges belong to different trainers",
		trainers[0].slice(0, 2) != trainers[1].slice(0, 2))

	_stage()

	# Two Game Boy Colors, each with its cartridge in, exactly as the room
	# builds them, and a metre and a half apart.
	for i in range(2):
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "gbc"
		sys.core_name = _cores[i]
		sys.name = "Gbc_%s" % ["a", "b"][i]
		add_child(sys)
		# Held where it is put: nothing here is a floor.
		sys.freeze = true
		sys.gravity_scale = 0.0
		_sys.append(sys)
	await _room_frames(4)
	for i in range(2):
		_lib.append(_sys[i].get_libretro_node())
		_port.append(_sys[i].find_child("IrPort", true, false) as IrPort)
		_window.append(_sys[i].find_child("IrWindow", true, false) as MeshInstance3D)
		# The unit's own input node sends the (idle) pad every frame and would
		# wipe a press out; this probe is the only hand on these machines.
		var input := _input_node(_sys[i])
		if input != null:
			input.set_process(false)
	_ok("each Game Boy Color carries an infrared port", _port.count(null) == 0)
	if _port.count(null) > 0 or _window.count(null) > 0:
		return _finish()
	for i in range(2):
		_dark.append(_window[i].get_surface_override_material(0))
	_face(1.5)

	for i in range(2):
		var cart := (load(CART_SCENE) as PackedScene).instantiate() as RetroCartridge
		cart.systemid = "gbc"
		cart.rom_path = _roms[i]
		cart.game_label = "IR %d" % i
		cart.save_id = "irroomprobe%d" % i
		add_child(cart)
		cart.global_position = _sys[i].global_position + Vector3(0, 0.3, 0)
		# The battery the machine will load, put where the machine will look,
		# before anything can have read it.
		var battery := SramPaths.resolve_cart_save("gbc", _cores[i], _roms[i], cart.save_id)
		DirAccess.make_dir_recursive_absolute(battery.get_base_dir())
		DirAccess.copy_absolute(_saves[i], battery)
		await _room_frames(4)
		_sys[i].restore_cartridge(cart)
		await _room_frames(20)
		_eq("machine %d keeps its battery where the scratch save was put" % i,
			str(_sys[i].get("_memcards").call("_compose_sram_path", _cores[i])), battery)
	for i in range(2):
		if not _sys[i].is_powered_on:
			_sys[i].power_on()
		_ok("machine %d is switched on" % i, _sys[i].is_powered_on)
	_ok("both cores run", await _runs(0) and await _runs(1))
	await _emulated(120)

	_eq("apart, machine 0 has no partner", _port[0].partner(), null)
	_eq("and its core sees nobody on the infrared port", _lib[0].LinkPeerCount(IR_PORT), 0)
	_ok("and both windows are dark", _lit(0) == false and _lit(1) == false)

	var linked := _leg.is_empty()
	match _leg:
		"apart":
			pass
		"away":
			_face(0.30)
			_sys[1].global_transform = Transform3D(_sys[0].global_transform.basis,
				_sys[1].global_position)
		"wall":
			_face(0.30)
			_wall()
		_:
			_face(0.30)
	await _room_seconds(1.5)

	if _leg == "cabled":
		_eq("face to face, the two link first", _port[0].partner(), _port[1])
		_eq("and the cores hear each other", [_peers(0), _peers(1)], [2, 2])
		await _seat_cable()
		await _room_seconds(1.5)
		_eq("with a link cable in, the cable carries both machines",
			[_lib[0].LinkPeerCount(CABLE_PORT), _lib[1].LinkPeerCount(CABLE_PORT)], [2, 2])

	if linked:
		_eq("face to face at 30 cm, machine 0's partner is machine 1", _port[0].partner(), _port[1])
		_eq("and machine 1's is machine 0", _port[1].partner(), _port[0])
		_eq("the cores hear each other on the infrared port", [_peers(0), _peers(1)], [2, 2])
		_ok("and both windows glow", _lit(0) and _lit(1))
	else:
		_eq("machine 0 has no partner", _port[0].partner(), null)
		_eq("machine 1 has no partner", _port[1].partner(), null)
		_eq("neither core sees anybody on the infrared port", [_peers(0), _peers(1)], [0, 0])
		_ok("and both windows stay dark", not _lit(0) and not _lit(1))
	await _photo("windows_%s" % ("lit" if linked else "dark_" + _leg))

	# One machine at a time, to the screen that says "Press A to link IR-Device".
	for i in range(2):
		var menu := await _to_main_menu(i)
		_ok("machine %d reaches a main menu offering MYSTERY GIFT" % i, menu)
		if not menu:
			return _finish()
	for i in range(2):
		for n in range(3):
			await _tap(i, BTN_DOWN, 4, 16)
		await _tap(i, BTN_A, 6, 30)
		var listening := await _until(func() -> bool: return (_peek(i, RP) & 0xC0) == 0xC0, 900)
		_ok("machine %d switches its receiver on" % i, listening, "RP reads %02X" % _peek(i, RP))
	await _emulated(60)
	_eq("neither has traded yet", [_peek(0, S_PARTNER_COUNT), _peek(1, S_PARTNER_COUNT)], [0, 0])

	# Machine 0 calls, and calls again if nothing comes of it: the game's own
	# greeting misses about one call in six (gbc_ir_probe says why).
	var presses := 0
	var done := false
	while presses < MAX_PRESSES and not done:
		presses += 1
		await _tap(0, BTN_A, 6, 0)
		done = await _until(func() -> bool:
			return _peek(0, S_PARTNER_COUNT) == 1 and _peek(1, S_PARTNER_COUNT) == 1, 240)
	print("[ir-room] machine 0 pressed A %d time(s)" % presses)
	await _emulated(90)
	await _photo("after_the_call")

	if linked:
		_ok("the gift is exchanged across the room", done, "after %d presses" % presses)
		for i in range(2):
			var other := 1 - i
			_eq("machine %d's cartridge holds machine %d's trainer id" % [i, other],
				_read(i, S_PARTNER_IDS, 2), trainers[other].slice(0, 2))
			_eq("machine %d's cartridge holds machine %d's name" % [i, other],
				_text(_read(i, S_PARTNER_NAME, NAME_LENGTH)), _text(trainers[other].slice(2)))
		_ok("still linked, and still lit, after it", _lit(0) and _lit(1))

		# Carried apart again: the link goes, and the windows go out.
		_face(1.5)
		await _room_seconds(1.5)
		_eq("carried apart, machine 0 has no partner", _port[0].partner(), null)
		_eq("and the cores are off the infrared bus", [_peers(0), _peers(1)], [0, 0])
		_ok("and both windows are dark again", not _lit(0) and not _lit(1))
		await _photo("windows_dark_again")
	else:
		_ok("nothing is exchanged", not done)
		_eq("both cartridges are untouched",
			[_peek(0, S_PARTNER_COUNT), _peek(1, S_PARTNER_COUNT)], [0, 0])
	_ok("machine 0 was not left frozen", await _runs(0))
	_ok("machine 1 was not left frozen", await _runs(1))

	for sys in _sys:
		sys.power_off()
	await _room_seconds(0.5)
	_eq("switched off, nothing is paired", _port[0].partner(), null)
	_finish()


# ── the room ─────────────────────────────────────────────────────────────────

func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.near = 0.01
	add_child(_camera)
	_camera.make_current()


## Machine 0 where it is, machine 1 turned to look back at it with `distance`
## between the two windows.
func _face(distance: float) -> void:
	_sys[0].global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	_sys[1].global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0, 1, 0))
	var want := _port[0].global_position + _port[0].beam_axis() * distance
	_sys[1].global_position += want - _port[1].global_position


func _wall() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.01)
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = box.size
	mesh.mesh = slab
	wall.add_child(mesh)
	add_child(wall)
	wall.collision_layer = 1
	wall.global_position = (_port[0].global_position + _port[1].global_position) * 0.5


func _seat_cable() -> void:
	var lead := (load(CABLE_SCENE) as PackedScene).instantiate() as LinkCable
	lead.name = "Lead0"
	add_child(lead)
	await _room_frames(4)
	for i in range(2):
		var socket := _sys[i].find_child("LinkPort", true, false) as XRToolsSnapZone
		socket.pick_up_object(lead.get_node(["PlugA0", "PlugB0"][i]))
		await _room_frames(6)


func _write_link_option(root: String, core: String) -> void:
	# Each core's own spelling, and its VALUE rather than the label beside it.
	var lines := {
		"gambatte": 'gambatte_gb_link_mode = "Link Cable"',
		"mgba": 'mgba_link_cable = "ON"',
	}
	if not lines.has(core):
		return
	DirAccess.make_dir_recursive_absolute("%s/core_options" % root)
	var writer := FileAccess.open("%s/core_options/%s.opt" % [root, core], FileAccess.WRITE)
	if writer != null:
		writer.store_string(str(lines[core]) + "\n")
		writer.close()


## Whether a window is wearing anything but the dark material it was built with.
func _lit(index: int) -> bool:
	return _window[index].get_surface_override_material(0) != _dark[index]


func _peers(index: int) -> int:
	return _lib[index].LinkPeerCount(IR_PORT)


## Two pictures: machine 0's window close up, from beside where machine 1
## stands, and both machines from above and to one side.
func _photo(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var at := _port[0].global_position
	var out := _port[0].beam_axis()
	_camera.fov = 30.0
	_camera.global_position = at + out * 0.075 + Vector3(0.035, 0.045, 0)
	_camera.look_at(at, Vector3.UP)
	await _snap(label + "_close")
	var far := _port[1].global_position
	var middle := (at + far) * 0.5
	var span := maxf(at.distance_to(far), 0.3)
	_camera.fov = 40.0
	_camera.global_position = middle + Vector3(span * 1.1 + 0.25, span * 0.6 + 0.2, 0)
	_camera.look_at(middle, Vector3.UP)
	await _snap(label + "_both")


func _snap(label: String) -> void:
	await _room_frames(4)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := _out
	if dir.begins_with("res://") or dir.begins_with("user://"):
		dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_shots += 1
	var path := "%s/%02d_%s.png" % [dir, _shots, label]
	image.save_png(path)
	print("[ir-room] photo %s" % path)


func _input_node(node: Node) -> Node:
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("handheld_input.gd"):
			return child
		var found := _input_node(child)
		if found != null:
			return found
	return null


# ── the game ─────────────────────────────────────────────────────────────────

func _to_main_menu(index: int) -> bool:
	for attempt in range(14):
		if _on_screen(index, "CONTINUE"):
			break
		await _tap(index, BTN_START, 6, 0)
		await _until(func() -> bool: return _on_screen(index, "CONTINUE"), 150)
	await _emulated(20)
	return _on_screen(index, "MYSTERY")


func _on_screen(index: int, word: String) -> bool:
	var tiles := _read(index, W_TILEMAP, TILEMAP_SIZE)
	if tiles.is_empty():
		return false
	var want := PackedByteArray()
	for c in word.to_upper():
		want.append(0x80 + (c.unicode_at(0) - 65))
	for at in range(tiles.size() - want.size() + 1):
		if tiles.slice(at, at + want.size()) == want:
			return true
	return false


func _runs(index: int) -> bool:
	var was: int = _lib[index].GetFrameCount()
	for i in range(600):
		await get_tree().process_frame
		if _lib[index].GetFrameCount() > was + 5:
			return true
	return false


func _read(index: int, address: int, n: int) -> PackedByteArray:
	var snap: Dictionary = _lib[index].SnapshotMappedRam()
	var data: PackedByteArray = snap.get("data", PackedByteArray())
	for region: Dictionary in snap.get("regions", []):
		var start: int = region["start"]
		var length: int = region["len"]
		if address >= start and address + n <= start + length:
			var at: int = int(region["offset"]) + (address - start)
			return data.slice(at, at + n)
	return PackedByteArray()


func _peek(index: int, address: int) -> int:
	var got := _read(index, address, 1)
	return got[0] if got.size() == 1 else -1


func _trainer_of(save_path: String) -> PackedByteArray:
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(FILE_TRAINER)
	return f.get_buffer(2 + NAME_LENGTH)


func _text(raw: PackedByteArray) -> String:
	var out := ""
	for b in raw:
		if b == 0x50:
			break
		if b >= 0x80 and b <= 0x99:
			out += char(65 + b - 0x80)
		elif b >= 0xA0 and b <= 0xB9:
			out += char(97 + b - 0xA0)
		elif b >= 0xF6:
			out += char(48 + b - 0xF6)
		elif b == 0x7F:
			out += " "
		else:
			out += "?"
	return out


func _tap(index: int, mask: int, press_frames: int, gap_frames: int) -> void:
	_lib[index].SetJoypadState(0, mask, 0, 0, 0, 0)
	await _emulated(press_frames)
	_lib[index].SetJoypadState(0, 0, 0, 0, 0, 0)
	await _emulated(gap_frames)


## Frames the cores have run, not frames the room has drawn.
func _emulated(n: int) -> void:
	var target: int = _lib[0].GetFrameCount() + n
	var guard := n * 40 + 400
	while _lib[0].GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame


func _until(cond: Callable, frames: int) -> bool:
	var target: int = _lib[0].GetFrameCount() + frames
	var guard := frames * 40 + 400
	while guard > 0:
		if cond.call():
			return true
		if _lib[0].GetFrameCount() >= target:
			return false
		guard -= 1
		await get_tree().process_frame
	return false


func _room_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## Wall-clock time in the room, which is what IrBus's looks and dwells run on.
func _room_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[ir-room] PASS  %s" % name)
	else:
		_fail += 1
		print("[ir-room] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	print("[ir-room] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
