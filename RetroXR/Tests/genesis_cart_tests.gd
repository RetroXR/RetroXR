## Sega Genesis cartridge self-tests — the model and the spawned cartridge that wears it.
##
##     "$godot" --headless --path RetroXR res://Tests/genesis_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/genesis_cart_tests.tscn -- --only=model
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one label fixture into the player's real genesis media/label folder
## (MediaDimensions derives the path from the ROM's name) and removes it at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const SYSTEMID := "genesis"
const FIXTURE := "__gencart_selftest"
const UV_MIN_WIDTH := 0.00005

## Every part of the moulding, the sticker, the connector and the fasteners.
const PARTS := ["Front_Shell", "Rear_Shell", "Label", "Label_Fold", "Caution_Plate", "Connector_PCB",
	"Connector_Contacts", "Security_Screw_L", "Security_Screw_R"]

## The measured sticker: 74 mm wide, 60 mm down the front, 7 mm over the top.
const LABEL_W := 0.074
const LABEL_FRONT := 0.060
const LABEL_FOLD := 0.007

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[gencart] TIMEOUT")
		get_tree().quit(1))
	_clear_fixture()

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

	_clear_fixture()
	await _settle_warm()
	print("[gencart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[gencart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[gencart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _path() -> String:
	return RetroCartridge._CART_MODELS[SYSTEMID]


func _body() -> Node3D:
	var node := (load(_path()) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


func _box(mi: MeshInstance3D) -> AABB:
	return mi.transform * mi.get_aabb()


func _bounds(root: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var box := _box(n as MeshInstance3D)
		ab = box if first else ab.merge(box)
		first = false
	return ab


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(SYSTEMID).path_join("media").path_join("label")


func _clear_fixture() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))


## Where a ray along -X from beyond the right side first meets the rear shell, or
## NAN: the side at that height and depth, or the floor of a notch.
func _rear_x(body: Node3D, y: float, z: float) -> float:
	var mi := _part(body, "Rear_Shell")
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var from := Vector3(0.2, y, z)
	var best := NAN
	for t in range(0, idx.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.LEFT,
			mi.transform * verts[idx[t]], mi.transform * verts[idx[t + 1]], mi.transform * verts[idx[t + 2]])
		if hit is Vector3 and (is_nan(best) or (hit as Vector3).x > best):
			best = (hit as Vector3).x
	return best


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	_ok(ResourceLoader.exists(_path()), "resources/%s exists" % _path().get_file())
	_ok(FileAccess.file_exists(_path().get_base_dir().path_join("LICENSE-genesis-cart.txt")),
		"resources/LICENSE-genesis-cart.txt beside it")


func _test_model() -> void:
	var body := _body()
	var missing := PackedStringArray()
	for part: String in PARTS:
		if _part(body, part) == null:
			missing.append(part)
	_ok(missing.is_empty(), "model/has every part", str(missing))
	if not missing.is_empty():
		body.free()
		return
	var ab := _bounds(body)
	var size := MediaDimensions.cart_size(SYSTEMID)
	_ok(absf(ab.size.x - size.x) < 0.0002 and absf(ab.size.y - size.y) < 0.0002
		and absf(ab.size.z - size.z) < 0.0002, "model/is MediaDimensions' size", "%s vs %s" % [ab.size, size])
	_ok(size.is_equal_approx(Vector3(0.108, 0.067, 0.017)), "model/MediaDimensions holds the measured 108 x 67 x 17 mm",
		str(size))
	var center := ab.get_center()
	var label := _box(_part(body, "Label"))
	_ok(_box(_part(body, "Connector_PCB")).get_center().y < center.y and label.get_center().z > center.z,
		"model/connector on -Y, label on +Z")
	_ok(absf(ab.position.y) < 0.0002 and _box(_part(body, "Connector_PCB")).position.y > 0.0008,
		"model/the mouth is y = 0 and the board sits 1 mm inside it")
	_ok(_box(_part(body, "Security_Screw_L")).get_center().z < center.z
		and _box(_part(body, "Security_Screw_R")).get_center().z < center.z
		and _box(_part(body, "Caution_Plate")).get_center().z < center.z,
		"model/the screws and the caution plate are on the back")
	# The notches: 7 mm into each side and 4 mm in from the back, up to 40 mm; the
	# rear half's lip stays flush with the side between them and the seam.
	var back := ab.position.z
	var notch := _rear_x(body, 0.020, back + 0.002)
	var above := _rear_x(body, 0.050, back + 0.002)
	var lip := _rear_x(body, 0.020, back + 0.0055)
	_ok(absf(notch - 0.047) < 0.0003, "model/the side notch is 7 mm deep", "%.4f" % notch)
	_ok(absf(above - 0.054) < 0.0003 and absf(lip - 0.054) < 0.0003,
		"model/the notch stops at 40 mm and leaves the lip", "above %.4f lip %.4f" % [above, lip])
	body.free()


## The body carries no publisher mark: the Acclaim plaque is modelled blank. The
## only normal maps are the plastic grain and the caution plate's lettering.
func _test_branding() -> void:
	var body := _body()
	var marks := PackedStringArray()
	var maps := {}
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for word in ["sega", "acclaim", "logo", "genesis_logo", "marks"]:
			if String(mi.name).containsn(word):
				marks.append(mi.name)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			for word in ["sega", "acclaim", "logo", "marks"]:
				if m.resource_name.containsn(word):
					marks.append(m.resource_name)
			if m.normal_texture != null:
				maps[m.normal_texture.resource_path.get_file().trim_prefix(
					_path().get_file().get_basename() + "_")] = true
	_ok(marks.is_empty(), "branding/no logo mesh or material", str(marks))
	var keys := maps.keys()
	keys.sort()
	_ok(keys == ["caution_plate_normal.png", "plastic_normal.png"],
		"branding/normal maps are the grain and the caution lettering only", str(keys))
	body.free()


## Every triangle of a normal-mapped surface has area in UV space; see
## n64_cart_tests' uv group. Tools/glb/fix_unmapped_uvs.py gave the boolean
## sliver on the front shell its UVs.
func _test_uv() -> void:
	var body := _body()
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
	_ok(unmapped.is_empty(), "uv/no unmapped triangle on a normal-mapped surface", str(unmapped))
	body.free()


## The label's UVs put the art's top-left corner at the label's top-left as seen
## from the front (+Z, so -X is left and +Y is up): a mirrored or upside-down
## mapping moves the corners, a correct one cannot pass by symmetry. ScreenScraper's
## Genesis labels are front-face scans, so the art covers the 60 mm front and the
## 7 mm fold over the top is its own plain mesh.
func _test_label() -> void:
	var body := _body()
	var label := _part(body, "Label")
	var arrays := label.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var top_left := -1
	var bottom_right := -1
	for i in verts.size():
		if normals[i].z < 0.9:
			continue
		if top_left < 0 or verts[i].y - verts[i].x > verts[top_left].y - verts[top_left].x:
			top_left = i
		if bottom_right < 0 or verts[i].x - verts[i].y > verts[bottom_right].x - verts[bottom_right].y:
			bottom_right = i
	_ok(top_left >= 0 and uvs[top_left].x < 0.1 and uvs[top_left].y < 0.1,
		"label/art's top-left is the label's top-left", str(uvs[top_left]) if top_left >= 0 else "no front face")
	_ok(bottom_right >= 0 and uvs[bottom_right].x > 0.9 and uvs[bottom_right].y > 0.9,
		"label/art's bottom-right is the label's bottom-right",
		str(uvs[bottom_right]) if bottom_right >= 0 else "no front face")
	var ab := _box(label)
	_ok(absf(ab.size.x - LABEL_W) < 0.0002 and absf(ab.size.y - LABEL_FRONT) < 0.0002,
		"label/is the measured 74 x 60 mm front of the sticker", str(ab.size))
	_ok(label.mesh.get_surface_count() == 1, "label/is one surface, as CartridgeLabel needs")
	var fold := _box(_part(body, "Label_Fold"))
	var top := _bounds(body).end.y
	_ok(fold.position.y >= ab.end.y - 0.0002 and absf(fold.end.y - top) < 0.0006
		and fold.size.z > LABEL_FOLD - 0.0035,
		"label/the fold goes over the top, above the front", "%s" % fold)
	_ok(CartridgeLabel.find_label(body) == label, "label/CartridgeLabel paints the front, not the fold")
	body.free()


func _test_cartridge() -> void:
	var img := Image.create(600, 490, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	DirAccess.make_dir_recursive_absolute(_label_dir())
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))
	var with_art := await _spawn("/roms/%s/%s.md" % [SYSTEMID, FIXTURE])
	var plain := await _spawn("/roms/%s/plain.md" % SYSTEMID)
	var model := with_art.get_node_or_null("CartModel")
	_ok(model != null and model.scene_file_path == _path(), "cartridge/a Genesis ROM spawns the model")
	var label := CartridgeLabel.find_label(model) if model != null else null
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 600,
		"cartridge/the scraped label is painted on the sticker")
	var fold := _part(model, "Label_Fold") if model != null else null
	_ok(fold != null and fold.get_surface_override_material(0) == null,
		"cartridge/the fold keeps its plain paper")
	_ok(with_art.get_node_or_null("ModelLabelArt") == null
		and not (with_art.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	var plain_model := plain.get_node_or_null("CartModel")
	var plain_label := CartridgeLabel.find_label(plain_model) if plain_model != null else null
	_ok(plain_label != null and plain_label.get_surface_override_material(0) == null
		and (plain.get_node("GameLabel") as Label3D).visible,
		"cartridge/no art: the blank sticker and the title")
	var gold := _part(model, "Connector_Contacts").get_active_material(0) as BaseMaterial3D if model != null else null
	var screw := _part(model, "Security_Screw_L").get_active_material(0) as BaseMaterial3D if model != null else null
	_ok(gold != null and gold.metallic > 0.5 and screw != null and screw.metallic > 0.5,
		"cartridge/contacts and screws keep their metal")
	var scale := (model as Node3D).scale if model != null else Vector3.ZERO
	_ok(absf(scale.x - 1.0) < 0.005 and absf(scale.y - 1.0) < 0.005 and absf(scale.z - 1.0) < 0.005,
		"cartridge/the body is not stretched to MediaDimensions' size", str(scale))
	for cart in [with_art, plain]:
		cart.queue_free()
	await get_tree().process_frame


func _spawn(rom: String) -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = SYSTEMID
	cart.rom_path = rom
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
