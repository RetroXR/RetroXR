## Arcade netplay self-tests — what an arcade cabinet tells a session, and what it hands it. Headless, no core, no ROM,
## no headset, no second machine: the session's own half (the spec crossing the wire, peers that refuse it) is
## netplay_tests' start/ group, over loopback; this is the cabinet's half.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_netplay_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_netplay_tests.tscn -- --only=route
##
## Exits 0 when everything passes, 1 otherwise.
##
## Groups:
##   boot/    the host's spec carries the board's disc manifest and its DIP switches; a client takes the host's DIPs
##            (its own put back to the defaults), and refuses a disc folder that is not the host's
##   route/   in a session every control on the cabinet -- a panel, a coin, a gun -- is handed to the session, never
##            straight to the core (attract mode staying out of a session is arcade_attract_tests')
##   form/    two peers with the same board build the same form, whatever their own settings
##
## The real arithmetic of a session (FinalBurn Neo rolling back an arcade game between two machines) is OWED: it needs
## a real core, a real game and two peers (docs/dev/netplay.md "Arcade cabinets").
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const ROOT := "user://arcade_netplay_test"


## A session that is running and takes everything it is handed, keeping it for the case to read.
class FakeSession extends NetplaySession:
	var routed: Array = []
	var gun_buttons: Array = []

	func is_running() -> bool:
		return true

	func route(sys: Object, port: int, pad: Dictionary) -> bool:
		routed.append({"sys": sys, "port": port, "btn": int(pad.get("btn", 0))})
		return true

	func set_lightgun_button(sys: Object, local_port: int, button: int, pressed: bool) -> bool:
		gun_buttons.append({"sys": sys, "port": local_port, "button": button, "pressed": pressed})
		return true

	func set_lightgun_aim(_sys: Object, _local_port: int, _px: int, _py: int, _offscreen: bool) -> bool:
		return true

	## Whether `port` of `sys` was ever handed over with `bit` down.
	func saw(sys: Object, port: int, bit: int) -> bool:
		for r: Dictionary in routed:
			if r["sys"] == sys and int(r["port"]) == port and (int(r["btn"]) >> bit) & 1 == 1:
				return true
		return false


var _only := ""
var _spawned: Array[Node] = []
var _real_session: NetplaySession = null


func _ready() -> void:
	suite_tag = "arcadenet"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[arcadenet] TIMED OUT")
		_unfake()
		get_tree().quit(1))
	_wipe(ProjectSettings.globalize_path(ROOT))
	if _want("boot"):
		await _group_boot()
		await _clear()
	if _want("route"):
		await _group_route()
		await _clear()
	if _want("form"):
		await _group_form()
		await _clear()
	_wipe(ProjectSettings.globalize_path(ROOT))
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# --- helpers -------------------------------------------------------------------

func _machine(model_id: String = ArcadeProfiles.CABINET_MODEL_ID, systemid: String = "arcade", frames: int = 10) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 4.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(frames)
	return sys


func _clear() -> void:
	_unfake()
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	for bay in get_tree().get_nodes_in_group(ArcadeBayUnit.GROUP):
		bay.queue_free()
	_spawned.clear()
	await _wait(6)


func _slot_of(sys: RetroSystem) -> XRToolsSnapZone:
	var bay := sys.get_bay()
	return bay.slot if bay != null else sys.get_node("CartridgeSlot") as XRToolsSnapZone


func _board(sys: RetroSystem, romset: String, frames: int = 30) -> void:
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = "/tmp/%s.zip" % romset
	cart.position = sys.global_position + Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(6)
	_slot_of(sys).pick_up_object(cart)
	await _wait(frames)


func _fake() -> FakeSession:
	if _real_session == null:
		_real_session = NetworkManager._netplay
	var fake := FakeSession.new()
	NetworkManager._netplay = fake
	return fake


func _unfake() -> void:
	if _real_session != null:
		var fake := NetworkManager._netplay
		NetworkManager._netplay = _real_session
		_real_session = null
		if fake != null and fake is FakeSession:
			fake.free()


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _bytes(n: int, seed_byte: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = (i * 7 + seed_byte) & 0xFF
	return b


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_wipe(dir_path.path_join(d))
	DirAccess.remove_absolute(dir_path)


# --- boot ----------------------------------------------------------------------

func _group_boot() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	var board := _bytes(4096, 1)
	var disc := _bytes(2048, 2)
	# The host: a board with its disc folder, and DIPs saved for this game and another.
	var host_board := root.path_join("host/roms/arcade/sf2.zip")
	_write(host_board, board)
	_write(root.path_join("host/roms/arcade/sf2/disc.chd"), disc)
	var host_cores := root.path_join("host/cores")
	CoreOptionsStore.save_values(host_cores, "fbneo", {
		"fbneo-dipswitch-sf2-Lives": "5",
		"fbneo-dipswitch-mslug-Lives": "1",
		"fbneo-frameskip": "0",
	})
	var host := await _machine()
	host.core_directory = host_cores
	host.rom_path = host_board
	var spec := host.net_boot_spec("fbneo")
	# The BIOS check runs before these and is the firmware's (netplay_tests link/); a suite's peers share one system folder.
	spec.erase("firmware")
	spec.erase("firmware_rows")
	# The session names the core in every machine's spec (NetplaySession._build_machine_specs).
	spec["core"] = "fbneo"
	_eq(spec.get("discs"), [{"name": "disc.chd", "size": disc.size()}], "boot: the host's spec names its disc, by name and size")
	var opts: Dictionary = spec.get("game_options", {})
	_eq(str(opts.get("prefix", "")), "fbneo-dipswitch-sf2-", "boot: and the DIP prefix of THIS game")
	_eq(opts.get("values", {}), {"fbneo-dipswitch-sf2-Lives": "5"},
		"boot: carrying this game's saved DIPs only, not another game's nor the core's other options")
	_ok(not host.net_boot_spec("mame").has("game_options"), "boot: a core that keeps its DIPs elsewhere sends none")
	_ok(host.net_boot_spec("mame").has("discs"), "boot: but still names the disc")

	# A client with the same game, its own DIPs set otherwise.
	var client_board := root.path_join("client/roms/arcade/sf2.zip")
	_write(client_board, board)
	_write(root.path_join("client/roms/arcade/sf2/disc.chd"), disc)
	var client_cores := root.path_join("client/cores")
	CoreOptionsStore.save_values(client_cores, "fbneo", {
		"fbneo-dipswitch-sf2-Lives": "1",
		"fbneo-dipswitch-sf2-Difficulty": "Hardest",
		"fbneo-dipswitch-mslug-Lives": "9",
		"fbneo-frameskip": "2",
	})
	var client := await _machine()
	client.core_directory = client_cores
	client.rom_path = client_board
	_ok(client.net_prepare_boot(spec), "boot: a client with the same board and disc prepares the boot")
	var saved := CoreOptionsStore.load_values(client_cores, "fbneo")
	_eq(str(saved.get("fbneo-dipswitch-sf2-Lives", "")), "5", "boot: and takes the host's DIP")
	_ok(not saved.has("fbneo-dipswitch-sf2-Difficulty"),
		"boot: a DIP the host left at its default is put back to the default here too")
	_eq(str(saved.get("fbneo-dipswitch-mslug-Lives", "")), "9", "boot: another game's DIPs are left alone")
	_eq(str(saved.get("fbneo-frameskip", "")), "2", "boot: and so are the core's other options")

	# The disc folder must hold what the host's does.
	_write(root.path_join("client/roms/arcade/sf2/disc.chd"), _bytes(1000, 3))
	_ok(not client.net_prepare_boot(spec) and client.net_boot_failure.contains("disc.chd is a different size"),
		"boot: a disc of another size is refused, and says so (%s)" % client.net_boot_failure)
	DirAccess.remove_absolute(root.path_join("client/roms/arcade/sf2/disc.chd"))
	_ok(not client.net_prepare_boot(spec) and client.net_boot_failure.contains("disc.chd is missing"),
		"boot: no disc at all is refused (%s)" % client.net_boot_failure)
	# A plain board on the host, a stray disc folder on the client: MAME would read it, so it is not the same game.
	var plain := root.path_join("host/roms/arcade/plain.zip")
	_write(plain, _bytes(512, 4))
	host.rom_path = plain
	var plain_spec := host.net_boot_spec("fbneo")
	plain_spec.erase("firmware")
	plain_spec.erase("firmware_rows")
	plain_spec["core"] = "fbneo"
	_eq(plain_spec.get("discs"), [], "boot: a plain board says it has no disc")
	var stray := root.path_join("client/roms/arcade/plain.zip")
	_write(stray, _bytes(512, 4))
	_write(root.path_join("client/roms/arcade/plain/extra.chd"), disc)
	client.rom_path = stray
	_ok(not client.net_prepare_boot(plain_spec) and client.net_boot_failure.contains("extra.chd is not in the host's"),
		"boot: a disc the host's game does not have is refused too (%s)" % client.net_boot_failure)


# --- route ---------------------------------------------------------------------

func _group_route() -> void:
	var sys := await _machine()
	await _board(sys, "sf2")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var input := model.arcade_input()
	# The game has run its boot, so a coin goes straight in (arcade_variants_tests fire/ does the same).
	input.frame_override = 0
	var fake := _fake()
	_ok(NetworkManager.netplay_running(), "route: (a session is running)")
	sys.is_powered_on = true
	await _wait(3)
	input.frame_override = input.wait_frames()
	# Player 2's panel, attached, a button pressed: the session gets it on port 1.
	var p2: ArcadeControlModule = null
	for m in model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		if (m as ArcadeControlModule).player == 1:
			p2 = m as ArcadeControlModule
	var grip := p2.grip()
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))
	await _wait(3)
	var bit_b := ControllerBindings.JOYPAD_B
	Input.action_press("RETRO_JOYPAD_B")
	await _wait(4)
	_ok(fake.saw(sys, 1, bit_b), "route: player 2's panel press is handed to the session on port 1")
	_ok(not fake.saw(sys, 0, bit_b), "route: and not on player 1's")
	_ok((int(input._heard_mask.get(1, 0)) & (1 << bit_b)) == 0, "route: and never straight to the core")
	Input.action_release("RETRO_JOYPAD_B")
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))
	await _wait(3)
	# Player 2's coin.
	var door: ArcadeCoinModule = null
	for m in model.modules_of_kind(ArcadeProfiles.KIND_COIN):
		if (m as ArcadeCoinModule).player == 1:
			door = m as ArcadeCoinModule
	_ok(door != null, "route: (player 2 has a coin door)")
	if door != null:
		fake.routed.clear()
		door.insert_coin()
		_ok(await _wait_until(func() -> bool: return fake.saw(sys, 1, ArcadeProfiles.COIN_BIT), 6.0),
			"route: player 2's coin is handed to the session on port 1")
		_ok(not fake.saw(sys, 0, ArcadeProfiles.COIN_BIT), "route: and credits nobody else")
	sys.is_powered_on = false
	await _wait(3)
	_unfake()

	# A gun game: the gun's START goes to the session as the gun's own button.
	var gun_sys := await _machine()
	await _board(gun_sys, "ptblank", 120)
	var gun_model := gun_sys.get_model() as RetroSystemModelArcadeCabinet
	gun_model.arcade_input().frame_override = 0
	var guns := gun_sys.captive_controllers()
	_ok(guns.size() >= 1 and guns[0] is LightGun, "route: (the gun game has its guns)")
	fake = _fake()
	gun_sys.is_powered_on = true
	await _wait(3)
	gun_model.arcade_input().frame_override = gun_model.arcade_input().wait_frames()
	var p1: ArcadeControlModule = null
	for m in gun_model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		if (m as ArcadeControlModule).player == 0:
			p1 = m as ArcadeControlModule
	var start := p1.grip()
	start.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, start, Vector3.ZERO, Vector3.ZERO))
	await _wait(6)
	var gun_start := fake.gun_buttons.any(func(r: Dictionary) -> bool:
		return r["sys"] == gun_sys and int(r["port"]) == 0 and int(r["button"]) == ControllerBindings.LIGHTGUN_START and r["pressed"])
	_ok(gun_start, "route: player 1's START reaches the session as the gun's START, on the gun's port (%d gun presses seen)"
		% fake.gun_buttons.size())
	_ok(fake.saw(gun_sys, 0, ArcadeProfiles.START_BIT), "route: and as the joypad's START on that port")
	start.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, null, start, Vector3.ZERO, Vector3.ZERO))
	gun_sys.is_powered_on = false
	await _wait(3)
	_unfake()


# --- form ----------------------------------------------------------------------

func _group_form() -> void:
	# Two peers' cabinets, the same board, each peer's own settings different: the form is the board's.
	var motion_before := AppPrefs.arcade_motion
	var a := await _machine()
	AppPrefs.arcade_motion = AppPrefs.MOTION_ON if motion_before != AppPrefs.MOTION_ON else AppPrefs.MOTION_OFF
	var b := await _machine()
	for romset in ["tmnt", "ptblank", "outrun"]:
		await _board(a, romset)
		await _board(b, romset)
		var fa := (a.get_model() as RetroSystemModelArcadeCabinet).form_spec()
		var fb := (b.get_model() as RetroSystemModelArcadeCabinet).form_spec()
		_ok(not fa.is_empty() and ArcadeCabinetSpecs._same_form(fa, fb),
			"form: %s builds the same form on both peers" % romset)
		_eq(a.captive_controllers().size(), b.captive_controllers().size(), "form: %s has the same guns on both" % romset)
		_slot_of(a).drop_object()
		_slot_of(b).drop_object()
		await _wait(10)
	AppPrefs.arcade_motion = motion_before
