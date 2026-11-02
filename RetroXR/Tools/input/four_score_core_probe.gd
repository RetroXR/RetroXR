## Drives the four-player adapters against a REAL fceumm, with a test ROM that reads
## the pads the way a four-player game does and leaves every bit it read in RAM.
##
##     "$godot" --headless --path RetroXR res://Tools/input/four_score_core_probe.tscn -- \
##         --root=<scratch libretro root holding cores/fceumm_libretro.dll> --leg=4p
##
## ONE LEG PER PROCESS (a core started wrongly can take the process with it):
##
##   --leg=4p       an NES, the Four Score's block in both ports at 4, a pad in each
##                  socket holding a different button
##   --leg=2p       the same at 2: the CONTROL -- no signature, players 3 and 4 gone
##   --leg=none     an NES with two pads plugged straight in: the other control
##   --leg=famicom  a Famicom, the 4 Players Adaptor in its expansion port, pads in
##                  sockets 1 and 2
##
## The ROM (written by this probe, 44 bytes of code): strobe $4016, then read $4016
## and $4017 twenty-four times each, storing bits 0-1 of every read at $0300 and
## $0320, for ever. The pads go through each pad's OWN delivery path
## (RetroController._deliver_joypad: its port, the port's filter, the core), on
## the ports the adapter routed them to; the devices the core is told are the
## adapter's. So a pass is the room's whole route, end to end, read back from the
## game's side:
##
##   4p: $4016 D0 = player 1 (A), player 3 (SELECT), then 0,0,0,1,0,0,0,0
##       $4017 D0 = player 2 (B), player 4 (START), then 0,0,1,0,0,0,0,0
##   2p / none: reads 9-24 on D0 are all 1 (no Four Score), whatever pads 3 and 4 do
##   famicom: $4016 D1 = player 3 (SELECT), $4017 D1 = player 4 (START), then 1s
##
## The RAM is snapshotted on the main thread while the core runs on its own, which
## is a race (famicom_mic_probe's note) -- harmless here: with the buttons held
## still the ROM writes the same 48 bytes every pass, so any frame reads the same.
## Point --root at a throwaway root: the probe writes core_options there.
extends Node

var root_dir := ""
var leg := "4p"
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		print("[fourcore] PASS  %s" % name)
	else:
		_fail += 1
		print("[fourcore] FAIL  %s%s" % [name, "  - " + detail if not detail.is_empty() else ""])


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--leg="):
			leg = a.trim_prefix("--leg=")
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[fourcore] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/fceumm_libretro.dll")):
		print("[fourcore] need --root=<libretro root holding cores/fceumm_libretro.dll>")
		get_tree().quit(1)
		return
	await _run()
	print("[fourcore] ---- %s (%s) ----" % ["FAIL" if _fail > 0 else "PASS", leg])
	get_tree().quit(1 if _fail > 0 else 0)


## The test ROM: NROM, 16 KB PRG (mirrored), 8 KB CHR of nothing.
static func _rom() -> PackedByteArray:
	var code := PackedByteArray([
		0x78, 0xD8, 0xA2, 0xFF, 0x9A,           # C000 SEI CLD LDX #$FF TXS
		0xA9, 0x01, 0x8D, 0x16, 0x40,           # C005 LDA #1  STA $4016
		0xA9, 0x00, 0x8D, 0x16, 0x40,           # C00A LDA #0  STA $4016
		0xA2, 0x00,                             # C00F LDX #0
		0xAD, 0x16, 0x40, 0x29, 0x03,           # C011 LDA $4016  AND #3
		0x9D, 0x00, 0x03,                       # C016 STA $0300,X
		0xAD, 0x17, 0x40, 0x29, 0x03,           # C019 LDA $4017  AND #3
		0x9D, 0x20, 0x03,                       # C01E STA $0320,X
		0xE8, 0xE0, 0x18, 0xD0, 0xEB,           # C021 INX  CPX #24  BNE C011
		0xE6, 0x40,                             # C026 INC $40 (a heartbeat)
		0x4C, 0x05, 0xC0,                       # C028 JMP C005
		0x40,                                   # C02B RTI
	])
	var prg := PackedByteArray()
	prg.resize(0x4000)
	for i in code.size():
		prg[i] = code[i]
	for at: int in [0x3FFA, 0x3FFE]:          # NMI, IRQ -> RTI
		prg[at] = 0x2B
		prg[at + 1] = 0xC0
	prg[0x3FFC] = 0x00                         # RESET -> C000
	prg[0x3FFD] = 0xC0
	var rom := PackedByteArray([0x4E, 0x45, 0x53, 0x1A, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	rom.append_array(prg)
	var chr := PackedByteArray()
	chr.resize(0x2000)
	rom.append_array(chr)
	return rom


func _spawn(path: String, at: Vector3) -> Node3D:
	var obj := (load(path) as PackedScene).instantiate() as Node3D
	add_child(obj)
	obj.global_position = at
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	return obj


func _run() -> void:
	var rom_path := root_dir.path_join("four_score_test.nes")
	var f := FileAccess.open(rom_path, FileAccess.WRITE)
	f.store_buffer(_rom())
	f.close()

	var famicom := leg == "famicom"
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "famicom" if famicom else "nes"
	sys.core_directory = root_dir
	sys.core_name = "fceumm"
	add_child(sys)
	sys.freeze = true
	for i in 10:
		await get_tree().physics_frame

	# Who holds which button, by player: A, B, SELECT, START.
	var held := [ControllerBindings.JOYPAD_A, ControllerBindings.JOYPAD_B,
		ControllerBindings.JOYPAD_SELECT, ControllerBindings.JOYPAD_START]
	var pads: Array = []      # by player, the pad that plays it (null where none)
	if leg == "4p" or leg == "2p":
		var fs := _spawn("res://Scenes/Objects/controllers/nes/nes_four_score.tscn", Vector3(0, 0, 0.3)) as NesFourScore
		for i in 4:
			pads.append(_spawn("res://Scenes/Objects/controllers/nes/nes_controller.tscn", Vector3(-0.3 + 0.2 * i, 0, 0.6)))
		for i in 6:
			await get_tree().physics_frame
		if leg == "2p":
			fs.set_mode(FourPlayerAdapter.MODE_2P)
		sys.restore_controller_plug(0, fs.get_plug())
		for i in 4:
			fs.restore_socket(i, pads[i])
	elif leg == "none":
		for i in 4:
			pads.append(_spawn("res://Scenes/Objects/controllers/nes/nes_controller.tscn", Vector3(-0.3 + 0.2 * i, 0, 0.6)))
		for i in 6:
			await get_tree().physics_frame
		for i in 2:
			sys.restore_controller_plug(i, pads[i].call("get_plug"))
	else:
		var hori := _spawn("res://Scenes/Objects/controllers/famicom/famicom_four_players_adaptor.tscn",
			Vector3(0, 0, 0.3)) as FamicomFourPlayersAdaptor
		var captive: Array = sys.captive_controllers()
		pads = [captive[0] if captive.size() > 0 else null, captive[1] if captive.size() > 1 else null]
		for i in 2:
			pads.append(_spawn("res://Scenes/Objects/controllers/retro_controller.tscn", Vector3(-0.2 + 0.4 * i, 0, 0.6)))
		for i in 6:
			await get_tree().physics_frame
		sys.restore_controller_plug(RetroSystem.ACCESSORY_SLOT, hori.get_plug())
		hori.restore_socket(0, pads[2])
		hori.restore_socket(1, pads[3])
	for i in 10:
		await get_tree().physics_frame
	# The pads' own frame loop is stopped, so nothing sends over what is set below.
	for p: Variant in pads:
		if is_instance_valid(p):
			(p as Node).set_physics_process(false)
			(p as Node).set_process(false)
	print("[fourcore] players on libretro ports %s" % str(pads.map(
		func(p: Variant) -> int: return int((p as Node).call("get_port_index")) if is_instance_valid(p) else -9)))

	sys.rom_path = rom_path
	sys.toggle_power()
	var lib := sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 60000
	while (lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ok("the core came up", not (lib.GetCoreIdentity() as Dictionary).is_empty())
	if (lib.GetCoreIdentity() as Dictionary).is_empty():
		return
	var target := int(lib.GetFrameCount()) + 30
	while int(lib.GetFrameCount()) < target:
		await get_tree().process_frame
	var ids: Array = []
	for e: Dictionary in sys.controller_ports().controller_info:
		ids.append("%d:%d" % [int(e.get("port", -1)), int(e.get("current_id", -1))])
	print("[fourcore] the core was told %s" % ", ".join(ids))

	# Each player's button, through that pad's own delivery path.
	for player in pads.size():
		var p: Variant = pads[player]
		if is_instance_valid(p) and int((p as Node).call("get_port_index")) >= 0:
			(p as Node).call("_deliver_joypad", {"btn": 1 << int(held[player]),
				"alx": 0, "aly": 0, "arx": 0, "ary": 0})
	target = int(lib.GetFrameCount()) + 30
	while int(lib.GetFrameCount()) < target:
		await get_tree().process_frame

	var reads := _reads(lib)
	if reads.is_empty():
		_ok("the ROM's RAM is mapped", false)
		return
	var p4016: Array = reads[0]
	var p4017: Array = reads[1]
	print("[fourcore] $4016: %s" % str(p4016))
	print("[fourcore] $4017: %s" % str(p4017))
	var d0_16 := p4016.map(func(v: int) -> int: return v & 1)
	var d0_17 := p4017.map(func(v: int) -> int: return v & 1)
	var d1_16 := p4016.map(func(v: int) -> int: return (v >> 1) & 1)
	var d1_17 := p4017.map(func(v: int) -> int: return (v >> 1) & 1)
	# The NES read order: A, B, SELECT, START, UP, DOWN, LEFT, RIGHT.
	match leg:
		"4p":
			_ok("player 1 is the pad in socket 1 (A)", d0_16.slice(0, 8) == [1, 0, 0, 0, 0, 0, 0, 0], str(d0_16.slice(0, 8)))
			_ok("player 3 is the pad in socket 3 (SELECT)", d0_16.slice(8, 16) == [0, 0, 1, 0, 0, 0, 0, 0], str(d0_16.slice(8, 16)))
			_ok("$4016 signs as the Four Score", d0_16.slice(16, 24) == [0, 0, 0, 1, 0, 0, 0, 0], str(d0_16.slice(16, 24)))
			_ok("player 2 is the pad in socket 2 (B)", d0_17.slice(0, 8) == [0, 1, 0, 0, 0, 0, 0, 0], str(d0_17.slice(0, 8)))
			_ok("player 4 is the pad in socket 4 (START)", d0_17.slice(8, 16) == [0, 0, 0, 1, 0, 0, 0, 0], str(d0_17.slice(8, 16)))
			_ok("$4017 signs as the Four Score", d0_17.slice(16, 24) == [0, 0, 1, 0, 0, 0, 0, 0], str(d0_17.slice(16, 24)))
		"2p", "none":
			_ok("player 1 (A)", d0_16.slice(0, 8) == [1, 0, 0, 0, 0, 0, 0, 0], str(d0_16.slice(0, 8)))
			_ok("player 2 (B)", d0_17.slice(0, 8) == [0, 1, 0, 0, 0, 0, 0, 0], str(d0_17.slice(0, 8)))
			_ok("no Four Score on $4016: all 1s after player 1", d0_16.slice(8, 24).all(func(v: int) -> bool: return v == 1), str(d0_16.slice(8, 24)))
			_ok("none on $4017 either", d0_17.slice(8, 24).all(func(v: int) -> bool: return v == 1), str(d0_17.slice(8, 24)))
		"famicom":
			_ok("player 1 is the hardwired Controller I (A)", d0_16.slice(0, 8) == [1, 0, 0, 0, 0, 0, 0, 0], str(d0_16.slice(0, 8)))
			_ok("player 3 is the pad in the adaptor's socket 1 (SELECT, on D1)", d1_16.slice(0, 8) == [0, 0, 1, 0, 0, 0, 0, 0], str(d1_16.slice(0, 8)))
			_ok("player 4 is the pad in its socket 2 (START, on D1)", d1_17.slice(0, 8) == [0, 0, 0, 1, 0, 0, 0, 0], str(d1_17.slice(0, 8)))
			_ok("then 1s, as the simple adapter does", d1_16.slice(8, 24).all(func(v: int) -> bool: return v == 1), str(d1_16.slice(8, 24)))
	sys.toggle_power()
	for i in range(60):
		await get_tree().process_frame


## The 24 reads of each port the ROM left at $0300 and $0320, or [] when the core
## maps no work RAM at $0000.
func _reads(lib: Object) -> Array:
	var snap: Dictionary = lib.call("SnapshotMappedRam")
	var data: PackedByteArray = snap.get("data", PackedByteArray())
	for r: Dictionary in snap.get("regions", []):
		var start := int(r.get("start", -1))
		if start != 0 or int(r.get("len", 0)) < 0x340:
			continue
		var base := int(r.get("offset", 0))
		var a: Array = []
		var b: Array = []
		for k in 24:
			a.append(int(data[base + 0x300 + k]))
			b.append(int(data[base + 0x320 + k]))
		return [a, b]
	print("[fourcore] mapped regions: %s" % str(snap.get("regions", [])))
	return []
