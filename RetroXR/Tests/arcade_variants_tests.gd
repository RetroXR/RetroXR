## Arcade variants self-tests — the other cabinets (light gun, Neo Geo MVS, laserdisc, DICE),
## the guns that hang on the gun cabinets, and the pedal. Headless, no core, no ROM, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_variants_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_variants_tests.tscn -- --only=guns
##
## Exits 0 when everything passes, 1 otherwise.
##
## The look is the probe's (Tools/models/arcade_cabinet_probe, windowed, `--model=<id>`); this is
## what a headless run CAN say: each variant is built from the module contract, its panel has the
## controls it should, its bay takes its system, and the guns are the cabinet's own, plugged in,
## not saved, hung in their holsters on a cord of the length the cabinet laid for them.
##
## Groups:
##   registry/   every cabinet has a persisted row, the generic one first
##   profiles/   which bay takes which system, and the romset family is unchanged
##   layout/     the controls each variant has: buttons, dials, START alone, coin doors, bay kind
##   guns/       captive guns: built with the machine, plugged in, not saved, in their holsters
##   cord/       the cord's route, laid to the cord's own length
##   settle/     the cords come to rest: above the floor, anchored at both ends, not stretched
##   fire/       START and the coin reach a gun's port as the gun's own buttons; the grip that holds a
##               cabinet's gun is no button
##   aim/        a gun aims at the cabinet's own tube
##   pedal/      the pedal is player 1's button 2, down while the gun is held; A/X, the key, the free hand or ducking lift it
##   console/    the consolized Neo Geo MVS: a console that takes the same cassette, with pads and phono AV out
##   names/      RomM's neogeomvs and neogeoaes are the one neogeo system, and so are the ROM folders
##   shooting/   the gun cabinets are wide, with a big STRAIGHT screen (a gun held up to it must not walk in)
##   holster/    a gun let go goes back in its holster
##   neogeo/     the MVS game is a plastic cassette, the MVS a rectangular unit with the slot the cassette stands in
##   stand/      a cabinet comes to stand: released upright it stays, released leaning it rights itself
##   seat/       each cabinet takes the board of ITS system, and gives the game up when it is pulled
##   art/        a board in the bay dresses the cabinet in the game's wheel and cover, and pulling it undresses it
##   card/       what the spawn card offers for each of the cabinets' systems
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

## id -> [systemid, buttons per player, players, coin doors, bay kind]
const VARIANTS := {
	"arcade_cabinet_generic": ["arcade", 6, 2, 2, "jamma"],
	"arcade_cabinet_neogeo": ["neogeo", 4, 2, 2, "mvs"],
	"arcade_cabinet_daphne": ["daphne", 1, 1, 1, "laserdisc"],
	"arcade_cabinet_daphne_gun": ["daphne", 0, 2, 2, "laserdisc"],
	"arcade_cabinet_dice": ["dice", 0, 2, 2, "discrete"],
}

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "variants"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[variants] TIMED OUT")
		get_tree().quit(1))
	await _run()
	_finish()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


## A machine wearing `model_id`, given `frames` physics frames to build itself (the guns' cords
## are made on a deferred call, and seat after it).
func _machine(model_id: String, systemid: String, frames: int = 8) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 2.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(frames)
	return sys


## The cabinet a gun game makes of the generic one: the board in its bay (the path every drop and restore
## takes), the morph built at the end of the frame, and `frames` for the guns' cords. There is no separately
## spawnable shooting cabinet any more: the shooting cabinet IS the generic one with a gun game in it.
func _gun_cabinet(romset := "ptblank", frames: int = 120) -> RetroSystem:
	var sys := await _machine("arcade_cabinet_generic", "arcade", 8)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = "/tmp/%s.zip" % romset
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(8)
	_slot_of(sys).pick_up_object(cart)
	await _wait(frames)
	return sys


## A shooting cabinet, whichever the group asks for: the generic one with a gun game in it, or the laserdisc gun one.
func _gun_machine(id: String, frames: int = 120) -> RetroSystem:
	if id == "gun":
		return await _gun_cabinet("ptblank", frames)
	return await _machine(id, "daphne", frames)


## Two guns and pedals of its own under them (no game has two guns and a pedal, so the form is made by hand):
## `xs` are the pedals' places, one pedal each, player 1's first.
func _pedal_cabinet(xs: Array, frames: int = 120) -> RetroSystem:
	var sys := await _gun_cabinet("ptblank", 20)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var spec := model.form_spec().duplicate(true)
	spec["gun_pedals"] = xs
	model.morph_to(spec)
	await _wait(frames)
	return sys


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	# The bays a cabinet seeded stand in the room, not in `_spawned`.
	for bay in get_tree().get_nodes_in_group(ArcadeBayUnit.GROUP):
		bay.queue_free()
	_spawned.clear()
	await _wait(6)


func _run() -> void:
	if _want("registry"):
		_group_registry()
		await _clear()
	if _want("profiles"):
		_group_profiles()
		await _clear()
	if _want("layout"):
		await _group_layout()
		await _clear()
	if _want("guns"):
		await _group_guns()
		await _clear()
	if _want("cord"):
		await _group_cord()
		await _clear()
	if _want("settle"):
		await _group_settle()
		await _clear()
	if _want("ghost"):
		await _group_ghost()
	if _want("fire"):
		await _group_fire()
		await _clear()
	if _want("aim"):
		await _group_aim()
		await _clear()
	if _want("pedal"):
		await _group_pedal()
		await _clear()
	if _want("shooting"):
		await _group_shooting()
		await _clear()
	if _want("holster"):
		await _group_holster()
		await _clear()
	if _want("neogeo"):
		await _group_neogeo()
		await _clear()
	if _want("console"):
		await _group_console()
		await _clear()
	if _want("names"):
		_group_names()
	if _want("stand"):
		await _group_stand()
		await _clear()
	if _want("seat"):
		await _group_seat()
		await _clear()
	if _want("art"):
		await _group_art()
		await _clear()
	if _want("card"):
		await _group_card()
		await _clear()
	await _clear()


# --- registry ------------------------------------------------------------------

func _group_registry() -> void:
	for id: String in VARIANTS:
		var want_system: String = VARIANTS[id][0]
		var row := SystemModelRegistry.row_for(id)
		_ok(not row.is_empty(), "registry: %s has a row" % id)
		_ok(SystemModelRegistry.rows_for(want_system).any(func(r: Dictionary) -> bool: return r["id"] == id),
			"registry: %s serves %s" % [id, want_system])
		_ok(ResourceLoader.exists(str(row.get("scene", ""))), "registry: %s's scene is baked" % id)
	var arcade_rows := SystemModelRegistry.rows_for("arcade")
	_ok(arcade_rows.size() >= 1 and arcade_rows[0]["id"] == ArcadeProfiles.CABINET_MODEL_ID,
		"registry: the generic cabinet stays the arcade tile's first, so its default")
	_ok(SystemModelRegistry.row_for("arcade_cabinet_lightgun").is_empty() and not arcade_rows.any(func(r: Dictionary) -> bool: return str(r["id"]).contains("lightgun")),
		"registry: and no shooting cabinet is spawnable on it (the generic one becomes it when a gun game is in the bay)")
	_ok(SystemInfo.for_system("daphne") != null and SystemInfo.for_system("dice") != null,
		"registry: Daphne and DICE are systems with a descriptor")


# --- profiles ------------------------------------------------------------------

func _group_profiles() -> void:
	_ok(ArcadeProfiles.bay_accepts("mvs", "neogeo") and not ArcadeProfiles.bay_accepts("mvs", "arcade"),
		"profiles: an MVS bay takes Neo Geo and not arcade boards")
	_ok(ArcadeProfiles.bay_accepts("laserdisc", "daphne") and ArcadeProfiles.bay_accepts("discrete", "dice"),
		"profiles: a laserdisc bay takes Daphne, a discrete-logic bay takes DICE")
	for sid: String in ["neogeo", "daphne", "dice", "arcade"]:
		_ok(ArcadeProfiles.is_cabinet_system(sid), "profiles: %s plays in a cabinet" % sid)
	# The romset family is the cores' business: the generic cabinet must not list Neo Geo's.
	_ok(ArcadeProfiles.is_arcade_system("arcade") and not ArcadeProfiles.is_arcade_system("neogeo"),
		"profiles: Neo Geo is a cabinet but not of the romset family (its cores are its own)")
	_ok(not RetroSystem.core_serves_machine(["neogeo"], "arcade"),
		"profiles: so a Neo Geo-only core does not serve the generic cabinet")
	_ok(not ArcadeProfiles.is_cabinet_system("nes"), "profiles: a NES is no cabinet")
	_ok(MediaDimensions.cart_size("neogeo", "").x > 0.0, "profiles: a Neo Geo board has a size")


# --- layout --------------------------------------------------------------------

func _group_layout() -> void:
	for id: String in VARIANTS:
		var spec: Array = VARIANTS[id]
		var sys := await _machine(id, spec[0])
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		_ok(model != null, "layout: %s is the cabinet model" % id)
		if model == null:
			continue
		var panels := model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
		_ok(panels.size() == spec[2], "layout: %s has %d player panel(s) (%d)" % [id, spec[2], panels.size()])
		_ok(model.modules_of_kind(ArcadeProfiles.KIND_COIN).size() == spec[3],
			"layout: %s has %d coin door(s)" % [id, spec[3]])
		_ok(model.modules_of_kind(ArcadeProfiles.KIND_SCREEN).size() == 1, "layout: %s has one screen" % id)
		var bay := model.modules_of_kind(ArcadeProfiles.KIND_BAY)[0] as ArcadeBayModule
		_ok(bay.bay_kind == spec[4], "layout: %s's bay is %s" % [id, spec[4]])
		_ok(ArcadeProfiles.bay_accepts(bay.bay_kind, spec[0]), "layout: and it takes %s" % spec[0])
		if panels.is_empty():
			continue
		var first := panels[0] as ArcadeControlModule
		var buttons := 0
		for k in 6:
			if first.find_child("Btn%d" % (k + 1), true, false) != null:
				buttons += 1
		_ok(buttons == spec[1], "layout: %s's panel has %d button(s) (%d)" % [id, spec[1], buttons])
		_ok(first.find_child("Start", true, false) != null, "layout: and a START")
		var dial := first.find_child("DialPivot", true, false) != null
		_ok(dial == (id == "arcade_cabinet_dice"), "layout: %s %s a paddle dial" % [id, "has" if dial else "has no"])
		var stick := first.find_child("StickPivot", true, false) != null
		var wants_stick: bool = spec[1] > 0
		_ok(stick == wants_stick, "layout: %s %s a stick" % [id, "has" if stick else "has no"])
		var grip := first.grip()
		_ok(grip != null and grip.momentary == (spec[1] == 0 and not dial),
			"layout: %s's panel is %s" % [id, "START alone (momentary)" if spec[1] == 0 and not dial else "one controller to attach to"])
	# The dial turns with LEFT and RIGHT: the knob is a picture that follows the input.
	var dice := await _machine("arcade_cabinet_dice", "dice")
	var dpanel := (dice.get_model() as RetroSystemModelArcadeCabinet).modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)[0] as ArcadeControlModule
	var knob := dpanel.find_child("DialPivot", true, false) as Node3D
	var before := knob.basis
	dpanel.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 10:
		dpanel.tick(0.05)
	_ok(not knob.basis.is_equal_approx(before), "layout: a held RIGHT turns the dial")
	dpanel.show_state(0)
	var settled := knob.basis
	dpanel.tick(0.05)
	_ok(knob.basis.is_equal_approx(settled), "layout: and it stops when RIGHT is let go")
	await _clear()


# --- guns ----------------------------------------------------------------------

func _group_guns() -> void:
	# A cabinet with sockets has no guns of its own.
	var plain := await _machine("arcade_cabinet_generic", "arcade", 30)
	_ok(plain.captive_controllers().is_empty(), "guns: the generic cabinet is not wired to any gun")
	for id: String in ["gun", "arcade_cabinet_daphne_gun"]:
		var sys := await _gun_machine(id, 120)
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		var guns := sys.captive_controllers()
		_ok(guns.size() == 2, "guns: %s is wired to two guns" % id)
		var rests := model.captive_controller_rests()
		_ok(rests.size() == 2, "guns: and has two holsters")
		var owners := sys.get_port_controllers()
		for i in guns.size():
			var gun := guns[i] as LightGun
			_ok(gun != null, "guns: %s's gun %d is a light gun" % [id, i + 1])
			if gun == null:
				continue
			_ok(gun.captive and not gun.is_in_group("spawned"),
				"guns: it is out of the group a save sweeps, so a load cannot bring back a second one")
			var cord := gun.cable_instance()
			_ok(cord != null and not cord.is_in_group("spawned"), "guns: and so is its cord")
			_ok(gun.get_connected_system() == sys and gun.get_port_index() == i,
				"guns: it is plugged into port %d" % (i + 1))
			_ok(i < owners.size() and owners[i] == gun, "guns: and owns that port, so no pad can take it")
			var holster := (model.find_child("Holster%d" % (i + 1), true, false) as Node3D).global_transform
			var off := gun.global_position.distance_to(holster.origin)
			# Along the gun's own aim: down, into the cup.
			var aim_dot := (-gun.global_transform.basis.z).dot(-holster.basis.z)
			_ok(off < 0.03, "guns: it hangs in its holster (%.3f m off)" % off)
			_ok(aim_dot > 0.995, "guns: muzzle down, not tilted by its cord (%.4f)" % aim_dot)
			_ok((-gun.global_transform.basis.z).dot(Vector3.DOWN) > 0.97, "guns: and the muzzle really points at the floor")
		_ok(guns.size() == 2 and (guns[0] as Node3D).global_position.x < (guns[1] as Node3D).global_position.x,
			"guns: player 1's hangs on the left")
		# The gun scene says what the cabinet assumes of it.
		var scene := (load(RetroSystemModelArcadeCabinet.GUN_SCENE) as PackedScene).instantiate()
		_ok((scene.get_node("CableAttachPoint") as Node3D).position.is_equal_approx(RetroSystemModelArcadeCabinet.GUN_CORD_BOSS),
			"guns: the cord leaves the butt where the cabinet laid its route from")
		_ok(float(scene.get("cable_length")) > 1.0, "guns: on a cord long enough to aim with (%.2f m)" % float(scene.get("cable_length")))
		_ok((scene.get_node("GrabPoint") as Node3D).transform.is_equal_approx(RetroSystemModelArcadeCabinet.GUN_GRAB),
			"guns: and its grab point is the one the wells seat it by")
		scene.free()
		# Every other shape of fixed gun keeps those numbers (the cabinet mounts, cords and wells them all alike): Rail Chase's joystick-like one, Laser Ghost's blaster,
		# and a rifle's. A blaster is a long gun, its muzzle well ahead of a pistol's.
		var shapes_ok: Array[String] = []
		for variant: String in ["stick", "blaster", "rifle"]:
			var path: String = ArcadeCabinetBuilder.RIFLE_SCENE if variant == "rifle" else str(ArcadeCabinetSpecs.GUN_SCENES[variant])
			var gun_scene := (load(path) as PackedScene).instantiate()
			var tip := (gun_scene.get_node("BarrelTip") as Node3D).position
			if not (gun_scene is LightGun and (gun_scene.get_node("CableAttachPoint") as Node3D).position.is_equal_approx(RetroSystemModelArcadeCabinet.GUN_CORD_BOSS)
					and (gun_scene.get_node("GrabPoint") as Node3D).transform.is_equal_approx(RetroSystemModelArcadeCabinet.GUN_GRAB)
					and float(gun_scene.get("cable_length")) > 1.0 and tip.z < -0.10 and (variant != "blaster" or tip.z < -0.30)):
				shapes_ok.append(variant)
			gun_scene.free()
		_ok(shapes_ok.is_empty(), "guns: the joystick-like gun, the blaster and the rifle keep the pistol's cord boss and grab point, on a cord, aiming forward (%s)" % str(shapes_ok))


# --- cord ----------------------------------------------------------------------

func _group_cord() -> void:
	var sys := await _gun_cabinet("ptblank", 8)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var length := 1.4
	var routes := model.captive_cord_routes(length)
	_ok(routes.size() == 2, "cord: a route for each gun")
	var origins := model.gun_origins()
	for i in routes.size():
		var route: PackedVector3Array = routes[i]
		var boss: Vector3 = origins[i] * RetroSystemModelArcadeCabinet.GUN_CORD_BOSS
		_ok(route.size() >= 4 and route[0].is_equal_approx(boss), "cord: route %d starts at the gun's butt" % (i + 1))
		var entry := model.global_transform.affine_inverse() * (model.find_child("PortSeat%d" % (i + 1), true, false) as Node3D).global_position
		_ok(route[route.size() - 1].is_equal_approx(entry), "cord: and ends where it goes into the cabinet")
		var got := CaptiveCord.polyline_length(route)
		_ok(absf(got - length) < 0.08, "cord: it spends the cord's own length (%.3f of %.2f)" % [got, length])
		var floor_y := 1e9
		for pt in route:
			floor_y = minf(floor_y, pt.y)
		_ok(floor_y > 0.0, "cord: and stays above the floor (%.3f)" % floor_y)
	# The lay helper resizes a rope to a length and lays it on a route.
	var rope := VerletRope.new()
	rope.segment_length = 0.1
	rope.segment_count = 5
	CaptiveCord.resize(rope, 1.4)
	_ok(absf(float(rope.segment_count) * rope.segment_length - 1.4) < 1e-4, "cord: resize makes the rope exactly that long")
	rope.free()


# --- settle --------------------------------------------------------------------

func _group_settle() -> void:
	# A floor, as the room has one: without it a cord that hangs low has nothing to rest on.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	col.shape = box
	ground.add_child(col)
	ground.position = Vector3(0, -0.1, 0)
	add_child(ground)
	_spawned.append(ground)
	var sys := await _gun_cabinet("ptblank", 360)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var guns := sys.captive_controllers()
	for i in guns.size():
		var gun := guns[i] as LightGun
		var rope := gun.cable_instance().get_node("VerletRope") as VerletRope
		var pts: PackedVector3Array = rope.get_points()
		_ok(pts.size() >= 10, "settle: gun %d's cord has its particles (%d)" % [i + 1, pts.size()])
		var low := 1e9
		var longest := 0.0
		for k in pts.size():
			low = minf(low, pts[k].y)
			if k > 0:
				longest = maxf(longest, pts[k].distance_to(pts[k - 1]))
		_ok(low > -0.02, "settle: it rests on the floor, not through it (lowest %.3f m)" % low)
		var rest_seg := rope.segment_length
		_ok(longest < rest_seg * 1.5, "settle: it is not stretched (%.4f against %.4f m a segment)" % [longest, rest_seg])
		var boss := gun.global_transform * RetroSystemModelArcadeCabinet.GUN_CORD_BOSS
		_ok(pts[0].distance_to(boss) < 0.04, "settle: it leaves the gun's butt (%.3f m off)" % pts[0].distance_to(boss))
		var entry := (model.find_child("PortSeat%d" % (i + 1), true, false) as Node3D).global_position
		_ok(pts[pts.size() - 1].distance_to(entry) < 0.05, "settle: and goes into the cabinet at its entry (%.3f m off)" % pts[pts.size() - 1].distance_to(entry))
		_ok(rope.is_sleeping(), "settle: and it has come to rest")
	await _clear()


# --- ghost ---------------------------------------------------------------------

## Everything that draws, under the machine and what is docked or hung on it.
func _drawn_parts(sys: RetroSystem) -> Array[Node]:
	var roots: Array[Node] = [sys]
	var bay := sys.get_bay()
	if bay != null:
		roots.append(bay)
	for gun in sys.captive_controllers():
		roots.append(gun)
	var out: Array[Node] = []
	for r in roots:
		for n in r.find_children("*", "GeometryInstance3D", true, false):
			out.append(n)
	return out


func _is_ghosted(n: GeometryInstance3D) -> bool:
	if n is Label3D:
		return (n as Label3D).modulate.a < 0.5
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return false
	var is_ghost := func(m: Material) -> bool:
		return m is ShaderMaterial and (m as ShaderMaterial).shader != null \
			and (m as ShaderMaterial).shader.code.contains("keep")
	if is_ghost.call(mi.material_override):
		return true
	if mi.material_override != null:
		return false
	for i in mi.mesh.get_surface_count():
		if not is_ghost.call(mi.get_surface_override_material(i)):
			return false
	return mi.mesh.get_surface_count() > 0


## Every part of every cabinet goes see-through when it is carried: the model, the machine's own
## button, the docked bay, the guns in their holsters. (A part that cannot be dithered is hidden,
## which takes it out of what is counted here.) A Quest owner found parts left solid in 2026-10-21.
func _group_ghost() -> void:
	for id: String in VARIANTS:
		var info: Array = VARIANTS[id]
		var sys := await _machine(id, info[0], 30)
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		var before := _drawn_parts(sys).filter(func(n: Node) -> bool: return n.is_visible_in_tree()).size()
		model._set_ghost_materials(RetroSystemModelArcadeCabinet.HELD_TRANSPARENCY)
		var solid: Array[String] = []
		var shown := 0
		for n in _drawn_parts(sys):
			if not n.is_visible_in_tree():
				continue
			shown += 1
			if not _is_ghosted(n as GeometryInstance3D):
				solid.append("%s %s" % [n.get_class(), str(n.get_path())])
		_ok(solid.is_empty(), "ghost: %s has no part left solid while carried (%d of %d shown, left: %s)"
			% [id, shown, before, str(solid.slice(0, 6))])
		_ok(sys.get_bay() == null or _all_ghost_bay(sys), "ghost: %s's docked bay is see-through with it" % id)
		# A bay that arrives (or a board seated) while it is a ghost is dressed too: a fresh cabinet seeds its
		# bay a moment after it spawns, which is when it is in the hand.
		model._ghost_root_count = 0
		model._relay_ghost()
		_ok(model._ghost_root_count > 0 and _all_ghost_bay(sys),
			"ghost: %s lays the ghost again when what moves with it changes" % id)
		model._set_ghost_materials(0.0)
		var restored := _drawn_parts(sys).filter(func(n: Node) -> bool: return n.is_visible_in_tree()).size()
		_ok(restored == before, "ghost: %s shows everything again when put down (%d, was %d)" % [id, restored, before])
		await _clear()


func _all_ghost_bay(sys: RetroSystem) -> bool:
	for n in sys.get_bay().find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null and not _is_ghosted(mi):
			return false
	return true


# --- fire ----------------------------------------------------------------------

func _group_fire() -> void:
	var sys := await _gun_cabinet("ptblank", 120)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var guns := sys.captive_controllers()
	var gun := guns[0] as LightGun
	# The suite's frame counter: the game has run its boot, so a coin goes straight in (a coin into a game
	# still coming up is held: arcade_attract_tests coins/).
	model.arcade_input().frame_override = 0
	sys.is_powered_on = true
	await _wait(3)
	model.arcade_input().frame_override = model.arcade_input().wait_frames()
	var panels := model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
	var p1: ArcadeControlModule = null
	for m in panels:
		if (m as ArcadeControlModule).player == 0:
			p1 = m as ArcadeControlModule
	var grip := p1.grip()
	_ok(grip.momentary and not p1.start_held(), "fire: START is not held until it is pressed")
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))
	await _wait(3)
	_ok(p1.start_held() and not p1.is_attached(), "fire: a press HOLDS START and attaches no one")
	_ok(gun.external_button(ControllerBindings.LIGHTGUN_START), "fire: and reaches player 1's gun as its START")
	var input := model.arcade_input()
	_ok((int(input.last_sent.get(0, 0)) & (1 << ArcadeProfiles.START_BIT)) != 0,
		"fire: and as the JOYPAD's START on that port, where the cores read it in a light-gun game")
	var gun2 := guns[1] as LightGun
	_ok(not gun2.external_button(ControllerBindings.LIGHTGUN_START), "fire: and not player 2's")
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, null, grip, Vector3.ZERO, Vector3.ZERO))
	await _wait(3)
	_ok(not p1.start_held() and not gun.external_button(ControllerBindings.LIGHTGUN_START), "fire: let go, START lets go")
	# The coin: a pulse that lands, as the gun's SELECT, then releases.
	for m in model.modules_of_kind(ArcadeProfiles.KIND_COIN):
		if (m as ArcadeCoinModule).player == 0:
			(m as ArcadeCoinModule).insert_coin()
	var seen := false
	var joypad_coin := false
	for i in 90:
		await get_tree().physics_frame
		if gun.external_button(ControllerBindings.LIGHTGUN_SELECT):
			seen = true
		if (int(input.last_sent.get(0, 0)) & (1 << ArcadeProfiles.COIN_BIT)) != 0:
			joypad_coin = true
	_ok(seen, "fire: a coin reaches the gun as its SELECT")
	_ok(joypad_coin, "fire: and as the JOYPAD's SELECT on that port, the credit the cores count")
	_ok(not gun.external_button(ControllerBindings.LIGHTGUN_SELECT), "fire: and is let go again")
	# The gun in a HAND has START (stick click) and SELECT (grip) of its own. MAME 0.289 reads a start and a
	# credit off the joypad only, so they are sent as the joypad's too (this was the Quest's "START does
	# not work" on the shooting cabinet).
	input.last_sent.clear()
	gun._pressed_out[ControllerBindings.LIGHTGUN_START] = true
	input._process(0.0)
	_ok((int(input.last_sent.get(0, 0)) & (1 << ArcadeProfiles.START_BIT)) != 0,
		"fire: START pressed on the gun in the hand is the joypad's START too")
	_ok((int(input.last_sent.get(0, 0)) & (1 << ArcadeProfiles.COIN_BIT)) == 0, "fire: and only START")
	gun._pressed_out.clear()
	gun._pressed_out[ControllerBindings.LIGHTGUN_SELECT] = true
	input._process(0.0)
	_ok((int(input.last_sent.get(0, 0)) & (1 << ArcadeProfiles.COIN_BIT)) != 0,
		"fire: and SELECT is the joypad's credit")
	gun._pressed_out.clear()
	# A cabinet's gun is held only while the grip is (press_to_hold). The grip is SELECT on a console's gun,
	# and held all the while, it held the coin down: every grab was a credit.
	var hand := _fake_hand()
	gun._holding_ctrl = hand["ctrl"]
	(hand["tracker"] as XRControllerTracker).set_input(&"grip", 1.0)
	gun.captive = false
	var console_select: bool = gun._pressed_now().get(ControllerBindings.LIGHTGUN_SELECT, false)
	gun.captive = true
	var cabinet_select: bool = gun._pressed_now().get(ControllerBindings.LIGHTGUN_SELECT, true)
	_ok(console_select, "fire: (on a console's gun, which stays in the hand by itself, the grip is SELECT)")
	_ok(not cabinet_select, "fire: on a cabinet's gun the grip only holds it: no SELECT")
	input.last_sent.clear()
	input._process(0.0)
	_ok((int(input.last_sent.get(0, 0)) & (1 << ArcadeProfiles.COIN_BIT)) == 0,
		"fire: so holding it puts no coin in")
	_drop_fake_hand(gun, hand)
	sys.is_powered_on = false


## A hand the suite works by hand: an XRController3D bound to a tracker whose inputs it sets, tracked (it has a
## pose, so get_is_active is true). `origin` puts it beside another hand under one XROrigin3D.
	_external_release_keeps_hand(ControllerBindings.LIGHTGUN_TRIGGER, "the trigger")
	_external_release_keeps_hand(ControllerBindings.LIGHTGUN_START, "START")


func _fake_hand(side := "right", origin: XROrigin3D = null) -> Dictionary:
	if origin == null:
		origin = XROrigin3D.new()
		add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = StringName(side + "_hand")
	ctrl.pose = &"default"
	origin.add_child(ctrl)
	var tracker := XRControllerTracker.new()
	tracker.name = StringName(side + "_hand")
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	return {"origin": origin, "ctrl": ctrl, "tracker": tracker}


func _drop_fake_hand(gun: LightGun, hand: Dictionary) -> void:
	gun._holding_ctrl = null
	gun._pressed_out.clear()
	XRServer.remove_tracker(hand["tracker"] as XRControllerTracker)
	(hand["origin"] as Node).free()


## The machine letting go of a button the HAND still holds: the core keeps hearing it held. set_external_button pushed the hand's side as up, so a held
## trigger or START read as released for a frame and pressed again (an extra shot, a second START). What reaches the core is caught by a subclass's _set_button.
const _PUSH_SPY := """
extends "res://Scripts/Objects/peripherals/light_gun.gd"
var pushed: Array = []
func _set_button(_libretro: Libretro, button: int, pressed: bool) -> void:
	pushed.append([button, _told(button, pressed)])
"""


func _external_release_keeps_hand(lid: int, label: String) -> void:
	var spy := GDScript.new()
	spy.source_code = _PUSH_SPY
	spy.reload()
	var gun: Variant = spy.new()
	var host := RetroSystem.new()
	gun._connected_system = host
	gun._port_index = 0
	gun._pressed_out[lid] = true
	gun.set_external_button(lid, true)
	gun.set_external_button(lid, false)
	var last: Array = (gun.pushed as Array).back() if not (gun.pushed as Array).is_empty() else []
	_ok(last == [lid, true], "fire: the machine letting go of %s while the hand holds it leaves it held for the core (%s)" % [label, str(gun.pushed)])
	(gun as Node).free()
	host.free()


# --- aim -----------------------------------------------------------------------

func _group_aim() -> void:
	var sys := await _gun_cabinet("ptblank", 120)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var gun := sys.captive_controllers()[0] as LightGun
	var screen := model.get_builtin_screen()
	_ok(screen != null, "aim: the cabinet has a tube to aim at")
	var aim := gun._current_aim()
	_ok(aim != null, "aim: a gun on a cabinet with no television aims at the cabinet's own tube")
	if aim == null:
		return
	var xf := screen.global_transform
	var normal := xf.basis.z.normalized()
	var hit := aim.hit(xf.origin + normal * 0.6, -normal)
	_ok(not hit.is_empty(), "aim: a ray down the glass's normal lands on it")
	if not hit.is_empty():
		var pic: Vector2 = hit["picture"]
		_ok(pic.distance_to(Vector2(0.5, 0.5)) < 0.02, "aim: at the middle of the picture (%.3f, %.3f)" % [pic.x, pic.y])
	# Off to the right of the centre by a quarter of the glass: the picture's x moves right.
	var quad := screen.mesh as QuadMesh
	var right := xf.basis.x.normalized() * (quad.size.x * 0.25 * xf.basis.x.length())
	var hit2 := aim.hit(xf.origin + right + normal * 0.6, -normal)
	_ok(not hit2.is_empty() and (hit2["picture"] as Vector2).x > 0.6, "aim: to the right of centre reads right of centre")
	# A vertical game is pillarboxed on the glass (fit_scale.x < 1): a quarter of the glass to the right of
	# centre is then further out in the PICTURE (0.75 of the glass is the picture: 0.5 + 0.25 / 0.75).
	var fitted := ShaderMaterial.new()
	fitted.shader = ArcadeScreenModule.SHADER
	fitted.set_shader_parameter("fit_scale", Vector2(0.75, 1.0))
	var kept := screen.get_surface_override_material(0)
	screen.set_surface_override_material(0, fitted)
	var hit3 := aim.hit(xf.origin + right + normal * 0.6, -normal)
	_ok(not hit3.is_empty() and absf((hit3["picture"] as Vector2).x - 0.8333) < 0.02,
		"aim: and a pillarboxed picture is measured on the picture, not the glass")
	screen.set_surface_override_material(0, kept)
	var miss := aim.hit(xf.origin + normal * 0.6 + Vector3(0, 3, 0), -normal)
	_ok(miss.is_empty(), "aim: a ray past the glass reads off-screen")


# --- pedal ---------------------------------------------------------------------

func _group_pedal() -> void:
	var plain_guns := await _gun_cabinet("ptblank", 20)
	_ok((plain_guns.get_model() as RetroSystemModelArcadeCabinet).modules_of_kind(ArcadeProfiles.KIND_PEDAL).is_empty(),
		"pedal: a gun game with no pedal (Point Blank) has none")
	await _clear()
	var gun_cab := await _pedal_cabinet([0.0])
	var model := gun_cab.get_model() as RetroSystemModelArcadeCabinet
	var pedals := model.modules_of_kind(ArcadeProfiles.KIND_PEDAL)
	_ok(pedals.size() == 1, "pedal: a form with one pedal has one")
	if pedals.size() == 1:
		var pedal := pedals[0] as ArcadePedalModule
		_ok(pedal.active and pedal.port() == 0 and not pedal.is_pressed(),
			"pedal: wired to player 1 (the pedal under the guns), and up")
		_ok(pedal.position.z > 0.5 and pedal.position.y < 0.05, "pedal: on the floor in front of the cabinet")
		await _pedal_presses(gun_cab, pedal)
	var generic := await _machine("arcade_cabinet_generic", "arcade")
	_ok((generic.get_model() as RetroSystemModelArcadeCabinet).modules_of_kind(ArcadeProfiles.KIND_PEDAL).is_empty(),
		"pedal: the other cabinets have none")
	# A gun in a port pins MAME's lightgun mode (its default ignores the gun); nothing else does.
	await _wait(60)
	_ok(ForcedCoreOptions.lightgun("mame", true) == {"mame_lightgun_mode": "lightgun"},
		"pedal: MAME is told to read a gun when there is one")
	_ok(ForcedCoreOptions.lightgun("mame", false).is_empty() and ForcedCoreOptions.lightgun("fbneo", true).is_empty(),
		"pedal: and neither with no gun nor for FinalBurn Neo, which lists its own gun device")
	# The Quest's arcade core and the older MAME read a game's X-Y from the MOUSE unless told: a gun that
	# never moves a mouse left the crosshair, and every shot, in the middle.
	_ok(ForcedCoreOptions.lightgun("mame2003_plus", true) == {"mame2003-plus_xy_device": "lightgun"},
		"pedal: MAME 2003-Plus is told to read the gun for its X-Y device")
	_ok(ForcedCoreOptions.lightgun("mamearcade", true) == {"mame_lightgun_mode": "lightgun"},
		"pedal: and the Quest's current MAME, mamearcade, is told like mame")
	_ok(ForcedCoreOptions.lightgun("mame2003", true) == {"mame2003_mouse_device": "pointer"}
		and ForcedCoreOptions.gun_feeds_pointer("mame2003") and not ForcedCoreOptions.gun_feeds_pointer("mame2003_plus"),
		"pedal: MAME 2003 has no gun value, so its gun is read as a pointer")
	_ok(ForcedCoreOptions.lightgun("mame2010", true) == {"mame_current_xy_type": "lightgun"},
		"pedal: and so is MAME 2010")
	_ok(ForcedCoreOptions.lightgun("mame2003_plus", false).is_empty(),
		"pedal: and neither with no gun")
	_ok(gun_cab._all_forced_options("mame").get("mame_lightgun_mode", "") == "lightgun",
		"pedal: the gun cabinet pins it for the run")
	_ok(not generic._all_forced_options("mame").has("mame_lightgun_mode"),
		"pedal: and the cabinet with sockets and no gun does not")
	await _clear()
	await _two_pedals()
	await _clear()
	await _pedal_kinds()


## The pedal's other kinds (ArcadeGameProfile.pedal_kind): Virtua Cop 3's is an ACTION (the ES mode: up until the player steps on it, down for the gestures that take cover in
## Time Crisis), Golgo 13's rifle has a scope SENSOR (a proximity switch the game's shooting waits for: down while the rifle is in a hand, lifted by the same gestures, and
## switched on by a head at the eyepiece with no hand on the rifle), on MAME's button 2 (Juusei no Requiem's on 3: Aux B and the pad's Y).
func _pedal_kinds() -> void:
	# Virtua Cop 3.
	var sys := await _gun_cabinet("vcop3")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var by_port := {}
	for pd in model.modules_of_kind(ArcadeProfiles.KIND_PEDAL):
		by_port[(pd as ArcadePedalModule).port()] = pd
	_ok(by_port.size() == 2, "pedal: Virtua Cop 3 has a pedal under each of its two guns")
	var input := model.arcade_input()
	var guns := sys.captive_controllers()
	var gun := guns[0] as LightGun
	var aux_a := ControllerBindings.LIGHTGUN_AUX_A
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	input.frame_override = input.wait_frames()
	sys.is_powered_on = true
	await _wait(3)
	var pedal := by_port[0] as ArcadePedalModule
	input.held_override = [gun]
	input._process(0.0)
	_ok(input.pedal_kind() == "action" and not pedal.is_pressed() and _pedal_off(input, gun, 0),
		"pedal: Virtua Cop 3's is an action pedal: the gun in a hand does NOT press it (the ES mode is on only when asked for)")
	gun._pressed_out[aux_a] = true
	input._process(0.0)
	_ok(pedal.is_pressed() and _pedal_sent(input, gun, 0) and gun.external_button(aux_a),
		"pedal: the gun hand's A or X steps on it: the gun's Aux A and the joypad's A, which is MAME's button 2")
	gun._pressed_out.clear()
	input._process(0.0)
	_ok(not pedal.is_pressed() and _pedal_off(input, gun, 0), "pedal: and let go, it comes up")
	Input.action_press(ArcadeInput.PEDAL_ACTION)
	input._process(0.0)
	var key_on := pedal.is_pressed() and _pedal_sent(input, gun, 0)
	Input.action_release(ArcadeInput.PEDAL_ACTION)
	input._process(0.0)
	_ok(key_on and not pedal.is_pressed(), "pedal: the pedal key (Space, a pad's RB) steps on it too, for as long as it is held")
	input.pedal_mode_override = AppPrefs.PEDAL_DUCK
	input.head_height_override = 1.70
	input._process(0.0)
	input.head_height_override = 1.45
	input._process(0.0)
	var ducked_on := pedal.is_pressed()
	input.head_height_override = 1.70
	input._process(0.0)
	_ok(ducked_on and not pedal.is_pressed(), "pedal: so does ducking (25 cm under the highest the head has been), and standing up lets go")
	input.head_height_override = NAN
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	input._process(0.0)
	var rows: Array = gun._cabinet_rows
	_ok(rows.size() == 2 and rows[0][0] == &"pedal_act" and str(rows[0][3]).contains("step on the pedal") and rows[1][0] == &"pedal_act_desktop",
		"pedal: the gun's hint says hold A or X to step on the pedal (it says take cover for Time Crisis)")
	input.held_override = []
	gun._pressed_out[aux_a] = true
	input._process(0.0)
	_ok(not pedal.is_pressed(), "pedal: a gun in its holster presses nothing, A or X or not")
	gun._pressed_out.clear()
	# A gun with no scope has no eyepiece for a head to be at, whatever the head does.
	input.head_position_override = gun.global_position
	_ok(not input._eye_at_scope(gun), "pedal: a pistol has no eyepiece: a head on top of it is at no scope")
	input.head_position_override = Vector3.INF
	sys.is_powered_on = false
	input._process(0.0)
	await _clear()

	# Golgo 13's scope sensor.
	sys = await _gun_cabinet("golgo13")
	model = sys.get_model() as RetroSystemModelArcadeCabinet
	var sensors := model.modules_of_kind(ArcadeProfiles.KIND_PEDAL)
	_ok(sensors.size() == 1 and (sensors[0] as Node).get_node_or_null("SensorLamp") != null and (sensors[0] as Node).get_node_or_null("PedalPlate") == null,
		"pedal: Golgo 13's rifle has one switch on its deck, a sensor with a lamp and no pedal plate")
	if sensors.size() != 1:
		return
	var sensor := sensors[0] as ArcadePedalModule
	input = model.arcade_input()
	var rifle := sys.captive_controllers()[0] as LightGun
	var lens := rifle.find_child("ScopeScreen", true, false) as Node3D
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	input.frame_override = input.wait_frames()
	sys.is_powered_on = true
	await _wait(3)
	input.held_override = []
	input._process(0.0)
	_ok(input.pedal_kind() == "sensor" and input.pedal_button() == 2 and not sensor.is_pressed() and _pedal_off(input, rifle, 0),
		"pedal: with the rifle in its cradle and nobody at it, the sensor is off")
	input.held_override = [rifle]
	input._process(0.0)
	_ok(sensor.is_pressed() and _pedal_sent(input, rifle, 0),
		"pedal: with the rifle in a hand the sensor is on: the rifle's Aux A and the joypad's A, MAME's button 2 (the game's shooting waits for it)")
	for i in 6:
		sensor.tick(0.02)
	var lamp := sensor.get_node("SensorLamp") as MeshInstance3D
	var glow := (lamp.material_override as StandardMaterial3D).emission_energy_multiplier
	rifle._pressed_out[aux_a] = true
	input._process(0.0)
	_ok(glow > 1.0 and not sensor.is_pressed() and _pedal_off(input, rifle, 0),
		"pedal: its lamp lights while it is on (glow %.1f), and the hand's A or X takes the eye off the scope: it goes off" % glow)
	for i in 6:
		sensor.tick(0.02)
	_ok(is_zero_approx((lamp.material_override as StandardMaterial3D).emission_energy_multiplier) and sensor.plate_down() == 0.0, "pedal: and the lamp goes out")
	rifle._pressed_out.clear()
	# A head at the eyepiece switches it on whatever the hands do: within 10 cm, kept to 13 once it is on.
	input.held_override = []
	var eye := lens.global_position
	input.head_position_override = eye + Vector3(0, 0, 0.06)
	input._process(0.0)
	var near := sensor.is_pressed() and _pedal_sent(input, rifle, 0)
	input.head_position_override = eye + Vector3(0, 0, 0.12)
	input._process(0.0)
	var kept := sensor.is_pressed()
	input.head_position_override = eye + Vector3(0, 0, 0.14)
	input._process(0.0)
	var gone := not sensor.is_pressed()
	input.head_position_override = eye + Vector3(0, 0, 0.12)
	input._process(0.0)
	var not_yet := not sensor.is_pressed()
	_ok(near and kept and gone and not_yet,
		"pedal: and so does the head at the eyepiece: on within 10 cm, kept to 13, off beyond, and not on again until it is back within 10")
	input.held_override = [rifle]
	rifle._pressed_out[aux_a] = true
	input.head_position_override = eye + Vector3(0, 0, 0.05)
	input._process(0.0)
	_ok(sensor.is_pressed(), "pedal: an eye at the scope is on even with A or X held (the eye is the sensor)")
	rifle._pressed_out.clear()
	input.head_position_override = Vector3.INF
	var srows: Array = rifle._cabinet_rows
	_ok(srows.size() == 2 and srows[0][0] == &"pedal_scope" and str(srows[0][3]).contains("eye off the scope") and srows[1][0] == &"pedal_scope_desktop",
		"pedal: the rifle's hint says hold A or X to take the eye off the scope")
	sys.is_powered_on = false
	input.held_override = []
	input._process(0.0)
	_ok(not sensor.is_pressed() and not rifle.external_button(aux_a), "pedal: switched off, the sensor is off and the rifle is let go")
	await _clear()

	# Juusei no Requiem's sensor is its button 3: the rifle's Aux B, the pad's Y.
	sys = await _gun_cabinet("g13jnr")
	model = sys.get_model() as RetroSystemModelArcadeCabinet
	input = model.arcade_input()
	var rifle3 := sys.captive_controllers()[0] as LightGun
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	input.frame_override = input.wait_frames()
	sys.is_powered_on = true
	await _wait(3)
	input.held_override = [rifle3]
	input._process(0.0)
	_ok(input.pedal_button() == 3 and rifle3.sent_button(ControllerBindings.LIGHTGUN_AUX_B) and not rifle3.sent_button(aux_a)
			and (int(input.last_sent.get(0, 0)) & (1 << ControllerBindings.JOYPAD_Y)) != 0 and (int(input.last_sent.get(0, 0)) & (1 << ControllerBindings.JOYPAD_A)) == 0,
		"pedal: Juusei no Requiem's scope sensor is MAME's button 3: the rifle's Aux B and the pad's Y, not Aux A")
	sys.is_powered_on = false
	input.held_override = []
	input._process(0.0)


## Two guns, a pedal under each: each pedal is its own player's, and works for the gun in that player's hand only.
func _two_pedals() -> void:
	var sys := await _pedal_cabinet([-0.2, 0.2])
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var pedals := model.modules_of_kind(ArcadeProfiles.KIND_PEDAL)
	var by_port := {}
	for pd in pedals:
		by_port[(pd as ArcadePedalModule).port()] = pd
	_ok(pedals.size() == 2 and by_port.has(0) and by_port.has(1)
			and (by_port[0] as Node3D).position.x < (by_port[1] as Node3D).position.x,
		"pedal: a pedal under each of two guns: player 1's on the left, player 2's on the right")
	if by_port.size() != 2:
		return
	var input := model.arcade_input()
	var guns := sys.captive_controllers()
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	input.frame_override = input.wait_frames()
	sys.is_powered_on = true
	await _wait(3)
	var p1 := by_port[0] as ArcadePedalModule
	var p2 := by_port[1] as ArcadePedalModule
	input.held_override = [guns[1]]
	input._process(0.0)
	_ok(p2.is_pressed() and not p1.is_pressed() and _pedal_sent(input, guns[1] as LightGun, 1) and _pedal_off(input, guns[0] as LightGun, 0),
		"pedal: player 2's gun in a hand works player 2's pedal, and not player 1's")
	input.held_override = [guns[0], guns[1]]
	input._process(0.0)
	_ok(p1.is_pressed() and p2.is_pressed(), "pedal: both guns in hand, both pedals are down")
	# One takes cover (A or X on ITS gun): only that pedal comes up.
	(guns[0] as LightGun)._pressed_out[ControllerBindings.LIGHTGUN_AUX_A] = true
	input._process(0.0)
	_ok(not p1.is_pressed() and p2.is_pressed(), "pedal: and taking cover with player 1's gun lifts player 1's pedal alone")
	(guns[0] as LightGun)._pressed_out.clear()
	sys.is_powered_on = false
	input._process(0.0)
	input.held_override = []


## What works the pedal and what it sends: MAME reads Time Crisis's pedal as player 1's BUTTON2, the gun's Aux A
## and the joypad's A. A headset reads no feet, so the pedal is down while the gun is in a hand and taking cover
## lifts it: A or X and the pedal key in every mode, the free hand's trigger or ducking in the other two.
func _pedal_presses(sys: RetroSystem, pedal: ArcadePedalModule) -> void:
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var input := model.arcade_input()
	var guns := sys.captive_controllers()
	var gun := guns[0] as LightGun
	var gun2 := guns[1] as LightGun
	var aux_a := ControllerBindings.LIGHTGUN_AUX_A
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	input.frame_override = input.wait_frames()
	sys.is_powered_on = true
	await _wait(3)
	var plate := pedal.get_node("PedalPlate") as Node3D
	var rest := plate.transform
	# The toe of the plate: it rests raised, and comes down when the pedal is pressed.
	var toe := Vector3(0, 0, -0.09)
	var toe_rest := (rest * toe).y
	input._process(0.0)
	_ok(not pedal.is_pressed() and _pedal_off(input, gun, 0), "pedal: with the gun in its holster it is up")
	input.held_override = [gun]
	input._process(0.0)
	_ok(pedal.is_pressed() and _pedal_sent(input, gun, 0),
		"pedal: with player 1's gun in a hand it is down (out of cover): the gun's Aux A and the joypad's A")
	for i in 6:
		pedal.tick(0.02)
	var toe_down := (plate.transform * toe).y
	_ok(pedal.plate_down() == 1.0 and toe_down < toe_rest - 0.02,
		"pedal: the plate goes down, toe first (%.3f -> %.3f m)" % [toe_rest, toe_down])
	_ok((plate.transform * Vector3.ZERO).is_equal_approx(rest * Vector3.ZERO)
			and absf((plate.transform * Vector3(0, 0, 0.02)).y - (rest * Vector3(0, 0, 0.02)).y) < 0.008,
		"pedal: about its hinge (the plate's own origin): the heel stays where it was")
	# The gun hand's A (or X), through the real binding, takes cover: the game hears the pedal come up, not the
	# hand's Aux A, which the cabinet has taken over.
	var hand := _fake_hand()
	gun._holding_ctrl = hand["ctrl"]
	(hand["tracker"] as XRControllerTracker).set_input(&"ax_button", 1.0)
	gun._pressed_now()
	input._process(0.0)
	_ok(gun.hand_button(aux_a) and not pedal.is_pressed() and _pedal_off(input, gun, 0),
		"pedal: the gun hand's A or X takes cover: the pedal comes up, and the hand's own Aux A is not sent")
	for i in 6:
		pedal.tick(0.02)
	_ok(pedal.plate_down() == 0.0 and plate.transform.is_equal_approx(rest), "pedal: the plate back where it rested")
	(hand["tracker"] as XRControllerTracker).set_input(&"ax_button", 0.0)
	gun._pressed_now()
	input._process(0.0)
	_ok(pedal.is_pressed() and _pedal_sent(input, gun, 0), "pedal: let go, out of cover again")
	# The pedal key (Space, a pad's RB, a foot switch) takes cover too.
	Input.action_press(ArcadeInput.PEDAL_ACTION)
	input._process(0.0)
	var key_cover := not pedal.is_pressed() and _pedal_off(input, gun, 0)
	Input.action_release(ArcadeInput.PEDAL_ACTION)
	input._process(0.0)
	_ok(key_cover and pedal.is_pressed(), "pedal: the pedal key takes cover while it is held")
	# A pedal that is not wired is a picture: the gun's Aux A is its own again.
	pedal.active = false
	gun._pressed_out[aux_a] = true
	input._process(0.0)
	_ok(not pedal.is_pressed() and gun.sent_button(aux_a) and not gun.external_button(aux_a)
		and (int(input.last_sent.get(0, 0)) & (1 << ControllerBindings.JOYPAD_A)) == 0,
		"pedal: one that is not wired is not pressed, and the gun's Aux A is its own (no joypad A)")
	gun._pressed_out.clear()
	pedal.active = true
	# Player 2's gun is player 2's: this pedal is player 1's, and player 2 has none.
	input.held_override = [gun2]
	gun2._pressed_out[aux_a] = true
	input._process(0.0)
	_ok(not pedal.is_pressed() and _pedal_off(input, gun, 0) and gun2.sent_button(aux_a)
		and (int(input.last_sent.get(1, 0)) & (1 << ControllerBindings.JOYPAD_A)) == 0,
		"pedal: player 2's gun in a hand does not work player 1's pedal, and its Aux A is its own")
	gun2._pressed_out.clear()
	# The hint the gun carries says how to take cover, the gun on a port with no pedal carries none.
	var rows: Array = gun._cabinet_rows
	_ok(rows.size() == 2 and rows[0][0] == &"pedal_cover" and rows[0][2] == ["quest_button_{ax}_outline"]
		and str(rows[1][3]).contains(DesktopBindings.event_display_name(ArcadeInput.PEDAL_ACTION))
		and gun2._cabinet_rows.is_empty(),
		"pedal: the gun's hint says hold A or X (Space on the desktop) to take cover, and player 2's says nothing")
	var declared := false
	for row: Array in gun._hint._rows:
		declared = declared or row[0] == &"pedal_cover"
	_ok(declared, "pedal: and the hint has the row, to show at the grab")
	# The free hand's trigger (the other mode): the right hand holds the gun, the left squeezes.
	input.pedal_mode_override = AppPrefs.PEDAL_FREE_HAND
	input.held_override = [gun]
	var left := _fake_hand("left", hand["origin"])
	input._left_vr_ctrl = left["ctrl"]
	input._right_vr_ctrl = hand["ctrl"]
	input._process(0.0)
	_ok(pedal.is_pressed() and input._free_hand(gun) == left["ctrl"],
		"pedal: free hand: out of cover, and the left hand is the free one (the right holds the gun)")
	_ok(input._free_hand_block.is_blocking(left["ctrl"]) and not input._free_hand_block.is_blocking(hand["ctrl"]),
		"pedal: its laser is off while it works the pedal, so the squeeze clicks nothing")
	gun._holding_ctrl = left["ctrl"]
	var swapped: XRController3D = input._free_hand(gun)
	gun._holding_ctrl = hand["ctrl"]
	_ok(swapped == hand["ctrl"], "pedal: (with the gun in the left hand the right one is free)")
	sys.is_powered_on = false
	input._process(0.0)
	var off_released := not input._free_hand_block.is_blocking(left["ctrl"])
	sys.is_powered_on = true
	input._process(0.0)
	_ok(off_released and input._free_hand_block.is_blocking(left["ctrl"]),
		"pedal: switched off, the free hand has its laser back; on again, it works the pedal again")
	(left["tracker"] as XRControllerTracker).set_input(&"trigger", 1.0)
	input._process(0.0)
	_ok(not pedal.is_pressed() and _pedal_off(input, gun, 0), "pedal: the free hand's trigger takes cover")
	(left["tracker"] as XRControllerTracker).set_input(&"trigger", 0.0)
	input._process(0.0)
	_ok(pedal.is_pressed(), "pedal: let go, out again")
	_ok(gun._cabinet_rows[0][0] == &"pedal_cover_free_hand"
		and HeldHint.glyph_name(gun._cabinet_rows[0][2][0], true) == "quest_trigger_left_outline",
		"pedal: the hint names the other hand's trigger")
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	(left["tracker"] as XRControllerTracker).set_input(&"trigger", 1.0)
	input._process(0.0)
	_ok(pedal.is_pressed() and not input._free_hand_block.is_blocking(left["ctrl"]),
		"pedal: in the other modes the free hand's trigger does nothing, and its laser is back")
	(left["tracker"] as XRControllerTracker).set_input(&"trigger", 0.0)
	XRServer.remove_tracker(left["tracker"] as XRControllerTracker)
	input._left_vr_ctrl = null
	input._right_vr_ctrl = null
	_drop_fake_hand(gun, hand)
	# Ducking: 18 cm under the highest the head has been since the grab, back above 12.
	input.pedal_mode_override = AppPrefs.PEDAL_DUCK
	input.head_height_override = 1.70
	input._process(0.0)
	var up := pedal.is_pressed()
	input.head_height_override = 1.60
	input._process(0.0)
	var bob := pedal.is_pressed()
	input.head_height_override = 1.50
	input._process(0.0)
	var ducked := not pedal.is_pressed() and _pedal_off(input, gun, 0)
	_ok(up and bob and ducked, "pedal: ducking takes cover: 10 cm under is still out, 20 is in")
	input.head_height_override = 1.57
	input._process(0.0)
	var held_down := not pedal.is_pressed()
	input.head_height_override = 1.60
	input._process(0.0)
	_ok(held_down and pedal.is_pressed(), "pedal: and out again only above 12 cm under, so it does not flicker")
	input.head_height_override = 1.80
	input._process(0.0)
	input.head_height_override = 1.61
	input._process(0.0)
	_ok(not pedal.is_pressed(), "pedal: measured from the highest the head has been (1.80), not where it was taken")
	input.held_override = []
	input._process(0.0)
	input.held_override = [gun]
	input.head_height_override = 1.40
	input._process(0.0)
	var fresh := pedal.is_pressed()
	gun._pressed_out[aux_a] = true
	input._process(0.0)
	_ok(fresh and not pedal.is_pressed(), "pedal: a new grab measures afresh (taken at 1.40, out), and A or X still takes cover")
	gun._pressed_out.clear()
	_ok(gun._cabinet_rows[0][0] == &"pedal_cover_duck", "pedal: and the hint says duck")
	input.head_height_override = NAN
	input.pedal_mode_override = AppPrefs.PEDAL_BUTTON
	# Switched off while out of cover: the pedal comes up and the gun is not left pressed.
	input._process(0.0)
	var was_down := pedal.is_pressed()
	sys.is_powered_on = false
	input._process(0.0)
	_ok(was_down and not pedal.is_pressed() and not gun.external_button(aux_a),
		"pedal: switched off with it down, it comes up and the gun is let go")
	input.held_override = []
	input.pedal_mode_override = ""
	# The setting is the player's, saved, and an unknown one reads as the default.
	var prefs_existed := FileAccess.file_exists(AppPrefs.PREFS_PATH)
	var prefs_before := FileAccess.get_file_as_bytes(AppPrefs.PREFS_PATH)
	var mode_before := AppPrefs.arcade_pedal_mode
	AppPrefs.arcade_pedal_mode = AppPrefs.PEDAL_DUCK
	AppPrefs.save_prefs()
	AppPrefs.arcade_pedal_mode = AppPrefs.PEDAL_BUTTON
	AppPrefs.load_prefs()
	var kept := AppPrefs.arcade_pedal_mode == AppPrefs.PEDAL_DUCK
	var data := JsonStore.read_dict(AppPrefs.PREFS_PATH, "test")
	data["arcade_pedal_mode"] = "feet"
	JsonStore.write_dict(AppPrefs.PREFS_PATH, data, "test")
	AppPrefs.load_prefs()
	_ok(kept and AppPrefs.arcade_pedal_mode == AppPrefs.PEDAL_BUTTON,
		"pedal: the mode is saved and read back, and one this build does not know reads as A or X")
	AppPrefs.arcade_pedal_mode = mode_before
	# The cabinet-motion setting is the player's too: saved, read back, and one this build does not know is automatic.
	var motion_before := AppPrefs.arcade_motion
	AppPrefs.arcade_motion = AppPrefs.MOTION_OFF
	AppPrefs.save_prefs()
	AppPrefs.arcade_motion = AppPrefs.MOTION_ON
	AppPrefs.load_prefs()
	var motion_kept := AppPrefs.arcade_motion == AppPrefs.MOTION_OFF
	var motion_data := JsonStore.read_dict(AppPrefs.PREFS_PATH, "test")
	motion_data["arcade_motion"] = "shaking"
	JsonStore.write_dict(AppPrefs.PREFS_PATH, motion_data, "test")
	AppPrefs.load_prefs()
	_ok(motion_kept and AppPrefs.arcade_motion == AppPrefs.MOTION_AUTO,
		"motion: the setting is saved and read back, and one this build does not know reads as automatic")
	AppPrefs.arcade_motion = motion_before
	if prefs_existed:
		var f := FileAccess.open(AppPrefs.PREFS_PATH, FileAccess.WRITE)
		f.store_buffer(prefs_before)
		f.close()
	elif FileAccess.file_exists(AppPrefs.PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppPrefs.PREFS_PATH))
	# The per-hand glyph names a hint resolves.
	_ok(HeldHint.glyph_name("quest_button_{ax}_outline", true) == "quest_button_a_outline"
		and HeldHint.glyph_name("quest_button_{ax}_outline", false) == "quest_button_x_outline"
		and HeldHint.glyph_name("quest_trigger_{other}_outline", false) == "quest_trigger_right_outline"
		and HeldHint.glyph_name("quest_grip_{side}_outline", false) == "quest_grip_left_outline",
		"pedal: {ax} is the hand's A or X, {other} the other hand ({side} unchanged)")
	var have_art := true
	for name: String in ["quest_button_a_outline", "quest_button_x_outline", "quest_trigger_left_outline",
			"quest_trigger_right_outline", "xbox_rb_outline"]:
		have_art = have_art and ResourceLoader.exists("%s/%s%s" % [HeldHint.GLYPH_DIR, name, ConsolePadDiagram.GLYPH_EXT])
	_ok(have_art, "pedal: and every glyph the pedal's hints name is there")


## Whether `port` is sending the pedal down: as `gun`'s Aux A (what the core is told of it) and as the joypad's A.
func _pedal_sent(input: ArcadeInput, gun: LightGun, port: int) -> bool:
	return gun.sent_button(ControllerBindings.LIGHTGUN_AUX_A) \
		and (int(input.last_sent.get(port, 0)) & (1 << ControllerBindings.JOYPAD_A)) != 0


## Whether `port` is sending the pedal up: neither `gun`'s Aux A nor the joypad's A, each on its own.
func _pedal_off(input: ArcadeInput, gun: LightGun, port: int) -> bool:
	return not gun.sent_button(ControllerBindings.LIGHTGUN_AUX_A) \
		and (int(input.last_sent.get(port, 0)) & (1 << ControllerBindings.JOYPAD_A)) == 0


## The slot a board stands in: the docked bay's (a cabinet's own is shut for good, ArcadeBayUnit).
func _slot_of(sys: Node3D) -> XRToolsSnapZone:
	var bay := (sys as RetroSystem).get_bay()
	return bay.slot if bay != null else sys.get_node("CartridgeSlot") as XRToolsSnapZone


## Where the board's centre stands: the docked bay's seat.
func _seat_of(model: Node3D) -> Node3D:
	var bay := (model.get_parent() as RetroSystem).get_bay()
	return bay.find_child("CartSeat", true, false) as Node3D


# --- seat ----------------------------------------------------------------------

func _group_seat() -> void:
	for id: String in VARIANTS:
		var systemid: String = VARIANTS[id][0]
		var sys := await _machine(id, systemid)
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		var slot := _slot_of(sys)
		model.set_lid_angle_deg(90.0)
		var cart := CART_SCENE.instantiate() as Node3D
		cart.systemid = systemid
		cart.rom_path = "/tmp/variant_test_board.zip"
		cart.position = Vector3(0, 3, 0)
		cart.freeze = true
		add_child(cart)
		_spawned.append(cart)
		await _wait(8)
		slot.pick_up_object(cart)
		await _wait(6)
		_ok(sys.rom_path == "/tmp/variant_test_board.zip", "seat: %s takes a %s board" % [id, systemid])
		_ok(cart.global_position.distance_to(_seat_of(model).global_position) < 0.02,
			"seat: and it stands in the socket")
		slot.drop_object()
		await _wait(4)
		_ok(sys.rom_path.is_empty(), "seat: pulling it takes the game away")
		await _clear()


# --- art -----------------------------------------------------------------------

## A texture with a corner marked, so a flipped or mirrored picture would not pass for the right one.
func _tex(w: int, h: int, c: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	img.set_pixel(0, 0, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _art_of(model: Node, node_name: String) -> MeshInstance3D:
	return model.find_child(node_name, true, false) as MeshInstance3D


func _art_tex(mi: MeshInstance3D) -> Texture2D:
	var m := mi.material_override as StandardMaterial3D
	return m.albedo_texture if m != null else null


func _group_art() -> void:
	var wheel := _tex(60, 20, Color.RED)
	var cover := _tex(30, 41, Color.BLUE)
	for id: String in VARIANTS:
		var info: Array = VARIANTS[id]
		var sys := await _machine(id, info[0], 20)
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		var mq := _art_of(model, "MarqueeArt")
		var sl := _art_of(model, "SideArtL")
		var sr := _art_of(model, "SideArtR")
		_ok(mq != null and sl != null and sr != null, "art: %s has the marquee and both side slots" % id)
		if mq == null or sl == null or sr == null:
			continue
		var title := _art_of(model, "Marquee").get_node("MarqueeTitle") as Label3D
		_ok(not mq.visible and not sl.visible and not sr.visible and title.visible,
			"art: %s starts plain, with its title" % id)
		# Each side's art is its own silhouette, outside the panel and facing out: the normal says which way.
		var nl := ((sl.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
		var nr := ((sr.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
		_ok(nl.dot(Vector3.LEFT) > 0.99 and nr.dot(Vector3.RIGHT) > 0.99, "art: %s's side art faces outward on each side" % id)
		var bl := sl.global_transform * sl.get_aabb()
		var br := sr.global_transform * sr.get_aabb()
		_ok(bl.position.x < model.global_position.x - model.cabinet_width * 0.49
			and br.position.x > model.global_position.x + model.cabinet_width * 0.49,
			"art: %s's side art stands on the outside of the panels" % id)
		# And it covers the whole flank: as tall as the cabinet, as deep as its silhouette.
		_ok(absf(bl.size.y - model.cabinet_height) < 0.01 and bl.size.z > 0.8,
			"art: %s's side art covers the whole flank (%s)" % [id, str(bl.size)])

		model.apply_art(wheel, cover)
		_ok(mq.visible and _art_tex(mq) == wheel and not title.visible,
			"art: %s's marquee shows the wheel, not the title" % id)
		_ok(sl.visible and sr.visible and _art_tex(sl) == cover and _art_tex(sr) == cover,
			"art: %s's sides show the cover" % id)
		# A cover is cropped to the flank, centred, never stretched: the part kept has the flank's proportions.
		var flank: float = sl.get_meta("aspect")
		var ml := sl.material_override as StandardMaterial3D
		var kept := (ml.uv1_scale.x * 30.0) / (ml.uv1_scale.y * 41.0)
		_ok(absf(kept - flank) < 0.001 and ml.uv1_scale.x <= 1.0 and ml.uv1_scale.y <= 1.0
			and absf(ml.uv1_offset.x - (1.0 - ml.uv1_scale.x) * 0.5) < 0.001 and sl.scale.is_equal_approx(Vector3.ONE),
			"art: %s's cover fills the flank, cropped to it (flank %.3f, kept %.3f)" % [id, flank, kept])
		var mbox: Vector2 = mq.get_meta("box")
		_ok(absf(mq.scale.x / mq.scale.y - 3.0) < 0.001 and mq.scale.x <= mbox.x + 0.001 and mq.scale.y <= mbox.y + 0.001,
			"art: %s's wheel keeps its proportions inside the marquee" % id)

		# Powered, the marquee art glows with the marquee; the sides never do.
		model.on_power_on()
		_ok((mq.material_override as StandardMaterial3D).emission_enabled
			and not (sl.material_override as StandardMaterial3D).emission_enabled,
			"art: %s's marquee art lights with the machine" % id)
		model.on_power_off()
		_ok(not (mq.material_override as StandardMaterial3D).emission_enabled, "art: %s's marquee art goes dark with it" % id)

		# Carried: the art is a BaseMaterial3D, so it dithers with the cabinet instead of hiding, and comes back.
		model._set_ghost_materials(RetroSystemModelArcadeCabinet.HELD_TRANSPARENCY)
		_ok(mq.visible and sl.visible and _is_ghosted(mq) and _is_ghosted(sl), "art: %s's art is see-through while carried" % id)
		model._set_ghost_materials(0.0)
		_ok(_art_tex(mq) == wheel and _art_tex(sl) == cover, "art: %s's art is back when it is put down" % id)

		# The fallbacks: no wheel -> the cover; no cover -> the wheel on the marquee alone; neither -> plain.
		model.apply_art(null, cover)
		_ok(mq.visible and _art_tex(mq) == cover, "art: %s's marquee falls back to the cover" % id)
		model.on_media_cleared()
		model.apply_art(wheel, null)
		_ok(mq.visible and _art_tex(mq) == wheel and not sl.visible and not sr.visible,
			"art: %s with only a wheel dresses the marquee and leaves the sides" % id)
		model.on_media_cleared()
		model.apply_art(null, null)
		_ok(not mq.visible and not sl.visible and title.visible, "art: %s with no art stays plain, title and all" % id)

		# "Cabinet Art" off: naked whatever is in the bay; on again: dressed from what was kept.
		model.apply_art(wheel, cover)
		sys.set_cabinet_art_enabled(false)
		_ok(not mq.visible and not sl.visible and not sr.visible and title.visible and not sys.cabinet_art_enabled,
			"art: %s goes naked when Cabinet Art is switched off" % id)
		model.apply_art(wheel, cover)
		_ok(not mq.visible and not sl.visible and title.visible, "art: %s stays naked when a game goes in with it off" % id)
		sys.set_cabinet_art_enabled(true)
		_ok(mq.visible and _art_tex(mq) == wheel and sl.visible and _art_tex(sr) == cover and not title.visible,
			"art: %s is dressed again when it is switched back on" % id)
		model.on_media_cleared()

		# The real path: a board seated in the bay dresses it, and pulling it undresses it.
		var rom := "/tmp/variant_art_board.zip"
		ArcadeCabinetArt.test_art[rom] = {"wheel": wheel, "cover": cover}
		var slot := _slot_of(sys)
		model.set_lid_angle_deg(90.0)
		var cart := CART_SCENE.instantiate() as Node3D
		cart.systemid = info[0]
		cart.rom_path = rom
		cart.position = Vector3(0, 3, 0)
		cart.freeze = true
		add_child(cart)
		_spawned.append(cart)
		await _wait(8)
		slot.pick_up_object(cart)
		await _wait(6)
		_ok(mq.visible and _art_tex(mq) == wheel and sl.visible and not title.visible,
			"art: %s is dressed when its board goes in" % id)
		slot.drop_object()
		await _wait(4)
		_ok(not mq.visible and not sl.visible and not sr.visible and title.visible,
			"art: %s is plain again when the board is pulled" % id)
		ArcadeCabinetArt.test_art.erase(rom)
		await _clear()

	# The System tab's row: shown for a cabinet, hidden for any other machine, and it asks the machine.
	var opts := preload("res://Scenes/UI/core_options_2d.tscn").instantiate() as CoreOptions2D
	add_child(opts)
	await get_tree().process_frame
	opts.populate_system(false, false, false, "", 0, -1.0, true, true)
	_ok(opts._cabinet_art_row.visible and opts._cabinet_art_check.button_pressed, "art: the System tab shows Cabinet Art, on")
	opts.populate_system(false, false, false, "", 0, -1.0, true, false)
	_ok(not opts._cabinet_art_check.button_pressed, "art: and shows it off for a cabinet whose art is off")
	var asked := [null]
	opts.cabinet_art_toggled.connect(func(on: bool) -> void: asked[0] = on)
	opts._cabinet_art_check.button_pressed = true
	_ok(asked[0] == true, "art: switching the row asks for it")
	opts.populate_system(false, false, false)
	_ok(not opts._cabinet_art_row.visible, "art: a machine that is not a cabinet has no such row")
	opts.queue_free()
	var plain := await _machine("", "snes", 6)
	_ok(not plain.supports_cabinet_art_toggle(), "art: only a cabinet offers the toggle")
	var cab := await _machine("arcade_cabinet_generic", "arcade", 8)
	_ok(cab.supports_cabinet_art_toggle() and cab.cabinet_art_enabled, "art: a cabinet offers it, on by default")
	# Saved only when off, and read back: the default room file is unchanged.
	var persist := ScenePersistence.new("arcade")
	var entry := persist._serialize_system(cab, 1, cab, {})
	_ok(not entry.has("cabinet_art"), "art: a cabinet with art on adds nothing to the saved room")
	cab.set_cabinet_art_enabled(false)
	entry = persist._serialize_system(cab, 1, cab, {})
	_ok(entry.get("cabinet_art", true) == false, "art: a cabinet with art off is saved that way")
	await _clear()

	# A cabinet baked before the slots (a mod's) takes the call and does nothing.
	var bare := RetroSystemModelArcadeCabinet.new()
	bare.apply_art(wheel, cover)
	bare.on_media_cleared()
	_ok(true, "art: a cabinet with no art slots is left alone")
	bare.free()

	# The sidecars -> an id by file name; a folder has no extension; a half-written index gives nothing.
	var by_name := ArcadeCabinetArt.ids_by_name(PackedInt32Array([6897, 6902, 6898]),
		PackedStringArray(["1941", "imgs", "1942"]), PackedStringArray(["zip", "", "zip"]))
	_ok(by_name.get("1941.zip") == 6897 and by_name.get("imgs") == 6902 and by_name.get("1942.zip") == 6898,
		"art: RomM ids are found by file name")
	_ok(ArcadeCabinetArt.ids_by_name(PackedInt32Array([1]), PackedStringArray(["a", "b"]), PackedStringArray()).is_empty(),
		"art: a half-written index gives no ids")
	_ok(ArcadeCabinetArt.fit(Vector2(30, 41), Vector2(0.44, 1.5)).is_equal_approx(Vector2(0.44, 0.44 * 41.0 / 30.0)),
		"art: fit takes the limiting side")


# --- card ----------------------------------------------------------------------

func _group_card() -> void:
	for sid: String in ["arcade", "neogeo", "daphne", "dice"]:
		var items := SpawnCatalog.items_for(sid)
		var labels: Array = items.map(func(i: Dictionary) -> String: return str(i.get("label", "")))
		var models: Array = items.map(func(i: Dictionary) -> String: return str(i.get("model_id", "")))
		for id: String in VARIANTS:
			if VARIANTS[id][0] == sid:
				_ok(models.has(id), "card: the %s card offers %s" % [sid, id])
		_ok(not labels.has("Primitive System"), "card: %s has no imaginary box beside its cabinets" % sid)
		# Neo Geo also has the consolized console, which has phono jacks and takes the lead.
		_ok(labels.has("Composite Cable") == (sid == "neogeo"),
			"card: %s %s a video lead (%s)" % [sid, "offers" if sid == "neogeo" else "has no", "the console's" if sid == "neogeo" else "the monitor is part of it"])
	_ok(SpawnCatalog.items_for("daphne").any(func(i: Dictionary) -> bool: return i.get("label", "") == "Light Gun"),
		"card: Daphne offers a gun for its sockets (the laserdisc shooters)")
	_ok(not SpawnCatalog.items_for("neogeo").any(func(i: Dictionary) -> bool: return i.get("label", "") == "Light Gun"),
		"card: Neo Geo never had one")


# --- stand ---------------------------------------------------------------------

func _group_stand() -> void:
	# The pure half: what turns a tilted body upright, and what it leaves alone.
	var upright := RetroSystemModelArcadeCabinet.right_angular_velocity(Vector3.UP, Vector3(0, 1.5, 0))
	_ok(upright.is_equal_approx(Vector3(0, 1.5, 0)), "stand: an upright cabinet is left alone, and so is a spin about UP")
	var lean := Basis(Vector3.RIGHT, 0.5).y
	var w := RetroSystemModelArcadeCabinet.right_angular_velocity(lean, Vector3.ZERO)
	_ok(w.length() > 0.5 and absf(w.y) < 1e-4, "stand: a leaning one is turned about the horizontal, not the heading")
	# Turning by w moves its up toward the world's up.
	var after := (Basis(w.normalized(), w.length() * 0.05) * lean).normalized()
	_ok(after.angle_to(Vector3.UP) < lean.angle_to(Vector3.UP), "stand: and the turn is TOWARD upright, not away")
	var far := RetroSystemModelArcadeCabinet.right_angular_velocity(Basis(Vector3.RIGHT, 1.4).y, Vector3.ZERO)
	_ok(far.length() <= RetroSystemModelArcadeCabinet.RIGHT_MAX + 1e-4, "stand: and it never spins faster than its cap")
	var flipped := RetroSystemModelArcadeCabinet.right_angular_velocity(Vector3.DOWN, Vector3.ZERO)
	_ok(flipped.length() > 0.5, "stand: even upside down it turns, about some horizontal axis")

	# The physical half: a body on a floor, let go leaning and turned.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	col.shape = box
	ground.add_child(col)
	ground.position = Vector3(0, -0.1, 0)
	add_child(ground)
	_spawned.append(ground)
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = "arcade_cabinet_generic"
	sys.systemid = "arcade"
	sys.freeze = false
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(10)
	_ok(not sys.freeze and sys.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM \
		and sys.center_of_mass.y > 0.2 and sys.center_of_mass.y < 0.6,
		"stand: its weight is low, in the base (%.2f m up)" % sys.center_of_mass.y)
	_ok(not sys.axis_lock_angular_x and not sys.axis_lock_angular_z, "stand: and nothing locks it at the tilt it was let go at")
	var heading := Basis(Vector3.UP, 0.9)
	sys.global_transform = Transform3D(heading * Basis(Vector3.RIGHT, 0.45) * Basis(Vector3.BACK, -0.25), Vector3(0, 0.6, 0))
	sys.angular_velocity = Vector3.ZERO
	await _wait(240)
	var tilt := sys.global_transform.basis.y.angle_to(Vector3.UP)
	_ok(tilt < 0.02, "stand: let go leaning, it stands again (%.4f rad off)" % tilt)
	var fwd := sys.global_transform.basis.z
	var yaw := atan2(fwd.x, fwd.z)
	_ok(absf(angle_difference(yaw, 0.9)) < 0.25, "stand: and still faces the way it was turned (%.2f rad)" % yaw)
	# The controller itself, with gravity out of it (a base on a floor rights a body by weight alone, which
	# would hide it): a body leaning in mid-air is turned upright by the controller and nothing else.
	sys.gravity_scale = 0.0
	sys.global_transform = Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.6), Vector3(5, 3, 5))
	sys.angular_velocity = Vector3.ZERO
	sys.linear_velocity = Vector3.ZERO
	await _wait(240)
	var floating := sys.global_transform.basis.y.angle_to(Vector3.UP)
	_ok(floating < 0.02, "stand: with no gravity to help it, the controller alone stands it up (%.4f rad off)" % floating)
	sys.gravity_scale = 1.0
	# Let go upright, it stays upright.
	sys.global_transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 0.6, 0))
	sys.angular_velocity = Vector3.ZERO
	await _wait(120)
	_ok(sys.global_transform.basis.y.angle_to(Vector3.UP) < 0.01, "stand: let go upright, it stays upright")
	# A frozen one is not touched.
	sys.freeze = true
	sys.global_transform = Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0, 0.6, 0))
	await _wait(30)
	_ok(sys.global_transform.basis.y.angle_to(Vector3.UP) > 0.3, "stand: a pinned cabinet stays as it was put")
	await _clear()


# --- neogeo --------------------------------------------------------------------

## The union of every mesh's box under `root`, in `root`'s frame.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi is Label3D or not vi.visible:
			continue
		var local := (vi as Node3D).transform
		var parent := vi.get_parent()
		while parent != null and parent != root:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		var b := local * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _group_neogeo() -> void:
	_ok(ArcadeProfiles.NEOGEO_CART_SCENE != ArcadeProfiles.BOARD_SCENE,
		"neogeo: an MVS game is not drawn as a JAMMA board")
	_ok(ResourceLoader.exists(ArcadeProfiles.NEOGEO_CART_SCENE), "neogeo: its cassette is baked")
	_ok(RetroCartridge._CART_MODELS.get("neogeo", "") == ArcadeProfiles.NEOGEO_CART_SCENE,
		"neogeo: and a Neo Geo ROM spawns wearing it")
	var cart := (load(ArcadeProfiles.NEOGEO_CART_SCENE) as PackedScene).instantiate() as Node3D
	var size := MediaDimensions.cart_size("neogeo", "")
	var box := _bounds(cart)
	_ok(box.size.is_equal_approx(size) or (box.size - size).length() < 0.002,
		"neogeo: the cassette is the size the table says (%s against %s)" % [str(box.size), str(size)])
	_ok(size.x > size.y and size.z < 0.04, "neogeo: wider than tall and thin, a cassette and not a board")
	var fingers := 0
	for mm in cart.find_children("*", "MultiMeshInstance3D", true, false):
		fingers += (mm as MultiMeshInstance3D).multimesh.instance_count
	_ok(fingers == 240, "neogeo: the edge connector has its 240 contacts (%d)" % fingers)
	var label := cart.find_child("Label", true, false) as MeshInstance3D
	_ok(label != null and label.position.z > 0.0, "neogeo: the label is on the front, +Z")
	_ok(box.position.y < label.position.y - 0.05, "neogeo: and the connector edge is the bottom, -Y")
	cart.free()
	# The cabinet: a rectangular unit with the slot, and the cassette's edge goes into it.
	var sys := await _machine("arcade_cabinet_neogeo", "neogeo")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	# The unit is the bay's now, a separate object clipped into the cabinet's mount.
	var bay: ArcadeBayUnit = (sys as RetroSystem).get_bay()
	_ok(bay != null and bay.bay_kind == "mvs", "neogeo: the cabinet comes with its own kind of bay")
	_ok(bay.find_child("MvsTray", true, false) != null and bay.find_child("MvsSlot", true, false) != null,
		"neogeo: the bay holds the MVS unit, a tray with the slot")
	_ok(bay.find_child("JammaSocket", true, false) == null, "neogeo: and no JAMMA socket")
	var tray := (bay.find_child("MvsTray", true, false) as MeshInstance3D)
	_ok(tray.get_aabb().size.x > tray.get_aabb().size.z, "neogeo: the unit is a wide rectangle")
	var slot := bay.find_child("MvsSlot", true, false) as MeshInstance3D
	var slot_top := slot.position.y + slot.get_aabb().size.y * 0.5
	var seat := bay.find_child("CartSeat", true, false) as Node3D
	var tip := seat.position.y - size.y * 0.5
	_ok(tip < slot_top and tip > slot_top - 0.03, "neogeo: the cassette's edge goes into the slot (%.3f m deep)" % (slot_top - tip))
	var generic := await _machine("arcade_cabinet_generic", "arcade")
	_ok((generic as RetroSystem).get_bay() != null and (generic as RetroSystem).get_bay().find_child("MvsTray", true, false) == null,
		"neogeo: the other cabinets have no MVS unit")


# --- console -------------------------------------------------------------------

func _group_console() -> void:
	var rows := SystemModelRegistry.rows_for("neogeo")
	var ids: Array = rows.map(func(r: Dictionary) -> String: return str(r["id"]))
	_ok(ids.has("arcade_cabinet_neogeo") and ids.has("neogeo_mvs_console"), "console: the Neo Geo tile offers the cabinet AND the console")
	_ok(ids[0] == "arcade_cabinet_neogeo", "console: and the cabinet stays the default")
	var sys := await _machine("neogeo_mvs_console", "neogeo", 20)
	var model := sys.get_model() as RetroSystemModelNeoGeoConsole
	_ok(model != null, "console: it wears the Neo Geo console model")
	if model == null:
		return
	_ok(model.brings_own_body() and not model.is_handheld(), "console: it draws its own body and is not held")
	_ok(model.get_controller_port_count() == 2, "console: two controller ports")
	_ok(model.av_port_channels().size() == 3, "console: picture and stereo sound on three phono jacks, like a SNES")
	_ok(model.uses_av_ports(), "console: so it takes the composite lead, not a captive cord")
	var back := model.find_child("AvSeat1", true, false) as Node3D
	var front := model.find_child("PortSeat1", true, false) as Node3D
	_ok(back != null and front != null and back.position.z < 0.0 and front.position.z > 0.0,
		"console: the jacks are on the back and the ports on the front")
	_ok(model.find_child("JammaSocket", true, false) == null and model.find_child("MvsTray", true, false) == null,
		"console: and no cabinet parts")
	# The cassette stands in the slot on the roof, edge in, label to the front.
	var slot := sys.get_node("CartridgeSlot") as XRToolsSnapZone
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "neogeo"
	cart.rom_path = "/tmp/console_test.zip"
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(8)
	slot.pick_up_object(cart)
	await _wait(6)
	_ok(sys.rom_path == "/tmp/console_test.zip", "console: the cassette in the slot is the machine's game")
	var seat := model.find_child("CartSeat", true, false) as Node3D
	_ok(cart.global_position.distance_to(seat.global_position) < 0.02, "console: and it stands in the slot")
	_ok(cart.global_transform.basis.y.dot(Vector3.UP) > 0.99 and cart.global_transform.basis.z.dot(Vector3.BACK) > 0.99,
		"console: edge down, label to the front")
	var housing := model.find_child("SlotHousing", true, false) as MeshInstance3D
	var slot_top := housing.position.y + housing.get_aabb().size.y * 0.5
	var tip := seat.position.y - MediaDimensions.cart_size("neogeo", "").y * 0.5
	_ok(tip < slot_top and tip > slot_top - 0.03, "console: its edge goes into the slot (%.3f m deep)" % (slot_top - tip))
	# The card: both machines, a pad, a gun is not there, and the composite lead is.
	var items := SpawnCatalog.items_for("neogeo")
	var labels: Array = items.map(func(i: Dictionary) -> String: return str(i.get("label", "")))
	_ok(labels.has("Primitive Neo Geo AES") and labels.has("Primitive Neo Geo MVS"), "console: the card lists both by name")
	_ok(labels.has("Composite Cable"), "console: and a video lead, for the console (the cabinet needs none)")
	_ok(labels.has("Primitive Controller"), "console: and a pad")
	_ok(not SpawnCatalog.items_for("arcade").any(func(i: Dictionary) -> bool: return i.get("label", "") == "Composite Cable"),
		"console: while the arcade card still offers no lead")


# --- names ---------------------------------------------------------------------

func _group_names() -> void:
	for folder: String in ["neogeomvs", "neogeoaes", "neogeo"]:
		_ok(SystemIds.systemid_for_folder(folder) == "neogeo", "names: the ROM folder %s is Neo Geo's" % folder)
	for slug: String in ["neogeomvs", "neogeoaes", "neo-geo-mvs", "neo-geo-aes", "neogeo"]:
		var got := RommPlatforms.systemid_for({"slug": slug, "fs_slug": slug})
		_ok(got == "neogeo", "names: RomM's %s is Neo Geo (%s)" % [slug, got])
	_ok(RommPlatforms.systemid_for({"slug": "neo-geo-cd", "fs_slug": "neogeocd"}) == "neogeocd",
		"names: and the Neo Geo CD is still its own system")


# --- shooting ------------------------------------------------------------------

func _group_shooting() -> void:
	var generic := await _machine("arcade_cabinet_generic", "arcade")
	var gmodel := generic.get_model() as RetroSystemModelArcadeCabinet
	var gscreen := gmodel.get_builtin_screen()
	var gquad := gscreen.mesh as QuadMesh
	for id: String in ["gun", "arcade_cabinet_daphne_gun"]:
		var sys := await _gun_machine(id, 12)
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		var screen := model.get_builtin_screen()
		var quad := screen.mesh as QuadMesh
		_ok(quad.size.x >= gquad.size.x * 1.5 - 0.001 and quad.size.y >= gquad.size.y * 1.5 - 0.001,
			"shooting: %s's tube is at least half as big again as the upright's (%.2f x %.2f against %.2f x %.2f)"
			% [id, quad.size.x, quad.size.y, gquad.size.x, gquad.size.y])
		# Straight: the glass faces the player (+Z of the cabinet), not up and back like the upright's.
		var normal := (model.global_transform.affine_inverse() * screen.global_transform).basis.z.normalized()
		_ok(normal.dot(Vector3.BACK) > 0.999, "shooting: the screen is STRAIGHT, not leaning (%.4f)" % normal.dot(Vector3.BACK))
		var gnormal := (gmodel.global_transform.affine_inverse() * gscreen.global_transform).basis.z.normalized()
		_ok(gnormal.dot(Vector3.BACK) < 0.95, "shooting: while the upright's still leans back")
		_ok(model.cabinet_width >= 0.85 and model.cabinet_width > gmodel.cabinet_width,
			"shooting: and the cabinet is wider to hold it (%.2f m)" % model.cabinet_width)
		_ok(model.screen_front_z < gmodel.screen_front_z, "shooting: its glass is where the straight screen is (z %.2f)" % model.screen_front_z)
		# The glass is inside the cabinet's width, and so is everything on the front.
		var fits := true
		for i in 2:
			var h := (model.find_child("Holster%d" % (i + 1), true, false) as Node3D).position
			fits = fits and absf(h.x) < model.cabinet_width * 0.5 - 0.05
		_ok(fits, "shooting: and the holsters stand inside it")
		var tube_edge := quad.size.x * 0.5
		_ok(tube_edge < model.cabinet_width * 0.5 - 0.05, "shooting: the tube fits between the side panels")
		# The collision follows the shape: a box for the front under the straight screen as well.
		var host_boxes := 0
		for c in sys.get_children():
			if c is CollisionShape3D:
				host_boxes += 1
		var gen_boxes := 0
		for c in generic.get_children():
			if c is CollisionShape3D:
				gen_boxes += 1
		_ok(host_boxes > gen_boxes, "shooting: %s has a collision box for the coin face the straight screen leaves open (%d against %d)" % [id, host_boxes, gen_boxes])


# --- holster -------------------------------------------------------------------

func _group_holster() -> void:
	var sys := await _gun_cabinet("ptblank", 120)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var guns := sys.captive_controllers()
	for i in guns.size():
		var gun := guns[i] as LightGun
		var well := gun.captive_well
		_ok(well != null and well.picked_up_object == gun, "holster: gun %d sits in its holster to begin with" % (i + 1))
		_ok(gun.press_to_hold, "holster: gun %d is held while the button is held, so letting go lets go" % (i + 1))
		if well == null:
			continue
		var home := gun.global_position
		# Taken out and carried off: the holster's own let-go would send it straight back, so it is
		# parted from it first (a hand does this in the same frame it takes hold).
		gun.captive_well = null
		well.drop_object()
		await _wait(2)
		_ok(well.picked_up_object != gun, "holster: taken out, it is out of the holster")
		gun.global_position = home + Vector3(0.0, 0.2, 0.9)
		gun.freeze = false
		await _wait(2)
		_ok(gun.global_position.distance_to(home) > 0.5, "holster: and carried a metre off")
		# Let go a metre away: it is NOT pulled back into the holster, it falls where it is.
		gun.captive_well = well
		gun.dropped.emit(gun)
		await _wait(40)
		_ok(well.picked_up_object != gun, "holster: let go away from it, gun %d is not pulled back (it falls)" % (i + 1))
		_ok(not gun._allow_drop, "holster: and the drop is not left armed for the next grab")
		# Let go AT the holster: the zone takes it, exactly where it hung.
		gun.global_position = home
		gun.linear_velocity = Vector3.ZERO
		await _wait(4)
		gun.dropped.emit(gun)
		await _wait(40)
		_ok(well.picked_up_object == gun, "holster: let go at the holster, gun %d goes in" % (i + 1))
		_ok(gun.global_position.distance_to(home) < 0.03, "holster: exactly where it hung (%.3f m off)" % gun.global_position.distance_to(home))
		_ok(gun.get_connected_system() == sys, "holster: and is still plugged in")
