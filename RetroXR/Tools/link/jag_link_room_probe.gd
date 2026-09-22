## A JagLink lead between two Atari Jaguars, seated the way a hand seats it.
##
##   "$godot" --headless --path RetroXR res://Tools/link/jag_link_room_probe.tscn -- \
##       "--rom=Z:/roms/atarijaguar/Air Cars (World).j64"
##
## jag_link_probe.gd joins two bare Libretro nodes with LinkConnect; this one
## builds two machines as the room does, seats each end of a JagLinkCable in a
## console's DSP port, and checks the room's path ends on the same bus: nobody
## cabled, one end in is still nobody, both ends in is a pair, AirCars'
## Two Player Direct Serial then moves bytes both ways, and pulling a plug parts them.
## A probe: it wants the virtualjaguar fork and a cartridge.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CABLE_SCENE := "res://Scenes/Objects/cables/jag_link_cable.tscn"
const CORE := "virtualjaguar"
const BUTTONS := {"b": 0, "start": 3, "up": 4, "down": 5, "right": 7, "a": 8}
const AIRCARS_WALK := "wait:600,ab:a:10,wait:200,ab:down:6,wait:60,ab:a:10,wait:200,b:down:6,wait:60,ab:a:10,wait:200,ab:a:10,wait:200,ab:a:10,wait:300,a:a:10,wait:600,ab:a:10,wait:300,ab:a:10,wait:600"

var rom := ""
var _systems: Array[RetroSystem] = []
var _pass := 0
var _fail := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			rom = a.trim_prefix("--rom=")
	if rom.is_empty():
		print("[jag-room] need --rom=")
		get_tree().quit(2)
		return
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[jag-room] TIMEOUT")
		get_tree().quit(2))
	await _run()


func _run() -> void:
	# A table to stand on: with nothing under them the consoles fall, and a
	# falling console drags the lead's plug out of its socket.
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.1, 4.0)
	shape.shape = box
	table.add_child(shape)
	var top := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = box.size
	top.mesh = slab
	table.add_child(top)
	add_child(table)
	table.global_position = Vector3(0.3, 0.9, 0.0)
	for i in range(2):
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "atarijaguar"
		sys.core_name = CORE
		sys.name = "Jag%d" % i
		add_child(sys)
		sys.global_position = Vector3(i * 0.6, 1.05, 0.0)
		_systems.append(sys)
	await get_tree().process_frame
	for sys in _systems:
		sys.rom_path = rom
		sys.power_on()
	await _frames(300)
	_ok("both Jaguars powered on", _systems[0].is_powered_on and _systems[1].is_powered_on)

	var ports: Array[JagLinkPort] = []
	for sys in _systems:
		ports.append(sys.find_child("JagLinkPort", true, false) as JagLinkPort)
	_ok("each Jaguar wears a DSP port", ports.count(null) == 0)
	if ports.count(null) > 0:
		return _finish()

	var lead := (load(CABLE_SCENE) as PackedScene).instantiate() as JagLinkCable
	add_child(lead)
	await get_tree().process_frame
	_eq("nobody is cabled to start with", _peers(0), 0)

	ports[0].pick_up_object(lead.get_node("PlugA0"))
	await _frames(6)
	_eq("one end in a socket is still nobody", _peers(0), 0)
	ports[1].pick_up_object(lead.get_node("PlugB0"))
	await _frames(6)
	_eq("both ends in: machine 0 sees a pair", _peers(0), 2)
	_eq("both ends in: machine 1 sees a pair", _peers(1), 2)
	_eq("the lead reports both machines", lead.linked_machines().size(), 2)

	# No controller is plugged in here, so port 0 carries no pad until one is
	# declared -- which is what plugging a pad into the console does.
	for i in 2:
		_lib(i).SetControllerPortDevice(0, 1)
	await _frames(10)
	var sent0 := _sent(0)
	# AirCars' walk from jag_link_probe.gd: its title waits for A, where Doom's
	# attract loop only listens in some phases and a room boot lands elsewhere.
	await _walk(AIRCARS_WALK)
	_ok("both plugs are still seated after the game",
		(lead.get_node("PlugA0") as RcaPlug).seated_port() == ports[0]
			and (lead.get_node("PlugB0") as RcaPlug).seated_port() == ports[1])
	_ok("AirCars trades bytes across the seated lead",
		_sent(0) - sent0 >= 200 and _sent(1) >= 200,
		"sent A=%d B=%d" % [_sent(0) - sent0, _sent(1)])
	_shot("end")
	# After the walk: the machines run on while the camera moves, and taken
	# earlier the photos shifted AirCars' title out from under the menu walk.
	if OS.get_cmdline_user_args().has("--shot"):
		await _photograph(ports[0], ports[1])

	var plug := lead.get_node("PlugB0") as RcaPlug
	ports[1].drop_object()
	plug.freeze = true
	plug.global_position += Vector3(0.0, 3.0, 0.0)
	await _frames(10)
	_eq("pulling a plug parts them", _peers(0), 0)
	_finish()


## The step script of jag_link_probe.gd: wait:N, and a|b|ab:button:hold.
func _walk(steps: String) -> void:
	for step in steps.split(","):
		var p := step.split(":")
		if p[0] == "wait":
			await _frames(int(p[1]))
			continue
		var who: Array = [0, 1] if p[0] == "ab" else ([0] if p[0] == "a" else [1])
		for i: int in who:
			_lib(i).SetJoypadState(0, 1 << int(BUTTONS[p[1]]), 0, 0, 0, 0)
		await _frames(int(p[2]))
		for i: int in who:
			_lib(i).SetJoypadState(0, 0, 0, 0, 0, 0)
		await _frames(12)


## --shot, windowed: the cabled pair from above, from behind, and the socket
## close up, to probe_out/jag/room/. Headless renders a blank image.
func _photograph(socket: Node3D, other: Node3D) -> void:
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-50, 150, 0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	cam.current = true
	# Framed off the sockets, not the machines' origins: the bodies are live and
	# settle wherever physics puts them. A socket's local +Z points out of the panel.
	var mid := (socket.global_position + other.global_position) * 0.5
	var out := socket.global_basis.z.normalized()
	var dir := ProjectSettings.globalize_path("res://probe_out/jag/room")
	DirAccess.make_dir_recursive_absolute(dir)
	var views := {"above": out * 0.5 + Vector3.UP * 0.9, "behind": out * 1.0 + Vector3.UP * 0.3,
		"socket": out * 0.22 + Vector3.UP * 0.08}
	for view: String in views:
		var target: Vector3 = socket.global_position if view == "socket" else mid
		cam.global_position = target + views[view]
		cam.look_at(target, Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, view])
		print("[jag-room] shot %s/%s.png" % [dir, view])
	cam.queue_free()
	light.queue_free()


func _shot(tag: String) -> void:
	var a: Image = _lib(0).GetVideoImage()
	var b: Image = _lib(1).GetVideoImage()
	if a == null or b == null or a.is_empty() or b.is_empty():
		return
	var pair := Image.create_empty(a.get_width() * 2 + 8, a.get_height(), false, a.get_format())
	pair.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	pair.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width() + 8, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://probe_out"))
	var path := "res://probe_out/jag_room_%s.png" % tag
	pair.save_png(path)
	print("[jag-room] shot %s" % ProjectSettings.globalize_path(path))


func _lib(i: int) -> Libretro:
	return _systems[i].get_libretro_node() as Libretro


func _peers(i: int) -> int:
	var lib := _lib(i)
	return lib.LinkPeerCount(0) if lib != null else -1


func _sent(i: int) -> int:
	var lib := _lib(i)
	return int(lib.LinkSent(0)) if lib != null else 0


## Emulated frames on both machines, bounded in host frames.
func _frames(n: int) -> void:
	var t0 := int(_lib(0).GetFrameCount()) + n if _lib(0) != null else 0
	var t1 := int(_lib(1).GetFrameCount()) + n if _lib(1) != null else 0
	var guard := n * 200 + 200
	while guard > 0 and _lib(0) != null and _lib(1) != null \
			and (int(_lib(0).GetFrameCount()) < t0 or int(_lib(1).GetFrameCount()) < t1):
		guard -= 1
		await get_tree().process_frame


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[jag-room] PASS  %s" % name)
	else:
		_fail += 1
		print("[jag-room] FAIL  %s%s" % [name, "  - " + detail if detail else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [got, want])


func _finish() -> void:
	for sys in _systems:
		if is_instance_valid(sys) and sys.is_powered_on:
			sys.power_off()
	await get_tree().create_timer(2.0).timeout
	print("[jag-room] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
