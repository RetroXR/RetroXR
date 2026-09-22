## Three real PlayStation 2s running Gran Turismo 3, cabled through the ROOM's
## i.LINK hub, for the three-screen i.LINK Battle "Broadcast" set-up
## (jamesfmackenzie.com, 2026-09-14): every console on Arcade -> i.LINK Battle ->
## Broadcast, the centre one the control unit, the outer two its side views.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/link/gt3_ilink_hub_probe.tscn -- "--rom=<GT3.iso>" \
##       --script=res://Tools/link/gt3_three_screen.txt \
##       --shots=res://probe_out/gt3 --until=9000 --every=150
##
## Windowed: pcsx2 renders on the GPU, and headless hands back blank frames.
## Wants the pcsx2 core in <root>/cores and a PS2 BIOS in
## <root>/system/pcsx2/pcsx2/bios. A probe, not a test: a real game and firmware.
##
## Script, one event per line, frames counted on EACH console's own clock:
##     <frame> <who> press <BUTTON[+BUTTON]> [hold=10]
##     <frame> <who> shot <label>          # triptych L|C|R, keyed on <who>'s clock
##     <frame> <who> replug                # pull <who>'s lead at the hub, re-seat
##     <frame> * reenter <until>           # bounced to the Arcade menu? back in
## <who> is L, C, R or * (each console at its own frame). # starts a comment.
## GT3 drops presses shorter than ~8 frames, hence the default hold of 10.
##
## Measured 2026-09-22 (docs/dev/ps2-ilink.md): all three reach i.LINK Battle,
## take Console IDs 3/2/1 (L/C/R), all choose Broadcast, ID 1 becomes the
## control unit and races; IDs 2 and 3 show its left and right views with no
## HUD, a continuous panorama when ordered ID 2 | ID 1 | ID 3.
extends Node

const NAMES := ["L", "C", "R"]
const BUTTONS := {
	"CROSS": 1 << 0, "SQUARE": 1 << 1, "SELECT": 1 << 2, "START": 1 << 3,
	"UP": 1 << 4, "DOWN": 1 << 5, "LEFT": 1 << 6, "RIGHT": 1 << 7,
	"CIRCLE": 1 << 8, "TRIANGLE": 1 << 9, "L1": 1 << 10, "R1": 1 << 11,
	"L2": 1 << 12, "R2": 1 << 13,
}

var _rom := ""
var _script_path := ""
var _shots := "res://probe_out/gt3"
var _until := 4000
var _stagger := 3.0
var _every := 0

var _sys: Array[Node3D] = []
var _hub: ILinkHub = null
var _leads: Array[ILinkCable] = []
var _presses: Array = []     # [who_index or -1, start, hold, bits]
var _events: Array = []      # {who, frame, op, arg, done: [bool x3] or bool}
var _replug_at: Array = [-1, -1, -1]
var _reenter_from := -1
var _reenter_until := -1
var _next_check: Array = [0, 0, 0]
var _pull_after: Array = [-1, -1, -1]


func _ready() -> void:
	get_tree().create_timer(1500.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--rom="):
			_rom = s.substr(6)
		elif s.begins_with("--script="):
			_script_path = s.substr(9)
		elif s.begins_with("--shots="):
			_shots = s.substr(8)
		elif s.begins_with("--until="):
			_until = int(s.substr(8))
		elif s.begins_with("--stagger="):
			_stagger = float(s.substr(10))
		elif s.begins_with("--every="):
			_every = int(s.substr(8))
	if not FileAccess.file_exists(_rom):
		print("[probe] need --rom=<GT3 image>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shots))
	_parse_script()
	await _run()
	get_tree().quit(0)


func _parse_script() -> void:
	if _script_path.is_empty():
		return
	for raw in FileAccess.get_file_as_string(_script_path).split("\n"):
		var line := raw.split("#")[0].strip_edges()
		if line.is_empty():
			continue
		var f := line.split(" ", false)
		var frame := int(f[0])
		var who := -1 if f[1] == "*" else NAMES.find(f[1])
		match f[2]:
			"press":
				var bits := 0
				for b in f[3].split("+"):
					bits |= int(BUTTONS[b])
				_presses.append([who, frame, int(f[4]) if f.size() > 4 else 10, bits])
			"reenter":
				# Until <arg>, a console showing the (blue) Arcade menu is pressed
				# back into i.LINK Battle and replugged once it is in.
				_reenter_from = frame
				_reenter_until = int(f[3])
			_:
				_events.append({"who": who, "frame": frame, "op": f[2],
					"arg": f[3] if f.size() > 3 else "", "done": [false, false, false]})


func _run() -> void:
	# The room: three consoles on a shelf, a hub in front, a lead from each
	# console's i.LINK socket into hub ports 1, 3 and 5 -- cabled BEFORE power-on,
	# the way the article's rig is built.
	for k in range(3):
		var sys := (preload("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as Node3D
		sys.set("systemid", "ps2")
		sys.set("core_name", "pcsx2")
		sys.name = "PS2_" + NAMES[k]
		sys.position = Vector3(-0.45 + 0.45 * k, 0, 0)
		add_child(sys)
		_sys.append(sys)
	_hub = (preload("res://Scenes/Objects/cables/ilink_hub.tscn") as PackedScene).instantiate()
	_hub.position = Vector3(0, 0, 0.45)
	_hub.freeze = true
	add_child(_hub)
	for k in range(3):
		var lead: ILinkCable = (preload("res://Scenes/Objects/cables/ilink_cable.tscn") as PackedScene).instantiate()
		lead.name = "Lead_" + NAMES[k]
		add_child(lead)
		_leads.append(lead)
	await get_tree().process_frame
	await get_tree().process_frame
	for k in range(3):
		(_sys[k].find_child("ILinkPort", true, false) as ILinkPort).pick_up_object(_leads[k].get_node("PlugA0"))
		_hub.sockets()[k * 2].pick_up_object(_leads[k].get_node("PlugB0"))
	await get_tree().process_frame
	for lead in _leads:
		lead._resolve()
	print("[probe] room bus: %d consoles" % (_leads[0].linked_machines() as Array).size())

	# Staggered power-on: three pcsx2 cores initialising in one instant is what
	# first broke the fork's six-console run.
	for k in range(3):
		_sys[k].set("rom_path", _rom)
		_sys[k].call("power_on")
		print("[probe] %s power_on -> %s" % [NAMES[k], str(_sys[k].get("is_powered_on"))])
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < int(_stagger * 1000.0):
			await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		var up := 0
		for k in range(3):
			if not (_lib(k).GetCoreIdentity() as Dictionary).is_empty():
				up += 1
		if up == 3:
			break
	for k in range(3):
		print("[probe] %s identity %s" % [NAMES[k], str(_lib(k).GetCoreIdentity())])

	var last_log := 0
	var next_every := _every
	while true:
		await get_tree().process_frame
		var frames: Array[int] = []
		for k in range(3):
			frames.append(int(_lib(k).GetFrameCount()))
		for k in range(3):
			var bits := 0
			for p: Array in _presses:
				if (p[0] == -1 or p[0] == k) and frames[k] >= p[1] and frames[k] < p[1] + p[2]:
					bits |= int(p[3])
			_lib(k).SetJoypadState(0, bits, 0, 0, 0, 0)
		for e: Dictionary in _events:
			for k in range(3):
				if e["done"][k] or (e["who"] != -1 and e["who"] != k) or frames[k] < e["frame"]:
					continue
				e["done"][k] = true
				_do(e, k, frames)
		for k in range(3):
			if _reenter_from < 0 or frames[k] < _reenter_from or frames[k] >= _reenter_until \
					or frames[k] < int(_next_check[k]):
				continue
			_next_check[k] = frames[k] + 90
			if _bluish(k):
				_presses.append([k, frames[k], 10, BUTTONS["CROSS"]])
				_pull_after[k] = frames[k] + 150
				print("[probe] %s back on the Arcade menu @%d, re-entering" % [NAMES[k], frames[k]])
		for k in range(3):
			if _pull_after[k] >= 0 and frames[k] >= _pull_after[k]:
				_pull_after[k] = -1
				_do({"op": "replug", "arg": ""}, k, frames)
		for k in range(3):
			if _replug_at[k] >= 0 and frames[k] >= _replug_at[k]:
				_replug_at[k] = -1
				_hub.sockets()[k * 2].pick_up_object(_leads[k].get_node("PlugB0"))
				await get_tree().process_frame
				_leads[k]._resolve()
				print("[probe] %s re-seated at the hub @%d, bus %d" % [NAMES[k], frames[k],
					(_leads[k].linked_machines() as Array).size()])
		if _every > 0 and frames[1] >= next_every:
			next_every += _every
			_triptych("f%05d" % frames[1], frames)
		if Time.get_ticks_msec() - last_log > 10000:
			last_log = Time.get_ticks_msec()
			print("[probe] frames L=%d C=%d R=%d  peers %d/%d/%d" % [frames[0], frames[1], frames[2],
				_lib(0).LinkPeerCount(0), _lib(1).LinkPeerCount(0), _lib(2).LinkPeerCount(0)])
		if frames.min() >= _until:
			break
	_triptych("end", [int(_lib(0).GetFrameCount()), int(_lib(1).GetFrameCount()), int(_lib(2).GetFrameCount())])
	for k in range(3):
		_sys[k].call("power_off")
	for i in range(90):
		await get_tree().process_frame


func _do(e: Dictionary, k: int, frames: Array) -> void:
	match str(e["op"]):
		"shot":
			# Keyed on one console's clock; `*` would take three.
			_triptych("%s" % e["arg"], frames)
		"replug":
			_hub.sockets()[k * 2].drop_object()
			_leads[k]._resolve()
			_replug_at[k] = frames[k] + 60
			print("[probe] %s pulled at the hub @%d" % [NAMES[k], frames[k]])


## The Arcade menu is a blue-white screen; every i.LINK Battle screen is red and
## black. Enough to tell a console that got bounced out from one that is in.
func _bluish(k: int) -> bool:
	var img: Image = _lib(k).GetVideoImage()
	if img == null or img.is_empty():
		return false
	var small := img.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	small.resize(16, 12, Image.INTERPOLATE_BILINEAR)
	var r := 0.0
	var b := 0.0
	for y in range(12):
		for x in range(16):
			var c := small.get_pixel(x, y)
			r += c.r
			b += c.b
	return b > r * 1.2


func _lib(k: int) -> Libretro:
	return _sys[k].call("get_libretro_node") as Libretro


## L | C | R side by side, each flattened to RGB (the core leaves alpha unfilled).
func _triptych(label: String, frames: Array) -> void:
	var imgs: Array[Image] = []
	var w := 0
	var h := 0
	for k in range(3):
		var img: Image = _lib(k).GetVideoImage()
		if img == null or img.is_empty():
			img = Image.create(320, 240, false, Image.FORMAT_RGB8)
		else:
			img = img.duplicate() as Image
			img.convert(Image.FORMAT_RGB8)
			img.resize(320, int(320.0 * img.get_height() / img.get_width()))
		imgs.append(img)
		w += img.get_width()
		h = maxi(h, img.get_height())
	var out := Image.create(w + 8, h, false, Image.FORMAT_RGB8)
	out.fill(Color(1, 0, 1))
	var x := 0
	for img in imgs:
		out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, 0))
		x += img.get_width() + 4
	var path := "%s/%s.png" % [_shots, label]
	out.save_png(path)
	print("[probe] shot %s  frames %s" % [path, str(frames)])
