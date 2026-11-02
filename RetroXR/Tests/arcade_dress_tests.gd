## Arcade dressing self-tests — a mod dresses the Morphing Arcade Cabinet's own parts by name and the
## cabinet keeps taking the shape of the game in its bay (ArcadeDressing, ModApi.dress_arcade_cabinet),
## and a mod adds a bay kind (ModApi.register_arcade_bay_kind). Headless, no core, no ROM, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_dress_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_dress_tests.tscn -- --only=morph
##
## Exits 0 when everything passes, 1 otherwise. How a dressing LOOKS is the probe's
## (Tools/models/arcade_cabinet_probe, windowed); this is what a headless run can say.
##
## Groups:
##   rows/     what register refuses, and which cabinets and forms a row picks
##   paint/    colours over the builder's paints, by group and by part, never into the scene's shared material
##   hide/     a hidden part draws nothing and its node stays
##   parts/    a scene instanced under a part, once
##   marquee/  a dressed marquee still lights, on a copy of its own
##   morph/    a form built for a game is dressed too, and the bay a morph keeps is not dressed twice
##   variant/  a row for one cabinet leaves another alone
##   api/      the ModApi calls: namespaced ids, the record, the bay kind, and withdraw taking both back
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PART_SCENE := "user://arcade_dress_test_part.tscn"
const RED := Color(1, 0, 0)
const GREEN := Color(0, 1, 0)

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "dress"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[dress] TIMED OUT")
		get_tree().quit(1))
	_write_part_scene()
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PART_SCENE))
	_finish()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _run() -> void:
	if _want("rows"):
		_group_rows()
	if _want("paint"):
		await _group_paint()
		await _clear()
	if _want("hide"):
		await _group_hide()
		await _clear()
	if _want("parts"):
		await _group_parts()
		await _clear()
	if _want("marquee"):
		await _group_marquee()
		await _clear()
	if _want("morph"):
		await _group_morph()
		await _clear()
	if _want("variant"):
		await _group_variant()
		await _clear()
	if _want("api"):
		_group_api()
	ArcadeDressing._rows.clear()


# --- helpers -------------------------------------------------------------------

func _write_part_scene() -> void:
	var root := Node3D.new()
	root.name = "DressPart"
	var mi := MeshInstance3D.new()
	mi.name = "Badge"
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, PART_SCENE)
	root.free()


func _machine(model_id: String = ArcadeProfiles.CABINET_MODEL_ID, systemid: String = "arcade") -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 4.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(10)
	return sys


func _model(sys: RetroSystem) -> RetroSystemModelArcadeCabinet:
	return sys.get_model() as RetroSystemModelArcadeCabinet


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	for bay in get_tree().get_nodes_in_group(ArcadeBayUnit.GROUP):
		bay.queue_free()
	_spawned.clear()
	ArcadeDressing._rows.clear()
	await _wait(6)


func _spec(romset: String) -> Dictionary:
	var base := ArcadeCabinetSpecs.variant("generic")
	base["variant"] = "generic"
	return ArcadeCabinetSpecs.for_game(base, ArcadeGameProfile.for_romset(romset))


func _parts(root: Node, part: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children(part, "MeshInstance3D", true, false):
		if not str(n.get_parent().name).begins_with(ArcadeDressing.PART_PREFIX):
			out.append(n as MeshInstance3D)
	return out


func _albedo(mi: MeshInstance3D) -> Color:
	var m := mi.get_active_material(0) as StandardMaterial3D
	return m.albedo_color if m != null else Color.BLACK


func _register(dress_id: String, row: Dictionary) -> String:
	return ArcadeDressing.register(dress_id, row, "test.dress")


# --- rows ----------------------------------------------------------------------

func _group_rows() -> void:
	_ok(not _register("t:a", {"paint": {}}).is_empty(), "rows: an unknown field is refused")
	_ok(not _register("t:a", {"shapes": ["tower"]}).is_empty(), "rows: a shape that is none is refused")
	_ok(not _register("t:a", {"variants": ["pinball"]}).is_empty(), "rows: a variant that is none is refused")
	_ok(not _register("t:a", {"colors": {"body": "red-ish"}}).is_empty(), "rows: a colour that is not one is refused")
	_ok(not _register("t:a", {"materials": {"body": "res://no/such.tres"}}).is_empty(), "rows: a missing material is refused")
	_ok(not _register("t:a", {"parts": {"Marquee": "res://no/such.tscn"}}).is_empty(), "rows: a missing scene is refused")
	_ok(ArcadeDressing._rows.is_empty(), "rows: nothing refused is kept")
	_eq(_register("t:all", {"colors": {"body": "#ff0000"}}), "", "rows: a plain colour row is taken")
	_eq(_register("t:gen", {"variants": ["generic"], "shapes": ["wide"]}), "", "rows: a row for one variant and shape is taken")
	_eq(_register("t:mine", {"variants": [""]}), "", "rows: \"\" is a cabinet that names no row")
	_eq(ArcadeDressing.matching("generic", "upright"), ["t:all"] as Array[String], "rows: an upright generic takes the row for every cabinet")
	_eq(ArcadeDressing.matching("generic", "wide"), ["t:all", "t:gen"] as Array[String], "rows: a wide generic takes its own row too, in id order")
	_eq(ArcadeDressing.matching("neogeo", "wide"), ["t:all"] as Array[String], "rows: another cabinet does not take the generic's row")
	_eq(ArcadeDressing.matching("", "upright"), ["t:all", "t:mine"] as Array[String], "rows: a mod's own cabinet takes the \"\" row")
	ArcadeDressing.drop_mod("someone.else")
	_eq(ArcadeDressing._rows.size(), 3, "rows: another mod's withdrawal leaves these")
	ArcadeDressing.drop_mod("test.dress")
	_ok(ArcadeDressing._rows.is_empty(), "rows: withdrawn with their mod")


# --- paint ---------------------------------------------------------------------

func _group_paint() -> void:
	_register("t:paint", {"colors": {"body": RED, "Btn1": "#00ff00"}})
	var sys := await _machine()
	var model := _model(sys)
	var side := _parts(model, "SideL")[0]
	var rear := _parts(model, "Rear")[0]
	_ok(_albedo(side).is_equal_approx(RED), "paint: a side (painted over its instance) takes the body colour")
	_ok(_albedo(rear).is_equal_approx(RED), "paint: the rear (painted on its mesh) takes the body colour")
	var own := rear.mesh.surface_get_material(0) as StandardMaterial3D
	_ok(own != null and not own.albedo_color.is_equal_approx(RED),
		"paint: the baked scene's own material, which every cabinet shares, is not repainted")
	var caps := _parts(model, "Btn1")
	_ok(caps.size() == 2 and caps.all(func(c: MeshInstance3D) -> bool: return _albedo(c).is_equal_approx(GREEN)),
		"paint: every player's Btn1 takes the part's colour (%d)" % caps.size())
	_ok(not _albedo(_parts(model, "Btn2")[0]).is_equal_approx(GREEN), "paint: Btn2 is left as built")
	_ok(not _albedo(_parts(model, "ApronTrim")[0]).is_equal_approx(RED), "paint: the trim is not the body")


# --- hide ----------------------------------------------------------------------

func _group_hide() -> void:
	_register("t:hide", {"hide": ["KickPlate"]})
	var sys := await _machine()
	var model := _model(sys)
	var kick := _parts(model, "KickPlate")
	_ok(kick.size() == 1, "hide: the hidden part's node stays")
	_ok(kick.size() == 1 and kick[0].mesh == null and kick[0].has_meta(ArcadeDressing.HIDDEN_META),
		"hide: it draws nothing, and keeps the mesh it had")
	_ok(_parts(model, "SideL")[0].mesh != null, "hide: nothing else is hidden")


# --- parts ---------------------------------------------------------------------

func _group_parts() -> void:
	_register("t:parts", {"parts": {"Marquee": PART_SCENE, "NoSuchPart": PART_SCENE}})
	var sys := await _machine()
	var model := _model(sys)
	var marquee := _parts(model, "Marquee")[0]
	var child := ArcadeDressing.PART_PREFIX + "t_parts"
	_ok(marquee.has_node(child) and marquee.get_node(child).has_node("Badge"),
		"parts: the scene is instanced under the marquee")
	ArcadeDressing.apply(model, "generic", model.form_spec())
	_eq(marquee.get_children().filter(func(c: Node) -> bool: return c.scene_file_path == PART_SCENE).size(), 1,
		"parts: dressed again, it is not instanced twice")
	_eq(_parts(model, "Badge").size(), 0, "parts: the scene's own parts are never taken for the builder's")


# --- marquee -------------------------------------------------------------------

func _group_marquee() -> void:
	var paint := ArcadeParts.mat(Color(0.1, 0.2, 0.9))
	_register("t:mq", {"materials": {"Marquee": paint}})
	var a := await _machine()
	var b := await _machine()
	var ma := _model(a)
	var mb := _model(b)
	var qa := _parts(ma, "Marquee")[0]
	var lit := ma._marquee_mat
	_ok(lit != null and lit != paint and lit.albedo_color.is_equal_approx(paint.albedo_color),
		"marquee: the cabinet lights a copy of the mod's paint")
	_ok(qa.get_active_material(0) == lit, "marquee: the copy is the one drawn")
	_ok(mb._marquee_mat != lit, "marquee: each cabinet has its own copy")
	ma._light_marquee(true)
	_ok(lit.emission_enabled and not paint.emission_enabled and not mb._marquee_mat.emission_enabled,
		"marquee: lighting one cabinet lights neither the mod's material nor the other cabinet")
	ma._collect_modules()
	_ok(ma._marquee_mat == lit, "marquee: collecting the modules again does not copy the copy")


# --- morph ---------------------------------------------------------------------

func _group_morph() -> void:
	_register("t:morph", {"colors": {"Btn1": GREEN}, "parts": {"Marquee": PART_SCENE, "DoorMesh": PART_SCENE}})
	var sys := await _machine()
	var model := _model(sys)
	model.morph_to(_spec("tmnt"))
	await _wait(2)
	var caps := _parts(model, "Btn1")
	_ok(caps.size() == 4 and caps.all(func(c: MeshInstance3D) -> bool: return _albedo(c).is_equal_approx(GREEN)),
		"morph: all four of TMNT's panels are dressed (%d Btn1)" % caps.size())
	var marquee := _parts(model, "Marquee")
	_ok(marquee.size() == 1 and marquee[0].has_node(ArcadeDressing.PART_PREFIX + "t_morph"),
		"morph: the new form's marquee has the mod's scene")
	var door := _parts(model, "DoorMesh")
	_ok(door.size() == 1 and door[0].get_children().filter(
			func(c: Node) -> bool: return c.scene_file_path == PART_SCENE).size() == 1,
		"morph: the bay door, which a morph keeps, carries the scene once")
	model.morph_to(model._base_spec)
	await _wait(2)
	caps = _parts(model, "Btn1")
	_ok(caps.size() == 2 and caps.all(func(c: MeshInstance3D) -> bool: return _albedo(c).is_equal_approx(GREEN)),
		"morph: back in its own form, still dressed")


# --- variant -------------------------------------------------------------------

func _group_variant() -> void:
	_register("t:gen", {"variants": ["generic"], "colors": {"body": RED}})
	var gen := await _machine()
	var neo := await _machine("arcade_cabinet_neogeo", "neogeo")
	_ok(_albedo(_parts(_model(gen), "SideL")[0]).is_equal_approx(RED), "variant: the generic cabinet is dressed")
	_ok(not _albedo(_parts(_model(neo), "SideL")[0]).is_equal_approx(RED), "variant: the MVS is not")


# --- api -----------------------------------------------------------------------

func _group_api() -> void:
	var api := ModApi.new(ModManifest.parse({"id": "test.dress", "api_version": 1,
		"entry": "res://mods/test.dress/m.gd", "name": "test.dress", "version": "1.0.0"}), ModHooks.new(get_tree()))
	_ok(not api.dress_arcade_cabinet("plain", {}), "api: a dressing id that is not the mod's own is refused")
	_ok(not api.dress_arcade_cabinet("test.dress:bad", {"shapes": ["tower"]}), "api: a bad row is refused")
	_ok(api.dress_arcade_cabinet("test.dress:look", {"variants": ["generic"], "colors": {"body": RED}}),
		"api: a good dressing is taken")
	_ok(ArcadeDressing._rows.has("test.dress:look"), "api: and is in the registry")
	_ok(not api.register_arcade_bay_kind("jamma2", "JAMMA 2", ["arcade"]), "api: a bay kind id that is not the mod's own is refused")
	_ok(not api.register_arcade_bay_kind("test.dress:none", "None", []), "api: a bay kind that takes nothing is refused")
	_ok(api.register_arcade_bay_kind("test.dress:pgm", "PGM", ["pgm"], false), "api: a bay kind is taken")
	_ok(ArcadeProfiles.bay_accepts("test.dress:pgm", "pgm") and not ArcadeProfiles.bay_accepts("test.dress:pgm", "arcade"),
		"api: the bay takes its system's boards and no other")
	_ok(not bool(ArcadeProfiles.bay_kinds()["test.dress:pgm"]["romsets"]), "api: romsets false is kept")
	_ok(not api.register_arcade_bay_kind("test.dress:pgm", "PGM", ["pgm"]), "api: the same bay kind twice is refused")
	_ok(not api.register_arcade_bay_kind("test.dress:jamma", "J", ["mame"]) or ArcadeProfiles.bay_accepts("test.dress:jamma", "arcade"),
		"api: a legacy systemid is the one arcade system")
	var record: Dictionary = api.contributions() if api.has_method("contributions") else api._record
	_ok((record.get("object", []) as Array).size() >= 2, "api: both are on the mod's record")
	api.withdraw()
	_ok(not ArcadeDressing._rows.has("test.dress:look"), "api: withdraw takes the dressing back")
	_ok(not ArcadeProfiles.bay_kinds().has("test.dress:pgm") and not ArcadeProfiles.bay_kinds().has("test.dress:jamma"),
		"api: and the bay kinds")
	_ok(ArcadeProfiles.bay_kinds().has("jamma") and ArcadeProfiles.bay_kinds().has("mvs"), "api: the shipped bay kinds stay")
