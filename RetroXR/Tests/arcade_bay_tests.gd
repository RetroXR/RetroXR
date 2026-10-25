## Arcade bay self-tests — the bay as an object of its own, clipped into a cabinet or cabled to it.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_bay_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_bay_tests.tscn -- --only=frank
##
## No ROM, core or headset: a board is a cartridge scene with a path that points at nothing, and the
## cabinet's game is whatever `rom_path` says it is (nothing is powered on).
##
## Groups (a pass here that cannot go red is not a pass -- see docs/dev/arcade.md):
##   default/   every cabinet comes with its own kind of bay already clipped into the mount
##   follow/    the bay in the mount rides with the cabinet, rigid, and nothing is left behind when it moves
##   pull/      taking the bay out stops the game, the board stays in the bay, and the slot is the bay's again
##   frank/     another kind of bay in the cabinet makes it play THAT system, and refuses the old one's boards
##   cable/     a JAMMA lead joins a free bay to a cabinet, is refused for a docked one, and lets go when pulled
##   inside/    from INSIDE the cabinet, above the compartment, a pointer ray and a hand reach the bay: no wall
##   ext/       a machine cabled to the bay's phono IN is the cabinet's picture source, and only while cabled
##   disc/      the JAMMA bay has a CD-ROM bay under it: a disc rides in and out, EJECT pushes it half out,
##              a game with a disc will not start without both, and each says what it is missing
##   names/     the four kinds have scenes, labels and a card row, and the lead is a lead the room can restore
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/jamma_cable.tscn")
const COMPOSITE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")

## id -> [systemid, bay kind]
const CABINETS := {
	"arcade_cabinet_generic": ["arcade", "jamma"],
	"arcade_cabinet_neogeo": ["neogeo", "mvs"],
	"arcade_cabinet_daphne": ["daphne", "laserdisc"],
	"arcade_cabinet_daphne_gun": ["daphne", "laserdisc"],
	"arcade_cabinet_dice": ["dice", "discrete"],
}

var _checks := 0
var _failed := 0
var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[bay] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[bay] %d checks, %d failed" % [_checks, _failed])
	print("[bay] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[bay] %s  %s" % ["PASS" if ok else "FAIL", what])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


## A cabinet in the tree, given time to build itself and seed its bay (a deferred call).
func _cabinet(model_id: String, systemid: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 2.5, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(10)
	return sys


func _bay(kind: String, at: Vector3) -> ArcadeBayUnit:
	var bay := ArcadeBayUnit.scene_for(kind).instantiate() as ArcadeBayUnit
	bay.position = at
	add_child(bay)
	_spawned.append(bay)
	await _wait(4)
	return bay


func _board(systemid: String, at: Vector3) -> Node3D:
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = systemid
	cart.rom_path = "/tmp/arcade_bay_test_%s.zip" % systemid
	cart.position = at
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(6)
	return cart


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	for bay in get_tree().get_nodes_in_group(ArcadeBayUnit.GROUP):
		bay.queue_free()
	_spawned.clear()
	await _wait(6)


func _mount_of(sys: RetroSystem) -> XRToolsSnapZone:
	return sys.find_child("BayMountZone", true, false) as XRToolsSnapZone


func _run() -> void:
	if _want("default"):
		await _group_default()
	if _want("follow"):
		await _group_follow()
	if _want("pull"):
		await _group_pull()
	if _want("frank"):
		await _group_frank()
	if _want("cable"):
		await _group_cable()
	if _want("inside"):
		await _group_inside()
	if _want("ext"):
		await _group_ext()
	if _want("disc"):
		await _group_disc()
	if _want("names"):
		_group_names()


# --- disc ----------------------------------------------------------------------

const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")
const DISC_ROOT := "user://arcade_disc_test"


## roms/arcade as a game with a disc leaves it: thisgame.zip + thisgame/a.chd, other.zip + other/b.chd,
## and a plain board with no folder.
func _disc_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(DISC_ROOT.path_join("thisgame"))
	DirAccess.make_dir_recursive_absolute(DISC_ROOT.path_join("other"))
	for f: String in ["thisgame.zip", "other.zip", "plain.zip", "thisgame/a.chd", "other/b.chd"]:
		var h := FileAccess.open(DISC_ROOT.path_join(f), FileAccess.WRITE)
		h.store_8(1)
		h.close()


func _disc_cleanup() -> void:
	for f: String in ["thisgame/a.chd", "other/b.chd", "thisgame.zip", "other.zip", "plain.zip"]:
		DirAccess.remove_absolute(DISC_ROOT.path_join(f))
	for d: String in ["thisgame", "other"]:
		DirAccess.remove_absolute(DISC_ROOT.path_join(d))
	DirAccess.remove_absolute(DISC_ROOT)


func _disc(rom: String) -> RetroDisc:
	var disc := DISC_SCENE.instantiate() as RetroDisc
	disc.systemid = "arcade"
	disc.rom_path = ProjectSettings.globalize_path(DISC_ROOT.path_join(rom))
	disc.game_label = rom
	disc.position = Vector3(0, 3, 0)
	disc.freeze = true
	add_child(disc)
	_spawned.append(disc)
	await _wait(6)
	return disc


func _group_disc() -> void:
	_disc_fixture()
	var root := ProjectSettings.globalize_path(DISC_ROOT)
	# What ArcadeDiscs says about the files.
	_ok(ArcadeDiscs.needs_disc(root.path_join("thisgame.zip")), "disc: a zip with a folder of CHDs needs a disc")
	_ok(not ArcadeDiscs.needs_disc(root.path_join("plain.zip")), "disc: a zip with none is a plain board")
	_ok(ArcadeDiscs.belongs_to(root.path_join("thisgame/a.chd"), root.path_join("thisgame.zip")), "disc: its CHD belongs to it")
	_ok(not ArcadeDiscs.belongs_to(root.path_join("other/b.chd"), root.path_join("thisgame.zip")), "disc: another game's does not")
	_ok(ArcadeDiscs.board_for(root.path_join("thisgame/a.chd")) == root.path_join("thisgame.zip"), "disc: a CHD names its board")

	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var bay := sys.get_bay()
	if bay == null:
		_ok(false, "disc: no bay")
		_disc_cleanup()
		return
	_ok(bay.has_drive() and bay.disc_slot != null, "disc: the JAMMA bay has a CD-ROM bay under it")
	_ok(bay.find_child("EjectButton", true, false) != null, "disc: with an EJECT button")
	_ok(sys.arcade_disc_gap().is_empty(), "disc: an empty cabinet is missing nothing")

	# A plain board plays alone.
	var plain := await _board("arcade", Vector3(0, 3, 0))
	plain.rom_path = root.path_join("plain.zip")
	bay.slot.pick_up_object(plain)
	await _wait(6)
	_ok(sys.arcade_disc_gap().is_empty(), "disc: a board with no disc folder needs no disc")
	bay.slot.drop_object()
	await _wait(4)

	# The board of a disc game, alone: the disc is what is missing.
	var board := await _board("arcade", Vector3(0, 3, 0))
	board.rom_path = root.path_join("thisgame.zip")
	bay.slot.pick_up_object(board)
	await _wait(6)
	_ok(sys.arcade_disc_gap() == "This game also requires a Disc, please insert Disc.",
		"disc: the board alone says it needs the Disc (%s)" % sys.arcade_disc_gap())
	# The control: it must not start. (Started with no core installed, the verdict would be about the core.)
	var disc := await _disc("thisgame/a.chd")
	_ok(not bay.accepts_board(disc), "disc: the board's slot refuses a disc")
	_ok(not sys.call("_accepts_media", disc), "disc: and so does the cabinet's own gate")
	_ok(bay.accepts_disc(disc) and not bay.accepts_disc(board), "disc: the drive takes a disc and not a board")
	bay.disc_slot.pick_up_object(disc)
	await _wait(40)
	_ok(bay.get_disc() == disc, "disc: the disc rides into the drive (%s)" % bay.get_disc())
	_ok(sys.arcade_disc_gap().is_empty(), "disc: board and disc together, nothing is missing")

	# EJECT pushes it half out; it is no longer read.
	bay.eject_disc()
	await _wait(60)
	_ok(bay.get_disc() == null, "disc: EJECT, and the drive reads nothing")
	_ok(sys.arcade_disc_gap() == "This game also requires a Disc, please insert Disc.",
		"disc: the game is missing its disc again")
	var mouth := bay.disc_slot.global_position
	_ok(disc.global_position.distance_to(mouth) < 0.03,
		"disc: it waits at the slot's mouth, half out (%.3f m from it)" % disc.global_position.distance_to(mouth))
	bay.eject_disc()
	await _wait(60)
	_ok(bay.get_disc() == disc and sys.arcade_disc_gap().is_empty(), "disc: EJECT again draws it back in")

	await _clear()

	# Another game's disc is not this game's.
	sys = await _cabinet("arcade_cabinet_generic", "arcade")
	bay = sys.get_bay()
	board = await _board("arcade", Vector3(0, 3, 0))
	board.rom_path = root.path_join("thisgame.zip")
	bay.slot.pick_up_object(board)
	var wrong := await _disc("other/b.chd")
	bay.restore_disc(wrong)
	await _wait(10)
	_ok(sys.arcade_disc_gap().begins_with("This Disc belongs to another game"),
		"disc: the wrong game's disc is refused by name (%s)" % sys.arcade_disc_gap())
	await _clear()

	# A disc alone.
	sys = await _cabinet("arcade_cabinet_generic", "arcade")
	bay = sys.get_bay()
	var alone := await _disc("thisgame/a.chd")
	bay.restore_disc(alone)
	await _wait(10)
	_ok(sys.arcade_disc_gap() == "This game also requires a JAMMA Board, please insert JAMMA Board.",
		"disc: a disc alone says it needs the JAMMA Board (%s)" % sys.arcade_disc_gap())
	await _clear()

	# Only the JAMMA bay has a drive.
	for kind: String in ["mvs", "laserdisc", "discrete"]:
		var other := await _bay(kind, Vector3(0, 0, 3))
		_ok(not other.has_drive(), "disc: the %s bay has no CD-ROM bay" % kind)
	await _clear()
	_disc_cleanup()


# --- default -------------------------------------------------------------------

func _group_default() -> void:
	for id: String in CABINETS:
		var spec: Array = CABINETS[id]
		var sys := await _cabinet(id, spec[0])
		var bay := sys.get_bay()
		_ok(bay != null, "default: %s comes with a bay" % id)
		if bay == null:
			await _clear()
			continue
		_ok(bay.bay_kind == spec[1], "default: and it is the %s kind (%s)" % [spec[1], bay.bay_kind])
		_ok(bay.is_docked() and sys.bay_link_kind() == ArcadeBayUnit.DOCK, "default: clipped into the mount")
		_ok(sys.systemid == spec[0], "default: and the cabinet still plays %s" % spec[0])
		_ok(bay.slot != null and bay.slot.snap_filter == Callable(sys, "_accepts_media"), "default: the board's slot is the bay's, with the cabinet's own gate")
		await _clear()


# --- follow --------------------------------------------------------------------

func _group_follow() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var bay := sys.get_bay()
	if bay == null:
		_ok(false, "follow: no bay to follow")
		return
	var rel := sys.global_transform.affine_inverse() * bay.global_transform
	sys.global_position += Vector3(1.5, 0, -0.7)
	sys.rotate_y(0.6)
	await _wait(10)
	var after := sys.global_transform.affine_inverse() * bay.global_transform
	_ok(rel.origin.distance_to(after.origin) < 0.01,
		"follow: moved and turned, the bay is still where it was in the cabinet (off by %.4f m)" % rel.origin.distance_to(after.origin))
	_ok(rel.basis.z.dot(after.basis.z) > 0.999, "follow: and faces the way it did")
	await _clear()


# --- pull ----------------------------------------------------------------------

func _group_pull() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var bay := sys.get_bay()
	if bay == null:
		_ok(false, "pull: no bay to pull")
		return
	model.set_lid_angle_deg(90.0)
	var cart := await _board("arcade", Vector3(0, 3, 0))
	bay.slot.pick_up_object(cart)
	await _wait(6)
	_ok(sys.rom_path == "/tmp/arcade_bay_test_arcade.zip", "pull: the board in the bay is the cabinet's game")
	_mount_of(sys).drop_object()
	await _wait(6)
	_ok(sys.get_bay() == null and sys.bay_link_kind().is_empty(), "pull: out of the mount, the cabinet has no bay")
	_ok(sys.rom_path.is_empty(), "pull: and no game")
	_ok(bay.get_board() == cart, "pull: the board stays in the bay")
	_ok(not bay.is_docked() and bay.get_host() == null, "pull: the bay is free")
	_ok(not (sys.get_node("CartridgeSlot") as XRToolsSnapZone).enabled, "pull: the cabinet's own slot is shut")
	# Put it back: the board is already in it, and the cabinet hears that.
	bay.global_position = _mount_of(sys).global_position
	_mount_of(sys).pick_up_object(bay)
	await _wait(6)
	_ok(sys.get_bay() == bay and sys.rom_path == "/tmp/arcade_bay_test_arcade.zip",
		"pull: clipped back in, its board is the game again")
	await _clear()


# --- frank ---------------------------------------------------------------------

func _group_frank() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	if sys.get_bay() == null:
		_ok(false, "frank: no bay to swap")
		return
	var mount := _mount_of(sys)
	mount.drop_object()
	await _wait(4)
	var mvs := await _bay("mvs", mount.global_position + Vector3(0, 1.0, 0))
	mount.pick_up_object(mvs)
	await _wait(6)
	_ok(sys.get_bay() == mvs, "frank: an MVS bay in the generic cabinet")
	_ok(sys.systemid == "neogeo", "frank: and the cabinet plays Neo Geo (%s)" % sys.systemid)
	var neo := await _board("neogeo", Vector3(3, 3, 0))
	var arc := await _board("arcade", Vector3(3, 3, 1))
	_ok(sys._accepts_media(neo), "frank: it takes a Neo Geo cassette")
	_ok(not sys._accepts_media(arc), "frank: and not a JAMMA board")
	model.set_lid_angle_deg(90.0)
	mvs.slot.pick_up_object(neo)
	await _wait(6)
	_ok(sys.rom_path == "/tmp/arcade_bay_test_neogeo.zip", "frank: the cassette is the game")
	# And back the other way.
	mount.drop_object()
	await _wait(4)
	var jamma := await _bay("jamma", mount.global_position + Vector3(0, 1.0, 0))
	mount.pick_up_object(jamma)
	await _wait(6)
	_ok(sys.systemid == "arcade" and sys._accepts_media(arc) and not sys._accepts_media(neo),
		"frank: a JAMMA bay puts it back (%s)" % sys.systemid)
	await _clear()


# --- cable ---------------------------------------------------------------------

func _group_cable() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var docked := sys.get_bay()
	if docked == null:
		_ok(false, "cable: no bay to start from")
		return
	var cab_port := sys.find_child("JammaPort", true, false) as JammaPort
	_ok(cab_port != null and cab_port.get_cabinet() == sys, "cable: the cabinet has a JAMMA socket on its back")
	var mount := _mount_of(sys)
	mount.drop_object()
	await _wait(4)
	_ok(sys.get_bay() == null, "cable: bay out")
	var far := await _bay("jamma", Vector3(sys.position.x + 1.5, 0.2, 0))
	var bay_port := far.find_child("JammaPort", true, false) as JammaPort
	_ok(bay_port != null and bay_port.get_bay() == far, "cable: and the bay has one")
	var lead := CABLE_SCENE.instantiate() as JammaCable
	add_child(lead)
	_spawned.append(lead)
	lead.global_position = Vector3(sys.position.x + 0.7, 0.9, 0)
	await _wait(3)
	cab_port.pick_up_object(lead.get_node("PlugA0"))
	await _wait(6)
	_ok(sys.get_bay() == null, "cable: one end in is nothing")
	bay_port.pick_up_object(lead.get_node("PlugB0"))
	await _wait(10)
	_ok(sys.get_bay() == far and sys.bay_link_kind() == ArcadeBayUnit.CABLE and far.link_kind() == ArcadeBayUnit.CABLE,
		"cable: both ends in, the cabinet plays from the bay")
	_ok(not far.is_docked(), "cable: a cabled bay is not a docked one")
	# A board put in the far bay is the cabinet's game, without a door in the way.
	var cart := await _board("arcade", Vector3(0, 3, 3))
	far.slot.pick_up_object(cart)
	await _wait(6)
	_ok(sys.rom_path == "/tmp/arcade_bay_test_arcade.zip", "cable: the board in the far bay is the game")
	cab_port.drop_object()
	await _wait(10)
	_ok(sys.get_bay() == null and sys.rom_path.is_empty(), "cable: a plug pulled and the cabinet has no bay and no game")
	_ok(far.get_board() == cart, "cable: the board stays in the bay")
	# A bay in the mount is joined by the mount: a lead to it joins nothing.
	cab_port.pick_up_object(lead.get_node("PlugA0"))
	mount.pick_up_object(docked)
	await _wait(8)
	_ok(sys.get_bay() == docked and sys.bay_link_kind() == ArcadeBayUnit.DOCK, "cable: the docked bay is the cabinet's")
	_ok(far.get_host() == null, "cable: the cabled one let go when the mount took a bay")
	await _clear()


# --- inside --------------------------------------------------------------------

## A player leaning into the cabinet (the compartment has no ceiling) reaches the bay from above. The
## upper body used to be one solid block over it: an invisible wall for a hand, and a pointer box that
## stopped every ray on its top face.
func _group_inside() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var bay := sys.get_bay()
	if bay == null:
		_ok(false, "inside: no bay")
		return
	var space := sys.get_world_3d().direct_space_state
	var top := sys.global_transform * Vector3(0.0, 1.2, -0.05)
	var down := sys.global_transform * Vector3(0.0, 0.12, -0.05)
	# A pointer ray (layer 21): the first thing it finds on the way down is the bay's own pointer box.
	var ray := PhysicsRayQueryParameters3D.create(top, down, 1 << 20)
	var hit := space.intersect_ray(ray)
	_ok(not hit.is_empty() and bay.is_ancestor_of(hit["collider"] as Node),
		"inside: a pointer ray from inside, aimed down, finds the bay (%s)" % [hit.get("collider", "nothing")])
	# The cabinet's own solid body is not in the way of a hand inside it: a small sphere (a hand) held at
	# several heights above the compartment overlaps nothing of the cabinet. A ray cannot say this (one that
	# starts inside a solid is not hit by it), a volume can.
	var hand := SphereShape3D.new()
	hand.radius = 0.04
	var blocked := []
	for y in [0.55, 0.75, 1.0, 1.25]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = hand
		q.transform = Transform3D(Basis(), sys.global_transform * Vector3(0.0, y, -0.1))
		q.collision_mask = sys.collision_layer
		q.exclude = [bay.get_rid()]
		for found in space.intersect_shape(q, 8):
			if found["collider"] == sys:
				blocked.append(y)
	_ok(blocked.is_empty(), "inside: and a hand inside the cabinet meets none of its body at heights %s" % [blocked])
	# And from the front the cabinet is still found where it is aimed at plain panel (the back wall).
	var front := PhysicsRayQueryParameters3D.create(
		sys.global_transform * Vector3(0.0, 0.64, 1.0), sys.global_transform * Vector3(0.0, 0.64, 0.0), 1 << 20)
	var plain := space.intersect_ray(front)
	_ok(not plain.is_empty() and (plain["collider"] == sys.get_node("PointerArea") or sys.is_ancestor_of(plain["collider"] as Node)),
		"inside: while a ray from the front at the plain coin face still finds the cabinet")
	await _clear()


# --- ext -----------------------------------------------------------------------

## The cabinet's composite input (ArcadeAvInModule): present always, taking input only while the compartment holds
## no unit; with a unit in, cords can be plugged and carry nothing.
func _group_ext() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var av := model.av_in()
	_ok(av != null, "ext: the cabinet has a composite input block")
	if av == null:
		return
	var video_in := sys.find_child("VideoIn", true, false) as RcaPort
	_ok(video_in != null and video_in.direction == RcaPort.Direction.IN and video_in.get_device() == sys,
		"ext: its VIDEO IN is a socket of the cabinet, not of a bay unit")
	_ok(sys.find_child("AudioLIn", true, false) != null and sys.find_child("AudioRIn", true, false) != null, "ext: and the two audio INs")
	_ok(sys.get_bay() != null and sys.get_bay().find_child("VideoIn", true, false) == null, "ext: and the bay unit has none")
	_ok(not av.is_enabled(), "ext: with a unit in the bay the block takes no input")
	var console := SYSTEM_SCENE.instantiate() as RetroSystem
	console.systemid = "nes"
	console.position = Vector3(8, 0, 0)
	console.freeze = true
	add_child(console)
	_spawned.append(console)
	await _wait(8)
	var lead := COMPOSITE_SCENE.instantiate() as Node3D
	add_child(lead)
	_spawned.append(lead)
	lead.global_position = Vector3(6, 0.9, 0)
	await _wait(3)
	var out := console.get_node_or_null("VideoOut") as RcaPort
	_ok(out != null, "ext: the console has a VIDEO OUT")
	if out == null or video_in == null:
		return
	_ok(av.source() == null, "ext: nothing cabled, no source")
	out.pick_up_object(lead.get_node("PlugA0"))
	video_in.pick_up_object(lead.get_node("PlugB0"))
	await _wait(8)
	_ok(av.source() == console, "ext: a console cabled to VIDEO IN is the source (cords connected, block idle)")
	_ok(av.external_picture() == null and not model.external_picture_active(), "ext: but with a unit in the bay it carries nothing")
	# Empty the compartment: the block is live.
	_mount_of(sys).drop_object()
	await _wait(6)
	_ok(sys.get_bay() == null and av.is_enabled(), "ext: the bay empty, the block takes input")
	_ok(av.source() == console, "ext: and the console that was cabled all along is its source")
	video_in.drop_object()
	await _wait(8)
	_ok(av.source() == null, "ext: and the source is gone when the cord is pulled")
	await _clear()


# --- names ---------------------------------------------------------------------

func _group_names() -> void:
	for kind: String in ["jamma", "mvs", "laserdisc", "discrete"]:
		var scene := ArcadeBayUnit.scene_for(kind)
		_ok(scene != null, "names: %s has a scene" % kind)
		if scene != null:
			var bay := scene.instantiate() as ArcadeBayUnit
			_ok(bay.bay_kind == kind and bay.type_id == "arcade_bay_" + kind, "names: and it knows what it is (%s)" % bay.type_id)
			_ok(ScenePersistence.PLAIN_SCENES.has(bay.type_id), "names: and the room can restore it")
			_ok(ArcadeBayUnit.LABELS.has(kind) and ArcadeBayUnit.kind_of_type(bay.type_id) == kind, "names: with a label")
			bay.free()
	_ok(ScenePersistence.LEAD_SCENES.has("jamma_cable"), "names: the JAMMA lead can be restored")
	for systemid: String in ["arcade", "neogeo", "daphne", "dice"]:
		var spawns: Array = SpawnCatalog.items_for(systemid).map(func(i: Dictionary) -> String: return str(i.get("spawn", "")))
		_ok(spawns.has("arcade_bay_jamma") and spawns.has("arcade_bay_mvs") and spawns.has("jamma_cable"),
			"names: the %s card offers the bays and the lead" % systemid)
	_ok(not SpawnCatalog.items_for("arcade").any(func(i: Dictionary) -> bool: return bool(i.get("default", false))),
		"names: and no cabinet on the arcade card is marked \"default\"")
	_ok(CoreRecommendations.core_for("arcade") == "fbneo", "names: the arcade tile's default core is FinalBurn Neo")
	_ok(Connectors.label_of("jamma_plug") == "a JAMMA harness plug", "names: the plug has a name")
