## The DMG-07 4 Player Adapter in the ROOM, with real cores: four Game Boys
## (RetroSystem, gambatte) and the adapter object (Dmg07Adapter, its own dmg07
## core), cabled through the room's own leads -- player 1's captive lead into the
## first Game Boy, a DMG-04 from each of the others into the adapter's sockets.
## Every Game Boy is switched on, a lead at a time as players would, then each picks
## MULTI (DOWN, A), and the adapter's core says in its own log who answered.
##
##     "$godot" --headless --path RetroXR res://Tools/link/dmg07_room_probe.tscn -- \
##         --rom="<Wave Race>.gb" --out=<dir> 2>&1 | grep -a -E "\[dmg07room\]|\[DMG-07\]"
##
## Uses the real cores folder (dmg07 and gambatte must be installed) and the real
## data root. `--nolink` the control: no leads, so nobody answers.
extends Node

var rom_path := ""
var out_dir := ""
var nolink := false
var _gbs: Array[RetroSystem] = []
var _adapter: Dmg07Adapter = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
		elif a == "--nolink":
			nolink = true
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[dmg07room] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if not FileAccess.file_exists(rom_path) or out_dir.is_empty():
		print("[dmg07room] need --rom= and --out=")
		get_tree().quit(1)
		return
	for core in ["dmg07", "gambatte"]:
		if CoreDownloadManager.installed_core_lib(core).is_empty():
			print("[dmg07room] SKIP  %s is not installed" % core)
			get_tree().quit(0)
			return
	await _run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _link_port(n: Node) -> LinkPort:
	if n is LinkPort:
		return n as LinkPort
	for c in n.get_children():
		var found := _link_port(c)
		if found != null:
			return found
	return null


func _run() -> void:
	_adapter = (load("res://Scenes/Objects/peripherals/dmg07_adapter.tscn") as PackedScene).instantiate() as Dmg07Adapter
	add_child(_adapter)
	_adapter.freeze = true
	for i in 4:
		var sys := (load("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as RetroSystem
		sys.systemid = "gb"
		sys.core_name = "gambatte"
		sys.name = "GameBoy%d" % (i + 1)
		add_child(sys)
		sys.position = Vector3(-0.6 + 0.4 * i, 0, 0.5)
		sys.freeze = true
		_gbs.append(sys)
	await _frames(12)
	var leads: Array = []
	if not nolink:
		for i in 3:
			var l := (load("res://Scenes/Objects/cables/dmg_link_cable.tscn") as PackedScene).instantiate() as LinkCable
			add_child(l)
			leads.append(l)
		await _frames(6)
		_link_port(_gbs[0]).pick_up_object(_adapter.lead().get_node("PlugB0"))
		for i in 3:
			_link_port(_gbs[i + 1]).pick_up_object(leads[i].get_node("PlugA0"))
			_adapter.sockets()[i].pick_up_object(leads[i].get_node("PlugB0"))
		await _frames(6)
	print("[dmg07room] cabled: %s; adapter powered %s" % [not nolink, _adapter.is_powered_on])

	# Switched on one at a time (identical machines on identical clocks otherwise
	# do everything on the same tick).
	for sys in _gbs:
		sys.rom_path = rom_path
		sys.toggle_power()
		await _frames(30)
	await _frames(240)
	print("[dmg07room] Game Boys on: %s" % str(_gbs.map(func(s: RetroSystem) -> bool: return s.is_powered_on)))
	if _adapter.get_libretro_node() != null:
		var lib: Node = _adapter.get_libretro_node()
		print("[dmg07room] adapter ports 0-3 see %s machines" % str(range(4).map(func(p: int) -> int: return int(lib.LinkPeerCount(p)))))
	print("[dmg07room] Game Boys' port 0 see %s machines" % str(_gbs.map(func(s: RetroSystem) -> int:
		return int((s.get_libretro_node() as Node).LinkPeerCount(0)))))

	# The room sends each handheld's idle pad every frame (HandheldInput), which
	# would wipe the presses out: held still for the rest of the run, as
	# vb_link_room_probe does around each press.
	for sys in _gbs:
		var input := _input_node(sys)
		if input != null:
			input.set_process(false)
	# Each picks MULTI: DOWN, then A, one Game Boy after another.
	for sys in _gbs:
		var lib: Node = sys.get_libretro_node()
		for spec: Array in [[1 << 5, 6], [0, 20], [1 << 8, 6], [0, 30]]:
			for f in int(spec[1]):
				lib.SetJoypadState(0, int(spec[0]), 0, 0, 0, 0)
				await get_tree().physics_frame
	await _frames(300)
	_shot("after_multi")
	print("[dmg07room] done")
	for sys in _gbs:
		sys.toggle_power()
	await _frames(30)
	get_tree().quit(0)


func _input_node(node: Node) -> Node:
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("handheld_input.gd"):
			return child
		var found := _input_node(child)
		if found != null:
			return found
	return null


func _shot(tag: String) -> void:
	var sheet := Image.create(160 * 2 * 4, 144 * 2, false, Image.FORMAT_RGB8)
	for p in 4:
		var img: Image = _gbs[p].get_libretro_node().call("GetVideoImage")
		if img == null or img.is_empty():
			continue
		img.convert(Image.FORMAT_RGB8)
		img.resize(320, 288, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(img, Rect2i(0, 0, 320, 288), Vector2i(320 * p, 0))
	var path := out_dir.path_join("%s_%s.png" % ["nolink" if nolink else "room", tag])
	sheet.save_png(path)
	print("[dmg07room] -> %s" % path)
