## mod_tests — the mod loading stack, headless, no mod installed and none needed.
##
##   godot --headless --path RetroXR res://Tests/mod_tests.tscn
##   godot --headless --path RetroXR res://Tests/mod_tests.tscn -- --only=pack
##
## Groups:
##   pack/        reading a container without mounting it, both formats
##   manifest/    what a mod.json must say, and what is refused
##   inventory/   namespace escapes, unclaimed paths, the three fatal files
##   registry/    the model overlay and its fallbacks
##   rooms/       the collapsed room descriptor and mod rooms
##   objects/     mod props, and their persistence type
##   media/       cart sizing, disc loaders, scraper mapping
##   shaders/     the three ways a mod lands on a shader
##   removal/     A SLOT MUST SURVIVE THE MOD THAT FILLED IT GOING AWAY
##   netplay/     the fingerprint and its mismatch report
##   consistency/ cross-table invariants a mod platform would break first
##   tvdefaults/  cabinet CRT defaults without overwriting restored/player values
##
## Almost every case runs WITHOUT mounting anything, because a mounted pack
## cannot be unmounted and a test that mounts pollutes every case after it.
## Fixtures are built into user:// at run time with ZIPPacker/PCKPacker, so
## nothing binary is committed.
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
extends "res://Tests/test_suite.gd"

## Cases in this file, NOT counting the guard below.
const EXPECTED_CASES := 415

var _only := ""
var _dir := ""


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[test] TIMEOUT"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_dir = OS.get_user_data_dir().replace("\\", "/") + "/mod_tests"
	DirAccess.make_dir_recursive_absolute(_dir)

	if _want("pack"):        _group_pack()
	if _want("manifest"):    _group_manifest()
	if _want("inventory"):   _group_inventory()
	if _want("registry"):    _group_registry()
	if _want("rooms"):       _group_rooms()
	if _want("objects"):     _group_objects()
	if _want("media"):       _group_media()
	if _want("shaders"):     _group_shaders()
	if _want("removal"):     _group_removal()
	if _want("netplay"):     _group_netplay()
	if _want("consistency"): _group_consistency()
	if _want("overlay"):     _group_overlay()
	if _want("standins"):    _group_standins()
	if _want("cartshell"):   await _group_cartshell()
	if _want("expshell"):    _group_expshell()
	if _want("tvdefaults"):  _group_tv_defaults()
	if _want("attach"):      _group_attach()
	if _want("mains"):       _group_mains()

	_cleanup()
	# A case that never RAN is not a case that passed: GDScript has no try/catch,
	# so one bad index aborts the function it is in and every case after it simply
	# never prints, leaving a green run that checked less than it claims. Skipped
	# for a filtered run, where a lower count is the point.
	if _only.is_empty():
		_eq(_case_count(), EXPECTED_CASES, "suite/every case ran")
	_finish()


## Scene restoration seeds parameters before the TV's shell enters the tree.
## Equal-to-stock overrides matter too: comparing against stock cannot detect them.
func _group_tv_defaults() -> void:
	var scene := load("res://Scenes/Objects/tv.tscn") as PackedScene
	var fresh := scene.instantiate() as RetroTV
	fresh.set_crt_defaults({"crt_mask_mode": 2.0, "crt_gamma": 1.09, "not_a_crt_key": 9})
	_eq(fresh.get_crt_params()["crt_mask_mode"], 2, "tvdefaults/fresh cabinet gets slot mask as int")
	_eq(fresh.get_crt_params()["crt_gamma"], 1.09, "tvdefaults/gamma is a ratio, not tube gamma")
	_ok(not fresh.get_crt_params().has("not_a_crt_key"), "tvdefaults/unknown defaults ignored")
	var restored := scene.instantiate() as RetroTV
	restored.set_crt_params({"crt_mask_mode": 1.0, "crt_gamma": 1.09, "crt_grain": 0.07})
	restored.set_crt_defaults({"crt_mask_mode": 2, "crt_gamma": 1.2,
		"crt_grain": 0.02, "crt_scanline_strength": 0.4})
	_eq(restored.get_crt_params()["crt_mask_mode"], 1, "tvdefaults/saved stock mask still overrides cabinet")
	_eq(restored.get_crt_params()["crt_gamma"], 1.09, "tvdefaults/saved stock gamma still overrides cabinet")
	_eq(restored.get_crt_params()["crt_grain"], 0.07, "tvdefaults/saved tuning beats defaults")
	_eq(restored.get_crt_params()["crt_scanline_strength"], 0.4, "tvdefaults/partial save gets remaining defaults")
	restored.set_crt_param("crt_scanline_strength", 0.2)
	restored.set_crt_defaults({"crt_scanline_strength": 0.5})
	_eq(restored.get_crt_params()["crt_scanline_strength"], 0.2, "tvdefaults/panel edit beats later defaults")
	fresh.set_crt_params({"crt_mask_mode": 3.0})
	_eq(fresh.get_crt_params()["crt_mask_mode"], 3, "tvdefaults/save applied after defaults wins too")
	var stock := scene.instantiate() as RetroTV
	_eq(stock.get_crt_params()["crt_mask_mode"], 1, "tvdefaults/other televisions stay unchanged")
	fresh.set_crt_defaults({"crt_halation": 0.06})
	_eq(fresh.get_crt_params()["crt_halation"], 0.06, "tvdefaults/unedited values can take cabinet defaults")
	var copy := fresh.get_crt_params()
	copy["crt_halation"] = 0.9
	_eq(fresh.get_crt_params()["crt_halation"], 0.06, "tvdefaults/readback does not expose mutable state")
	for tv: RetroTV in [fresh, restored, stock]:
		tv.free()


## A mod prop sitting in a snap zone saves WHICH zone, and a load puts it back
## in it -- a part on a part, not two parts standing where they were.
func _group_attach() -> void:
	# A pickable with one snap zone, "Top", standing in for a mod's stackable part.
	var proto := XRToolsPickable.new()
	proto.name = "Part"
	var top_zone := XRToolsSnapZone.new()
	top_zone.name = "Top"
	proto.add_child(top_zone)
	top_zone.owner = proto
	var packed := PackedScene.new()
	packed.pack(proto)
	proto.free()
	var scene := "%s/attach_part.tscn" % _dir
	ResourceSaver.save(packed, scene)
	_eq(ScenePersistence.register_mod_object("t.att:part", scene, "t.att"), "",
		"attach/a part registers")
	var store := ScenePersistence.new("__mod_selftest")

	var base := ScenePersistence._instantiate_mod_object("t.att:part")
	var top := ScenePersistence._instantiate_mod_object("t.att:part")
	for n: Node3D in [base, top]:
		add_child(n)
		n.add_to_group("spawned")
	var map := {base: 0, top: 1}
	_ok(not store.serialize_node(top, 1, map).has("attached"),
		"attach/a loose prop saves no attachment")
	(base.get_node("Top") as XRToolsSnapZone).pick_up_object(top)
	var top_entry := store.serialize_node(top, 1, map)
	var base_entry := store.serialize_node(base, 0, map)
	_eq(top_entry.get("attached", {}), {"to": 0, "zone": "Top"},
		"attach/a snapped prop names its host's id and the zone's path in it")
	_ok(not base_entry.has("attached"), "attach/the host itself is loose")
	_eq(ScenePersistence._objects_validation_error([base_entry, top_entry]), "",
		"attach/an attached entry validates")
	_ok(not ScenePersistence._objects_validation_error([top_entry]).is_empty(),
		"attach/a dangling host is refused")
	var bad := top_entry.duplicate(true)
	bad["attached"]["zone"] = 3
	_ok(not ScenePersistence._objects_validation_error([base_entry, bad]).is_empty(),
		"attach/a zone that is not a path is refused")
	for n: Node in [base, top]:
		n.free()

	# Pass 1 then pass 2, as a slot load runs them: entries in the order that
	# puts the held prop FIRST, so its host must already exist by pass 2 only.
	var spawned := store.instantiate_objects(self, [top_entry, base_entry])
	var back_base := spawned.get(0) as XRToolsPickable
	var back_top := spawned.get(1) as XRToolsPickable
	_ok(back_top != null and back_base != null
		and back_top.get_picked_up_by() == back_base.get_node("Top"),
		"attach/a load puts the prop back in its host's zone")
	for n: Variant in spawned.values():
		(n as Node).free()

	# A zone that is part of the room, not of a spawned object, is named by path.
	var room_zone := XRToolsSnapZone.new()
	room_zone.name = "RoomZone"
	add_child(room_zone)
	var loose := ScenePersistence._instantiate_mod_object("t.att:part")
	add_child(loose)
	loose.add_to_group("spawned")
	room_zone.pick_up_object(loose)
	var room_entry := store.serialize_node(loose, 0, {loose: 0})
	_eq(room_entry.get("attached", {}), {"to": str(room_zone.get_path()), "zone": "."},
		"attach/a room's zone is named by its own path")
	loose.free()
	var room_back := store.instantiate_objects(self, [room_entry])
	var again := room_back.get(0) as XRToolsPickable
	_ok(again != null and again.get_picked_up_by() == room_zone,
		"attach/and a load finds it there")
	if again != null:
		again.free()
	room_zone.free()

	# A SHIPPED object in a mod's zone -- a console in a stand -- saves the same
	# way, and comes back held.
	var stand := ScenePersistence._instantiate_mod_object("t.att:part")
	var console := (load("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as RetroSystem
	for n: Node3D in [stand, console]:
		add_child(n)
		n.add_to_group("spawned")
	(stand.get_node("Top") as XRToolsSnapZone).pick_up_object(console)
	var stand_map := {stand: 0, console: 1}
	var console_entry := store.serialize_node(console, 1, stand_map)
	var stand_entry := store.serialize_node(stand, 0, stand_map)
	_eq(console_entry.get("attached", {}), {"to": 0, "zone": "Top"},
		"attach/a console in a mod's stand names the stand")
	_eq(ScenePersistence._objects_validation_error([stand_entry, console_entry]), "",
		"attach/and validates")
	stand.free()
	console.free()
	var stood := store.instantiate_objects(self, [console_entry, stand_entry])
	var back_stand := stood.get(0) as Node3D
	var back_console := stood.get(1) as RetroSystem
	_ok(back_console != null and back_stand != null
		and back_console.get_picked_up_by() == back_stand.get_node("Top"),
		"attach/a load puts the console back in the stand")
	for n: Variant in stood.values():
		(n as Node).free()

	# The game's own zones are not a mod's: what they hold has fields of its own,
	# restored by calls that do more than seat it. A plain pickable with a zone
	# stands in for a console's slot.
	var shipped := XRToolsPickable.new()
	var socket := XRToolsSnapZone.new()
	socket.name = "Socket"
	shipped.add_child(socket)
	var held_console := (load("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as RetroSystem
	var held_part := ScenePersistence._instantiate_mod_object("t.att:part")
	for n: Node3D in [shipped, held_console, held_part]:
		add_child(n)
		n.add_to_group("spawned")
	var shipped_map := {shipped: 0, held_console: 1, held_part: 2}
	socket.pick_up_object(held_console)
	_ok(not store.serialize_node(held_console, 1, shipped_map).has("attached"),
		"attach/a shipped object in the game's own zone saves no attachment")
	# Unless a mod hung that zone there and said so.
	socket.add_to_group(ScenePersistence.MOD_ZONE_GROUP)
	_eq(store.serialize_node(held_console, 1, shipped_map).get("attached", {}),
		{"to": 0, "zone": "Socket"}, "attach/a zone in the mod_zone group is a mod's")
	socket.remove_from_group(ScenePersistence.MOD_ZONE_GROUP)
	# A plain mod prop has no field of its own anywhere, so any zone counts.
	socket.pick_up_object(held_part)
	_eq(store.serialize_node(held_part, 2, shipped_map).get("attached", {}),
		{"to": 0, "zone": "Socket"}, "attach/a mod prop in the game's zone still saves it")
	for n: Node in [held_part, held_console, shipped]:
		n.free()

	# The host's mod is gone: the prop loads, loose, rather than failing the slot.
	var orphan := top_entry.duplicate(true)
	var gone := {"id": 0, "type": "t.gone:plate", "position": [0, 0, 0], "rotation": [0, 0, 0]}
	var pruned := ScenePersistence._prune_unknown_types([gone, orphan], "attach")
	_ok(pruned.size() == 1 and not (pruned[0] as Dictionary).has("attached"),
		"attach/a host whose mod is gone leaves the prop loose")
	ScenePersistence.drop_mod_objects("t.att")


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


# ── pack/ ─────────────────────────────────────────────────────────────────────

func _group_pack() -> void:
	var payload := {
		"mods/t.one/mod.json": '{"id":"t.one","api_version":1,"entry":"res://mods/t.one/m.gd"}',
		"mods/t.one/m.gd": "extends RetroMod",
	}
	var zip_path := _write_zip("pack.zip", payload)
	var pck_path := _write_pck("pack.pck", payload)

	# Both containers must present the SAME view, or the two readers have
	# diverged and only one of them is being exercised by everything below.
	for label: String in ["zip", "pck"]:
		var r := ModPackReader.open(zip_path if label == "zip" else pck_path)
		_ok(r.error.is_empty(), "pack/%s opens" % label, r.error)
		var files := r.files()
		files.sort()
		_eq(files, PackedStringArray(["res://mods/t.one/m.gd", "res://mods/t.one/mod.json"]),
			"pack/%s lists res:// paths" % label)
		_eq(r.read("res://mods/t.one/m.gd").get_string_from_utf8(),
			"extends RetroMod", "pack/%s reads a member" % label)
		_eq(str(r.read_json("res://mods/t.one/mod.json").get("id", "")),
			"t.one", "pack/%s parses json" % label)
		_ok(r.read("res://nope").is_empty(), "pack/%s misses cleanly" % label)
		r.close()

	var bad := ModPackReader.open(_dir.path_join("nope.zip"))
	_ok(not bad.error.is_empty(), "pack/absent file errors")
	var wrong := ModPackReader.open(_dir.path_join("pack.txt"))
	_ok(not wrong.error.is_empty(), "pack/unknown extension refused")


# ── manifest/ ─────────────────────────────────────────────────────────────────

func _group_manifest() -> void:
	var good := ModManifest.parse({
		"id": "a.b", "api_version": 1, "entry": "res://mods/a.b/m.gd",
		"name": "Nice", "version": "1.2.3", "priority": 5,
	})
	_ok(good.error.is_empty(), "manifest/valid parses", good.error)
	_eq(good.own_root(), "res://mods/a.b/", "manifest/own root")
	_eq(good.priority, 5, "manifest/priority kept")

	_ok(not ModManifest.parse({"api_version": 1, "entry": "x"}).error.is_empty(),
		"manifest/no id refused")
	_ok(not ModManifest.parse({"id": "Bad", "api_version": 1, "entry": "res://mods/Bad/m.gd"}).error.is_empty(),
		"manifest/upper-case id refused")
	_ok(not ModManifest.parse({"id": "a.b", "entry": "res://mods/a.b/m.gd"}).error.is_empty(),
		"manifest/no api_version refused")
	# A future mod is refused by version, not by crashing on its contents. This
	# is the break marker doing its job.
	var future := ModManifest.parse({"id": "a.b", "api_version": 9999,
		"entry": "res://mods/a.b/m.gd"})
	_ok(not future.error.is_empty(), "manifest/future api refused")
	_ok(future.error.contains("newer"), "manifest/future says which", future.error)
	_ok(not ModManifest.parse({"id": "a.b", "api_version": 1, "entry": "res://Scripts/evil.gd"}).error.is_empty(),
		"manifest/entry outside namespace refused")

	var here := ModManifest.parse({"id": "a.b", "api_version": 1,
		"entry": "res://mods/a.b/m.gd", "platforms": [OS.get_name()]})
	_ok(here.runs_here(), "manifest/runs on this platform")
	var elsewhere := ModManifest.parse({"id": "a.b", "api_version": 1,
		"entry": "res://mods/a.b/m.gd", "platforms": ["Nintendo64"]})
	_ok(not elsewhere.runs_here(), "manifest/other platform excluded")
	_ok(good.runs_here(), "manifest/no platforms means all")


# ── inventory/ ────────────────────────────────────────────────────────────────

func _group_inventory() -> void:
	var m := ModManifest.parse({"id": "a.b", "api_version": 1,
		"entry": "res://mods/a.b/m.gd"})
	_ok(m.inventory_error(PackedStringArray(["res://mods/a.b/m.gd"])).is_empty(),
		"inventory/own files accepted")
	_ok(not m.inventory_error(PackedStringArray()).is_empty(), "inventory/empty container refused")
	_ok(not m.inventory_error(PackedStringArray(["res://mods/other/x.gd"])).is_empty(),
		"inventory/nothing of its own refused")
	_ok(not m.inventory_error(PackedStringArray( ["res://mods/a.b/m.gd", "res://Textures/x.png"])).is_empty(),
		"inventory/unclaimed outside path refused")
	_ok(not m.inventory_error(PackedStringArray( ["res://mods/a.b/m.gd", "res://mods/victim/m.gd"])).is_empty(),
		"inventory/another mod's namespace refused")

	# The three files that would damage the RUNNING game rather than merely fail
	# — a mod's own export carries these, so this is not a hypothetical.
	for path: String in ModManifest.FORBIDDEN:
		var err := m.inventory_error(PackedStringArray(["res://mods/a.b/m.gd", path]))
		_ok(not err.is_empty(), "inventory/refuses %s" % path.get_file())

	# An SDK leak IS an unclaimed outside path — the namespace rule is what
	# stops an author's stale copy of a shipped class replacing the real one.
	_ok(not m.inventory_error(PackedStringArray( ["res://mods/a.b/m.gd", "res://Scripts/Objects/widgets/vr_hinge.gd"])).is_empty(),
		"inventory/SDK leak refused")

	var claiming := ModManifest.parse({"id": "a.b", "api_version": 1,
		"entry": "res://mods/a.b/m.gd", "claims": ["res://Textures/x.png"]})
	_ok(claiming.inventory_error(PackedStringArray( ["res://mods/a.b/m.gd", "res://Textures/x.png"])).is_empty(),
		"inventory/claimed path accepted")
	# ...but claiming does NOT buy a pass on the fatal three.
	_ok(not ModManifest.parse({"id": "a.b", "api_version": 1, "entry": "res://mods/a.b/m.gd", "claims": ["res://project.binary"]} ).inventory_error(PackedStringArray( ["res://mods/a.b/m.gd", "res://project.binary"])).is_empty(),
		"inventory/claim cannot buy project.binary")

	# A claim on a path the game does not ship ADDS a file; only a claim that
	# lands on a shipped one shadows it, and only that needs replace_files.
	var adder := ModManifest.parse({"id": "a.b", "api_version": 1,
		"entry": "res://mods/a.b/m.gd",
		"claims": ["res://Textures/SystemIcons/does_not_exist.svg"]})
	_eq(adder.shadowing_claims().size(), 0, "inventory/adding claim is not shadowing")
	_eq(adder.adding_claims().size(), 1, "inventory/adding claim counted")
	var shadower := ModManifest.parse({"id": "a.b", "api_version": 1,
		"entry": "res://mods/a.b/m.gd",
		"claims": ["res://Scripts/Objects/widgets/vr_hinge.gd"]})
	_eq(shadower.shadowing_claims().size(), 1, "inventory/shadowing claim detected")


# ── registry/ ─────────────────────────────────────────────────────────────────

const _SCRIPT := "res://Scripts/Objects/system_models/default_model.gd"

func _group_registry() -> void:
	var owner := "t.reg"
	_eq(SystemModelRegistry.register_mod_row(
		"t.reg:box", {"platform": "nes", "label": "Box", "script": _SCRIPT}, owner), "", "registry/row registers")
	_eq(str(SystemModelRegistry.resolve("t.reg:box", "nes").get("id", "")), "t.reg:box",
		"registry/resolves")
	_ok(SystemModelRegistry.is_available("t.reg:box"), "registry/is available")
	_ok(SystemModelRegistry.is_mod_row("t.reg:box"), "registry/marked as a mod row")
	_eq(SystemModelRegistry.owner_of("t.reg:box"), owner, "registry/owner recorded")

	# A shipped platform's DEFAULT must not change because a mod added a row.
	_eq(str(SystemModelRegistry.resolve("", "nes").get("id", "")),
		"nes", "registry/shipped default unchanged")

	_ok(not SystemModelRegistry.register_mod_row( "t.reg:box", {"platform": "nes", "label": "X", "script": _SCRIPT}, owner).is_empty(),
		"registry/duplicate refused")
	_ok(not SystemModelRegistry.register_mod_row( "nes", {"platform": "nes", "label": "X", "script": _SCRIPT}, owner).is_empty(),
		"registry/shipped id refused")

	# validate_row is shared with model_registry_probe, so these are the same
	# rules the shipped table is held to.
	_ok(not SystemModelRegistry.register_mod_row( "t.reg:a", {"label": "A", "script": _SCRIPT}, owner).is_empty(),
		"registry/no platform refused")
	_ok(not SystemModelRegistry.register_mod_row( "t.reg:b", {"platform": "nes", "label": "B", "script": _SCRIPT, "scene": "res://Scenes/Objects/system_models/nes.tscn"}, owner).is_empty(),
		"registry/both scene and script refused")
	_ok(not SystemModelRegistry.register_mod_row( "t.reg:c", {"platform": "nes", "label": "C"}, owner).is_empty(),
		"registry/neither refused")
	_ok(not SystemModelRegistry.register_mod_row( "t.reg:d", {"platform": "nes", "label": "D", "script": "res://nope.gd"}, owner).is_empty(),
		"registry/missing file refused")

	_eq(SystemModelRegistry.override_mod_row(
		"wii", {"platform": "wii", "label": "Modded Wii", "script": _SCRIPT}, owner), "", "registry/override registers")
	_eq(str(SystemModelRegistry.resolve("wii", "wii").get("id", "")),
		"wii", "registry/override keeps the id")
	_eq(str(SystemModelRegistry.resolve("wii", "wii").get("label", "")),
		"Modded Wii", "registry/override replaces the label")
	_ok(not SystemModelRegistry.override_mod_row("nope", {"platform": "x", "label": "L", "script": _SCRIPT}, owner).is_empty(),
		"registry/override of an unknown id refused")

	# Mod models must stay OUT of the boot warm, or boot time becomes a function
	# of how many mods are installed.
	_ok(not SystemModelRegistry.stand_in_ids().has("t.reg:box"),
		"registry/mod row not in the warm set")

	SystemModelRegistry.drop_mod(owner)
	_ok(SystemModelRegistry.row_for("t.reg:box").is_empty(), "registry/drop removes the row")
	_eq(str(SystemModelRegistry.resolve("wii", "wii").get("label", "")),
		"Wii", "registry/drop restores the shipped row")
	# The whole point of the fallback: a save naming a model that has gone still
	# lands on something spawnable rather than on nothing.
	_eq(str(SystemModelRegistry.resolve("t.reg:box", "nes").get("id", "")),
		"nes", "registry/removed model falls back")


# ── rooms/ ────────────────────────────────────────────────────────────────────

func _group_rooms() -> void:
	# The collapsed descriptor must still describe the shipped rooms exactly.
	_eq(RoomCatalog.path_of("arcade"), "res://Scenes/MainScene.tscn", "rooms/arcade path")
	_eq(RoomCatalog.title_of("bedroom"), "90s BEDROOM", "rooms/bedroom loading title")
	_eq(RoomCatalog.menu_title_of("bedroom"), "90s Bedroom", "rooms/bedroom menu title")
	_ok(RoomCatalog.has_slots("arcade"), "rooms/arcade keeps slots")
	_ok(not RoomCatalog.has_slots("den"), "rooms/den keeps none")
	_eq(RoomCatalog.slot_rooms(), ["arcade", "bedroom", "passthrough"], "rooms/slot rooms")
	_ok(not RoomCatalog.has("nope"), "rooms/unknown room is absent")

	var owner := "t.room"
	_eq(RoomCatalog.register_mod_room("t.room:attic", {
		"path": "res://Scenes/DenScene.tscn", "menu_title": "The Attic"}, owner), "", "rooms/registers")
	_ok(RoomCatalog.has("t.room:attic"), "rooms/mod room exists")
	_ok(RoomCatalog.is_mod_room("t.room:attic"), "rooms/marked as a mod room")
	_eq(RoomCatalog.menu_title_of("t.room:attic"), "The Attic", "rooms/menu title kept")
	_eq(RoomCatalog.title_of("t.room:attic"), "THE ATTIC", "rooms/loading title derived")
	_ok(RoomCatalog.has_slots("t.room:attic"), "rooms/defaults to keeping slots")
	_ok(not RoomCatalog.register_mod_room( "arcade", {"path": "res://Scenes/DenScene.tscn"}, owner).is_empty(),
		"rooms/shipped id refused")
	_ok(not RoomCatalog.register_mod_room( "t.room:void", {"path": "res://Scenes/Nope.tscn"}, owner).is_empty(),
		"rooms/missing scene refused")
	_ok(not RoomCatalog.register_mod_room("t.room:void2", {}, owner).is_empty(),
		"rooms/no path refused")
	RoomCatalog.drop_mod(owner)
	_ok(not RoomCatalog.has("t.room:attic"), "rooms/drop removes it")
	_eq(RoomCatalog.ids().size(), 5, "rooms/shipped rooms survive a drop")

	# Pad art tracked no owner until the overlay tables were shared, so a mod's
	# drawing could be registered and never taken back.
	var art_owner := "t.art"
	var art_row := {"anchors": {"a": Vector2(0.5, 0.5)}, "rows": [["a"]]}
	_eq(ConsolePadArt.register_mod_row("t.art:pad", art_row, art_owner), "",
		"pad art/a good row reports no error")
	_ok(ConsolePadArt.has("t.art:pad"), "pad art/mod row registers")
	# These three registries used to return void and drop bad input where they
	# stand, while ModApi reported success and filed the contribution anyway.
	_ok(not ConsolePadArt.register_mod_row("", art_row, art_owner).is_empty(),
		"pad art/an empty systemid is refused out loud")
	_eq(ConsolePadArt.owner_of("t.art:pad"), art_owner, "pad art/owner recorded")
	_ok(not ConsolePadArt.row("t.art:pad").is_empty(), "pad art/row is served")
	ConsolePadArt.drop_mod(art_owner)
	_ok(not ConsolePadArt.has("t.art:pad"), "pad art/drop removes it")
	_ok(ConsolePadArt.has("nes"), "pad art/shipped art survives a drop")


# ── objects/ ──────────────────────────────────────────────────────────────────

func _group_objects() -> void:
	var owner := "t.obj"
	var scene := "res://Scenes/Objects/table.tscn"
	if not ResourceLoader.exists(scene):
		scene = "res://Scenes/Objects/system.tscn"
	_eq(ScenePersistence.register_mod_object(
		"t.obj:crate", scene, owner), "", "objects/registers")
	_ok(ScenePersistence.is_mod_object("t.obj:crate"), "objects/known")
	_eq(ScenePersistence.mod_object_scene("t.obj:crate"), scene, "objects/scene recorded")
	_ok(not ScenePersistence.register_mod_object( "table", scene, owner).is_empty(),
		"objects/shipped type refused")
	_ok(not ScenePersistence.register_mod_object( "t.obj:crate", scene, owner).is_empty(),
		"objects/duplicate refused")
	_ok(not ScenePersistence.register_mod_object( "t.obj:void", "res://nope.tscn", owner).is_empty(),
		"objects/missing scene refused")

	# The instance must carry the stamp _serialize_node recognises, or it saves
	# as its base class and loses the scene it came from.
	var inst := ScenePersistence._instantiate_mod_object("t.obj:crate")
	_ok(inst != null, "objects/instantiates")
	if inst != null:
		_eq(str(inst.get_meta(ScenePersistence.MOD_TYPE_META)),
			"t.obj:crate", "objects/carries its type stamp")
		inst.free()

	ScenePersistence.drop_mod_objects(owner)
	_ok(not ScenePersistence.is_mod_object("t.obj:crate"), "objects/drop removes it")

	# A mod's LEAD saves as a lead. It used to be written as a pose alone, like
	# any other mod prop, so a room came back with the lead on the floor and
	# nothing plugged in. A shipped lead stands in for the mod's scene.
	var lead_type := "t.lead:av"
	var lead_scene := "res://Scenes/Objects/system_models/dreamcast/dc_av_cable.tscn"
	_eq(ScenePersistence.register_mod_object(lead_type, lead_scene, "t.lead"), "",
		"objects/a lead registers")
	var store := ScenePersistence.new("__mod_selftest")
	var lead := ScenePersistence._instantiate_mod_object(lead_type) as CompositeCable
	lead.cord_length = 2.5
	add_child(lead)
	var plug := lead.get_node("PlugA0") as Node3D
	plug.global_position = Vector3(1.0, 2.0, 3.0)
	var entry := store.serialize_node(lead, 4, {lead: 4})
	_eq(str(entry.get("type", "")), lead_type, "objects/a lead keeps its mod type")
	var plugs: Array = entry.get("plugs", [])
	_eq(plugs.size(), 4, "objects/a lead saves every plug")
	var first: Dictionary = plugs[0] if not plugs.is_empty() else {}
	_eq(first.get("position", []), [1.0, 2.0, 3.0], "objects/with where each plug is")
	_eq(float(entry.get("cord_length", 0.0)), 2.5, "objects/and its cord length")
	_eq(ScenePersistence._objects_validation_error([entry]), "",
		"objects/a saved lead validates")
	lead.free()
	var back := store.deserialize_object(entry) as CompositeCable
	_ok(back != null and back.scene_file_path == lead_scene
		and str(back.get_meta(ScenePersistence.MOD_TYPE_META, "")) == lead_type,
		"objects/a lead restores from the mod's scene")
	if back != null:
		_eq(back.cord_length, 2.5, "objects/with its cord length")
		add_child(back)
		back.restore_plug_poses(entry.get("plugs", []))
		_ok((back.get_node("PlugA0") as Node3D).global_position.is_equal_approx(
			Vector3(1.0, 2.0, 3.0)), "objects/and its plugs where they were")
		back.free()
	# An ordinary mod prop is still a pose and nothing else.
	ScenePersistence.register_mod_object("t.lead:crate", scene, "t.lead")
	var crate := ScenePersistence._instantiate_mod_object("t.lead:crate")
	add_child(crate)
	var plain := store.serialize_node(crate, 5, {crate: 5})
	_ok(str(plain.get("type", "")) == "t.lead:crate" and not plain.has("plugs"),
		"objects/a plain prop still saves as a pose")
	crate.free()
	# And a mod's PAD saves as a pad: by the scene it came from, with its port.
	# A shipped pad stands in for the mod's scene.
	var pad_scene := "res://Scenes/Objects/controllers/playstation/ps1_controller.tscn"
	ScenePersistence.register_mod_object("t.lead:pad", pad_scene, "t.lead")
	var pad := ScenePersistence._instantiate_mod_object("t.lead:pad")
	_ok(pad is RetroController, "objects/a mod pad instantiates as a controller")
	add_child(pad)
	var pad_entry := store.serialize_node(pad, 6, {pad: 6})
	_eq(str(pad_entry.get("scene", "")), pad_scene, "objects/a mod pad saves the scene it came from")
	_eq(str(pad_entry.get("type", "")), "retro_controller",
		"objects/as a controller entry, which is what carries its port, not as a bare prop")
	_ok(ScenePersistence.is_known_controller_scene(pad_scene), "objects/and that scene is one a save may name")
	pad.free()
	# A mod's LIGHT GUN saves as a gun, by the scene it came from, and comes back
	# as that gun. The shipped gun under another path stands in for the mod's.
	var shipped_gun := (load("res://Scenes/Objects/peripherals/light_gun.tscn") as PackedScene).instantiate()
	var gun_packed := PackedScene.new()
	gun_packed.pack(shipped_gun)
	shipped_gun.free()
	var gun_scene := "%s/mod_gun.tscn" % _dir
	ResourceSaver.save(gun_packed, gun_scene)
	ScenePersistence.register_mod_object("t.lead:gun", gun_scene, "t.lead")
	var gun := ScenePersistence._instantiate_mod_object("t.lead:gun")
	_ok(gun is LightGun, "objects/a mod gun instantiates as a light gun")
	add_child(gun)
	var gun_entry := store.serialize_node(gun, 7, {gun: 7})
	_eq(str(gun_entry.get("type", "")), "light_gun",
		"objects/a mod gun saves as a light gun entry, which is what carries its port")
	_eq(str(gun_entry.get("scene", "")), gun_scene, "objects/with the scene it came from")
	_ok(gun_entry.has("port_index"), "objects/and its port")
	gun.free()
	var gun_back := store.deserialize_object(gun_entry)
	_ok(gun_back is LightGun and gun_back.scene_file_path == gun_scene,
		"objects/a save brings the mod's gun back, not the generic one")
	if gun_back != null:
		gun_back.free()
	var plain_gun := (load("res://Scenes/Objects/peripherals/light_gun.tscn") as PackedScene).instantiate() as Node3D
	add_child(plain_gun)
	var plain_entry := store.serialize_node(plain_gun, 8, {plain_gun: 8})
	_ok(not plain_entry.has("scene"), "objects/the game's own gun saves as it always did")
	plain_gun.free()
	var stray := gun_entry.duplicate()
	stray["scene"] = "res://Scenes/Objects/controllers/playstation/ps1_controller.tscn"
	var stray_back := store.deserialize_object(stray)
	_ok(stray_back is LightGun and stray_back.scene_file_path == "res://Scenes/Objects/peripherals/light_gun.tscn",
		"objects/a gun entry naming something that is not a gun gets the generic gun")
	if stray_back != null:
		stray_back.free()
	ScenePersistence.drop_mod_objects("t.lead")


# ── media/ ────────────────────────────────────────────────────────────────────

func _group_media() -> void:
	var sid := "t_media_platform"
	_eq(MediaDimensions.register_mod_media(sid, {
		"cart_size": Vector3(0.1, 0.2, 0.01)}), "", "media/registers")
	_eq(MediaDimensions.cart_size(sid), Vector3(0.1, 0.2, 0.01), "media/cart size")
	_ok(MediaDimensions.has_cart_size(sid), "media/has a cart size")
	_ok(not MediaDimensions.is_disc_system(sid), "media/cartridge system is not a disc one")
	_eq(MediaDimensions.disc_loader(sid), MediaDimensions.LOADER_NONE,
		"media/no disc means no loader")

	var disc := "t_disc_platform"
	MediaDimensions.register_mod_media(disc, {"disc_diameter": 0.12})
	_ok(MediaDimensions.is_disc_system(disc), "media/disc system")
	_eq(MediaDimensions.disc_loader(disc), MediaDimensions.LOADER_TRAY, "media/tray by default")
	var slot := "t_slot_platform"
	MediaDimensions.register_mod_media(slot, {"disc_diameter": 0.12, "slot_load": true})
	_eq(MediaDimensions.disc_loader(slot), MediaDimensions.LOADER_SLOT, "media/slot load")
	_ok(not MediaDimensions.register_mod_media("t_bad", {"slot_load": true}).is_empty(),
		"media/slot without a disc refused")
	_ok(not MediaDimensions.register_mod_media("t_bad2", {"cart_size": "big"}).is_empty(),
		"media/bad cart size refused")
	# A shipped platform must be untouched by any of this.
	_eq(MediaDimensions.disc_loader("nes"), MediaDimensions.LOADER_NONE,
		"media/shipped nes unchanged")

	# Without a scraper mapping a platform's carts stay blank for ever, and
	# nothing anywhere says why — so the mapping is a first-class registration.
	_eq(ScreenscraperSystems.get_systemeid("t_media_platform"), -1, "media/unmapped platform")
	_eq(ScreenscraperSystems.register_mod_system("t_media_platform", 4242), "",
		"media/a good mapping reports no error")
	_eq(ScreenscraperSystems.get_systemeid("t_media_platform"), 4242, "media/mapped platform")
	_eq(ScreenscraperSystems.get_systemeid("nes"), 3, "media/shipped mapping unchanged")
	_ok(not ScreenscraperSystems.register_mod_system("t_bad", 0).is_empty(),
		"media/a non-positive screenscraper id is refused out loud")
	_ok(not SpawnCatalog.register_mod_peripherals("t_bad", [], "t.bad").is_empty(),
		"media/an empty peripheral list is refused rather than reported as added")

	# Two mods adding pads to ONE console land in one list, so dropping either
	# must take only its own rows. drop_mod erased the whole systemid, which
	# left the console short of the surviving mod's pads with nothing to say why.
	var pad_a := "t.pads_a"
	var pad_b := "t.pads_b"
	SpawnCatalog.register_mod_peripherals("nes",
		[{"label": "A pad", "spawn": "retro_controller"}], pad_a)
	SpawnCatalog.register_mod_peripherals("nes",
		[{"label": "B pad", "spawn": "retro_controller"}], pad_b)
	var labels := func() -> Array:
		var out: Array = []
		for it: Variant in SpawnCatalog.items_for("nes"):
			out.append(str((it as Dictionary).get("label", "")))
		return out
	_ok(labels.call().has("A pad") and labels.call().has("B pad"),
		"peripherals/both mods' rows are offered")
	SpawnCatalog.drop_mod(pad_a)
	_ok(not labels.call().has("A pad"), "peripherals/dropping one mod removes its row")
	_ok(labels.call().has("B pad"),
		"peripherals/and leaves the other mod's row on the same console")
	SpawnCatalog.drop_mod(pad_b)
	_ok(not labels.call().has("B pad"), "peripherals/dropping the second removes it too")
	_ok(labels.call().has("Controller"),
		"peripherals/the console's shipped rows survive both drops")

	# These three tables tracked no owner, so what a mod contributed to them
	# could be registered and never taken back — the exact defect the shared
	# overlay tables were extracted to end, in the three that did not adopt one.
	var withdrawn := "t.withdraw"
	MediaDimensions.register_mod_media("t_withdraw_platform",
		{"disc_diameter": 0.12}, withdrawn)
	_eq(ScreenscraperSystems.register_mod_system("t_withdraw_platform", 909, withdrawn), "",
		"withdraw/a mapping registers under an owner")
	var info := SystemInfo.new()
	info.systemid = "t_withdraw_platform"
	_eq(SystemInfo.register_mod_info(info, withdrawn), "",
		"withdraw/a good descriptor reports no error")
	_ok(not SystemInfo.register_mod_info(null, withdrawn).is_empty(),
		"withdraw/a null descriptor is refused out loud")
	_ok(not SpawnCatalog.register_mod_spawnable("", {"label": "X"}, withdrawn).is_empty(),
		"withdraw/a spawnable with no type is refused out loud")
	_ok(SystemInfo.for_system("t_withdraw_platform") != null, "withdraw/descriptor is served")

	MediaDimensions.drop_mod(withdrawn)
	ScreenscraperSystems.drop_mod(withdrawn)
	SystemInfo.drop_mod(withdrawn)
	_eq(MediaDimensions.disc_loader("t_withdraw_platform"), MediaDimensions.LOADER_NONE,
		"withdraw/media goes back")
	_eq(ScreenscraperSystems.get_systemeid("t_withdraw_platform"), -1,
		"withdraw/the scraper mapping goes back")
	_ok(SystemInfo.for_system("t_withdraw_platform") == null,
		"withdraw/the descriptor goes back, negative cache and all")
	# Another mod's rows, and every shipped row, survive one mod being dropped.
	_eq(ScreenscraperSystems.get_systemeid("t_media_platform"), 4242,
		"withdraw/another owner's mapping survives")
	_eq(ScreenscraperSystems.get_systemeid("nes"), 3, "withdraw/shipped mapping survives")


# ── shaders/ ──────────────────────────────────────────────────────────────────

func _group_shaders() -> void:
	# Landing place 1: a shell that says nothing gets the stock CRT. Asserted on
	# the base class, which is what every shipped cabinet uses.
	var shell := RetroTVShell.new()
	_ok(shell.screen_shader() == null, "shaders/stock is the default")
	shell.free()

	# Landing place 2: a built-in by name, and the SAME resource rather than a
	# second copy — asking for one must not cost a compile.
	var crt := ModShaders.get_shader("crt")
	_ok(crt != null, "shaders/crt by name")
	_ok(crt == ModShaders.get_shader("crt"), "shaders/same resource twice")
	_ok(crt == load("res://Shaders/crt_effect.gdshader"), "shaders/is the shipped crt")
	for shader_name: String in ModShaders.names():
		_ok(ModShaders.get_shader(shader_name) != null, "shaders/%s resolves" % shader_name)
	# An unknown name must not hand back a null that lands in a material and
	# paints nothing, with no clue why.
	_ok(not ModShaders.has("no_such_shader"), "shaders/unknown name is not known")


# ── removal/ ──────────────────────────────────────────────────────────────────
#
# The group that guards player data. Removing a mod used to make every save slot
# containing one of its props UNREADABLE — the player lost the room, not the
# prop. These are the cases that must never regress.

func _group_removal() -> void:
	var objects: Array = [
		{"id": 0, "type": "table", "position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"id": 1, "type": "gone.mod:lamp", "position": [1, 0, 0], "rotation": [0, 0, 0]},
		{"id": 2, "type": "tv_remote", "position": [2, 0, 0], "rotation": [0, 0, 0],
			"system": 1},
		{"id": 3, "type": "gone.mod:rug", "position": [3, 0, 0], "rotation": [0, 0, 0]},
	]
	var kept := ScenePersistence._prune_unknown_types(objects, "test")
	_eq(kept.size(), 2, "removal/keeps everything else")
	_eq(_types_of(kept), ["table", "tv_remote"], "removal/dropped the mod props")
	# Dropping an entry creates dangling references. Not scrubbing them turns
	# "one missing prop" straight back into "the whole slot is invalid".
	var remote := _entry_of(kept, "tv_remote")
	_ok(remote.get("system") == null, "removal/dangling reference scrubbed")
	_eq(ScenePersistence._objects_validation_error(kept),
		"", "removal/slot still validates")

	# A slot with nothing missing must come back byte-identical, not merely
	# equivalent — this path runs on every load.
	var clean: Array = [{"id": 0, "type": "table", "position": [0, 0, 0],
		"rotation": [0, 0, 0]}]
	_ok(ScenePersistence._prune_unknown_types(clean, "test") == clean,
		"removal/untouched when nothing is missing")

	# An unknown entry with NO id. Every case above gives one, which is why this
	# went unnoticed: the early return keyed on the dropped IDS rather than on
	# whether anything was dropped, so an id-less row was pruned from the kept
	# list and then handed back anyway in the original array. The validator
	# rejected it and failed the entire slot — the outcome pruning exists to
	# prevent. A save written before ids were recorded looks exactly like this.
	var idless: Array = [
		{"id": 0, "type": "table", "position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"type": "gone.mod:lamp", "position": [1, 0, 0], "rotation": [0, 0, 0]},
	]
	var pruned := ScenePersistence._prune_unknown_types(idless, "test")
	_eq(pruned.size(), 1, "removal/an unknown entry with no id is still dropped")
	_eq(_types_of(pruned), ["table"], "removal/and the known one survives")
	_eq(ScenePersistence._objects_validation_error(pruned), "",
		"removal/so the slot still validates")

	# And the guard that must NOT be weakened: structural corruption is still
	# all-or-nothing. Only an unrecognised type is survivable.
	_ok(not ScenePersistence._objects_validation_error( [{"id": -1, "type": "table"}]).is_empty(),
		"removal/negative id still refused")
	_ok(not ScenePersistence._objects_validation_error( [{"id": 0, "type": "table"}, {"id": 0, "type": "table"}]).is_empty(),
		"removal/duplicate id still refused")
	_ok(not ScenePersistence._objects_validation_error( [{"id": 0, "type": "tv_remote", "system": 77}]).is_empty(),
		"removal/reference to a never-existing id still refused")

	# Through a REAL slot file, not just the pure function.
	#
	# Every case above calls _prune_unknown_types directly, which proves the
	# function works and proves nothing about it being wired in — deleting the
	# call in _read_objects left all of them green. This is the one that fails if
	# the pruning is not actually on the load path.
	var store := ScenePersistence.new("__mod_selftest")
	var slot_dir := store.slot_dir()
	DirAccess.make_dir_recursive_absolute(slot_dir)
	var slot_path := slot_dir.path_join("selftest.json")
	var f := FileAccess.open(slot_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": ScenePersistence.VERSION,
			"objects": objects}))
		f.close()
		var read: Variant = store._read_objects(slot_path)
		_ok(read != null,
			"removal/a real slot with a missing mod still loads", "the whole slot was refused")
		if read is Array:
			_eq(_types_of(read as Array),
				["table", "tv_remote"], "removal/and comes back without the missing props")
		DirAccess.remove_absolute(slot_path)
	DirAccess.remove_absolute(slot_dir)

	# A registered mod prop is NOT pruned while its mod is loaded.
	var owner := "t.keep"
	var scene := "res://Scenes/Objects/system.tscn"
	ScenePersistence.register_mod_object("t.keep:thing", scene, owner)
	var live: Array = [{"id": 0, "type": "t.keep:thing", "position": [0, 0, 0],
		"rotation": [0, 0, 0]}]
	_eq(ScenePersistence._prune_unknown_types(live, "test").size(),
		1, "removal/loaded mod prop survives")
	ScenePersistence.drop_mod_objects(owner)
	_eq(ScenePersistence._prune_unknown_types(live, "test").size(),
		0, "removal/same prop drops once the mod is gone")


func _types_of(entries: Array) -> Array:
	var out: Array = []
	for e: Variant in entries:
		out.append(str((e as Dictionary)["type"]))
	return out


func _entry_of(entries: Array, type: String) -> Dictionary:
	for e: Variant in entries:
		if str((e as Dictionary)["type"]) == type:
			return e as Dictionary
	return {}


# ── netplay/ ──────────────────────────────────────────────────────────────────

func _group_netplay() -> void:
	# With nothing loaded the fingerprint is empty, so two stock builds match and
	# the check costs an untouched room nothing.
	# The player's autoload may have installed mods. An empty manager is the
	# fixture here; never disable real mods or depend on the player's enable list.
	var empty_manager: Node = load("res://Scripts/Mods/mod_manager.gd").new()
	_eq(empty_manager.fingerprint().size(), 0, "netplay/no mods means an empty fingerprint")
	empty_manager.free()

	var ours := PackedStringArray(["a@1.0.0", "b@2.0.0"])
	var same := PackedStringArray(["a@1.0.0", "b@2.0.0"])
	_ok(ours == same, "netplay/identical sets match")
	_ok(ours == PackedStringArray(["a@1.0.0", "b@2.0.0"]), "netplay/order-independent by sorting")
	_ok(ours != PackedStringArray(["a@1.0.0", "b@2.0.1"]),
		"netplay/a different version is a mismatch")

	var msg := Mods.fingerprint_mismatch(ours, PackedStringArray(["a@1.0.0"]))
	_ok(msg.contains("b@2.0.0"), "netplay/names what is missing", msg)
	var msg2 := Mods.fingerprint_mismatch(PackedStringArray(["a@1.0.0"]), ours)
	_ok(msg2.contains("extra"), "netplay/names what is extra", msg2)


# ── consistency/ ──────────────────────────────────────────────────────────────
#
# Cross-table invariants the codebase documents but never checked. A mod
# platform is what would break either of them first.

func _group_consistency() -> void:
	# model_registry.gd lists the computer platforms by hand and says they must
	# match SystemInfo.computer. Nothing enforced it until now.
	var declared: Array = []
	for id: String in SystemModelRegistry.all_ids():
		var row := SystemModelRegistry.row_for(id)
		var field: Variant = row.get("platform", "")
		if field is Array:
			declared.append_array(field as Array)
	var mismatched := PackedStringArray()
	for sid: String in declared:
		var info := SystemInfo.for_system(sid)
		if info == null or not info.computer:
			mismatched.append(sid)
	_eq(", ".join(mismatched),
		"", "consistency/computer platforms match SystemInfo.computer")

	# system_info.gd says MediaType intentionally matches MediaDimensions.LOADER_*
	# so the two "never disagree". They are separate tables, so check it.
	_eq(int(SystemInfo.MediaType.CARTRIDGE),
		MediaDimensions.LOADER_NONE, "consistency/CARTRIDGE == LOADER_NONE")
	_eq(int(SystemInfo.MediaType.DISC_TRAY),
		MediaDimensions.LOADER_TRAY, "consistency/DISC_TRAY == LOADER_TRAY")
	_eq(int(SystemInfo.MediaType.DISC_INSERT),
		MediaDimensions.LOADER_SLOT, "consistency/DISC_INSERT == LOADER_SLOT")

	# EVERY descriptor, not just the platforms that happen to have a model row.
	# Checking only those hid the PS2, which has no row and disagreed just as
	# loudly as the PSP that was caught.
	var disagree := PackedStringArray()
	var checked := 0
	var dir := DirAccess.open("res://SystemInfo")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			# Exported builds remap .tres to .remap, so match on the stem.
			if not dir.current_is_dir() and f.get_extension() in ["tres", "remap"]:
				var sid := f.get_basename()
				if sid.get_extension() == "tres":
					sid = sid.get_basename()
				var info := SystemInfo.for_system(sid)
				if info != null:
					checked += 1
					if int(info.media_type) != MediaDimensions.disc_loader(sid):
						disagree.append("%s (%d vs %d)" % [sid, int(info.media_type),
							MediaDimensions.disc_loader(sid)])
			f = dir.get_next()
		dir.list_dir_end()
	_ok(checked > 50,
		"consistency/descriptors were actually read", "only %d read — the check would pass vacuously" % checked)
	_eq(", ".join(disagree), "", "consistency/media_type agrees with disc_loader")


# ── fixtures ──────────────────────────────────────────────────────────────────

func _write_zip(name: String, entries: Dictionary) -> String:
	var path := _dir.path_join(name)
	var z := ZIPPacker.new()
	if z.open(path) != OK:
		return path
	for member: String in entries:
		z.start_file(member)
		z.write_file(str(entries[member]).to_utf8_buffer())
		z.close_file()
	z.close()
	return path


func _write_pck(name: String, entries: Dictionary) -> String:
	var path := _dir.path_join(name)
	var p := PCKPacker.new()
	if p.pck_start(path) != OK:
		return path
	for member: String in entries:
		var tmp := _dir.path_join(member.get_file())
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_string(str(entries[member]))
		f.close()
		p.add_file("res://" + member, tmp)
	p.flush(false)
	return path


func _cleanup() -> void:
	var dir := DirAccess.open(_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(_dir.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(_dir)


# ── assertions ────────────────────────────────────────────────────────────────


# ── overlay/ ──────────────────────────────────────────────────────────────────
#
# ModOverlayTable is the bookkeeping several tables had each grown their own
# copy of, and those copies had drifted: two owner-key conventions, some with a
# merged cache and some rebuilding per read, and ConsolePadArt tracking no owner
# at all — so its rows could be registered and never withdrawn. The mechanism is
# now shared, which means one set of cases decides how every overlaid table
# behaves.
func _group_overlay() -> void:
	var base := {"nes": {"name": "shipped nes"}, "snes": {"name": "shipped snes"}}
	var t := ModOverlayTable.new(base)

	_eq(t.table(), base, "overlay/an untouched table is the shipped one")
	_ok(t.is_shipped("nes"), "overlay/a shipped key is shipped")
	_ok(not t.is_mod("nes"), "overlay/and is not a mod row")
	_eq(t.owner_of("nes"), "", "overlay/an untouched row has no owner")

	t.add("dreamcast", {"name": "modded dc"}, "xenu.dc")
	_eq(t.table()["dreamcast"]["name"], "modded dc", "overlay/an added row appears")
	_ok(t.is_mod("dreamcast"), "overlay/and is a mod row")
	_ok(not t.is_shipped("dreamcast"), "overlay/but is not shipped")
	_eq(t.owner_of("dreamcast"), "xenu.dc", "overlay/it remembers who added it")
	_eq(t.mod_keys(), ["dreamcast"], "overlay/and is listed as a mod key")

	# The distinction that matters for saves: overriding a shipped row does NOT
	# make it a mod row. Its id has to survive the mod being removed, because
	# rooms and saves name it.
	t.override("nes", {"name": "modded nes"}, "xenu.nes")
	_eq(t.table()["nes"]["name"], "modded nes", "overlay/an override replaces the shipped row")
	_ok(t.is_shipped("nes"), "overlay/an overridden row is STILL shipped")
	_ok(not t.is_mod("nes"), "overlay/and still not a mod row")
	_ok(t.has_override("nes"), "overlay/but it is marked overridden")
	_eq(t.owner_of("nes"), "xenu.nes", "overlay/and blames the mod that replaced it")
	_ok(not t.mod_keys().has("nes"), "overlay/an override is not a mod key")

	# The base is the base: a merged view must never write back into the shipped
	# table, or one mod's row would outlive every uninstall in the process.
	_eq(base["nes"]["name"], "shipped nes", "overlay/the shipped table is never mutated")

	# table() caches and rebuilds only when a registration changed it. A stale
	# read here is invisible: the caller loops over a table that looks right.
	var before: Dictionary = t.table()
	t.add("saturn", {"name": "modded saturn"}, "xenu.dc")
	_ok(t.table().has("saturn"), "overlay/the cache rebuilds after a registration")
	_eq(before.has("saturn"), false, "overlay/and the earlier copy is unaffected")

	# Withdrawal takes additions and overrides alike, and only this owner's.
	t.drop_owner("xenu.dc")
	_ok(not t.table().has("dreamcast"), "overlay/dropping an owner withdraws its addition")
	_ok(not t.table().has("saturn"), "overlay/including its later ones")
	_eq(t.table()["nes"]["name"], "modded nes",
		"overlay/but leaves another mod's override alone")
	_eq(t.owner_of("dreamcast"), "", "overlay/and forgets the owner it dropped")

	t.drop_owner("xenu.nes")
	_eq(t.table()["nes"]["name"], "shipped nes",
		"overlay/withdrawing an override restores the shipped row")
	_eq(t.table(), base, "overlay/and the table is the shipped one again")


## A mod's mains regions and its region callback go with it: withdraw() once
## left both, so a switched-off mod's outlets stayed on the dropdown and its
## callback went on running.
func _group_mains() -> void:
	_hooks = ModHooks.new(get_tree())
	var rid := "t_mr_island"
	_ok(not MainsRegions.has(rid), "mains/the region under test is not shipped")
	var a := _api("t.mra")
	_ok(a.register_mains_region(rid, {"name": "Island"}), "mains/a mod registers a region",
		a.errors_text())
	_ok(MainsRegions.has(rid), "mains/and the dropdown has it")
	var heard: Array = []
	a.on_mains_region_changed(func(region: String) -> void: heard.append(region))
	AppPrefs.mains_region_changed.emit("na")
	_eq(heard, ["na"], "mains/its callback hears a change")
	a.withdraw()
	_ok(not MainsRegions.has(rid), "mains/withdraw takes the region back")
	AppPrefs.mains_region_changed.emit("na")
	_eq(heard, ["na"], "mains/and disconnects its callback")

	# A later mod's entry under the same id is that mod's, not the first one's.
	var b := _api("t.mrb")
	var c := _api("t.mrc")
	b.register_mains_region(rid, {"name": "B"})
	c.register_mains_region(rid, {"name": "C"})
	b.withdraw()
	_eq(str(MainsRegions.of(rid).get("name", "")), "C",
		"mains/withdrawing an earlier mod leaves a later mod's region of the same id")
	c.withdraw()
	_ok(not MainsRegions.has(rid), "mains/and that mod's withdraw takes it")


# ── standins/ ─────────────────────────────────────────────────────────────────

func _labels(systemid: String) -> Array:
	var out: Array = []
	for item: Dictionary in SpawnCatalog.items_for(systemid):
		out.append(str(item.get("label", "")))
	return out


func _api(mod_id: String) -> ModApi:
	return ModApi.new(ModManifest.parse({"id": mod_id, "api_version": 1,
		"entry": "res://mods/%s/m.gd" % mod_id, "name": mod_id, "version": "1.0.0"}), _hooks)


var _hooks: ModHooks = null


## A scene file a test can register as a mod's object: written where a mod
## pack's would be read from, so the spawn card reads it the same way.
func _scene_file(name: String, body: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://mod_tests_scenes")
	var path := "user://mod_tests_scenes/%s.tscn" % name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()
	return path


## A lead whose console end is `connector`, with a phono at the set.
func _lead_scene(name: String, connector: String) -> String:
	return _scene_file(name, """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Scripts/Objects/cables/rca_plug.gd" id="1"]

[node name="Lead" type="Node3D"]

[node name="PlugA0" type="RigidBody3D" parent="."]
script = ExtResource("1")
connector = "%s"

[node name="PlugB0" type="RigidBody3D" parent="."]
script = ExtResource("1")
""" % connector)


## A pad (or, with `gun`, a light gun) made for `systemid`.
func _pad_scene(name: String, systemid: String, gun := false) -> String:
	var script := "res://Scripts/Objects/peripherals/light_gun.gd" if gun \
		else "res://Scripts/Objects/controllers/retro_controller.gd"
	return _scene_file(name, """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="%s" id="1"]

[node name="Pad" type="RigidBody3D"]
script = ExtResource("1")
systemid = "%s"
""" % [script, systemid])


## A stand-in stays on a card only while nothing installed does its job, and
## what fits a card is read from the object, not claimed by its mod.
func _group_standins() -> void:
	_hooks = ModHooks.new(get_tree())
	ConnectorScan.clear_cache()
	# A console the game ships no model of, so its card is all stand-ins.
	var sysid := "saturn"
	_ok(SystemModelRegistry.rows_for(sysid).is_empty(), "standins/the console under test has no model")
	var before := _labels(sysid)
	_ok(before.has("Primitive System") and before.has("Primitive Controller")
		and before.has("Composite Cable") and before.has("Light Gun"),
		"standins/its card is the stand-ins", str(before))

	# A mod's console takes the box off the card by being there.
	var a := _api("t.sa")
	_ok(a.register_model({"id": "t.sa:console", "platform": sysid, "label": "Saturn A",
		"script": _SCRIPT, "requires": [_SCRIPT], "sockets": ["t.sa:av"]}),
		"standins/a model listing its own socket registers", a.errors_text())
	var with_console := _labels(sysid)
	_ok(not with_console.has("Primitive System"), "standins/the box leaves the card")
	_ok(with_console.has("Saturn A"), "standins/the mod's console stays")
	_ok(with_console.has("Primitive Controller"), "standins/the stand-in pad stays: nothing fits its port")
	_ok(not with_console.has("Composite Cable"),
		"standins/with no phono jacks left on the card the composite lead goes")
	_ok("t.sa:av" in "; ".join(a.problems()), "standins/and its page says nothing fits its socket",
		"; ".join(a.problems()))
	var marked := 0
	for item: Dictionary in SpawnCatalog.items_for(sysid):
		marked += 1 if bool(item.get("default", false)) else 0
	_eq(marked, 0, "standins/a lone console is not marked default")

	# A second mod's console, with nothing said about its sockets: phono jacks.
	var b := _api("t.sb")
	_ok(b.register_model({"id": "t.sb:console", "platform": sysid, "label": "Saturn B",
		"script": _SCRIPT, "requires": [_SCRIPT]}), "standins/a second mod's console registers")
	var both := _labels(sysid)
	_ok(both.has("Saturn A") and both.has("Saturn B"), "standins/both consoles are offered")
	_ok(both.has("Composite Cable"), "standins/a console with phono jacks brings the composite lead back")
	var defaults: Array = []
	for item: Dictionary in SpawnCatalog.items_for(sysid):
		if bool(item.get("default", false)):
			defaults.append(str(item.get("model_id", "")))
	_eq(defaults, [str(SystemModelRegistry.resolve("", sysid).get("id", ""))],
		"standins/exactly the model the game falls back to is marked default")

	# A pad for this console, from a mod that names no card at all.
	var p := _api("t.pad")
	_ok(p.register_object("t.pad:pad", _pad_scene("t_pad", sysid)), "standins/a pad registers")
	var padded := _labels(sysid)
	_ok(not padded.has("Primitive Controller"), "standins/the stand-in pad leaves: a pad fits the port")
	_ok(padded.has("Pad"), "standins/and the mod's pad is offered, named after itself", str(padded))
	_ok(padded.has("Light Gun"), "standins/a pad does not take the gun's place")
	var g := _api("t.gun")
	_ok(g.register_object("t.gun:gun", _pad_scene("t_gun", sysid, true)), "standins/a gun registers")
	_ok(not _labels(sysid).has("Light Gun"), "standins/the generic gun leaves: a gun fits the port")
	g.withdraw()
	p.withdraw()
	var unpadded := _labels(sysid)
	_ok(unpadded.has("Primitive Controller") and unpadded.has("Light Gun"),
		"standins/both come back with their mods")

	a.withdraw()
	var only_b := _labels(sysid)
	_ok(not only_b.has("Primitive System") and only_b.has("Saturn B"),
		"standins/the box stays away while another mod's console is on the card")
	b.withdraw()
	_eq(_labels(sysid), before, "standins/with both gone the card is the stand-ins again")

	# A row that refers to the old field is told so.
	var old := _api("t.old")
	_ok(not old.register_model({"id": "t.old:console", "platform": sysid, "label": "Old",
		"script": _SCRIPT, "av_connector": "ps2_av_multi"}), "standins/av_connector is refused")
	_ok("sockets" in old.errors_text(), "standins/with what to use instead", old.errors_text())
	old.withdraw()

	# Pads by connector: consoles that share a port share pads.
	_eq(Connectors.controller_port_of("ps2"), Connectors.controller_port_of("psx"),
		"sockets/a PlayStation 2's pad port is a PlayStation's")
	_eq(Connectors.controller_port_of("genesis"), Connectors.controller_port_of("atari2600"),
		"sockets/a Genesis's is an Atari 2600's: the DE-9")
	_ok(Connectors.controller_port_of("snes") != Connectors.controller_port_of("nes"),
		"sockets/a Super NES's is not a NES's")
	var ds := _api("t.ds")
	_ok(ds.register_object("t.ds:pad", _pad_scene("t_ds", "ps2")),
		"sockets/a PlayStation 2 pad registers, on no card")
	_ok(_labels("ps2").has("Pad") and not _labels("ps2").has("Primitive Controller"),
		"sockets/its console's card offers it in the stand-in's place", str(_labels("ps2")))
	_eq(ConnectorScan.of_scene(ScenePersistence.mod_object_scene("t.ds:pad"))["plugs"],
		PackedStringArray([Connectors.controller_port_of("psx")]),
		"sockets/its plug fits a PlayStation's port too")
	_ok(not _labels("psx").has("Pad"), "sockets/but a PlayStation's card lists only pads made for it",
		str(_labels("psx")))
	ds.add_peripherals("ps2", [{"label": "Dual Pad", "spawn": "mod:t.ds:pad"}])
	_eq(_labels("ps2").count("Dual Pad"), 1, "sockets/listed on its card by its mod, it is there once")
	ds.withdraw()
	# Nor does a pad made for another console take this card's stand-in away.
	var gp := _api("t.gp")
	_ok(gp.register_object("t.gp:pad", _pad_scene("t_gp", "genesis")), "sockets/a Genesis pad registers")
	var sms := _labels("mastersystem")
	_ok(not sms.has("Pad") and sms.has("Primitive Controller"),
		"sockets/the Master System's card, whose port is the same DE-9, keeps its own", str(sms))
	gp.withdraw()

	# Socket names: any name will do, only the spelling is checked.
	_eq(Connectors.problem("ps2_av_multi"), "", "sockets/a socket the game ships a lead for is a name")
	_eq(Connectors.problem("t.sd:dock"), "", "sockets/so is a namespaced one of the mod's own")
	_eq(Connectors.problem("saturn_av_out"), "", "sockets/and so is one nobody has listed")
	_ok(not Connectors.problem("Saturn_AV").is_empty(), "sockets/upper case is not: it would fit nothing")
	_ok(not Connectors.problem("av out").is_empty(), "sockets/nor is a space")
	var bad := _api("t.bad")
	_ok(not bad.register_model({"id": "t.bad:console", "platform": sysid, "label": "Saturn Bad",
		"script": _SCRIPT, "sockets": ["Saturn_AV"]}), "sockets/a console misspelling one is refused")
	_ok(SystemModelRegistry.row_for("t.bad:console").is_empty(), "sockets/and is not registered")
	bad.withdraw()

	# A console whose socket no installed lead fits, and another author's lead
	# that fits it, read off the lead's own scene.
	var d := _api("t.sd")
	_ok(d.register_model({"id": "t.sd:console", "platform": sysid, "label": "Saturn D",
		"script": _SCRIPT, "requires": [_SCRIPT], "sockets": ["saturn_av_out"]}),
		"sockets/a console listing an unlisted socket registers", d.errors_text())
	_ok(not d.failed(), "sockets/which is no failure")
	_ok("saturn_av_out" in "; ".join(d.problems()), "sockets/but its page says nothing fits that socket",
		"; ".join(d.problems()))
	var l := _api("t.lead")
	_ok(l.register_object("t.lead:cable", _lead_scene("t_lead", "saturn_av_out")),
		"sockets/a lead whose plug is that socket registers")
	var info := ConnectorScan.of_scene(ScenePersistence.mod_object_scene("t.lead:cable"))
	_eq(str(info["role"]), ConnectorScan.ROLE_LEAD, "sockets/its scene reads as a lead")
	_ok((info["plugs"] as PackedStringArray).has("saturn_av_out")
		and (info["plugs"] as PackedStringArray).has(Connectors.PHONO),
		"sockets/with both of its ends", str(info["plugs"]))
	_ok(_labels(sysid).has("Cable"), "sockets/the console's card offers that lead", str(_labels(sysid)))
	_ok(not "saturn_av_out" in "; ".join(d.problems()), "sockets/and the console's page stops warning",
		"; ".join(d.problems()))
	l.withdraw()
	_ok(not _labels(sysid).has("Cable"), "sockets/the lead leaves with its mod")
	_ok("saturn_av_out" in "; ".join(d.problems()), "sockets/and the warning comes back")
	# Read as text: a scene whose model is not there is read all the same, which a
	# load would fail on -- it is what keeps a card from loading every mod's models.
	var unbuilt := _scene_file("t_unbuilt", """[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://Scripts/Objects/cables/rca_plug.gd" id="1"]
[ext_resource type="PackedScene" path="res://mods/t.nothere/model/lead.glb" id="2"]

[node name="Lead" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("2")]

[node name="PlugA0" type="RigidBody3D" parent="."]
script = ExtResource("1")
connector = "saturn_av_out"
""")
	var read := ConnectorScan.of_scene(unbuilt)
	_ok((read["plugs"] as PackedStringArray).has("saturn_av_out"),
		"scan/a lead is read without loading what its scene names", str(read))
	# A plug class's own connector, when the scene names none: LinkPlug's is set
	# in _init, where no declared default shows it.
	var link_lead := _scene_file("t_link", """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Scripts/Objects/cables/link/link_plug.gd" id="1"]

[node name="Lead" type="Node3D"]

[node name="PlugA0" type="RigidBody3D" parent="."]
script = ExtResource("1")
""")
	_eq(ConnectorScan.of_scene(link_lead)["plugs"], PackedStringArray(["link_plug"]),
		"scan/a plug of a class gets that class's own connector")
	# A phono end fits every console with jacks, so it says nothing of which.
	var phono_lead := _api("t.ph")
	_ok(phono_lead.register_object("t.ph:cable", _lead_scene("t_ph", Connectors.PHONO)),
		"sockets/a plain phono lead registers")
	_ok(not _labels(sysid).has("Cable"), "sockets/and is offered on no card for it")
	phono_lead.withdraw()
	d.withdraw()
	_ok(SpawnCatalog.socket_problems_for("t.sd").is_empty(), "sockets/a withdrawn console leaves no warning behind")

	# A mod's lead for a socket the game ships a lead for takes the game's place.
	var lead := str(Connectors.GAME_LEADS["ps2_av_multi"]["label"])
	var ps := _api("t.ps")
	_ok(ps.register_model({"id": "t.ps:console", "platform": sysid, "label": "Saturn PS",
		"script": _SCRIPT, "requires": [_SCRIPT], "sockets": ["ps2_av_multi"]}),
		"sockets/a console on a socket the game has a lead for")
	_ok(ps.problems().is_empty(), "sockets/has nothing to warn about", "; ".join(ps.problems()))
	var socketed := _labels(sysid)
	_ok(not socketed.has("Composite Cable"), "sockets/it is not offered the phono lead")
	_ok(socketed.has(lead), "sockets/and is offered the game's lead", str(socketed))
	for connector: String in Connectors.GAME_LEADS:
		var type := str(Connectors.GAME_LEADS[connector].get("spawn", ""))
		_ok(ScenePersistence.LEAD_SCENES.has(type),
			"sockets/the game's lead for %s is something it can spawn" % connector)
		var scene := (ScenePersistence.LEAD_SCENES[type] as PackedScene).resource_path
		_ok((ConnectorScan.of_scene(scene)["plugs"] as PackedStringArray).has(connector),
			"sockets/and its plug is that socket's", scene)
	var ml := _api("t.ml")
	_ok(ml.register_object("t.ml:cable", _lead_scene("t_ml", "ps2_av_multi"))
		and ml.add_peripherals(sysid, [{"label": "Modelled AV Cable", "spawn": "mod:t.ml:cable"}]),
		"sockets/a lead mod lists its lead on the card")
	var modelled := _labels(sysid)
	_ok(not modelled.has(lead), "sockets/the game's lead leaves the card", str(modelled))
	_eq(modelled.count("Modelled AV Cable"), 1, "sockets/and the mod's is there once")
	ml.withdraw()
	_ok(_labels(sysid).has(lead), "sockets/the game's lead comes back when it goes")
	ps.withdraw()
	_eq(_labels(sysid), before, "sockets/and the card is the stand-ins once more")

	# A console, once built, is checked against the sockets its row lists.
	SpawnCatalog.note_built_sockets("t.nb", "t.nb:console", ["ps2_av_multi"], ["ps2_av_multi", "ilink_plug"])
	var noted := "; ".join(SpawnCatalog.socket_problems_for("t.nb"))
	_ok("ilink_plug" in noted, "sockets/a socket the row leaves out is said on its page", noted)
	SpawnCatalog.note_built_sockets("t.nb", "t.nb:console", ["ps2_av_multi", "ilink_plug"], ["ps2_av_multi", "ilink_plug"])
	_ok(SpawnCatalog.socket_problems_for("t.nb").is_empty(), "sockets/and goes once the row lists it")

	# A socket the game ships a lead for is no warning, A/V or not.
	_ok(SpawnCatalog.game_lead_connectors().has("ilink_plug")
		and SpawnCatalog.game_lead_connectors().has("n64_av_plug"),
		"sockets/the game's leads are read off their scenes, its i.LINK cable among them")
	var il := _api("t.il")
	_ok(il.register_model({"id": "t.il:console", "platform": sysid, "label": "Saturn IL",
		"script": _SCRIPT, "requires": [_SCRIPT], "sockets": ["ilink_plug"]}),
		"sockets/a console with an i.LINK socket registers")
	_ok(il.problems().is_empty(), "sockets/and is not told nothing fits it", "; ".join(il.problems()))
	il.withdraw()

	# The game's own scenes read the way the room fits them.
	var nes_pad := ConnectorScan.of_scene("res://Scenes/Objects/controllers/nes/nes_controller.tscn")
	_eq(str(nes_pad["role"]), ConnectorScan.ROLE_CONTROLLER, "scan/a NES pad is a controller")
	_eq(nes_pad["plugs"], PackedStringArray(["nes_controller"]), "scan/whose plug is a NES's")
	# A plug the game has no class for is named by its connector, to be dressed.
	var plug_node := RcaPlug.new()
	plug_node.connector = "n64_av_plug"
	_ok(ModHooks._matches(plug_node, &"n64_av_plug"), "scan/a plug answers to its connector, for a mod to dress")
	_ok(not ModHooks._matches(plug_node, &"wii_av_plug"), "scan/and not to another")
	plug_node.free()
	for file: String in DirAccess.get_files_at("user://mod_tests_scenes"):
		DirAccess.remove_absolute("user://mod_tests_scenes/" + file)
	DirAccess.remove_absolute("user://mod_tests_scenes")

	# Dressing a shipped object belongs to one mod at a time.
	var seen: Array = []
	var first := _api("t.da")
	var second := _api("t.db")
	_ok(first.dress(&"Timer", "kind", func(n: Node) -> void: seen.append("a:" + n.name)),
		"standins/the first mod to ask dresses it")
	_ok(not second.dress(&"Timer", "kind", func(n: Node) -> void: seen.append("b:" + n.name)),
		"standins/a second is turned away")
	_ok(not second.failed(), "standins/which is not a failure of that mod")
	_ok("t.da" in "; ".join(second.problems()), "standins/and its page names who has it",
		"; ".join(second.problems()))
	_ok(second.dress(&"Timer", "other", func(_n: Node) -> void: pass),
		"standins/another key of the same class is free")
	var probe := Timer.new()
	probe.name = "DressProbe"
	add_child(probe)
	_eq(seen, ["a:DressProbe"], "standins/only the holder's callback runs")
	probe.free()
	first.withdraw()
	_ok(second.dress(&"Timer", "kind", func(_n: Node) -> void: pass),
		"standins/and it is free again once the holder is withdrawn")
	second.withdraw()


# ── cartshell/ ────────────────────────────────────────────────────────────────

## A body for the cases below: a box of `size` with a label face, saved where a
## pack's model would be.
func _save_body(name: String, size: Vector3) -> String:
	var root := Node3D.new()
	root.name = "Body"
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var box := BoxMesh.new()
	box.size = size
	var plastic := StandardMaterial3D.new()
	plastic.resource_name = "T_Shell_Plastic"
	plastic.albedo_color = Color(0.5, 0.5, 0.5)
	box.material = plastic
	shell.mesh = box
	root.add_child(shell)
	shell.owner = root
	# A part that is not shell plastic, inside the box so the bounds are the shell's.
	var contacts := MeshInstance3D.new()
	contacts.name = "Contacts"
	var pins := BoxMesh.new()
	pins.size = size * 0.5
	var metal := StandardMaterial3D.new()
	metal.resource_name = "T_Contacts"
	metal.albedo_color = Color(0.9, 0.8, 0.2)
	pins.material = metal
	contacts.mesh = pins
	root.add_child(contacts)
	contacts.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var path := "%s/%s.tscn" % [_dir, name]
	ResourceSaver.save(packed, path)
	root.free()
	return path


## The colour a part of a cartridge model is showing.
func _shown(model: Node3D, part: String) -> Color:
	var mesh := model.get_node(part) as MeshInstance3D
	var material := mesh.get_active_material(0) as BaseMaterial3D
	return material.albedo_color if material != null else Color(-1, -1, -1)


## What the mod under test says a ROM wears. Static, as a mod's must be.
static func _choose_shell(info: Dictionary) -> Dictionary:
	if "(Japan)" in str(info.get("file", "")):
		return {"body": "t.cs:jpn", "preset": "t.cs:red"}
	if "Gold" in str(info.get("file", "")):
		return {"preset": "t.cs:red"}
	if "Lost" in str(info.get("file", "")):
		return {"body": "t.cs:no_such_body"}
	return {}


## A mod brings a system's cartridge shells and says which a ROM wears.
func _group_cartshell() -> void:
	_hooks = ModHooks.new(get_tree())
	var sysid := "t_cartsys"
	var usa_size := Vector3(0.116, 0.075, 0.018)
	var jpn_size := Vector3(0.100, 0.070, 0.016)
	var usa := _save_body("cs_usa", usa_size)
	var jpn := _save_body("cs_jpn", jpn_size)
	var palette := CartridgeShellPalette.new()
	var red := CartridgeShellPreset.new()
	red.id = &"t.cs:red"
	red.display_name = "Red"
	red.color = Color(0.8, 0.1, 0.1)
	palette.presets = [red]
	var palette_path := "%s/cs_palette.tres" % _dir
	ResourceSaver.save(palette, palette_path)

	var n64_before := RetroCartridge.body_model_for("n64", "Some Game (Japan).z64", "", &"")
	_ok(not ModCartShells.has(sysid), "cartshell/nothing is registered to begin with")
	_eq(RetroCartridge.body_model_for(sysid, "Game.bin", "", &""), "",
		"cartshell/and a cartridge of that system is the box")

	var good := {"bodies": [
			{"id": "t.cs:usa", "label": "USA", "model": usa, "size": usa_size},
			{"id": "t.cs:jpn", "label": "Japan", "model": jpn, "size": jpn_size}],
		"palette": palette_path, "choose": _choose_shell, "tint": ["T_Shell_Plastic"]}

	# Refusals: each is a row the mod believes it registered.
	var bad := _api("t.cs")
	_ok(not bad.register_cart_shell(sysid, {"bodies": []}), "cartshell/no bodies is refused")
	_ok(not bad.register_cart_shell(sysid, {"bodies": [
		{"id": "usa", "model": usa, "size": usa_size}]}), "cartshell/a bare body id is refused")
	_ok(not bad.register_cart_shell(sysid, {"bodies": [
		{"id": "other.mod:usa", "model": usa, "size": usa_size}]}),
		"cartshell/and another mod's namespace")
	_ok(not bad.register_cart_shell(sysid, {"bodies": [
		{"id": "t.cs:usa", "model": "res://nope.glb", "size": usa_size}]}),
		"cartshell/a model that is not there is refused")
	_ok(not bad.register_cart_shell(sysid, {"bodies": [
		{"id": "t.cs:usa", "model": usa, "size": Vector3(0.1, 0.0, 0.01)}]}),
		"cartshell/a body with no thickness is refused")
	_ok(not bad.register_cart_shell(sysid, {"bodies": [
		{"id": "t.cs:usa", "model": usa, "size": usa_size}], "palette": usa}),
		"cartshell/a palette that is not a palette is refused")
	_ok(not bad.register_cart_shell(sysid, {"bodies": [
		{"id": "t.cs:usa", "model": usa, "size": usa_size}], "palette": palette_path}),
		"cartshell/colours with nothing named to put them on are refused")
	_ok(bad.failed() and not ModCartShells.has(sysid), "cartshell/and none of them registered")
	bad.withdraw()

	var api := _api("t.cs")
	_ok(api.register_cart_shell(sysid, good), "cartshell/a good row registers", api.errors_text())
	_ok(ModCartShells.has(sysid), "cartshell/the system has mod shells")
	_eq((api.contributions().get("media", []) as Array), ["%s cartridge shells (2)" % sysid],
		"cartshell/it is on the mod's page")

	# Which body a ROM wears.
	_eq(RetroCartridge.body_model_for(sysid, "Game (USA).bin", "", &""), usa,
		"cartshell/a ROM nothing is said about gets the first body")
	_eq(RetroCartridge.body_model_for(sysid, "Game (Japan).bin", "", &""), jpn,
		"cartshell/the mod's function picks the Japanese body for a Japanese ROM")
	_eq(RetroCartridge.body_model_for(sysid, "Game (Japan).bin", "t.cs:usa", &""), usa,
		"cartshell/a body the player forced wins over it")
	_eq(RetroCartridge.body_model_for(sysid, "Game (Japan).bin", "usa", &""), jpn,
		"cartshell/a forced body it does not have is ignored")
	_eq(RetroCartridge.body_model_for(sysid, "Lost Game.bin", "", &""), usa,
		"cartshell/and so is one the function made up")

	# Its colour.
	_eq(ModCartShells.preset_for(sysid, "Game (Japan).bin"), &"t.cs:red",
		"cartshell/the function's colour for the ROM is kept")
	_eq(ModCartShells.preset_for(sysid, "Game (USA).bin"), &"",
		"cartshell/a ROM it says nothing about has none")
	_eq(RetroCartridge.body_model_for(sysid, "Gold Game.bin", "", &""), usa,
		"cartshell/a colour alone leaves the first body")
	_ok(CartridgeColor.get_palette(sysid) != null
		and CartridgeColor.get_palette(sysid).find(&"t.cs:red") != null,
		"cartshell/the mod's palette is the system's")

	# Its size, per body.
	_ok(MediaDimensions.has_cart_size(sysid), "cartshell/the system has a cartridge size now")
	_eq(MediaDimensions.cart_size(sysid, "", usa), usa_size, "cartshell/the first body's size")
	_eq(MediaDimensions.cart_size(sysid, "", jpn), jpn_size, "cartshell/the second body's own")
	_eq(MediaDimensions.cart_size(sysid), usa_size,
		"cartshell/with no body named, a system the game has no size for takes the first")

	# The hold menu has something to offer.
	_ok(SpawnMenuSpawnView._has_spawn_options(sysid), "cartshell/its ROM rows open the hold options")

	# A real cartridge.
	var cart := (load("res://Scenes/Objects/media/cartridge.tscn") as PackedScene).instantiate() as RetroCartridge
	cart.systemid = sysid
	cart.rom_path = "Game (Japan).bin"
	cart.freeze = true
	add_child(cart)
	await get_tree().process_frame
	var worn := cart.get_node_or_null("CartModel") as Node3D
	_ok(worn != null, "cartshell/a cartridge wears the mod's body")
	if worn != null:
		var mesh := worn.get_node("Shell") as MeshInstance3D
		var fitted := (mesh.mesh as BoxMesh).size * worn.scale
		_ok(fitted.is_equal_approx(jpn_size), "cartshell/the Japanese one, at its own size",
			str(fitted))
		_ok(not (cart.get_node("CartridgeMesh") as Node3D).visible,
			"cartshell/and the stand-in box is hidden under it")
		_ok(_shown(worn, "Shell").is_equal_approx(Color(0.8, 0.1, 0.1)),
			"cartshell/in the colour the mod said this ROM came in", str(_shown(worn, "Shell")))
		_ok(_shown(worn, "Contacts").is_equal_approx(Color(0.9, 0.8, 0.2)),
			"cartshell/and a material it did not name is left alone")
	cart.free()

	# A colour the player mixed goes on the same materials, over the mod's own.
	var mixed := (load("res://Scenes/Objects/media/cartridge.tscn") as PackedScene).instantiate() as RetroCartridge
	mixed.systemid = sysid
	mixed.rom_path = "Game (Japan).bin"
	mixed.shell_color = "#00ff00"
	mixed.freeze = true
	add_child(mixed)
	await get_tree().process_frame
	var mixed_model := mixed.get_node_or_null("CartModel") as Node3D
	_ok(mixed_model != null and _shown(mixed_model, "Shell").is_equal_approx(Color(0, 1, 0)),
		"cartshell/a mixed colour is painted over the mod's choice")
	_ok(mixed_model != null and _shown(mixed_model, "Contacts").is_equal_approx(Color(0.9, 0.8, 0.2)),
		"cartshell/and still not on the contacts")
	mixed.free()

	# One mod holds a system.
	var late := _api("t.ct")
	_ok(not late.register_cart_shell(sysid, {"bodies": [
		{"id": "t.ct:any", "model": usa, "size": usa_size}]}), "cartshell/a second mod is turned away")
	_ok(not late.failed() and "t.cs" in "; ".join(late.problems()),
		"cartshell/told who has it, which is not a failure", "; ".join(late.problems()))
	_eq(ModCartShells.owner_of(sysid), "t.cs", "cartshell/the first still holds it")
	late.withdraw()
	_ok(ModCartShells.has(sysid), "cartshell/and the loser withdrawing takes nothing with it")

	# The game's own shells are not disturbed by a mod for another system.
	_eq(RetroCartridge.body_model_for("n64", "Some Game (Japan).z64", "", &""), n64_before,
		"cartshell/an N64 cartridge is what it was")

	api.withdraw()
	_ok(not ModCartShells.has(sysid), "cartshell/withdrawing the mod takes its shells")
	_ok(not ModCartShells.is_tint(&"T_Shell_Plastic"), "cartshell/and its material names")

	# Shells with no materials named cannot be coloured, and are not offered it.
	var plain := _api("t.cs")
	_ok(plain.register_cart_shell(sysid, {"bodies": [
		{"id": "t.cs:usa", "model": usa, "size": usa_size}]}), "cartshell/one body, nothing named, registers")
	_ok(not ModCartShells.tintable(sysid), "cartshell/it cannot be coloured")
	_ok(not SpawnMenuSpawnView._has_spawn_options(sysid),
		"cartshell/so with one body its ROM rows have no hold options")
	var kept := (load("res://Scenes/Objects/media/cartridge.tscn") as PackedScene).instantiate() as RetroCartridge
	kept.systemid = sysid
	kept.rom_path = "Game.bin"
	kept.shell_color = "#00ff00"
	kept.freeze = true
	add_child(kept)
	await get_tree().process_frame
	var kept_model := kept.get_node_or_null("CartModel") as Node3D
	_ok(kept_model != null and _shown(kept_model, "Shell").is_equal_approx(Color(0.5, 0.5, 0.5)),
		"cartshell/and a colour forced on it anyway leaves its own material")
	kept.free()
	plain.withdraw()
	_eq(RetroCartridge.body_model_for(sysid, "Game (Japan).bin", "", &""), "",
		"cartshell/a cartridge is the box again")
	_ok(CartridgeColor.get_palette(sysid) == null, "cartshell/and the palette is gone")
	_ok(not MediaDimensions.has_cart_size(sysid), "cartshell/and the size")


# ── expshell/ ─────────────────────────────────────────────────────────────────

## A mod replaces the shell an expansion unit wears, and nothing else about it.
func _group_expshell() -> void:
	_hooks = ModHooks.new(get_tree())
	var unit := "ereader_usa"
	var other := "ereader"
	var size := Vector3(0.09, 0.11, 0.04)
	var model := _save_body("exp_shell", size)
	var before: Dictionary = ExpansionCatalog.row(unit).duplicate(true)
	var other_before: Dictionary = ExpansionCatalog.row(other).duplicate(true)
	_ok(not str(before.get("shell", "")).is_empty(), "expshell/the unit under test has a shell of the game's")

	var bad := _api("t.ex")
	_ok(not bad.override_expansion_shell("no_such_unit", {"shell": model, "size": size}),
		"expshell/a unit that does not exist is refused")
	_ok(not bad.override_expansion_shell(unit, {"shell": "res://nope.glb", "size": size}),
		"expshell/a shell that is not there is refused")
	_ok(not bad.override_expansion_shell(unit, {"shell": model}), "expshell/a shell with no size is refused")
	_ok(not bad.override_expansion_shell(unit, {"shell": model, "size": Vector3(0.1, 0.0, 0.1)}),
		"expshell/and one with no height")
	_ok(not bad.override_expansion_shell(unit, {"shell": model, "size": size, "host": "snes"}),
		"expshell/what the unit IS cannot be set")
	_ok(not bad.override_expansion_shell(unit, {"shell": model, "size": size, "connector": 3}),
		"expshell/a placement of the wrong type is refused")
	_ok(not bad.override_expansion_shell(unit, {"shell": model, "size": size,
		"shell_lods": [["res://nope.glb", 1.0]]}), "expshell/and a lower level that is not there")
	_ok(bad.failed() and ExpansionCatalog.row(unit) == before, "expshell/none of which changed the unit")
	bad.withdraw()

	var api := _api("t.ex")
	_ok(api.override_expansion_shell(unit, {"shell": model, "size": size}),
		"expshell/a shell and its size register", api.errors_text())
	_eq(ExpansionCatalog.shell_of(unit), model, "expshell/the unit wears the mod's shell")
	_eq(ExpansionCatalog.size_of(unit), size, "expshell/at the mod's size")
	_eq(ExpansionCatalog.shell_lods_of(unit), [], "expshell/without the game's lower levels of the old one")
	_eq(ExpansionCatalog.shell_albedo_of(unit), "", "expshell/or its recolour")
	_eq(ExpansionCatalog.connector_of(unit), before.get("connector"),
		"expshell/its tongue is where the game measured it")
	_eq(ExpansionCatalog.swipe_slit_of(unit), before.get("swipe_slit"), "expshell/and its card channel")
	_eq(ExpansionCatalog.host_of(unit), str(before.get("host")), "expshell/it is still the same unit")
	_eq(ExpansionCatalog.row(other), other_before, "expshell/and another revision is untouched")
	_eq(ExpansionCatalog.shell_owner_of(unit), "t.ex", "expshell/the catalog knows whose it is")

	var late := _api("t.ey")
	_ok(not late.override_expansion_shell(unit, {"shell": model, "size": size}),
		"expshell/a second mod is turned away")
	_ok(not late.failed() and "t.ex" in "; ".join(late.problems()),
		"expshell/told who has it, which is not a failure")
	_ok(late.override_expansion_shell(other, {"shell": model, "size": size,
		"connector": Vector3(0.0, -0.04, 0.0)}), "expshell/but may dress another unit")
	_eq(ExpansionCatalog.connector_of(other), Vector3(0.0, -0.04, 0.0),
		"expshell/with a tongue of its own, for a model in another frame")
	_eq(ExpansionCatalog.shell_offset_of(other), Vector3.ZERO, "expshell/a shell sits on the middle of its bounds unless it says")
	_ok(late.override_expansion_shell(other, {"shell": model, "size": size, "shell_offset": Vector3(0.0, 0.0, 0.002)}),
		"expshell/a shell may say it sits off the middle")
	_eq(ExpansionCatalog.shell_offset_of(other), Vector3(0.0, 0.0, 0.002), "expshell/and the unit reads that")
	late.withdraw()
	_eq(ExpansionCatalog.row(other), other_before, "expshell/which goes when that mod does")
	_eq(ExpansionCatalog.shell_of(unit), model, "expshell/leaving the first mod's alone")

	api.withdraw()
	_eq(ExpansionCatalog.row(unit), before, "expshell/withdrawn, the unit is exactly what it was")
