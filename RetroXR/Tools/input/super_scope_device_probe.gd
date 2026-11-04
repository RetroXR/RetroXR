## Super Scope device probe — what snes9x makes of the Super Scope's receiver.
##
## Oracle: snes9x draws its Super Scope crosshair into the frame AT the gun's
## position, but only on its second port, only while that port really is a Super
## Scope and only while the gun is on the screen (controls.cpp, the SUPERSCOPE
## case of the per-frame poll). So: park the gun offscreen, grab a frame, aim it
## at a fixed spot, grab another, and measure how much the pixels around that
## spot changed against the frame as a whole. Any SNES content runs the poll; a
## Super Game Boy BIOS is what is on this machine, so it is the default.
##
## One leg per process (starting a core wrongly can kill the process):
##   --leg=scope  the device SystemPorts.core_device_id picks for the receiver on
##                libretro port 1, from the list THIS core declares: expect 260
##                and a crosshair where the gun points
##   --leg=pad    the control: port 1 told a plain joypad, aimed the same: expect
##                no crosshair (proves the oracle can tell the two apart)
##   --leg=port0  the receiver in the FIRST socket: the resolver must say NONE,
##                and port 0 aimed shows no crosshair
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/input/super_scope_device_probe.tscn -- --leg=scope [--rom=...]
extends Node3D

static var _home := OS.get_environment("HOME") if OS.get_name() == "Linux" \
		else OS.get_environment("USERPROFILE").replace("\\", "/")

var root_dir := _home + "/retroxr/libretro"
var core := "snes9x"
var rom := _home + "/retroxr/roms/snes/Super Game Boy (World) (Rev 2).sfc"
var leg := "scope"

const NAMES := ["superscope", "super scope"]
const AIM_U := 0.35
const AIM_V := 0.40
const WINDOW := 12

var _lib: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--leg="):
			leg = arg.trim_prefix("--leg=")
		elif arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[scope_probe] TIMEOUT")
		get_tree().quit(1))
	if not FileAccess.file_exists(rom):
		print("[scope_probe] SKIP: rom not found (%s)" % rom)
		get_tree().quit(0)
		return
	var obj: Object = ClassDB.instantiate("Libretro")
	_lib = obj as Node
	add_child(_lib)
	_run()


func _wait_frames(n: int) -> void:
	var target: int = int(_lib.GetFrameCount()) + n
	while int(_lib.GetFrameCount()) < target:
		await get_tree().process_frame


func _grab() -> Image:
	await get_tree().process_frame
	var tex: Texture2D = _lib.GetVideoTexture()
	return tex.get_image() if tex != null else null


## Mean per-pixel change inside the window round the aim point, and over the frame.
func _diff(a: Image, b: Image) -> Array:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var cx := int(AIM_U * w)
	var cy := int(AIM_V * h)
	var win := 0.0
	var win_n := 0
	var all := 0.0
	for y in range(h):
		for x in range(w):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			all += d
			if absi(x - cx) <= WINDOW and absi(y - cy) <= WINDOW:
				win += d
				win_n += 1
	return [win / maxi(win_n, 1), all / float(maxi(w * h, 1))]


func _opaque(img: Image) -> Image:
	var out := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	return out


## Aim `port` offscreen then at the spot; true when a crosshair appeared there.
func _crosshair_on(port: int, tag: String) -> bool:
	_lib.SetLightgunIsOffscreen(port, true)
	await _wait_frames(15)
	var off: Image = await _grab()
	_lib.SetLightgunIsOffscreen(port, false)
	_lib.SetLightgunPosition(port, int((AIM_U * 2.0 - 1.0) * 32767), int((AIM_V * 2.0 - 1.0) * 32767))
	await _wait_frames(15)
	var on: Image = await _grab()
	if off == null or on == null:
		print("[scope_probe] %s: no video texture" % tag)
		return false
	var d := _diff(off, on)
	var seen: bool = d[0] > 0.05 and d[0] > d[1] * 4.0
	print("[scope_probe] %s: port %d aimed-window delta %.4f, frame delta %.4f -> %s"
		% [tag, port, d[0], d[1], "CROSSHAIR" if seen else "nothing"])
	var dir := ProjectSettings.globalize_path("res://probe_out")
	DirAccess.make_dir_recursive_absolute(dir)
	_opaque(on).save_png("%s/super_scope_%s.png" % [dir, tag])
	return seen


func _run() -> void:
	print("[scope_probe] leg %s: booting %s with %s" % [leg, rom.get_file(), core])
	_lib.StartContent(root_dir, core, rom)
	await _wait_frames(240)
	var info: Array = _lib.GetControllerInfo()
	for entry: Dictionary in info:
		var names: Array = []
		for c2: Dictionary in entry["controllers"]:
			names.append("%s=%d" % [c2["name"], c2["id"]])
		print("[scope_probe] core port %d devices: %s" % [entry["port"], ", ".join(names)])
	# SystemPorts.core_device_id, fed the list this very core declared, as the
	# receiver's plug is announced (strict names).
	var sys: Object = load("res://Scripts/Objects/systems/system.gd").new()
	sys.controller_ports().controller_info = info
	var on_two: int = sys.call("core_device_id", 4, 1, PackedStringArray(NAMES), true)
	var on_one: int = sys.call("core_device_id", 4, 0, PackedStringArray(NAMES), true)
	sys.free()
	print("[scope_probe] resolver: receiver on libretro port 1 -> %d %s" % [on_two, "PASS" if on_two == 260 else "FAIL (expected 260)"])
	print("[scope_probe] resolver: receiver on libretro port 0 -> %d %s" % [on_one, "PASS" if on_one == 0 else "FAIL (expected NONE)"])
	var ok := false
	match leg:
		"scope":
			_lib.SetControllerPortDevice(1, on_two)
			await _wait_frames(20)
			ok = await _crosshair_on(1, "scope")
			print("[scope_probe] leg scope: %s" % ("PASS (the core draws the Super Scope where it points)" if ok
				else "FAIL (no crosshair on port 2)"))
		"pad":
			_lib.SetControllerPortDevice(1, 1)
			await _wait_frames(20)
			var seen: bool = await _crosshair_on(1, "pad")
			ok = not seen
			print("[scope_probe] leg pad (control): %s" % ("PASS (a joypad draws nothing: the oracle tells them apart)" if ok
				else "FAIL (a crosshair with no Super Scope: the oracle is blind)"))
		"port0":
			_lib.SetControllerPortDevice(0, on_one)
			await _wait_frames(20)
			var seen0: bool = await _crosshair_on(0, "port0")
			ok = on_one == 0 and not seen0
			print("[scope_probe] leg port0: %s" % ("PASS (nothing reads a Super Scope in the first socket)" if ok else "FAIL"))
		_:
			print("[scope_probe] unknown leg '%s'" % leg)
	_lib.StopContent()
	await get_tree().create_timer(0.5).timeout
	print("[scope_probe] done: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
