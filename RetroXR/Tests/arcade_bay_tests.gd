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
extends "res://Tests/test_suite.gd"

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

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "bay"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[bay] TIMED OUT")
		get_tree().quit(1))
	await _run()
	_finish()


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
	if _want("atomiswave"):
		await _group_atomiswave()
	if _want("naomi"):
		await _group_naomi()
	if _want("hookup"):
		await _group_hookup()
	if _want("captive"):
		await _group_captive()
	if _want("converter"):
		await _group_converter()
	if _want("gdrom"):
		await _group_gdrom()
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


## Deleting a game's disc takes its disc images and nothing else from the folder named for it: the folder only shares the board's name. It took the whole
## tree, so a player's own files beside the CHD (samples, notes) went too, and a plain board's same-named folder was emptied with no disc in it.
func _disc_delete_cases() -> void:
	var r := ProjectSettings.globalize_path("user://arcade_disc_delete_test")
	var made: Array[String] = ["game.zip", "game/a.chd", "game/notes.txt", "game/sub/b.chd", "game/keep/sample.wav",
		"plain.zip", "plain/readme.txt", "only.zip", "only/x.chd"]
	for f: String in made:
		DirAccess.make_dir_recursive_absolute(r.path_join(f).get_base_dir())
		var h := FileAccess.open(r.path_join(f), FileAccess.WRITE)
		h.store_8(1)
		h.close()
	var gone := ArcadeDiscs.delete_for(r.path_join("game.zip"))
	_ok(gone == 2 and not FileAccess.file_exists(r.path_join("game/a.chd")) and not FileAccess.file_exists(r.path_join("game/sub/b.chd")),
		"disc: deleting a game takes every disc image in its folder (%d)" % gone)
	_ok(FileAccess.file_exists(r.path_join("game/notes.txt")) and FileAccess.file_exists(r.path_join("game/keep/sample.wav"))
			and not DirAccess.dir_exists_absolute(r.path_join("game/sub")),
		"disc: and leaves the player's own files there, taking only the folders it emptied")
	_ok(ArcadeDiscs.delete_for(r.path_join("plain.zip")) == 0 and FileAccess.file_exists(r.path_join("plain/readme.txt")),
		"disc: a plain board's folder of the same name, with no disc in it, is left as it is")
	_ok(ArcadeDiscs.delete_for(r.path_join("only.zip")) == 1 and not DirAccess.dir_exists_absolute(r.path_join("only")),
		"disc: a folder that held only discs goes with them")
	for f: String in made:
		DirAccess.remove_absolute(r.path_join(f))
	for d: String in ["game/keep", "game/sub", "game", "plain", "only", ""]:
		DirAccess.remove_absolute(r.path_join(d))


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
	_disc_delete_cases()

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


# --- naomi ---------------------------------------------------------------------

## The Atomiswave bay: a board of its own with a JAMMA edge. Its cartridge lies flat, label up; the bay keeps a
## JAMMA socket (on its edge, where the harness goes); in the generic cabinet the cabinet plays Atomiswave; and a
## cabinet that stands the board on edge (ArcadeCabinetFromModel.bay_roll_deg) turns the mount.
func _group_atomiswave() -> void:
	var bay := await _bay("atomiswave", Vector3(0, 0, 4))
	_ok(bay.bay_kind == "atomiswave" and bay.primary_system() == "atomiswave", "atomiswave: the bay is an Atomiswave (%s)" % bay.primary_system())
	var cart := await _board("atomiswave", Vector3(0, 2, 4))
	var jamma := await _board("arcade", Vector3(1, 2, 4))
	_ok(bay.accepts_board(cart) and not bay.accepts_board(jamma), "atomiswave: it takes an Atomiswave cartridge and not a JAMMA board")
	_ok(MediaDimensions.cart_size("atomiswave").is_equal_approx(Vector3(0.0983, 0.0915, 0.0241)), "atomiswave: the cartridge is the Atomiswave's size")
	bay.slot.pick_up_object(cart)
	await _wait(10)
	_ok(cart.global_basis.z.normalized().y > 0.99, "atomiswave: the cartridge lies flat, label up")
	_ok(cart.global_basis.y.normalized().x < -0.99, "atomiswave: its connector (-Y) toward the board's right")
	var port := bay.find_child("JammaPort", true, false) as Node3D
	var edge := bay.find_child("JammaEdgeAnchor", true, false) as Node3D
	_ok(port != null and edge != null and port.get_parent() == edge, "atomiswave: its JAMMA socket is on its edge")
	_ok(edge != null and edge.position.z > bay.box_size().z * 0.5, "atomiswave: and the edge stands out of the front")
	await _clear()

	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var mount := _mount_of(sys)
	mount.drop_object()
	await _wait(4)
	var aw := await _bay("atomiswave", mount.global_position + Vector3(0, 1.0, 0))
	mount.pick_up_object(aw)
	await _wait(6)
	_ok(sys.get_bay() == aw and sys.systemid == "atomiswave", "atomiswave: an Atomiswave in the generic cabinet plays Atomiswave (%s)" % sys.systemid)
	var game := await _board("atomiswave", Vector3(3, 3, 0))
	_ok(sys._accepts_media(game), "atomiswave: the cabinet takes the Atomiswave cartridge")
	await _clear()


const NAOMI_SHELL := "user://arcade_bay_naomi_shell_test.tscn"


## The NAOMI bay: a board of its own kind. Its cartridge lies flat, label up; it goes in the generic
## cabinet as any bay does and the cabinet plays NAOMI; a mod's model of the board moves its seat.
func _group_naomi() -> void:
	var bay := await _bay("naomi", Vector3(0, 0, 4))
	_ok(bay.bay_kind == "naomi" and bay.primary_system() == "naomi", "naomi: the bay is a NAOMI (%s)" % bay.primary_system())
	var cart := await _board("naomi", Vector3(0, 2, 4))
	var jamma := await _board("arcade", Vector3(1, 2, 4))
	_ok(bay.accepts_board(cart) and not bay.accepts_board(jamma), "naomi: it takes a NAOMI cartridge and not a JAMMA board")
	_ok(MediaDimensions.cart_size("naomi").is_equal_approx(Vector3(0.2546, 0.1258, 0.020)), "naomi: the cartridge is the NAOMI's size")
	bay.slot.pick_up_object(cart)
	await _wait(10)
	var up := cart.global_basis.z.normalized()
	_ok(up.y > 0.99, "naomi: the cartridge lies flat, label up (its +Z is %s)" % str(up))
	_ok(cart.global_basis.x.normalized().z < -0.99, "naomi: its long side front to back, the arrow tab (-X) to the front")
	for socket: String in ["VgaAnchor", "JvsAnchor", "AudioLAnchor", "AudioRAnchor", "PowerAnchor"]:
		_ok(bay.find_child(socket, true, false) is Marker3D, "naomi: the front has %s" % socket)
	_ok(bay.find_child("JammaPort", true, false) == null, "naomi: and no JAMMA socket")
	await _clear()

	# In the generic cabinet: the cabinet plays NAOMI, and a NAOMI cartridge is its game.
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var mount := _mount_of(sys)
	mount.drop_object()
	await _wait(4)
	var naomi := await _bay("naomi", mount.global_position + Vector3(0, 1.0, 0))
	mount.pick_up_object(naomi)
	await _wait(6)
	_ok(sys.get_bay() == naomi and sys.systemid == "naomi", "naomi: a NAOMI in the generic cabinet plays NAOMI (%s)" % sys.systemid)
	var game := await _board("naomi", Vector3(3, 3, 0))
	_ok(sys._accepts_media(game), "naomi: the cabinet takes the NAOMI cartridge")
	await _clear()

	# A mod's model: the stand-in's look hidden, the model fitted over the box, the seat moved onto its CartAnchor.
	var model := Node3D.new()
	model.name = "NaomiModel"
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = BoxMesh.new()                              # 1 m a side, centred: fitted to the bay's box
	model.add_child(mi)
	mi.owner = model
	var anchor := Marker3D.new()
	anchor.name = "CartAnchor"
	anchor.position = Vector3(0.1, 0.3, -0.2)
	model.add_child(anchor)
	anchor.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	ResourceSaver.save(packed, NAOMI_SHELL)
	model.free()
	var size := Vector3(0.272, 0.066, 0.340)
	_ok(ArcadeBayShells.register_mod_shell("naomi", {"shell": NAOMI_SHELL, "size": size}, "test.naomi").is_empty(),
		"naomi: a mod gives the bay a model")
	_ok(not ArcadeBayShells.register_mod_shell("naomi", {"shell": NAOMI_SHELL, "size": size}, "test.other").is_empty(),
		"naomi: and a second mod is told who has it")
	_ok(not ArcadeBayShells.register_mod_shell("naomi", {"shell": NAOMI_SHELL}, "test.naomi").is_empty(),
		"naomi: a model needs its size")
	var dressed := await _bay("naomi", Vector3(0, 0, 6))
	var shell := dressed.get_node_or_null("Shell") as Node3D
	_ok(shell != null, "naomi: the bay wears the model")
	var case_mesh := dressed.find_child("NaomiCase", true, false) as GeometryInstance3D
	_ok(case_mesh != null and not case_mesh.visible, "naomi: and the stand-in's case is hidden")
	var want := Vector3(0.1 * size.x, 0.3 * size.y + dressed.box_size().y * 0.5, -0.2 * size.z)
	var seat := dressed.find_child("CartSeat", true, false) as Node3D
	_ok(seat != null and seat.position.is_equal_approx(want), "naomi: the seat moved onto the model's CartAnchor (%s, want %s)"
		% [str(seat.position if seat != null else Vector3.ZERO), str(want)])
	_ok(dressed.slot.transform.origin.is_equal_approx(want), "naomi: and the cartridge slot with it")
	_ok(dressed.slot.transform.basis.z.y > 0.99, "naomi: the seat keeps its own turn (label up)")
	ArcadeBayShells.drop_mod("test.naomi")
	_ok(not ArcadeBayShells.has_shell("naomi"), "naomi: the model goes with its mod")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NAOMI_SHELL))
	await _clear()


# --- hookup --------------------------------------------------------------------

## Each cabinet its own files: a scene loaded once stays cached under its path.
var HK_MODEL := "user://arcade_hookup_model_test.tscn"
var HK_CAB := "user://arcade_hookup_cabinet_test.tscn"
const HK_ID := "test.hookup:cabinet"


func _hk_node(root: Node3D, type: String, node_name: String, at: Vector3) -> Node3D:
	var n := ClassDB.instantiate(type) as Node3D
	n.name = node_name
	root.add_child(n)
	n.owner = root
	n.position = at
	return n


## A cabinet built from a model (ArcadeCabinetFromModel) with a NAOMI's leads, its seeded NAOMI wired up cord by cord.
func _group_hookup() -> void:
	_hk_build(false)
	_ok(SystemModelRegistry.register_mod_row(HK_ID, {"platform": ["naomi"], "label": "Hookup test", "sockets": [], "scene": HK_CAB},
		"test.hookup").is_empty(), "hookup: a cabinet from a model registers")
	await _hk_run()


## A cabinet whose VGA lead is its own cord (ArcadeCabinetFromModel.captive_leads): fresh, the cord's cabinet end is in its
## grommet, hidden and fixed, the cord a metre; only its free end comes out of the board, and back in it the picture is back.
func _group_captive() -> void:
	_hk_captive = PackedStringArray(["VgaLead"])
	_hk_build(false)
	_hk_captive = PackedStringArray()
	_ok(SystemModelRegistry.register_mod_row(HK_ID, {"platform": ["naomi"], "label": "Captive test", "sockets": [], "scene": HK_CAB},
		"test.hookup").is_empty(), "captive: a cabinet from a model registers")
	var sys := await _cabinet(HK_ID, "naomi")
	await _wait(30)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var bay := sys.get_bay()
	if model == null or bay == null:
		_ok(false, "captive: it comes with a NAOMI")
		await _hk_done()
		return
	var cab := model.find_child(NaomiHookup.CAB_VGA, true, false) as Port
	var end := cab.seated_plug() as XRToolsPickable if cab != null else null
	_ok(cab != null and cab.has_meta(NaomiHookup.CAPTIVE_META) and not cab.enabled, "captive: the VGA lead's socket is the cabinet's own, fixed")
	var shown := 0
	if end != null:
		for mi in end.find_children("*", "MeshInstance3D", true, false):
			shown += 1 if (mi as MeshInstance3D).visible else 0
	_ok(end != null and not end.enabled and shown == 0, "captive: its cord's cabinet end is in the grommet, hidden and fixed")
	var rope := end.get_parent().get_node_or_null("VerletRope") as VerletRope if end != null else null
	var run := cab.global_position.distance_to((bay.find_child(NaomiHookup.BOARD_VGA, true, false) as Node3D).global_position) if cab != null else 0.0
	var cord_len: float = rope.segment_count * rope.segment_length if rope != null else 0.0
	_ok(rope != null and absf(cord_len - run - NaomiHookup.CORD_SPARE) < 0.03,
		"captive: the cord is cut to its run, %.2f m for %.2f m" % [cord_len, run])
	_ok(model.hookup_missing().is_empty(), "captive: fresh, it comes wired (%s)" % str(model.hookup_missing()))
	var out := bay.find_child(NaomiHookup.BOARD_VGA, true, false) as Port
	var free := out.seated_plug()
	out.drop_object()
	await _wait(30)
	_ok(not bool(model._hookup.get("video", true)) and cab.seated_plug() == end, "captive: its free end out of the board: no picture, the cord still the cabinet's")
	out.pick_up_object(free)
	await _wait(30)
	_ok(bool(model._hookup.get("video", false)), "captive: back in: the picture")
	await _hk_done()


func _hk_build(jamma: bool) -> void:
	var tag := "jamma" if jamma else "jvs"
	HK_MODEL = "user://arcade_hookup_model_%s_test.tscn" % tag
	HK_CAB = "user://arcade_hookup_cabinet_%s_test.tscn" % tag
	var m := Node3D.new()
	m.name = "HookupModel"
	var body := _hk_node(m, "MeshInstance3D", "Body", Vector3(0, 0.9, -0.45)) as MeshInstance3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 1.8, 0.9)
	body.mesh = bm
	var glass := _hk_node(m, "MeshInstance3D", "Screen", Vector3(0, 1.3, -0.2)) as MeshInstance3D
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.4)
	glass.mesh = qm
	_hk_node(m, "Marker3D", "BoardAnchor", Vector3(0, 0.1, -0.5))
	_hk_node(m, "Marker3D", "VgaLead", Vector3(-0.2, 0.3, -0.8))
	_hk_node(m, "Marker3D", "AudioLeadL", Vector3(0.1, 0.1, -0.8))
	_hk_node(m, "Marker3D", "AudioLeadR", Vector3(0.12, 0.1, -0.8))
	if jamma:
		_hk_node(m, "Marker3D", "JammaLead", Vector3(0.0, 0.2, -0.7))
	else:
		_hk_node(m, "Marker3D", "JvsLead", Vector3(0.2, 0.1, -0.8))
	_hk_node(m, "Marker3D", "BoardPowerLead", Vector3(0.25, 0.15, -0.8))
	_hk_node(m, "Marker3D", "GdDriveAnchor", Vector3(0.22, 0.0, -0.3))
	# The main switch on the back, pressed from behind.
	_hk_node(m, "Marker3D", "PowerSwitchAnchor", Vector3(0.1, 0.12, -0.9))
	_hk_node(m, "Marker3D", "PowerSwitchAim", Vector3(0.1, 0.12, -1.2))
	# A panel on the front that lifts off.
	var lpan := _hk_node(m, "MeshInstance3D", "TestPanelLiftOff", Vector3(0.15, 0.55, 0.0)) as MeshInstance3D
	var lbm := BoxMesh.new()
	lbm.size = Vector3(0.2, 0.25, 0.012)
	lpan.mesh = lbm
	# A door on the front's leaning face (it leans back 20 degrees going up), hinged on its left edge.
	var spiv := _hk_node(m, "Node3D", "SlantDoorPivot", Vector3(-0.25, 0.70, 0.30))
	_hk_node(m, "Marker3D", "SlantDoorAxis", Vector3(-0.25, 0.43, 0.40))
	var smesh := MeshInstance3D.new()
	smesh.name = "SlantDoor"
	var sbm := BoxMesh.new()
	sbm.size = Vector3(0.2, 0.28, 0.012)
	smesh.mesh = sbm
	spiv.add_child(smesh)
	smesh.owner = m
	smesh.position = Vector3(0.1, -0.135, 0.05)
	smesh.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	# The VGA socket faces back (its plug from behind); a door at the front right, hinged on its right edge.
	_hk_node(m, "Marker3D", "VgaLeadAim", Vector3(-0.2, 0.3, -1.2))
	var dpiv := _hk_node(m, "Node3D", "DriveDoorPivot", Vector3(0.30, 0.05, 0.0))
	var dmesh := MeshInstance3D.new()
	dmesh.name = "DriveDoor"
	var dbm := BoxMesh.new()
	dbm.size = Vector3(0.2, 0.2, 0.015)
	dmesh.mesh = dbm
	dpiv.add_child(dmesh)
	dmesh.owner = m
	dmesh.position = Vector3(-0.1, 0.1, -0.0075)
	# A service hatch on the back, hinged along its bottom edge.
	var hpiv := _hk_node(m, "Node3D", "ServiceHatchPivot", Vector3(0.0, 1.0, -0.9))
	var hmesh := MeshInstance3D.new()
	hmesh.name = "ServiceHatch"
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.2, 0.2, 0.01)
	hmesh.mesh = hbm
	hpiv.add_child(hmesh)
	hmesh.owner = m
	hmesh.position = Vector3(0.0, 0.1, 0.005)
	var mp := PackedScene.new()
	mp.pack(m)
	ResourceSaver.save(mp, HK_MODEL)
	m.free()
	var cab := Node3D.new()
	cab.name = "HookupCabinet"
	cab.set_script(load("res://Scripts/Objects/system_models/arcade_cabinet_model.gd"))
	var adapter := Node3D.new()
	adapter.name = "FromModel"
	adapter.set_script(load("res://Scripts/Objects/arcade/arcade_cabinet_from_model.gd"))
	adapter.set("model", load(HK_MODEL))
	adapter.set("bay_kind", "naomi")
	adapter.set("captive_leads", _hk_captive)
	cab.add_child(adapter)
	adapter.owner = cab
	var cp := PackedScene.new()
	cp.pack(cab)
	ResourceSaver.save(cp, HK_CAB)
	cab.free()


func _hk_run() -> void:
	var sys := await _cabinet(HK_ID, "naomi")
	await _wait(30)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var bay := sys.get_bay()
	_ok(model != null and bay != null and bay.bay_kind == "naomi", "hookup: it comes with a NAOMI")
	if model == null or bay == null:
		await _hk_done()
		return
	_ok(NaomiHookup.wired(model), "hookup: the cabinet has the NAOMI's leads")
	_ok(model.find_child("IoBoard", true, false) != null, "hookup: and its I/O board, the JVS socket on it")
	var power_btn := sys.get_node_or_null("PowerButton") as Node3D
	var switch_at := model.find_child("PowerSwitchAnchor", true, false) as Node3D
	_ok(power_btn != null and switch_at != null and power_btn.global_position.distance_to(switch_at.global_position) < 0.005
		and power_btn.global_basis.y.dot(Vector3.FORWARD) > 0.9 and not (power_btn.get_node("ButtonMesh") as Node3D).visible,
		"hookup: the power button is the cabinet's main switch, on its back, pressed from behind, its own face hidden")
	_ok(model.hookup_missing().is_empty() and not model.input_cut(), "hookup: fresh, it comes wired (%s)" % str(model.hookup_missing()))
	# Every cord out, both ends.
	for pn: String in [NaomiHookup.BOARD_POWER, NaomiHookup.BOARD_VGA, NaomiHookup.BOARD_AUDIO_L, NaomiHookup.BOARD_AUDIO_R, NaomiHookup.BOARD_JVS]:
		(bay.find_child(pn, true, false) as Port).drop_object()
	for pn: String in [NaomiHookup.CAB_POWER, NaomiHookup.CAB_VGA, NaomiHookup.CAB_AUDIO_L, NaomiHookup.CAB_AUDIO_R, NaomiHookup.CAB_JVS]:
		(model.find_child(pn, true, false) as Port).drop_object()
	await _wait(30)
	var missing := model.hookup_missing()
	_ok(missing.size() == 4 and model.input_cut() and model.host_picture() == null and bool(model.audio_gate()["gated"]),
		"hookup: nothing plugged: no power, no picture, no sound, no controls (%s)" % str(missing))
	# The power harness.
	var power := _hk_cable("naomi_power_cable")
	(bay.find_child(NaomiHookup.BOARD_POWER, true, false) as Port).pick_up_object(power.get_node("PlugA0"))
	(model.find_child(NaomiHookup.CAB_POWER, true, false) as Port).pick_up_object(power.get_node("PlugB0"))
	await _wait(30)
	_ok(not model.hookup_missing().has("the NAOMI's power lead"), "hookup: the power harness on: powered (%s)" % str(model.hookup_missing()))
	# The VGA cable.
	var vga := _hk_cable("vga_cable")
	(bay.find_child(NaomiHookup.BOARD_VGA, true, false) as Port).pick_up_object(vga.get_node("PlugA0"))
	(model.find_child(NaomiHookup.CAB_VGA, true, false) as Port).pick_up_object(vga.get_node("PlugB0"))
	await _wait(30)
	_ok(bool(model._hookup.get("video", false)), "hookup: the VGA cable on: the monitor has the picture")
	# The two phono leads (the composite cable's white and red).
	var av := _hk_cable("composite_cable")
	(bay.find_child(NaomiHookup.BOARD_AUDIO_L, true, false) as Port).pick_up_object(av.get_node("PlugA1"))
	(model.find_child(NaomiHookup.CAB_AUDIO_L, true, false) as Port).pick_up_object(av.get_node("PlugB1"))
	await _wait(30)
	var g := model.audio_gate()
	_ok(bool(g["gated"]) and bool(g["left"]) and not bool(g["right"]) and int(sys.audio_speakers()["right"]) == -1,
		"hookup: the left lead only: the left channel plays, the right is silent")
	(bay.find_child(NaomiHookup.BOARD_AUDIO_R, true, false) as Port).pick_up_object(av.get_node("PlugA2"))
	(model.find_child(NaomiHookup.CAB_AUDIO_R, true, false) as Port).pick_up_object(av.get_node("PlugB2"))
	# The JVS cable.
	var jvs := _hk_cable("jvs_cable")
	# Its USB-A end wears the game's USB-A plug model (it was the xenu.usba mod's), on every JVS lead, not only on the
	# ones a fresh cabinet comes wired with; the cord leaves from the model's CordExit.
	var usba := jvs.get_node("PlugA0") as RcaPlug
	var usba_shell := usba.get_node_or_null("Shell") as Node3D
	_ok(usba_shell != null and usba_shell.scene_file_path == "res://imported-assets/connectors/usb_a_plug/usb_a_plug.glb"
		and usba.get_node_or_null("PlugTip") == null, "hookup: the JVS lead's USB-A end wears the USB-A plug model")
	_ok(usba.cable_anchor.is_equal_approx(Vector3(0, 0, -0.03225)),
		"hookup: and its cord leaves the plug's strain relief (%s)" % str(usba.cable_anchor))
	(bay.find_child(NaomiHookup.BOARD_JVS, true, false) as Port).pick_up_object(jvs.get_node("PlugA0"))
	(model.find_child(NaomiHookup.CAB_JVS, true, false) as Port).pick_up_object(jvs.get_node("PlugB0"))
	await _wait(30)
	_ok(model.hookup_missing().is_empty() and not model.input_cut() and not bool(model.audio_gate()["gated"]),
		"hookup: every cord on: the cabinet plays the NAOMI (%s)" % str(model.hookup_missing()))
	# The power off again: everything goes with it.
	(model.find_child(NaomiHookup.CAB_POWER, true, false) as Port).drop_object()
	await _wait(30)
	_ok(model.input_cut() and not bool(model._hookup.get("video", true)), "hookup: the power harness out: dark and dead again")
	# A GD-ROM game in this cabinet: the drive runs from the cabinet's supply too.
	var dimm := _gd_obj("res://Scenes/Objects/peripherals/naomi_dimm_board.tscn", Vector3(2, 2, 2)) as NaomiDimm
	var drive := _gd_obj("res://Scenes/Objects/peripherals/naomi_gd_drive.tscn", Vector3(2.5, 2, 2)) as NaomiGdDrive
	var key := _gd_obj("res://Scenes/Objects/peripherals/naomi_key.tscn", Vector3(3, 2, 2)) as NaomiKey
	key.rom_path = "/tmp/naomi_gd/ikaruga.zip"
	var disc := DISC_SCENE.instantiate() as RetroDisc
	disc.systemid = "naomi"
	disc.rom_path = "/tmp/naomi_gd/ikaruga.zip"
	disc.freeze = true
	add_child(disc)
	_spawned.append(disc)
	await _wait(6)
	bay.slot.drop_object()
	await _wait(4)
	bay.slot.pick_up_object(dimm)
	(dimm.find_child("KeySocket", true, false) as XRToolsSnapZone).pick_up_object(key)
	var gd := _hk_cable("gd_cable")
	(dimm.find_child(NaomiGdRom.DIMM_DATA, true, false) as Port).pick_up_object(gd.get_node("PlugA0"))
	(drive.find_child(NaomiGdRom.DRIVE_DATA, true, false) as Port).pick_up_object(gd.get_node("PlugB0"))
	drive.set_lid_open(true)
	(drive.find_child("DiscSeat", true, false) as XRToolsSnapZone).pick_up_object(disc)
	drive.set_lid_open(false)
	await _wait(30)
	_ok(dimm.missing().has("the drive's power lead"), "hookup: a GD-ROM drive with no power lead: no game (%s)" % str(dimm.missing()))
	var dpow := _hk_cable("naomi_power_cable")
	(drive.find_child(NaomiGdRom.DRIVE_POWER, true, false) as Port).pick_up_object(dpow.get_node("PlugA0"))
	(model.find_child(NaomiGdRom.CAB_DRIVE_POWER, true, false) as Port).pick_up_object(dpow.get_node("PlugB0"))
	await _wait(40)
	_ok(dimm.missing().is_empty() and dimm.get_rom_path() == "/tmp/naomi_gd/ikaruga.zip", "hookup: the drive powered: the DIMM board has the game (%s)" % str(dimm.missing()))
	var vga_in := model.find_child(NaomiHookup.CAB_VGA, true, false) as Node3D
	_ok(vga_in != null and vga_in.global_basis.z.dot(Vector3.FORWARD) > 0.9, "hookup: the VGA socket faces its aim, a plug from behind (%s)"
		% (str(vga_in.global_basis.z) if vga_in != null else "none"))
	var dgrab := model.find_child("DriveDoorGrab", true, false) as VRHinge
	_ok(dgrab != null, "hookup: the cabinet's other door has a hinge")
	if dgrab != null:
		var dmesh := model.find_child("DriveDoor", true, false) as Node3D
		var shut_z := dmesh.global_position.z
		dgrab.set_rotation_deg_remote(90.0)
		await _wait(2)
		_ok(dmesh.global_position.z > shut_z + 0.05, "hookup: and opens toward the player (%.3f m)" % (dmesh.global_position.z - shut_z))
	await _wait(5)
	var lift := CoverSlots.of(sys)
	var lslot := lift.slot("cabinet_test_panel_lift_off") if lift != null else null
	_ok(lslot != null and lslot.picked_up_object is PortCover and (lslot.picked_up_object as Node3D).has_node("Shell"),
		"hookup: a lift-off panel is a cover on the cabinet, wearing the panel")
	var sgrab := model.find_child("SlantDoorGrab", true, false) as VRHinge
	_ok(sgrab != null, "hookup: the door on the leaning face has a hinge")
	if sgrab != null:
		var sdoor := model.find_child("SlantDoor", true, false) as Node3D
		var s_shut := sdoor.global_position
		sgrab.set_rotation_deg_remote(80.0)
		await _wait(2)
		var s_moved := sdoor.global_position - s_shut
		_ok(s_moved.z > 0.04, "hookup: and swings out, toward the front (%s)" % str(s_moved))
	# A door's solid body is a child of the cabinet's own RigidBody3D, on a layer the cabinet's mask takes:
	# unexempted, every cabinet pushed against its own doors and flew about the room (2026-11-13).
	var parts: Array[Node] = sys.find_children("DoorBody", "PhysicsBody3D", true, false)
	parts.append_array(sys.find_children("TrayBody", "PhysicsBody3D", true, false))
	var exempt := parts.filter(func(b: Node) -> bool: return (b as PhysicsBody3D).get_collision_exceptions().has(sys))
	_ok(not parts.is_empty() and exempt.size() == parts.size(),
		"hookup: every door body is exempt from its own cabinet (%d of %d)" % [exempt.size(), parts.size()])
	var hgrab := model.find_child("ServiceHatchGrab", true, false) as VRHinge
	_ok(hgrab != null, "hookup: the cabinet's service hatch has a hinge")
	if hgrab != null:
		var hmesh := model.find_child("ServiceHatch", true, false) as Node3D
		var shut := hmesh.global_position
		hgrab.set_rotation_deg_remote(80.0)
		await _wait(2)
		var moved := hmesh.global_position - shut
		_ok(moved.z < -0.05 and moved.y < -0.03, "hookup: and drops open away from the cabinet (%s)" % str(moved))
	var dmount := model.find_child("GdDriveMount", true, false) as XRToolsSnapZone
	_ok(dmount != null and dmount.snap_require == NaomiGdDrive.GROUP, "hookup: the cabinet has a place for the GD-ROM drive")
	if dmount != null:
		dmount.pick_up_object(drive)
		await _wait(10)
		_ok(dmount.picked_up_object == drive and drive.global_position.distance_to(dmount.global_position) < 0.005,
			"hookup: the drive stands in it (%.3f m off)" % drive.global_position.distance_to(dmount.global_position))
		_ok(dimm.missing().is_empty(), "hookup: and still reads the disc there (%s)" % str(dimm.missing()))
	await _hk_done()


## A JAMMA cabinet (a harness, no I/O board): a fresh one's NAOMI comes with a converter on the harness.
func _group_converter() -> void:
	_hk_build(true)
	_ok(SystemModelRegistry.register_mod_row(HK_ID, {"platform": ["naomi"], "label": "JAMMA test", "sockets": [], "scene": HK_CAB},
		"test.hookup").is_empty(), "converter: a JAMMA cabinet from a model registers")
	var sys := await _cabinet(HK_ID, "naomi")
	await _wait(30)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var bay := sys.get_bay()
	_ok(model != null and bay != null and model.find_child(NaomiHookup.CAB_JVS, true, false) == null, "converter: no I/O board in a JAMMA cabinet")
	var convs := get_tree().get_nodes_in_group(NaomiHookup.CONV_GROUP)
	_ok(convs.size() == 1, "converter: a fresh one comes with a converter (%d)" % convs.size())
	for c in convs:
		_spawned.append(c)
	_ok(model != null and model.hookup_missing().is_empty() and not model.input_cut(), "converter: wired through it: everything plays (%s)"
		% str(model.hookup_missing() if model != null else []))
	if model != null:
		(model.find_child(NaomiHookup.CAB_JAMMA, true, false) as Port).drop_object()
		await _wait(30)
		_ok(model.input_cut() and bool(model._hookup.get("video", false)),
			"converter: the harness off it: no controls, the picture still on the monitor's own VGA (%s)" % str(model.hookup_missing()))
	await _hk_done()


# --- gdrom ---------------------------------------------------------------------

const GD_ROOT := "user://naomi_gdrom_test"


func _gd_obj(scene: String, at: Vector3) -> Node3D:
	var o := (load(scene) as PackedScene).instantiate() as Node3D
	o.position = at
	add_child(o)
	if o is RigidBody3D:
		(o as RigidBody3D).freeze = true
	_spawned.append(o)
	return o


## The GD-ROM system: a DIMM board in a NAOMI, the game's key in it, a drive cabled to it, the game's disc in the drive.
func _group_gdrom() -> void:
	var sys := await _cabinet("arcade_cabinet_generic", "arcade")
	var mount := _mount_of(sys)
	mount.drop_object()
	await _wait(4)
	var naomi := await _bay("naomi", mount.global_position + Vector3(0, 1.0, 0))
	mount.pick_up_object(naomi)
	await _wait(6)
	var dimm := _gd_obj("res://Scenes/Objects/peripherals/naomi_dimm_board.tscn", Vector3(2, 2, 2)) as NaomiDimm
	var drive := _gd_obj("res://Scenes/Objects/peripherals/naomi_gd_drive.tscn", Vector3(2.5, 2, 2)) as NaomiGdDrive
	var key := _gd_obj("res://Scenes/Objects/peripherals/naomi_key.tscn", Vector3(3, 2, 2)) as NaomiKey
	key.rom_path = "/tmp/naomi_gd/ikaruga.zip"
	var disc := DISC_SCENE.instantiate() as RetroDisc
	disc.systemid = "naomi"
	disc.rom_path = "/tmp/naomi_gd/ikaruga.zip"
	disc.position = Vector3(3.5, 2, 2)
	disc.freeze = true
	add_child(disc)
	_spawned.append(disc)
	await _wait(8)
	_ok(not naomi.accepts_board(disc), "gdrom: the NAOMI's seat does not take a disc")
	_ok(naomi.accepts_board(dimm), "gdrom: it takes the DIMM board")
	naomi.slot.pick_up_object(dimm)
	await _wait(20)
	_ok(sys.systemid == "naomi" and sys.rom_path.is_empty(), "gdrom: the DIMM board alone: no game (%s)" % sys.rom_path)
	_ok(dimm.missing().size() == 2, "gdrom: it waits for the key and the drive (%s)" % str(dimm.missing()))
	(dimm.find_child("KeySocket", true, false) as XRToolsSnapZone).pick_up_object(key)
	var cable := _hk_cable("gd_cable")
	(dimm.find_child(NaomiGdRom.DIMM_DATA, true, false) as Port).pick_up_object(cable.get_node("PlugA0"))
	(drive.find_child(NaomiGdRom.DRIVE_DATA, true, false) as Port).pick_up_object(cable.get_node("PlugB0"))
	var seat := drive.find_child("DiscSeat", true, false) as XRToolsSnapZone
	_ok(not drive._accepts_disc(disc), "gdrom: the drive's lid shut: no disc goes in")
	var lid := (CoverSlots.of(drive).slot(NaomiGdDrive.LID_SOCKET) as XRToolsSnapZone).picked_up_object as Node3D
	drive.set_lid_open(true)
	_ok(lid is PortCover and not drive.lid_shut() and lid.get_parent() != CoverSlots.of(drive).slot(NaomiGdDrive.LID_SOCKET),
		"gdrom: the lid is not hinged: it comes off the drum as a thing of its own")
	_ok(drive._accepts_disc(disc), "gdrom: the lid off: the disc goes on the spindle")
	seat.pick_up_object(disc)
	await _wait(20)
	_ok(sys.rom_path.is_empty() and dimm.missing().has("the drive's lid shut"), "gdrom: the lid still off: not yet (%s)" % str(dimm.missing()))
	drive.set_lid_open(false)
	await _wait(40)
	_ok(sys.rom_path == "/tmp/naomi_gd/ikaruga.zip", "gdrom: key, cable, disc, lid shut: the cabinet loads the disc's game (%s)" % sys.rom_path)
	_ok(drive.lid_shut() and not disc.enabled and not seat.enabled, "gdrom: the lid back on: the disc cannot be taken out")
	# Another game's key.
	key.rom_path = "/tmp/naomi_gd/vonot.zip"
	await _wait(40)
	_ok(sys.rom_path.is_empty() and str(dimm.missing()).contains("ERROR 33"), "gdrom: another game's key: ERROR 33 (%s)" % str(dimm.missing()))
	# A GD-ROM game spawns as its disc and its key.
	DirAccess.make_dir_recursive_absolute(GD_ROOT.path_join("ikaruga"))
	FileAccess.open(GD_ROOT.path_join("ikaruga.zip"), FileAccess.WRITE).store_string("zip")
	FileAccess.open(GD_ROOT.path_join("ikaruga/gdl-0010.chd"), FileAccess.WRITE).store_string("chd")
	var zip := ProjectSettings.globalize_path(GD_ROOT.path_join("ikaruga.zip"))
	_ok(NaomiGdRom.is_gd_game("naomi", zip) and not NaomiGdRom.is_gd_game("arcade", zip), "gdrom: a NAOMI romset with a GD-ROM image is a GD-ROM game")
	for f: String in ["ikaruga/gdl-0010.chd", "ikaruga.zip"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GD_ROOT.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GD_ROOT.path_join("ikaruga")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GD_ROOT))
	await _clear()


func _hk_cable(kind: String) -> Node3D:
	var cable := (ScenePersistence.LEAD_SCENES[kind] as PackedScene).instantiate() as Node3D
	cable.position = Vector3(0, 1.0, 2.0)
	add_child(cable)
	_spawned.append(cable)
	return cable


var _hk_captive := PackedStringArray()


func _hk_done() -> void:
	SystemModelRegistry.drop_mod("test.hookup")
	for path: String in [HK_MODEL, HK_CAB]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
	# And back the other way. Taking the MVS bay out leaves the generic cabinet its OWN kind, with no bay in at all (it stayed `neogeo`, and was saved so).
	mount.drop_object()
	await _wait(4)
	_ok(sys.get_bay() == null and sys.systemid == "arcade", "frank: with the MVS bay taken out the cabinet is arcade again, before any bay goes in (%s)" % sys.systemid)
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
	for kind: String in ["jamma", "mvs", "laserdisc", "discrete", "naomi", "naomi2", "atomiswave"]:
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
