## Nintendo DS and 3DS Game Card self-tests — the two models and the spawned
## cartridge that wears them.
##
##     "$godot" --headless --path RetroXR res://Tests/ds_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/ds_cart_tests.tscn -- --only=model
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one label fixture into the player's real nds and n3ds media/label
## folders (MediaDimensions derives the path from the ROM's name) and removes
## both at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__dscart_selftest"
const UV_MIN_WIDTH := 0.00005
const SYSTEMS := ["nds", "n3ds"]

## Every part of the moulding and the connector.
const PARTS := ["FrontShell", "RearShell", "RearMarkingPanel", "ConnectorPCB", "GoldContacts",
	"ContactSeparators", "ConnectorBottomLedge", "CartridgeLabel"]

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[dscart] TIMEOUT")
		get_tree().quit(1))
	_clear_fixtures()

	if _wants("resources"):
		_test_resources()
	if _wants("model"):
		_test_model()
	if _wants("branding"):
		_test_branding()
	if _wants("uv"):
		_test_uv()
	if _wants("label"):
		_test_label()
	if _wants("cartridge"):
		await _test_cartridge()

	_clear_fixtures()
	await _settle_warm()
	print("[dscart] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _settle_warm() -> void:
	for i in range(1200):
		if ModelWarmer.is_warmed():
			return
		await get_tree().process_frame


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, test_name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[dscart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[dscart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _path(systemid: String) -> String:
	return RetroCartridge._CART_MODELS[systemid]


func _body(systemid: String) -> Node3D:
	var node := (load(_path(systemid)) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


func _bounds(root: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.transform * mi.get_aabb()
		ab = box if first else ab.merge(box)
		first = false
	return ab


func _label_dir(systemid: String) -> String:
	return RomLibrary.rom_dir_for_system(systemid).path_join("media").path_join("label")


func _clear_fixtures() -> void:
	for systemid: String in SYSTEMS:
		DirAccess.remove_absolute(_label_dir(systemid).path_join(FIXTURE + ".png"))


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	for systemid: String in SYSTEMS:
		_ok(ResourceLoader.exists(_path(systemid)), "resources/%s exists" % _path(systemid).get_file())


func _test_model() -> void:
	for systemid: String in SYSTEMS:
		var body := _body(systemid)
		var missing := PackedStringArray()
		for part: String in PARTS:
			if _part(body, part) == null:
				missing.append(part)
		_ok(missing.is_empty(), "model/%s has every part" % systemid, str(missing))
		var ab := _bounds(body)
		var size := MediaDimensions.cart_size(systemid)
		_ok(absf(ab.size.x - size.x) < 0.0002 and absf(ab.size.y - size.y) < 0.0002
			and absf(ab.size.z - size.z) < 0.0002, "model/%s is MediaDimensions' size" % systemid,
			"%s vs %s" % [ab.size, size])
		var pcb := _part(body, "ConnectorPCB")
		var label := _part(body, "CartridgeLabel")
		_ok((pcb.transform * pcb.get_aabb()).get_center().y < ab.get_center().y
			and (label.transform * label.get_aabb()).get_center().z > ab.get_center().z,
			"model/%s connector on -Y, label on +Z" % systemid)
		body.free()
	# The 3DS card's tab widens it by 2 mm on one side only.
	var ds := _body("nds")
	var n3ds := _body("n3ds")
	var ds_ab := _bounds(ds)
	var n3ds_ab := _bounds(n3ds)
	_ok(absf(n3ds_ab.position.x - ds_ab.position.x) < 0.0002
		and absf(n3ds_ab.end.x - ds_ab.end.x - 0.002) < 0.0002,
		"model/the 3DS tab adds 2 mm on +X only", "%s vs %s" % [ds_ab, n3ds_ab])
	ds.free()
	n3ds.free()


## The shipped bodies carry no moulded mark: no logo or revision-text mesh or
## material, and no normal map but the plastic grain.
func _test_branding() -> void:
	for systemid: String in SYSTEMS:
		var body := _body(systemid)
		var marks := PackedStringArray()
		var maps := {}
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for word in ["nintendo", "logo", "revision", "wordmark", "lettering"]:
				if String(mi.name).containsn(word):
					marks.append(mi.name)
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				if m == null:
					continue
				for word in ["nintendo", "logo", "revision", "wordmark", "lettering", "baked"]:
					if m.resource_name.containsn(word):
						marks.append(m.resource_name)
				if m.normal_texture != null:
					maps[m.normal_texture.resource_path.get_file().trim_prefix(
						_path(systemid).get_file().get_basename() + "_")] = true
		_ok(marks.is_empty(), "branding/%s no logo mesh or material" % systemid, str(marks))
		_ok(maps.keys() == ["plastic_grain.png"], "branding/%s no normal map but the plastic grain" % systemid,
			str(maps.keys()))
		body.free()


## Every triangle of a normal-mapped surface has area in UV space; see
## n64_cart_tests' uv group. The export projected the shells' UVs from the front,
## leaving their walls unmapped; Tools/glb/fix_unmapped_uvs.py gave them UVs.
func _test_uv() -> void:
	for systemid: String in SYSTEMS:
		var body := _body(systemid)
		var unmapped := {}
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null or not m.normal_enabled:
					continue
				var arrays := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var count := 0
				for t in range(0, idx.size(), 3):
					var a := idx[t]
					var b := idx[t + 1]
					var c := idx[t + 2]
					var longest := maxf(verts[a].distance_to(verts[b]),
							maxf(verts[b].distance_to(verts[c]), verts[c].distance_to(verts[a])))
					if (verts[b] - verts[a]).cross(verts[c] - verts[a]).length() <= UV_MIN_WIDTH * longest:
						continue
					if absf((uvs[b] - uvs[a]).cross(uvs[c] - uvs[a])) < 1e-12:
						count += 1
				if count > 0:
					unmapped[String(mi.name)] = count
		_ok(unmapped.is_empty(), "uv/%s no unmapped triangle on a normal-mapped surface" % systemid,
			str(unmapped))
		body.free()


## The sticker's UVs put the art's top-left corner at the label's top-left as
## seen from the front (+Z, so -X is left and +Y is up): a mirrored or upside-down
## mapping moves the corners, a correct one cannot pass by symmetry.
func _test_label() -> void:
	for systemid: String in SYSTEMS:
		var body := _body(systemid)
		var label := _part(body, "CartridgeLabel")
		var arrays := label.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var top_left := 0
		var bottom_right := 0
		for i in verts.size():
			if verts[i].y - verts[i].x > verts[top_left].y - verts[top_left].x:
				top_left = i
			if verts[i].x - verts[i].y > verts[bottom_right].x - verts[bottom_right].y:
				bottom_right = i
		_ok(uvs[top_left].x < 0.1 and uvs[top_left].y < 0.1,
			"label/%s art's top-left is the label's top-left" % systemid, str(uvs[top_left]))
		_ok(uvs[bottom_right].x > 0.9 and uvs[bottom_right].y > 0.9,
			"label/%s art's bottom-right is the label's bottom-right" % systemid, str(uvs[bottom_right]))
		_ok(label.mesh.get_surface_count() == 1, "label/%s is one surface, as CartridgeLabel needs" % systemid)
		body.free()


func _test_cartridge() -> void:
	var img := Image.create(420, 460, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	for systemid: String in SYSTEMS:
		DirAccess.make_dir_recursive_absolute(_label_dir(systemid))
		img.save_png(_label_dir(systemid).path_join(FIXTURE + ".png"))
		var ext := "nds" if systemid == "nds" else "3ds"
		var with_art := await _spawn(systemid, "/roms/%s/%s.%s" % [systemid, FIXTURE, ext])
		var plain := await _spawn(systemid, "/roms/%s/plain.%s" % [systemid, ext])
		var model := with_art.get_node_or_null("CartModel")
		_ok(model != null and model.scene_file_path == _path(systemid),
			"cartridge/a %s ROM spawns the model" % systemid)
		var label := CartridgeLabel.find_label(model) if model != null else null
		var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
		_ok(label != null and label.visible and art != null and art.get_width() == 420,
			"cartridge/%s the scraped label is painted on the sticker" % systemid)
		_ok(with_art.get_node_or_null("ModelLabelArt") == null
			and not (with_art.get_node("GameLabel") as Label3D).visible,
			"cartridge/%s no quad and no title over the art" % systemid)
		var plain_model := plain.get_node_or_null("CartModel")
		var plain_label := CartridgeLabel.find_label(plain_model) if plain_model != null else null
		_ok(plain_label != null and plain_label.get_surface_override_material(0) == null
			and (plain.get_node("GameLabel") as Label3D).visible,
			"cartridge/%s no art: the blank sticker and the title" % systemid)
		var gold := _part(model, "GoldContacts").get_active_material(0) as BaseMaterial3D if model != null else null
		_ok(gold != null and gold.metallic > 0.5, "cartridge/%s contacts keep their metal" % systemid)
		var scale := (model as Node3D).scale if model != null else Vector3.ZERO
		_ok(absf(scale.x - 1.0) < 0.005 and absf(scale.y - 1.0) < 0.005 and absf(scale.z - 1.0) < 0.005,
			"cartridge/%s the body is not stretched to MediaDimensions' size" % systemid, str(scale))
		for cart in [with_art, plain]:
			cart.queue_free()
		await get_tree().process_frame


func _spawn(systemid: String, rom: String) -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = systemid
	cart.rom_path = rom
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
