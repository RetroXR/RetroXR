## Console stand self-tests -- a console mounted in a stand that decides how it
## stands (StandCatalog, StandFoot, ConsoleStand). Headless, no core, no ROM.
##
##     "$godot" --headless --path RetroXR res://Tests/console_stand_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/console_stand_tests.tscn -- --only=foot
##
## Groups:
##   catalog/  the rows, which stands a console and a card are offered, the
##             spawn token, and a mod's stand coming and going
##   override/ a mod giving a shipped stand its model, keeping the id
##   foot/     each face's foot puts THAT face on the seat, the right way round
##   seat/     real consoles in real stands: seated at the stand's pose, refused
##             by a stand not made for them, no feet on a console no stand takes
##   save/     a stand's record names its stand and its console, and comes back
##             holding it
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const STAND_SCENE := preload("res://Scenes/Objects/stands/console_stand.tscn")

## A pose is right to this, in metres or (as a dot product's distance from 1) in
## direction.
const TOL := 0.001

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "stand"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[stand] TIMED OUT")
		get_tree().quit(1))
	if _want("catalog"):
		_group_catalog()
	if _want("override"):
		_group_override()
	if _want("foot"):
		_group_foot()
	if _want("seat"):
		await _group_seat()
	if _want("save"):
		await _group_save()
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _console(systemid: String, at: Vector3) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = at
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(20)
	return sys


func _stand(stand_id: String, at: Vector3) -> ConsoleStand:
	var stand := STAND_SCENE.instantiate() as ConsoleStand
	stand.stand_id = stand_id
	stand.position = at
	stand.freeze = true
	add_child(stand)
	_spawned.append(stand)
	await _wait(2)
	return stand


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(3)


# ── catalog ───────────────────────────────────────────────────────────────────

func _group_catalog() -> void:
	for id: String in StandCatalog.ids():
		var r := StandCatalog.row(id)
		_ok(StandCatalog.FACES.has(StandCatalog.face_of(id)), "catalog/%s rests on a known face" % id)
		_ok(not (r.get("fits", []) as Array).is_empty(), "catalog/%s fits something" % id)
		_ok(not (r.get("parts", []) as Array).is_empty(), "catalog/%s has parts to stand on" % id)
	_ok(StandCatalog.fits("wii_stand", "wii", ""), "catalog/the Wii stand takes a Wii")
	_ok(not StandCatalog.fits("wii_stand", "ps2", ""), "catalog/and not a PS2")
	_eq(StandCatalog.faces_for("ps2", ""), ["left"], "catalog/a PS2 stands on its left side")
	_eq(StandCatalog.faces_for("snes", ""), [], "catalog/nothing stands a SNES up")
	# On the card, as a token the menu reads back as this stand.
	var tokens := SpawnCatalog.items_for("ps2").map(func(i: Dictionary) -> String:
		return str(i.get("spawn", "")))
	_ok(tokens.has("console_stand:ps2_vertical_stand"), "catalog/the PS2 card offers its stand")
	_ok(not SpawnCatalog.items_for("snes").any(func(i: Dictionary) -> bool:
		return str(i.get("spawn", "")).begins_with(SpawnCatalog.CONSOLE_STAND_PREFIX)),
		"catalog/a card no stand fits offers none")
	var parsed := SpawnCatalog.parse_token("console_stand:wii_stand")
	_eq(parsed["kind"], SpawnCatalog.TokenKind.CONSOLE_STAND, "catalog/the token parses as a stand")
	_eq(parsed["stand_id"], "wii_stand", "catalog/naming its id")
	# A mod's stand: refused when it fits nothing or has nothing to stand on,
	# offered on the card while installed, and gone with the mod.
	var row := {"label": "Test Rack", "fits": ["snes"], "face": "back",
		"seat": Vector3(0, 0.01, 0), "parts": [{"box": Vector3(0.2, 0.01, 0.1)}]}
	_ok(not StandCatalog.register_mod_stand("t:none", {"parts": row["parts"]}, "t").is_empty(),
		"catalog/a mod stand that fits nothing is refused")
	_ok(not StandCatalog.register_mod_stand("t:flat", {"fits": ["snes"]}, "t").is_empty(),
		"catalog/so is one with no parts")
	_ok(not StandCatalog.register_mod_stand("wii_stand", row, "t").is_empty(),
		"catalog/a mod cannot replace a shipped stand")
	_eq(StandCatalog.register_mod_stand("t:rack", row, "t"), "", "catalog/a whole mod stand registers")
	_eq(StandCatalog.faces_for("snes", ""), ["back"], "catalog/and the SNES now has a face to stand on")
	_ok(SpawnCatalog.items_for("snes").any(func(i: Dictionary) -> bool:
		return str(i.get("spawn", "")) == "console_stand:t:rack"), "catalog/on the SNES card")
	StandCatalog.drop_mod("t")
	_ok(not StandCatalog.has("t:rack"), "catalog/and withdrawn with its mod")


func _group_override() -> void:
	# A model pack replacing a shipped primitive: same id, merged fields.
	var model := "res://imported-assets/consoles/sega_32x/sega32x_spacer.glb"
	var shipped_seat: Vector3 = StandCatalog.row("wii_stand")["seat"]
	_ok(not StandCatalog.override_stand("t:rack", {"scene": model}, "t").is_empty(),
		"override/only a shipped stand can be overridden")
	_ok(not StandCatalog.override_stand("wii_stand", {"scene": "res://nope.glb"}, "t").is_empty(),
		"override/a model that does not exist is refused")
	_eq(StandCatalog.override_stand("wii_stand", {"scene": model, "seat": Vector3(0, 0.02, 0)}, "t"), "",
		"override/a model for the Wii stand is taken")
	_ok(not StandCatalog.override_stand("wii_stand", {"scene": model}, "u").is_empty(),
		"override/and a second mod's is refused")
	var r := StandCatalog.row("wii_stand")
	_eq(r.get("scene"), model, "override/the stand wears the mod's model")
	_eq(r.get("seat"), Vector3(0, 0.02, 0), "override/at the seat the mod measured")
	_eq(r.get("face"), "right", "override/keeping everything the mod did not change")
	var stand := STAND_SCENE.instantiate() as ConsoleStand
	stand.stand_id = "wii_stand"
	add_child(stand)
	_ok(stand.get_node_or_null("Model") != null, "override/a built stand shows the model")
	_ok(not stand.get_children().any(func(c: Node) -> bool: return c.name.begins_with("PartMesh")),
		"override/instead of the primitive")
	_ok(stand.get_node_or_null("Part0") is CollisionShape3D, "override/still standing on its parts")
	stand.free()
	StandCatalog.drop_mod("t")
	_eq(StandCatalog.row("wii_stand")["seat"], shipped_seat, "override/withdrawn, the primitive is back")
	_ok(not StandCatalog.row("wii_stand").has("scene"), "override/with no model")


# ── foot ──────────────────────────────────────────────────────────────────────

## For each face: the console placed as a mount at the origin places it (zone *
## foot^-1) has THAT face's middle on the seat, its outward normal pointing down,
## and the rest of the box above the seat. An asymmetric box, so a swapped axis or
## a mirrored basis cannot pass.
func _group_foot() -> void:
	var box := AABB(Vector3(-0.15, -0.02, -0.05), Vector3(0.30, 0.07, 0.17))
	var normals := {"bottom": Vector3.DOWN, "top": Vector3.UP, "left": Vector3.LEFT,
		"right": Vector3.RIGHT, "back": Vector3.FORWARD, "front": Vector3.BACK}
	for face: String in StandCatalog.FACES:
		var foot := StandCatalog.foot_transform(face, box)
		_ok(absf(foot.basis.determinant() - 1.0) < TOL, "foot/%s is a rotation, not a mirror" % face)
		var pose := foot.affine_inverse()
		var n: Vector3 = normals[face]
		var mid := box.get_center() + n * (box.size * n.abs()) * 0.5
		_ok((pose * mid).length() < TOL, "foot/%s: its middle lands on the seat" % face,
			"at %s" % (pose * mid))
		_ok((pose.basis * n).dot(Vector3.DOWN) > 1.0 - TOL, "foot/%s: and faces down" % face,
			"normal %s" % (pose.basis * n))
		var lowest := INF
		for i in 8:
			lowest = minf(lowest, (pose * box.get_endpoint(i)).y)
		_ok(absf(lowest) < TOL, "foot/%s: with the whole box above the seat" % face,
			"lowest corner %f" % lowest)
		if face in ["bottom", "top", "left", "right"]:
			_ok((pose.basis * Vector3.BACK).dot(Vector3.BACK) > 1.0 - TOL,
				"foot/%s: its front still faces front" % face)


# ── seat ──────────────────────────────────────────────────────────────────────

func _group_seat() -> void:
	for case: Array in [["wii", "wii_stand"], ["ps2", "ps2_vertical_stand"]]:
		var systemid: String = case[0]
		var stand_id: String = case[1]
		var face := StandCatalog.face_of(stand_id)
		var stand := await _stand(stand_id, Vector3(0, 1, 0))
		var sys := await _console(systemid, Vector3(0.6, 1.2, 0.3))
		_ok(StandFoot.find(sys, face) == null, "seat/%s: no foot before a stand asks" % systemid)
		_ok(stand.mount().snap_filter.call(sys), "seat/%s: its stand will take it" % systemid)
		var foot := StandFoot.find(sys, face)
		_ok(foot != null, "seat/%s: and asking grew its %s foot" % [systemid, face])
		stand.restore_console(sys)
		await _wait(10)
		_ok(stand.seated_console() == sys, "seat/%s: it is mounted" % systemid)
		if foot != null:
			var at := foot.global_position
			var want := stand.mount().global_position
			_ok(at.distance_to(want) < TOL, "seat/%s: with its %s face on the seat" % [systemid, face],
				"foot %s, seat %s" % [at, want])
			_ok(foot.global_basis.y.dot(Vector3.UP) > 1.0 - TOL,
				"seat/%s: and that face down" % systemid, "foot up %s" % foot.global_basis.y)
		# Which way up it stands -- asymmetric, so the wrong face cannot pass. The
		# Wii's model is authored upright and laid flat by its own root, so its
		# authored up is the real one; a PS2 on its left side has its right up.
		var up := sys.get_model().global_basis.y.normalized() if systemid == "wii" \
			else sys.global_basis.x.normalized()
		_ok(up.dot(Vector3.UP) > 1.0 - TOL, "seat/%s: stands the way the real one does" % systemid,
			"up is %s" % up)
		# The stand is the one body now: the console's shapes are lent to it.
		var lent := stand.get_children().any(func(c: Node) -> bool: return c.name.begins_with("Lent"))
		_ok(lent, "seat/%s: its collision is lent to the stand" % systemid)
		stand.mount().drop_object()
		await _wait(2)
		_ok(stand.seated_console() == null, "seat/%s: and it comes off again" % systemid)
		_ok(not stand.get_children().any(func(c: Node) -> bool: return c.name.begins_with("Lent")),
			"seat/%s: taking its collision back" % systemid)
		await _clear()
	# A stand made for one console does not take another.
	var wii_stand := await _stand("wii_stand", Vector3(0, 1, 0))
	var ps2 := await _console("ps2", Vector3(0.6, 1.2, 0))
	_ok(not wii_stand.mount().snap_filter.call(ps2), "seat/the Wii stand refuses a PS2")
	wii_stand.restore_console(ps2)
	await _wait(5)
	_ok(wii_stand.seated_console() == null, "seat/even from a save")
	# And a console no stand fits grows nothing.
	var snes := await _console("snes", Vector3(-0.6, 1.2, 0))
	_ok(StandFoot.build_for(snes), "seat/a SNES needs no feet")
	_ok(not snes.get_children().any(func(c: Node) -> bool: return c is StandFoot),
		"seat/and has none")
	await _clear()


# ── save ──────────────────────────────────────────────────────────────────────

func _group_save() -> void:
	var stand := await _stand("ps2_vertical_stand", Vector3(0, 1, 0))
	var sys := await _console("ps2", Vector3(0.6, 1.2, 0))
	stand.restore_console(sys)
	await _wait(5)
	var sp := ScenePersistence.new()
	var rec: Dictionary = sp.serialize_node(stand, 1, {sys: 7})
	_eq(str(rec.get("type", "")), "console_stand", "save/a stand is recorded as a console_stand")
	_eq(str(rec.get("stand_id", "")), "ps2_vertical_stand", "save/naming which stand")
	_eq(rec.get("console"), 7, "save/and the console in it")
	stand.mount().drop_object()
	await _wait(2)
	var back := sp.deserialize_object(rec) as ConsoleStand
	_ok(back != null and back.stand_id == "ps2_vertical_stand", "save/it is rebuilt as that stand")
	if back != null:
		add_child(back)
		_spawned.append(back)
		await _wait(2)
		sp._restore_console_stand(self, 1, back, {7: sys}, rec)
		await _wait(5)
		_ok(back.seated_console() == sys, "save/holding its console again")
	var gone := sp.deserialize_object({"type": "console_stand", "stand_id": "t:uninstalled"})
	_ok(gone == null, "save/a stand nothing defines any more is skipped")
	await _clear()
