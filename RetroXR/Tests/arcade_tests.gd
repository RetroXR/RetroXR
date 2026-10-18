## Arcade self-tests — the Generic Arcade Cabinet, its JAMMA board and the input that
## reaches the core. Headless, no core, no ROM, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_tests.tscn -- --only=door
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
##
## What a headless run cannot show is how any of it LOOKS, so none of this is the
## proof of the geometry: Tools/models/arcade_cabinet_probe (windowed) is.
##
## Groups:
##   profiles/   the data tables: which systems a bay takes, which bits are which
##   input/      the pure half of the cabinet's input: masks, coin pulse, port owner
##   screen/     how a picture's shape becomes a fit on the glass
##   bridge/     the libretro extension hands up the picture's geometry
##   board/      a MAME/FBNeo ROM is a JAMMA board, not a cartridge slab
##   registry/   the cabinet is the hardware of both arcade tiles
##   cabinet/    a built cabinet: modules found by type, sockets, bay, power
##   door/       the lower door gates the slot and is saved as the lid angle
##   pointer/    a ray aimed at a control reaches the control, not a box over the cabinet
##   attach/     a player's panel is ONE controller: aimed at it lights whole, a press attaches you to it
##   hold/       the cabinet is grabbed by HOLDING on it, ring filling, never by a stray squeeze
##   panel/      its options panel stands beside it, and the System tab picks the machine's core
##   art/        a board's sticker shows the cover (or a real label), never the cabinet render
##   seat/       a board goes in, plays, and powers the cabinet off when it leaves
##   card/       what the spawn card offers for an arcade tile
##   ports/      front sockets place the system's zones; a pad owns its port
##   coin/       a coin door tosses a coin and says so when it lands
##   restore/    the ASYNC restore (what the loading overlay waits on) finishes with a cabinet in the room
##   keep/       a room saved with the cabinet in it brings it back
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const MODEL_ID := "arcade_cabinet_generic"

var _checks := 0
var _failed := 0
var _cases_failed := 0
var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[arcade] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[arcade] %d checks, %d case(s) failed" % [_checks, _cases_failed])
	print("[arcade] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		_cases_failed += 1
	print("[arcade] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _near(a: float, b: float, eps: float = 1e-4) -> bool:
	return absf(a - b) <= eps


## A cabinet in the tree, modelled and wired the way the room spawns one.
func _cabinet(systemid: String = "arcade") -> Node3D:
	var sys := SYSTEM_SCENE.instantiate() as Node3D
	sys.model_id = MODEL_ID
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 2.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(6)
	return sys


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(6)


func _run() -> void:
	if _want("profiles"):
		_group_profiles()
	if _want("input"):
		_group_input()
	if _want("screen"):
		_group_screen()
	if _want("bridge"):
		_group_bridge()
	if _want("board"):
		await _group_board()
	if _want("registry"):
		_group_registry()
	if _want("cabinet"):
		await _group_cabinet()
	if _want("door"):
		await _group_door()
	if _want("pointer"):
		await _group_pointer()
	if _want("attach"):
		await _group_attach()
	if _want("hold"):
		await _group_hold()
	if _want("panel"):
		await _group_panel()
	if _want("art"):
		_group_art()
	if _want("seat"):
		await _group_seat()
	if _want("card"):
		await _group_card()
	if _want("ports"):
		await _group_ports()
	if _want("coin"):
		await _group_coin()
	if _want("restore"):
		await _group_restore()
	if _want("keep"):
		await _group_keep()
	await _clear()


# --- profiles ------------------------------------------------------------------

func _group_profiles() -> void:
	_ok(ArcadeProfiles.CONTRACT_VERSION == 1, "profiles: the module contract is version 1")
	_ok(ArcadeProfiles.CABINET_MODEL_ID == MODEL_ID, "profiles: the cabinet id is the persisted one")
	_ok(ArcadeProfiles.is_arcade_system("arcade"), "profiles: arcade plays in a cabinet")
	# mame, fbneo and hbmame were three tiles of one machine (docs/dev/arcade.md): a
	# saved room, a binding or a ledger key that still says one of them reads as arcade,
	# and their ROM folders are arcade's, never renamed.
	for old: String in ["mame", "fbneo", "hbmame", "fb_alpha"]:
		_ok(SystemIds.canonical(old) == "arcade", "profiles: an old %s id is read as arcade" % old)
	for folder: String in ["mame", "fbneo", "fba", "hbmame", "cps1", "cps2", "cps3", "model2", "stv"]:
		_ok(SystemIds.systemid_for_folder(folder) == "arcade", "profiles: roms/%s is arcade's" % folder)
	_ok(SystemIds.folder_names("arcade").has("mame") and SystemIds.folder_names("arcade")[0] == "arcade",
		"profiles: arcade is looked for first under its own name, then the emulators'")
	for own: String in ["neogeo", "naomi", "naomi2", "atomiswave", "daphne", "dice"]:
		_ok(SystemIds.canonical(own) == own, "profiles: %s is a system of its own" % own)
		_ok(SystemIds.systemid_for_folder(own) == own, "profiles: and so is its folder")
	_ok(not ArcadeProfiles.is_arcade_system("nes"), "profiles: a NES is not an arcade system")
	_ok(ArcadeProfiles.bay_accepts("jamma", "arcade") and not ArcadeProfiles.bay_accepts("jamma", "snes"),
		"profiles: a JAMMA bay takes arcade boards and nothing else")
	_ok(ArcadeProfiles.BUTTON_BITS.size() == ArcadeProfiles.BUTTON_COUNT,
		"profiles: one joypad bit per panel button")
	var seen := {}
	for b in ArcadeProfiles.BUTTON_BITS:
		seen[b] = true
	seen[ArcadeProfiles.START_BIT] = true
	seen[ArcadeProfiles.COIN_BIT] = true
	_ok(seen.size() == ArcadeProfiles.BUTTON_COUNT + 2, "profiles: six buttons, START and the coin are eight different bits")
	_ok(ArcadeProfiles.COIN_BIT == ControllerBindings.JOYPAD_SELECT, "profiles: the coin is SELECT, where the cores read it")
	ArcadeProfiles.register_bay_kind("test_mvs", "Test MVS", ["neogeo"])
	_ok(ArcadeProfiles.bay_accepts("test_mvs", "neogeo") and ArcadeProfiles.is_arcade_system("neogeo"),
		"profiles: a mod's bay kind adds its systems")
	ArcadeProfiles._mod_bays.erase("test_mvs")
	_ok(not ArcadeProfiles.is_arcade_system("neogeo"), "profiles: and takes them away when it goes")


# --- input ---------------------------------------------------------------------

func _group_input() -> void:
	var none := [false, false, false, false, false, false]
	_ok(ArcadeInputState.panel_mask(none, false) == 0, "input: an untouched panel sends nothing")
	var one := [true, false, false, false, false, false]
	_ok(ArcadeInputState.panel_mask(one, false) == (1 << ArcadeProfiles.BUTTON_BITS[0]),
		"input: button 1 is its own bit")
	var all := [true, true, true, true, true, true]
	var mask := ArcadeInputState.panel_mask(all, true)
	var want := 0
	for b in ArcadeProfiles.BUTTON_BITS:
		want |= 1 << b
	want |= 1 << ArcadeProfiles.START_BIT
	_ok(mask == want, "input: six buttons and START together are exactly those seven bits")
	_ok(ArcadeInputState.panel_mask([true], false) == (1 << ArcadeProfiles.BUTTON_BITS[0]),
		"input: a short array leaves the rest up")
	_ok(ArcadeInputState.direction_mask(Vector2(-1, 0)) == (1 << ControllerBindings.JOYPAD_LEFT),
		"input: left")
	_ok(ArcadeInputState.direction_mask(Vector2(0, 1)) == (1 << ControllerBindings.JOYPAD_DOWN),
		"input: y is DOWN positive, so +y is down")
	_ok(ArcadeInputState.direction_mask(Vector2(0.2, -0.2)) == 0, "input: inside the threshold is centred")
	_ok(ArcadeInputState.direction_mask(Vector2(1, -1)) == ((1 << ControllerBindings.JOYPAD_RIGHT) | (1 << ControllerBindings.JOYPAD_UP)),
		"input: a diagonal is two bits")
	var coin := ArcadeInputState.compose(0, 0, true)
	_ok(coin == (1 << ArcadeProfiles.COIN_BIT), "input: a coin is the coin bit")
	var both := ArcadeInputState.compose(1 << 0, 1 << 8, false)
	_ok(both == ((1 << 0) | (1 << 8)), "input: panel and the player's own controller OR together")
	_ok(ArcadeInputState.compose(0xff, 0, true, 1 << ArcadeProfiles.COIN_BIT) == 0xff & ~(1 << ArcadeProfiles.COIN_BIT),
		"input: bits the hardware has no control for are cleared, a coin included")
	_ok(not ArcadeInputState.panel_speaks(true) and ArcadeInputState.panel_speaks(false),
		"input: a controller in a front socket silences that player's panel")
	var pulse := ArcadeInputState.CoinPulse.new()
	_ok(not pulse.advance(0.016), "input: no coin, no pulse")
	pulse.insert()
	_ok(pulse.active() and pulse.advance(0.016), "input: a coin holds its bit")
	var frames := 0
	while pulse.advance(0.016) and frames < 60:
		frames += 1
	_ok(frames >= 4 and frames <= 8, "input: and lets go after about a tenth of a second (%d frames)" % frames)
	_ok(not pulse.active(), "input: then it is spent")


# --- screen --------------------------------------------------------------------

func _group_screen() -> void:
	var glass := Vector2(0.38, 0.285)
	var f := ArcadeScreenModule.fit_for(4.0 / 3.0, glass)
	_ok(f.is_equal_approx(Vector2.ONE), "screen: a 4:3 picture fills a 4:3 glass")
	f = ArcadeScreenModule.fit_for(3.0 / 4.0, glass)
	_ok(_near(f.x, (3.0 / 4.0) / (4.0 / 3.0)) and _near(f.y, 1.0),
		"screen: a vertical game is pillarboxed on a landscape glass")
	f = ArcadeScreenModule.fit_for(16.0 / 9.0, glass)
	_ok(_near(f.x, 1.0) and f.y < 1.0, "screen: a wider picture gets bars above and below")
	_ok(ArcadeScreenModule.fit_for(0.0, glass).is_equal_approx(Vector2.ONE),
		"screen: an unknown shape fills the glass")
	_ok(ArcadeScreenModule.fit_for(1.0, Vector2.ZERO).is_equal_approx(Vector2.ONE),
		"screen: a glass of no size is not divided by")
	_ok(_near(ArcadeScreenModule.fallback_aspect(Vector2(384, 224)), 4.0 / 3.0),
		"screen: without geometry a landscape frame is shown 4:3, not at its 1.71 pixel ratio")
	_ok(_near(ArcadeScreenModule.fallback_aspect(Vector2(224, 384)), 3.0 / 4.0),
		"screen: and a portrait one 3:4")
	_ok(ArcadeScreenModule.fallback_aspect(Vector2.ZERO) == 0.0, "screen: no frame, no shape")


# --- bridge --------------------------------------------------------------------

func _group_bridge() -> void:
	var lib := ClassDB.instantiate("Libretro") as Node
	if lib == null:
		_ok(false, "bridge: the Libretro extension is not loaded")
		return
	_ok(lib.has_method("GetVideoGeometry") and lib.has_method("GetVideoGeometrySerial"),
		"bridge: the extension exposes the picture's geometry")
	if lib.has_method("GetVideoGeometry"):
		var g: Dictionary = lib.GetVideoGeometry()
		var keys := ["width", "height", "aspect", "rotation", "base_width", "base_height", "core_aspect"]
		var all := true
		for k in keys:
			all = all and g.has(k)
		_ok(all, "bridge: and it carries every field")
		_ok(float(g.get("aspect", -1.0)) == 0.0, "bridge: an idle machine has no shape yet (0), not a made-up one")
		_ok(int(lib.GetVideoGeometrySerial()) == 0, "bridge: and its serial has not moved")
	lib.free()


# --- board ---------------------------------------------------------------------

func _group_board() -> void:
	for sid in ["arcade"]:
		_ok(MediaDimensions.has_cart_size(sid), "board: %s has a size of its own" % sid)
		_ok(RetroCartridge.body_model_for(sid, "", "", &"") == ArcadeProfiles.BOARD_SCENE,
			"board: a %s ROM spawns wearing the board" % sid)
	var packed := load(ArcadeProfiles.BOARD_SCENE) as PackedScene
	_ok(packed != null, "board: the board scene loads")
	if packed == null:
		return
	var root := packed.instantiate() as Node3D
	add_child(root)
	var label := root.find_child("Label", true, false) as MeshInstance3D
	_ok(label != null and label.mesh != null, "board: it carries a Label sticker for the art")
	_ok(root.find_child("CombTop", true, false) != null and root.find_child("CombBottom", true, false) != null,
		"board: the comb has contacts on both faces")
	var top := root.find_child("CombTop", true, false) as MultiMeshInstance3D
	_ok(top != null and top.multimesh.instance_count == 28, "board: 28 contacts a side, 56 in all")
	var pcb := root.find_child("PCB", true, false) as MeshInstance3D
	_ok(pcb != null, "board: it is a bare PCB, not a shell")
	var box := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	var want := MediaDimensions.cart_size("arcade")
	_ok(absf(box.size.x - want.x) < 0.002 and absf(box.size.y - want.y) < 0.002 and absf(box.size.z - want.z) < 0.002,
		"board: its meshes add up to its size (%s vs %s)" % [box.size, want])
	_ok(absf(box.get_center().x) < 0.002 and absf(box.get_center().y) < 0.002,
		"board: centred, connector toward -Y")
	if label != null and pcb != null:
		_ok(label.transform.origin.z > pcb.transform.origin.z and label.transform.basis.z.dot(Vector3.BACK) > 0.99,
			"board: the label is on the component side, facing +Z")
	root.queue_free()

	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(8)
	var model := cart.get_node_or_null("CartModel") as Node3D
	_ok(model != null, "board: a spawned MAME cartridge wears the board model")
	if model != null:
		_ok(model.scale.is_equal_approx(Vector3.ONE) or (model.scale - Vector3.ONE).length() < 0.05,
			"board: at 1:1, so nothing is squashed per axis (%s)" % model.scale)
	_ok(CartridgeLabel.find_label(cart) != null, "board: and CartridgeLabel finds the sticker")
	# The title is printed on the sticker, and STAYS there when the board is put down: every
	# drop runs the size pass again, which used to put it back where the old box had it.
	cart.game_label = "STREET FIGHTER II"
	await _wait(2)
	var lab := CartridgeLabel.find_label(cart) as MeshInstance3D
	var title := cart.get_node_or_null("GameLabel") as Label3D
	var face: Vector3 = lab.global_transform * lab.get_aabb().get_center()
	_ok(title != null and title.visible and title.global_position.distance_to(face) < 0.003,
		"board: the title is on the sticker")
	cart.emit_signal("dropped", cart)
	await _wait(2)
	_ok(title.global_position.distance_to(face) < 0.003,
		"board: and still on it after the board is put down (%f m)" % title.global_position.distance_to(face))
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.1, 0.1))
	_ok(CartridgeLabel.apply_texture(cart, ImageTexture.create_from_image(img)) == OK,
		"board: label art paints onto the sticker")
	await _clear()


# --- registry ------------------------------------------------------------------

func _group_registry() -> void:
	for sid in ["arcade"]:
		var row := SystemModelRegistry.resolve("", sid)
		_ok(str(row.get("id", "")) == MODEL_ID, "registry: %s's hardware is the generic cabinet" % sid)
	_ok(SystemModelRegistry.rows_for("nes").filter(func(r: Dictionary) -> bool: return r["id"] == MODEL_ID).is_empty(),
		"registry: and no other system's")
	_ok(SystemModelRegistry.is_available(MODEL_ID), "registry: it needs no asset a build can lack")
	_ok(SystemModelRegistry.platform_of(MODEL_ID).is_empty(),
		"registry: it serves several systems, so the token decides which core")
	var packed := SystemModelRegistry.packed_scene(str(SystemModelRegistry.resolve(MODEL_ID, "arcade")["scene"]))
	_ok(packed != null and packed.instantiate() is RetroSystemModelArcadeCabinet,
		"registry: its scene is the cabinet model")


# --- cabinet -------------------------------------------------------------------

func _group_cabinet() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	_ok(model != null, "cabinet: the system is wearing the cabinet")
	if model == null:
		return
	_ok(model.modules_of_kind(ArcadeProfiles.KIND_SCREEN).size() == 1, "cabinet: one screen")
	_ok(model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS).size() == 2, "cabinet: two player panels")
	_ok(model.modules_of_kind(ArcadeProfiles.KIND_COIN).size() == 2, "cabinet: two coin doors")
	_ok(model.modules_of_kind(ArcadeProfiles.KIND_BAY).size() == 1, "cabinet: one bay")
	_ok(model.modules_of_kind(ArcadeProfiles.KIND_SOCKETS).size() == 1, "cabinet: one set of sockets")
	var players := []
	for m in model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		players.append(m.player)
	players.sort()
	_ok(players == [0, 1], "cabinet: the panels are players 1 and 2")
	_ok(model.brings_own_body(), "cabinet: it draws its own body, so the generic box is hidden")
	_ok(not model.is_handheld(), "cabinet: it is not held")
	_ok(model.get_builtin_screen() != null, "cabinet: its monitor is the machine's screen")
	_ok(model.get_builtin_screen().get_surface_override_material(0) != null,
		"cabinet: and shows dark glass until a picture comes")
	_ok(model.get_controller_port_count() == 2 and model.port_count_is_fixed(),
		"cabinet: two sockets, and SystemInfo's four do not get a vote")
	_ok(sys is RigidBody3D and (sys as RigidBody3D).axis_lock_angular_x and (sys as RigidBody3D).axis_lock_angular_z,
		"cabinet: it stays upright: only yaw is free")
	_ok(not ObjectLock.is_locked(sys) and (sys as XRToolsPickable).enabled,
		"cabinet: and it can be picked up and moved, not locked where it spawned")
	# The glass is the cabinet's own slanted front, and the tube sits inside it: a pane that
	# stands off the silhouette (as it once did, 4 cm proud with a frame floating round it)
	# reads as a panel hovering in front of the machine.
	var glass := model.find_child("Glass", true, false) as Node3D
	var tube := model.get_builtin_screen() as Node3D
	var ga := Vector2(0.30, 1.00)
	var gb := Vector2(0.07, 1.46)
	var gp := model.to_local(glass.global_position)
	var edge := Vector2(gp.z, gp.y)
	var along := (gb - ga).normalized()
	var off := absf((edge - ga).dot(Vector2(-along.y, along.x)))
	_ok(off < 0.01, "cabinet: the glass lies on the silhouette's slanted edge, not in front of it (off by %.3f)" % off)
	var inward := glass.global_position.distance_to(tube.global_position)
	var depth := (glass.global_position - tube.global_position).dot(glass.global_transform.basis.z.normalized())
	_ok(depth > 0.05 and absf(inward - depth) < 0.02,
		"cabinet: the picture is set well behind the glass, inside (depth %.3f)" % depth)
	var lean := rad_to_deg(atan2(ga.x - gb.x, gb.y - ga.y))
	_ok(lean > 20.0 and lean < 35.0, "cabinet: the monitor leans back about 25 degrees (%.1f)" % lean)
	var body := sys.get_node("SystemBody") as MeshInstance3D
	_ok(not body.visible, "cabinet: the generic box is hidden")
	_ok(model.arcade_input() != null, "cabinet: the input node is on the system")
	var shapes := sys.find_children("CabinetBox*", "CollisionShape3D", false, false)
	_ok(shapes.size() == 5, "cabinet: the body is six boxes with the bay left open (%d extra)" % shapes.size())
	var power := sys.get_node("PowerButton") as Node3D
	var seat := model.find_child("PowerSwitch", true, false) as Node3D
	_ok(power.global_position.distance_to(seat.global_position) < 0.001, "cabinet: the power switch is where the model seats it")
	var at := model.to_local(power.global_position)
	_ok(absf(at.x) < 0.30 and at.y > 0.10 and at.y < 0.50 and absf(at.z) < 0.38,
		"cabinet: and it is inside the bay, beside the JAMMA socket (%s)" % at)
	_ok(not (sys.get_node("ResetButton") as Node3D).visible and not (sys.get_node("EjectButton") as Node3D).visible,
		"cabinet: and reset and open are gone")
	await _clear()


# --- door ----------------------------------------------------------------------

func _group_door() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var slot := sys.get_node("CartridgeSlot") as XRToolsSnapZone
	var seat := model.find_child("CartSeat", true, false) as Node3D
	_ok(slot.global_position.distance_to(seat.global_position) < 0.001, "door: the slot sits on the board's seat")
	_ok(not slot.enabled and not model.is_lid_open(), "door: shut, the bay takes nothing")
	_ok(_near(model.get_lid_angle_deg(), 0.0), "door: and reads 0 degrees")
	model.set_lid_angle_deg(90.0)
	_ok(slot.enabled and model.is_lid_open(), "door: open, the bay takes a board")
	_ok(_near(model.get_lid_angle_deg(), 90.0, 0.01), "door: and reads the angle it was set to")
	model.set_lid_angle_deg(40.0)
	_ok(not slot.enabled, "door: under half open the bay is shut again")
	_ok(_near(model.get_lid_angle_deg(), 40.0, 0.01), "door: the saved angle round-trips (%f)" % model.get_lid_angle_deg())
	var pivot := model.find_child("DoorPivot", true, false) as Node3D
	model.set_lid_angle_deg(90.0)
	var top := pivot.global_transform * Vector3(0, 0.40, 0)
	_ok(top.z > pivot.global_position.z + 0.3 and absf(top.y - pivot.global_position.y) < 0.02,
		"door: it drops forward and lies flat, toward the player")
	model.set_lid_angle_deg(0.0)
	var up := pivot.global_transform * Vector3(0, 0.40, 0)
	_ok(up.y > pivot.global_position.y + 0.39 and absf(up.z - pivot.global_position.z) < 0.01,
		"door: and shut it stands on the front plane")
	# A hand moves it through the hinge, the way a player does, and the same gate follows.
	var hinge := model.find_child("DoorGrab", true, false) as VRHinge
	hinge.set_rotation_deg_remote(80.0)
	_ok(slot.enabled and model.is_lid_open(), "door: swung by the hinge, the bay opens")
	hinge.set_rotation_deg_remote(10.0)
	_ok(not slot.enabled and not model.is_lid_open(), "door: and shuts with it")
	_ok(pivot.is_ancestor_of(hinge), "door: the grab box rides the door, so an open door can still be taken hold of")
	model.set_lid_angle_deg(0.0)
	var shut_at := hinge.global_position
	model.set_lid_angle_deg(90.0)
	_ok(hinge.global_position.distance_to(shut_at) > 0.15, "door: and it has moved with it when the door swings open")
	await _clear()


# --- pointer -------------------------------------------------------------------

## The first thing a pointer ray finds on the pointable layer between two world points.
func _first_pointable(from: Vector3, to: Vector3) -> Object:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 << 20)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider") if not hit.is_empty() else null


func _group_pointer() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _wait(4)
	var door := model.find_child("DoorGrab", true, false) as Node3D
	var front := Vector3(0, 0, 1.0)
	_ok(_first_pointable(door.global_position + front, door.global_position - front) == door,
		"pointer: aimed at the shut door, a ray finds the door, not a box over the cabinet")
	# The shut door's lower part is the CABINET (to pick up), never the board standing behind it.
	var body_node := sys.get_node("PointerArea")
	_ok(_first_pointable(model.to_global(Vector3(0.0, 0.22, 1.0)), model.to_global(Vector3(0.0, 0.22, -0.2))) == body_node,
		"pointer: aimed at the shut door below its handle, a ray finds the cabinet")
	var coin := model.modules_of_kind(ArcadeProfiles.KIND_COIN)[0].find_child("CoinSlot", true, false) as Node3D
	_ok(_first_pointable(coin.global_position + front, coin.global_position - front) == coin,
		"pointer: the coin slot")
	var deck := model.find_child("Deck", true, false) as Node3D
	var n := deck.global_transform.basis.z.normalized()
	var panels := model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
	for panel in panels:
		var grip := (panel as ArcadeControlModule).grip()
		_ok(grip != null, "pointer: player %d's panel is one pointable thing" % (panel.player + 1))
		for part in ["Btn1", "Btn4", "Start", "StickPivot"]:
			var piece := panel.find_child(part, true, false) as Node3D
			_ok(_first_pointable(piece.global_position + n * 0.4, piece.global_position - n * 0.02) == grip,
				"pointer: aimed at P%d's %s a ray finds the whole panel" % [panel.player + 1, part])
	var body := sys.get_node("PointerArea")
	_ok(_first_pointable(model.to_global(Vector3(0.2, 1.62, 1.0)), model.to_global(Vector3(0.2, 1.62, 0.0))) == body,
		"pointer: while plain marquee still reaches the cabinet itself")
	model.set_lid_angle_deg(90.0)
	await _wait(4)
	_ok(_first_pointable(door.global_position + Vector3.UP * 0.5, door.global_position - Vector3.UP * 0.5) == door,
		"pointer: an open door is found where it lies")
	# With the door down, a ray from above and in front reaches into the bay: the power
	# switch beside the socket, and the board's seat, not a box over the cabinet.
	var power := sys.get_node("PowerButton") as Node3D
	var from := power.global_position + model.global_transform.basis * Vector3(0, 0.5, 0.6)
	_ok(_first_pointable(from, power.global_position) == power,
		"pointer: the power switch, through the open bay")
	var seat := model.find_child("CartSeat", true, false) as Node3D
	var aim := seat.global_position + model.global_transform.basis * Vector3(0, 0.33, 0.8)
	_ok(_first_pointable(aim, seat.global_position) != body,
		"pointer: and the board's seat is not boxed over")
	await _clear()


# --- attach --------------------------------------------------------------------

func _event(type: XRToolsPointerEvent.Type, grip: Node3D) -> XRToolsPointerEvent:
	return XRToolsPointerEvent.new(type, null, grip, Vector3.ZERO, Vector3.ZERO)


func _group_attach() -> void:
	var sys := await _cabinet("mame")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var panels := model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
	var p1 := panels[0] as ArcadeControlModule
	var p2 := panels[1] as ArcadeControlModule
	if p1.player != 0:
		var t := p1
		p1 = p2
		p2 = t
	var g1 := p1.grip()
	var g2 := p2.grip()
	await _wait(2)
	var plate1 := g1.get_node("PanelHighlight") as MeshInstance3D
	var plate2 := g2.get_node("PanelHighlight") as MeshInstance3D
	_ok(not plate1.visible and not plate2.visible, "attach: nothing is lit until a panel is aimed at")
	g1.pointer_event(_event(XRToolsPointerEvent.Type.ENTERED, g1))
	_ok(plate1.visible and not plate2.visible, "attach: aimed at, player 1's WHOLE panel lights, and only it")
	g1.pointer_event(_event(XRToolsPointerEvent.Type.EXITED, g1))
	g2.pointer_event(_event(XRToolsPointerEvent.Type.ENTERED, g2))
	_ok(plate2.visible and not plate1.visible, "attach: aimed at player 2's, that lights instead")
	g2.pointer_event(_event(XRToolsPointerEvent.Type.EXITED, g2))
	_ok(not plate2.visible, "attach: and goes dark when the aim leaves")
	var input := model.arcade_input()
	_ok(not input.playing, "attach: not attached to anything yet")
	g1.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, g1))
	_ok(g1.attached and p1.is_attached() and input.playing and input.attached.has(0),
		"attach: a press attaches you to player 1's panel, as to a controller")
	_ok(not g1.is_hovered() or plate1.visible, "attach: it stays lit while you are attached")
	g2.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, g2))
	_ok(g2.attached and not g1.attached and input.attached.has(1) and not input.attached.has(0),
		"attach: attaching to player 2's lets go of player 1's: one controller, one panel")
	g2.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, g2))
	_ok(not g2.attached and not input.playing, "attach: a second press lets go")
	sys.is_powered_on = true
	await _wait(3)
	# Attached to a powered machine, the keyboard plays that player at once (no Scroll Lock),
	# and what is pressed reaches the core's port through the same seam a pad uses.
	var bit_b := 1 << ControllerBindings.JOYPAD_B
	Input.action_press("RETRO_JOYPAD_B")
	await _wait(3)
	_ok((int(input.last_sent.get(0, 0)) & bit_b) == 0,
		"attach: a key does not play a player you are not attached to")
	g1.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, g1))
	await _wait(3)
	_ok(g1.attached and (int(input.last_sent.get(0, 0)) & bit_b) != 0,
		"attach: attached, a pressed key reaches the core as player 1's button")
	_ok((int(input.last_sent.get(1, 0)) & bit_b) == 0, "attach: and only player 1's port hears it")
	Input.action_release("RETRO_JOYPAD_B")
	await _wait(3)
	_ok((int(input.last_sent.get(0, 0)) & bit_b) == 0, "attach: released, the button lets go")
	sys.is_powered_on = false
	await _wait(3)
	_ok(not g1.attached and not input.playing, "attach: switching the machine off lets go")
	# The panel is a picture of what reached the core: the caps sink and the stick leans.
	var cap := p1.find_child("Btn1", true, false) as Node3D
	var rest := cap.position
	p1.show_state(1 << ArcadeProfiles.BUTTON_BITS[0])
	_ok(cap.position.z < rest.z - 0.004, "attach: a held button's cap sinks into the deck")
	var other := p1.find_child("Btn2", true, false) as Node3D
	_ok(absf(other.position.z - (p1.find_child("Btn2", true, false) as Node3D).position.z) < 1e-6 and other.position.z > cap.position.z,
		"attach: and only that one")
	p1.show_state(0)
	_ok(is_equal_approx(cap.position.z, rest.z), "attach: and comes back up")
	p1.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 30:
		p1.tick(0.016)
	_ok(p1.stick_lean().x > 0.9, "attach: the stick leans to the right")
	await _clear()


# --- hold ----------------------------------------------------------------------

func _group_hold() -> void:
	var h := HoldToGrab.new()
	var thing := Node3D.new()
	add_child(thing)
	_ok(not h.is_active() and h.progress() == 0.0 and not h.advance(0.5, true), "hold: idle does nothing")
	h.begin(thing, 2.0)
	_ok(h.is_active() and h.progress() == 0.0, "hold: begins empty")
	_ok(not h.advance(0.9, true) and _near(h.progress(), 0.45), "hold: fills as the control stays down")
	_ok(not h.advance(0.9, false) and not h.is_active() and h.progress() == 0.0,
		"hold: letting go of the control starts it over")
	h.begin(thing, 2.0)
	h.advance(0.5, true)
	_ok(not h.advance(0.2, true, false) and h.is_active() and _near(h.progress(), 0.25),
		"hold: a flicker off the target waits, it does not reset")
	_ok(not h.advance(0.5, true, false) and not h.is_active(), "hold: but long enough off it gives up")
	h.begin(thing, 2.0)
	_ok(not h.advance(1.0, true) and not h.advance(0.9, true), "hold: not done just short of the time")
	_ok(h.advance(0.2, true) and h.finished_target == thing and not h.is_active(),
		"hold: done once, at the time, with the target to grab")
	_ok(not h.advance(1.0, true), "hold: and not done a second time")
	h.begin(thing, 2.0, true)
	h.advance(2.5, true)
	_ok(h.finished_ranged, "hold: it remembers whether it was a laser grab")
	thing.free()
	_ok(HoldToGrab.seconds_for(null) == 0.0 and HoldToGrab.seconds_for(Node3D.new()) == 0.0,
		"hold: ordinary objects are grabbed at once")
	var sys := await _cabinet("arcade")
	_ok(_near(HoldToGrab.seconds_for(sys), 1.0) and _near(sys.grab_hold_seconds(), 1.0),
		"hold: the cabinet asks for one second")
	# In a hand the cabinet turns see-through (dithered per-instance transparency).
	var cab := sys.get_model() as RetroSystemModelArcadeCabinet
	_ok(cab.held_transparency() == 0.0, "hold: a cabinet on the floor is solid")
	var hand := Node3D.new()
	add_child(hand)
	_spawned.append(hand)
	sys.emit_signal("grabbed", sys, hand)
	_ok(_near(cab.held_transparency(), RetroSystemModelArcadeCabinet.HELD_TRANSPARENCY),
		"hold: in a hand it is see-through, so the room behind a 1.8 m box can be seen")
	sys.emit_signal("dropped", sys)
	_ok(cab.held_transparency() == 0.0, "hold: and solid again once put down")
	var plain := SYSTEM_SCENE.instantiate() as Node3D
	plain.model_id = "placeholder"
	plain.systemid = "nes"
	plain.freeze = true
	plain.position = Vector3(6, 0, 0)
	add_child(plain)
	_spawned.append(plain)
	await _wait(6)
	_ok(plain.grab_hold_seconds() == 0.0, "hold: and an ordinary console does not")
	var ring := HoldRing.new()
	add_child(ring)
	_spawned.append(ring)
	ring.show_at(Vector3(0, 1, 0), 0.5)
	_ok(ring.visible, "hold: the VR ring shows while filling")
	ring.hide_ring()
	_ok(not ring.visible, "hold: and goes away")
	var reticle := Control.new()
	reticle.set_script(load("res://Scripts/Desktop/desktop_reticle.gd"))
	add_child(reticle)
	_spawned.append(reticle)
	await _wait(2)
	get_tree().call_group("desktop_reticle", "set_hold_progress", 0.6)
	_ok(_near(reticle.get_hold_progress(), 0.6), "hold: the desktop crosshair takes the progress")
	get_tree().call_group("desktop_reticle", "set_hold_progress", 0.0)
	_ok(reticle.get_hold_progress() == 0.0, "hold: and clears it")
	await _clear()


# --- panel ---------------------------------------------------------------------

func _group_panel() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var size := Vector2(0.6, 0.5)
	var local: Variant = model.options_panel_anchor(size)
	_ok(local is Vector3 and (local as Vector3).x > RetroSystemModelArcadeCabinet.SIZE.x * 0.5,
		"panel: the cabinet's options panel stands to its right")
	_ok(local is Vector3 and absf((local as Vector3).y - 1.2) < 0.4, "panel: at eye height, not above a 1.8 m box")
	var world: Variant = sys.options_panel_anchor(size)
	_ok(world is Vector3 and (world as Vector3).distance_to(sys.global_transform * (local as Vector3)) < 0.001,
		"panel: and the system carries it into the world")
	sys.rotate_y(PI * 0.5)
	var turned: Variant = sys.options_panel_anchor(size)
	_ok(turned is Vector3 and (turned as Vector3).distance_to(world as Vector3) > 0.3,
		"panel: it follows the cabinet when it is turned")
	sys.rotate_y(-PI * 0.5)
	var cam := Node3D.new()
	add_child(cam)
	_spawned.append(cam)
	sys._options_panel.show_for(sys, cam)
	await _wait(3)
	_ok(sys._options_panel._anchor().distance_to(sys.options_panel_anchor(sys._options_panel._viewport_node.screen_size) as Vector3) < 0.001,
		"panel: the options panel itself is placed there")
	sys._options_panel.hide_panel()
	var plain := SYSTEM_SCENE.instantiate() as Node3D
	plain.model_id = "placeholder"
	plain.systemid = "nes"
	plain.freeze = true
	plain.position = Vector3(6, 0, 0)
	add_child(plain)
	_spawned.append(plain)
	await _wait(6)
	_ok(plain.options_panel_anchor(size) == null, "panel: other machines keep it over their top")

	# Notices float in front of the monitor, PARALLEL to it, detached from the geometry.
	var spot: Variant = sys.toast_anchor_world()
	var screen_node := model.get_builtin_screen()
	_ok(spot is Transform3D and model.to_local((spot as Transform3D).origin).z > 0.47 + 0.05,
		"panel: a notice floats well clear of the control panel, in front of the screen")
	_ok(spot is Transform3D and (spot as Transform3D).basis.z.dot(screen_node.global_transform.basis.z.normalized()) > 0.999,
		"panel: and parallel to the monitor, which is tilted back")
	var mt: AchievementToast = sys._machine_toast()
	mt._place()
	_ok(mt.global_position.distance_to((spot as Transform3D).origin) < 0.001, "panel: the machine's notice is placed there")
	_ok(mt.global_transform.basis.z.dot((spot as Transform3D).basis.z) > 0.999, "panel: parallel to the screen")
	var st: AchievementToast = sys._screen_toast()
	st._place()
	_ok(st != null and st.global_position.distance_to((spot as Transform3D).origin) < 0.001,
		"panel: and so is the one over its screen")
	_ok(plain.toast_anchor_world() == null, "panel: other machines keep their notices where they were")

	# The System tab picks the core THIS machine runs.
	var ui := preload("res://Scenes/UI/core_options_2d.tscn").instantiate() as CoreOptions2D
	add_child(ui)
	_spawned.append(ui)
	await _wait(3)
	var picked := []
	ui.core_selected.connect(func(c: String) -> void: picked.append(c))
	ui.populate_cores([], "", "")
	_ok(ui._core_picker == null, "panel: no installed core, no picker")
	ui.populate_cores([{"core_name": "mame", "label": "MAME"}, {"core_name": "mame2003_plus", "label": "MAME 2003-Plus"}],
		"", "mame")
	_ok(ui._core_picker != null, "panel: with cores installed the System tab offers them")
	ui._core_picker.item_selected.emit("mame2003_plus")
	_ok(picked == ["mame2003_plus"], "panel: and picking one says which")
	ui._core_picker.item_selected.emit("")
	_ok(picked == ["mame2003_plus", ""], "panel: Default is the empty choice")
	sys.core_name = ""
	sys.set_core_choice("mame2003_plus")
	_ok(sys.core_name == "mame2003_plus", "panel: the machine takes the core it was given")
	var sp := ScenePersistence.new("arcade_tests")
	var objects: Array[Dictionary] = sp._collect_objects(self)
	var entry := {}
	for o in objects:
		if o.get("type") == "system" and o.get("systemid") == "arcade":
			entry = o
	_ok(str(entry.get("core_name", "")) == "mame2003_plus", "panel: the pick is saved with the room")
	await _clear()
	var made := sp.instantiate_objects(self, [entry])
	var back: Node = null
	for k in made:
		if made[k] is RetroSystem:
			back = made[k]
			_spawned.append(back)
	_ok(back != null and back.core_name == "mame2003_plus", "panel: and comes back with it")
	await _clear()


# --- art -----------------------------------------------------------------------

func _group_art() -> void:
	# A laid-flat box (back, spine, front): the front is its right-hand end.
	var wrap := Image.create(1090, 680, false, Image.FORMAT_RGBA8)
	wrap.fill(Color(0, 1, 0))
	for x in range(593, 1090):
		for y in 680:
			wrap.set_pixel(x, y, Color(1, 0, 0))
	var cover := ArcadeProfiles.front_cover(wrap)
	_ok(cover.get_height() == 680 and cover.get_width() > 440 and cover.get_width() < 560,
		"art: the front is cut out of a laid-flat box (%dx%d)" % [cover.get_width(), cover.get_height()])
	_ok(cover.get_pixel(5, 5) == Color(1, 0, 0) and cover.get_pixel(cover.get_width() - 5, 675) == Color(1, 0, 0),
		"art: and it is the right-hand end, not the blank back")
	var single := Image.create(300, 420, false, Image.FORMAT_RGBA8)
	_ok(ArcadeProfiles.front_cover(single) == single, "art: a box image that is already a cover is left whole")
	var cabinet := Image.create(517, 999, false, Image.FORMAT_RGBA8)
	_ok(ArcadeProfiles.board_art(wrap, cabinet).get_width() < 600, "art: with a box image the sticker takes the cover")
	_ok(ArcadeProfiles.board_art(null, cabinet) == cabinet, "art: with no box image, the scraped label")
	_ok(ArcadeProfiles.board_art(null, null) == null, "art: and with neither, nothing (the title is printed)")
	_ok(ScreenscraperSystems.is_arcade_systemeid(ScreenscraperSystems.get_systemeid("mame")),
		"art: the scraper knows MAME's system as arcade")
	_ok(not ScreenscraperSystems.is_arcade_systemeid(ScreenscraperSystems.get_systemeid("nes")),
		"art: and not the NES")
	_ok(not ScreenscraperSystems.is_arcade_systemeid(0) and not ScreenscraperSystems.is_arcade_systemeid(-1),
		"art: and no system at all is not arcade")
	# Cores a cabinet can run: either tile's core, and the "arcade"-filed ones.
	_ok(RetroSystem.core_serves_machine(["mame"], "mame") and RetroSystem.core_serves_machine(["fbneo"], "mame"),
		"cores: a MAME cabinet offers FBNeo's core too")
	_ok(RetroSystem.core_serves_machine(["arcade"], "fbneo"), "cores: and the cores filed under plain arcade")
	_ok(not RetroSystem.core_serves_machine(["nes"], "mame"), "cores: but not a console's")
	_ok(RetroSystem.core_serves_machine(["nes"], "nes") and not RetroSystem.core_serves_machine(["fbneo"], "nes"),
		"cores: and any other machine keeps its own system's cores only")


# --- seat ----------------------------------------------------------------------

func _group_seat() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var slot := sys.get_node("CartridgeSlot") as XRToolsSnapZone
	model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = "/tmp/arcade_test_board.zip"
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(8)
	slot.pick_up_object(cart)
	await _wait(6)
	_ok(sys.rom_path == "/tmp/arcade_test_board.zip", "seat: the board in the bay is the machine's game")
	_ok(cart.global_position.distance_to((model.find_child("CartSeat", true, false) as Node3D).global_position) < 0.02,
		"seat: and it stands in the socket, comb down")
	_ok((cart.global_transform.basis.y).dot(Vector3.UP) > 0.99 and (cart.global_transform.basis.z).dot(Vector3.BACK) > 0.99,
		"seat: connector down, label to the front")
	slot.drop_object()
	await _wait(6)
	_ok(sys.rom_path.is_empty(), "seat: pulling the board takes the game away")
	await _clear()


# --- card ----------------------------------------------------------------------

func _group_card() -> void:
	for sid in ["arcade"]:
		var items := SpawnCatalog.items_for(sid)
		var labels: Array = items.map(func(i: Dictionary) -> String: return str(i.get("label", "")))
		var models: Array = items.map(func(i: Dictionary) -> String: return str(i.get("model_id", "")))
		_ok(models.has(MODEL_ID), "card: the %s card offers the cabinet" % sid)
		_ok(not labels.has("Primitive System"), "card: and no imaginary box beside it")
		_ok(not labels.has("Composite Cable"), "card: and no video lead: the monitor is part of it")
		_ok(labels.has("Primitive Controller"), "card: a pad is offered, for the front sockets")
		_ok(labels.has("Light Gun"), "card: and a gun")
	var sys := await _cabinet("arcade")
	_ok(sys.spawns_on_floor(), "card: a cabinet is stood on the floor, not handed to a hand")
	var pad := PAD_SCENE.instantiate() as Node3D
	pad.position = Vector3(0, 3, 0)
	add_child(pad)
	_spawned.append(pad)
	await _wait(4)
	_ok(not pad.has_method("spawns_on_floor"), "card: while a pad still goes to the hand")
	await _clear()


# --- ports ---------------------------------------------------------------------

func _group_ports() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var sockets := model.modules_of_kind(ArcadeProfiles.KIND_SOCKETS)[0] as ArcadeSocketModule
	_ok(sockets.seat_count() == 2, "ports: two seats")
	var zones: Array = []
	for i in 4:
		zones.append(sys.get_node("ControllerPort%d" % (i + 1)))
	for i in 2:
		var seat := sockets.find_child("PortSeat%d" % (i + 1), true, false) as Node3D
		_ok((zones[i] as Node3D).global_position.distance_to(seat.global_position) < 0.001,
			"ports: zone %d is on its seat" % (i + 1))
		_ok((zones[i] as Node3D).visible and zones[i].enabled, "ports: and live")
	_ok(not (zones[2] as Node3D).visible and not zones[2].enabled and not (zones[3] as Node3D).visible,
		"ports: the other two are gone")
	_ok(model.arcade_input() != null, "ports: input is there")
	# Who owns a port: a controller seated in one silences that player's panel.
	var states: Array = []
	for p in 2:
		var owned: bool = p < sys.get_port_controllers().size() and sys.get_port_controllers()[p] != null
		states.append(ArcadeInputState.panel_speaks(owned))
	_ok(states == [true, true], "ports: with nothing plugged in both panels speak")
	await _clear()

	# A pad in the first socket takes that port: the panel of player 1 goes quiet while
	# player 2's keeps speaking. The plug is the pad's own, on its cord.
	var cab := await _cabinet("arcade")
	var input := (cab.get_model() as RetroSystemModelArcadeCabinet).arcade_input()
	cab.is_powered_on = true
	await _wait(6)
	_ok(input.last_sent.has(0) and input.last_sent.has(1), "ports: a running cabinet speaks for both players")
	var pad := PAD_SCENE.instantiate() as Node3D
	pad.systemid = "arcade"
	pad.position = Vector3(2, 2, 0)
	add_child(pad)
	_spawned.append(pad)
	await _wait(30)
	var plug := get_tree().current_scene.find_child("ControllerPlug", true, false) as Node3D
	if plug != null and is_instance_valid(plug.get_parent()):
		_spawned.append(plug.get_parent())
	_ok(plug != null, "ports: the pad has a plug on its cord")
	if plug != null:
		var zone := cab.get_node("ControllerPort1") as XRToolsSnapZone
		zone.pick_up_object(plug)
		await _wait(30)
		_ok(cab.get_port_controllers()[0] != null, "ports: the pad is the machine's player 1")
		input.last_sent.clear()
		await _wait(6)
		_ok(not input.last_sent.has(0), "ports: so the cabinet's own panel no longer speaks for it")
		_ok(input.last_sent.has(1), "ports: while player 2's still does")
	cab.is_powered_on = false
	await _clear()


# --- coin ----------------------------------------------------------------------

func _group_coin() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var door := model.modules_of_kind(ArcadeProfiles.KIND_COIN)[1] as ArcadeCoinModule
	var landed := []
	door.coin_inserted.connect(func(p: int) -> void: landed.append(p))
	_ok(door.player == 1, "coin: the second door is player 2's")
	door.insert_coin()
	_ok(landed.is_empty() and door.in_flight == 1, "coin: a coin is in the air, not yet in the box")
	_ok(door.find_child("Coin", false, false) != null, "coin: it is a plain mesh")
	_ok(not door.find_child("Coin", false, false).is_in_group("spawned"), "coin: never a saved object")
	await get_tree().create_timer(ArcadeCoinModule.FLIGHT_SECONDS + 0.2).timeout
	_ok(landed == [1] and door.in_flight == 0, "coin: it lands, and only then is the credit said")
	_ok(door.find_child("Coin", false, false) == null, "coin: and the mesh is gone")
	var wav := ArcadeCoinModule.clink()
	_ok(wav.data.size() > 4000 and wav == ArcadeCoinModule.clink(), "coin: the clink is synthesised once and shared")
	# Through the input: with the machine off a coin is not held for the core.
	var input := model.arcade_input()
	sys.is_powered_on = false
	door.insert_coin()
	await get_tree().create_timer(ArcadeCoinModule.FLIGHT_SECONDS + 0.2).timeout
	_ok(not input.last_sent.has(1), "coin: a switched-off cabinet sends nothing")
	sys.is_powered_on = true
	door.insert_coin()
	await get_tree().create_timer(ArcadeCoinModule.FLIGHT_SECONDS + 0.05).timeout
	await get_tree().process_frame
	_ok(input.last_sent.has(1) and (int(input.last_sent[1]) & (1 << ArcadeProfiles.COIN_BIT)) != 0,
		"coin: a coin into a running cabinet is the coin bit on its player's port")
	await get_tree().create_timer(0.3).timeout
	_ok((int(input.last_sent[1]) & (1 << ArcadeProfiles.COIN_BIT)) == 0, "coin: and the bit is let go")
	_ok(not input.last_sent.has(2), "coin: nobody else's port was touched")
	sys.is_powered_on = false
	await _clear()


# --- restore -------------------------------------------------------------------

## The room is saved with a cabinet that has a board in its bay, the door open and a pad in
## a front socket, and loaded the way the app loads one: the ASYNC restore, which is what
## the loading overlay waits on. It has to FINISH (a script error or a wait that never ends
## here is the overlay stuck at "RESTORING OBJECTS 9 / 9"), and bring everything back.
func _group_restore() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = "/tmp/arcade_restore_board.zip"
	cart.game_label = "RESTORE ME"
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	cart.add_to_group("spawned")
	_spawned.append(cart)
	await _wait(8)
	(sys.get_node("CartridgeSlot") as XRToolsSnapZone).pick_up_object(cart)
	await _wait(6)
	var pad := PAD_SCENE.instantiate() as Node3D
	pad.systemid = "arcade"
	pad.position = Vector3(3, 2, 0)
	add_child(pad)
	pad.add_to_group("spawned")
	_spawned.append(pad)
	await _wait(30)
	var sp := ScenePersistence.new("arcade_tests")
	var objects: Array[Dictionary] = sp._collect_objects(self)
	_ok(objects.size() >= 2, "restore: the room saved with %d objects" % objects.size())
	await _clear()
	var finished := [false]
	var progress := []
	sp.restore_progress.connect(func(d: int, t: int) -> void: progress.append([d, t]))
	var run := func() -> void:
		await sp.instantiate_objects_async(self, objects)
		finished[0] = true
	run.call()
	var waited := 0
	while not finished[0] and waited < 600:
		await get_tree().process_frame
		waited += 1
	_ok(finished[0], "restore: the async restore FINISHES (%d frames)" % waited)
	_ok(not progress.is_empty() and progress[-1][0] == progress[-1][1],
		"restore: and reports every object, last %s" % [progress[-1] if not progress.is_empty() else "none"])
	await _wait(10)
	var back: Node = null
	for n in get_children():
		if n is RetroSystem:
			back = n
			_spawned.append(n)
		elif n is RetroController or n is RetroCartridge:
			_spawned.append(n)
	_ok(back != null, "restore: the cabinet is back")
	if back != null:
		var m2 := back.get_model() as RetroSystemModelArcadeCabinet
		_ok(m2 != null and m2.is_lid_open(), "restore: with its door as it was left")
		_ok(back.rom_path == "/tmp/arcade_restore_board.zip", "restore: and the board in its bay (%s)" % back.rom_path)
	await _clear()


# --- keep ----------------------------------------------------------------------

func _group_keep() -> void:
	var sys := await _cabinet("arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.set_lid_angle_deg(90.0)
	var sp := ScenePersistence.new("arcade_tests")
	var objects: Array[Dictionary] = sp._collect_objects(self)
	var entry := {}
	for o in objects:
		if o.get("type") == "system":
			entry = o
	_ok(str(entry.get("model_id", "")) == MODEL_ID, "keep: the saved cabinet names its hardware")
	_ok(_near(float(entry.get("lid_angle", -1.0)), 90.0, 0.01), "keep: and how far its door stands open")
	await _clear()
	var made := sp.instantiate_objects(self, [entry])
	var back: Node = null
	for k in made:
		if made[k] is RetroSystem:
			back = made[k]
			_spawned.append(back)
	_ok(back != null, "keep: the room brings a system back")
	if back != null:
		await _wait(6)
		var m2 := back.get_model() as RetroSystemModelArcadeCabinet
		_ok(m2 != null and str(back.model_id) == MODEL_ID, "keep: wearing the cabinet")
		_ok(m2 != null and m2.is_lid_open() and _near(m2.get_lid_angle_deg(), 90.0, 0.01),
			"keep: with its door as it was left")
		_ok((back.get_node("CartridgeSlot") as XRToolsSnapZone).enabled, "keep: and the bay open to a board")
	await _clear()
