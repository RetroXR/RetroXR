## Super Famicom / PAL cartridge self-tests: the third Super NES body, the markets
## that get it, the size it spawns at, and the shell colours that paint it.
##
##     "$godot" --headless --path RetroXR res://Tests/sfc_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/sfc_cart_tests.tscn -- --only=lookup
##
## Exits 0 when everything passes, 1 otherwise. Writes ROM fixtures under user://
## and removes them at each end. The North American bodies are snes_cart_tests'.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__sfccart_selftest"
const BODY := SnesCartShell.BODY_SFC

## The moulding a shell colour paints: both halves (the rear one's flat panel
## carries the baked ribbing as a material of its own) and the moulded lettering.
const SHELL_PARTS := ["Front_Shell", "Rear_Shell", "Molded_Made_In_Japan", "Cavity_Mold_ID"]
## Parts a shell colour must never reach.
const KEPT_PARTS := ["Label", "Rear_Sticker", "Connector_PCB", "Connector_Contacts", "Grounding_Clip",
	"Security_Screw_L", "Security_Screw_R"]
## A triangle narrower than this, relative to its longest edge, has no area to map.
const UV_MIN_WIDTH := 0.00005
## Measured bounds, metres: 128 wide, 87.5 high, 20 thick over the rear ribs.
const MODEL_SIZE := Vector3(0.128, 0.0875, 0.020)
## The rear sticker art is 2400 x 1000. Where the branded art had its trademark
## notice line and the tail of SUPER FAMICOM(R), and where MODEL NO. and the
## serial still are (pixels, top-left origin).
const TRADEMARK_RECT := Rect2i(90, 932, 1440, 56)
const MARK_RECT := Rect2i(1870, 45, 270, 75)
const MODEL_NO_RECT := Rect2i(1350, 150, 740, 56)
const SERIAL_RECT := Rect2i(1740, 936, 575, 45)

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[sfccart] TIMEOUT")
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
	if _wants("surfaces"):
		_test_surfaces()
	if _wants("color"):
		_test_color()
	if _wants("kept"):
		_test_kept()
	if _wants("lookup"):
		_test_lookup()
	if _wants("size"):
		_test_size()
	if _wants("cartridge"):
		await _test_cartridge()

	_clear_fixtures()
	await _settle_warm()
	print("[sfccart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[sfccart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[sfccart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _body() -> Node3D:
	var node := (load(BODY) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


func _mat(root: Node, part: String, surface := 0) -> BaseMaterial3D:
	return _part(root, part).get_active_material(surface) as BaseMaterial3D


func _source(root: Node, part: String, surface := 0) -> BaseMaterial3D:
	return _part(root, part).mesh.surface_get_material(surface) as BaseMaterial3D


func _materials(mi: MeshInstance3D) -> Array[Material]:
	var out: Array[Material] = []
	for i in mi.mesh.get_surface_count():
		out.append(mi.get_active_material(i))
	return out


func _preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(SnesCartShell.SYSTEMID).find(id)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.003 and absf(a.g - b.g) < 0.003 and absf(a.b - b.b) < 0.003


## Every surface of the moulding: [mesh, surface index].
func _shell_surfaces(root: Node) -> Array:
	var out := []
	for p: String in SHELL_PARTS:
		var mi := _part(root, p)
		for i in mi.mesh.get_surface_count():
			out.append([mi, i])
	return out


## The moulding as imported: the model's colour and roughness, solid.
func _as_model(root: Node) -> bool:
	for s: Array in _shell_surfaces(root):
		var m := (s[0] as MeshInstance3D).get_active_material(s[1]) as BaseMaterial3D
		var src := (s[0] as MeshInstance3D).mesh.surface_get_material(s[1]) as BaseMaterial3D
		if m == null or not (_near(m.albedo_color, src.albedo_color) and is_equal_approx(m.roughness, src.roughness)
				and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED):
			return false
	return true


## The whole moulding painted `color`, each surface keeping its own roughness.
func _painted(root: Node, color: Color) -> bool:
	for s: Array in _shell_surfaces(root):
		var m := (s[0] as MeshInstance3D).get_active_material(s[1]) as BaseMaterial3D
		var src := (s[0] as MeshInstance3D).mesh.surface_get_material(s[1]) as BaseMaterial3D
		if m == null or not (_near(m.albedo_color, color) and is_equal_approx(m.roughness, src.roughness)):
			return false
	return true


## Bounds of every mesh under `root`, in `frame`'s space (`root`'s own by default).
func _bounds(root: Node3D, frame: Node3D = null) -> AABB:
	var to_frame := (frame if frame != null else root).global_transform.affine_inverse()
	var ab := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := (to_frame * mi.global_transform) * mi.get_aabb()
		ab = box if first else ab.merge(box)
		first = false
	return ab


## A ROM with a checksummed internal header titled `title` at `at` (0x7FC0 LoROM,
## 0xFFC0 HiROM) for `destination` (0x00 Japan, 0x02 Europe, 0x01 North America).
func _rom(title: String, destination: int, at := 0x7FC0, size := 0x8000) -> PackedByteArray:
	var rom := PackedByteArray()
	rom.resize(size)
	for i in SnesCartShell.TITLE_BYTES:
		rom[at + i] = title.unicode_at(i) if i < title.length() else 0x20
	rom[at + SnesCartShell.DESTINATION_AT] = destination
	var checksum := 0x5A3C
	rom.encode_u16(at + SnesCartShell.CHECKSUM_AT, checksum)
	rom.encode_u16(at + SnesCartShell.CHECKSUM_COMPLEMENT_AT, ~checksum & 0xFFFF)
	return rom


func _write_rom(file_name: String, bytes: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


## The scraped-label folder the cartridge reads: the REAL roms root, as
## snes_cart_tests uses. Folders this suite had to create there are removed again.
func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(SnesCartShell.SYSTEMID).path_join("media").path_join("label")


var _created_dirs: Array[String] = []


func _make_label_dir() -> void:
	var missing: Array[String] = []
	var d := _label_dir()
	while not DirAccess.dir_exists_absolute(d):
		missing.push_front(d)
		d = d.get_base_dir()
	DirAccess.make_dir_recursive_absolute(_label_dir())
	missing.reverse()
	_created_dirs.append_array(missing)


func _clear_fixtures() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))
	for d in _created_dirs:
		DirAccess.remove_absolute(d)
	_created_dirs.clear()
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


## How much a rectangle of an image varies: the spread of its luminance.
func _spread(img: Image, r: Rect2i) -> float:
	var lo := 1.0
	var hi := 0.0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			var l := img.get_pixel(x, y).get_luminance()
			lo = minf(lo, l)
			hi = maxf(hi, l)
	return hi - lo


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	_ok(ResourceLoader.exists(BODY), "resources/%s exists" % BODY.get_file())
	_ok(BODY != SnesCartShell.BODY_TYPE_A and BODY != SnesCartShell.BODY_TYPE_B,
		"resources/the Super Famicom body is a model of its own")


func _test_model() -> void:
	var body := _body()
	var missing := PackedStringArray()
	for part: String in SHELL_PARTS + KEPT_PARTS:
		if _part(body, part) == null:
			missing.append(part)
	_ok(missing.is_empty(), "model/every part is there", str(missing))
	var ab := _bounds(body)
	_ok(ab.size.distance_to(MODEL_SIZE) < 0.0003, "model/128 x 87.5 x 20 mm", str(ab.size))
	var label := _part(body, "Label")
	var lab := label.transform * label.get_aabb()
	_ok(lab.get_center().z > ab.get_center().z and lab.get_center().y > ab.get_center().y,
		"model/the label is on the front (+Z), in the upper half")
	var sticker := _part(body, "Rear_Sticker")
	_ok((sticker.transform * sticker.get_aabb()).get_center().z < ab.get_center().z,
		"model/the warning sticker is on the back")
	var connector := _part(body, "Connector_PCB")
	_ok((connector.transform * connector.get_aabb()).get_center().y < ab.get_center().y,
		"model/the connector is at the bottom (-Y)")
	body.free()


## RetroXR's debranding: trademarks go, the factual markings stay.
func _test_branding() -> void:
	var body := _body()
	var marks := PackedStringArray()
	var maps := {}
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for word in ["nintendo", "logo", "wordmark", "emblem", "famicom", "registered"]:
			if String(mi.name).containsn(word):
				marks.append(mi.name)
		for sm in mi.mesh.get_surface_count():
			var m := mi.get_active_material(sm) as BaseMaterial3D
			if m == null:
				continue
			for word in ["nintendo", "logo", "wordmark", "emblem", "famicom"]:
				if m.resource_name.containsn(word):
					marks.append(m.resource_name)
			if m.normal_texture != null:
				maps[m.normal_texture.resource_path.get_file().trim_prefix(BODY.get_file().get_basename() + "_")] = true
	_ok(marks.is_empty(), "branding/no logo mesh or material", str(marks))
	var map_names := maps.keys()
	map_names.sort()
	# The grain, and the rear ribbing baked flat. The oval was never baked into it.
	_ok(map_names == ["ABS_Grain_Normal.png", "RearDetail_Normal.png"],
		"branding/no normal map but the plastic grain and the rear ribs", str(map_names))
	_ok(_part(body, "Molded_Made_In_Japan") != null, "branding/the moulded MADE IN JAPAN stays")
	var art := _source(body, "Rear_Sticker").albedo_texture
	var img := art.get_image() if art != null else null
	if img != null and img.is_compressed():
		img.decompress()
	_ok(img != null and img.get_width() == 2400, "branding/the sticker art is the 2400 px recreation",
		str(img.get_size() if img != null else null))
	if img != null and img.get_width() == 2400:
		_ok(_spread(img, TRADEMARK_RECT) < 0.05 and _spread(img, MARK_RECT) < 0.05,
			"branding/the sticker has no SUPER FAMICOM mark and no trademark notice")
		_ok(_spread(img, MODEL_NO_RECT) > 0.3 and _spread(img, SERIAL_RECT) > 0.3,
			"branding/the sticker keeps MODEL NO. and the serial")
	body.free()


## Every triangle of a normal-mapped surface has area in UV space; see
## n64_cart_tests' uv group. A triangle with none shades black on some faces.
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
	# The scraped art is a scan of the label, which is front-only on this shell:
	# the label spans the image, top left at the label's top left.
	var label := _part(body, "Label")
	var uvs: PackedVector2Array = label.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = label.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mid := (label.get_aabb().get_center())
	var lo := Vector2(INF, INF)
	var hi := -lo
	var top_left := true
	for i in uvs.size():
		lo = lo.min(uvs[i])
		hi = hi.max(uvs[i])
		# Image top (v 0) is the label's top edge, image left (u 0) its left.
		if uvs[i].y < 0.01 and verts[i].y < mid.y:
			top_left = false
		if uvs[i].x < 0.01 and verts[i].x > mid.x:
			top_left = false
	_ok(lo.distance_to(Vector2.ZERO) < 0.01 and hi.distance_to(Vector2.ONE) < 0.01 and top_left,
		"uv/the label covers the art 0-1, top left at top left", "%s..%s" % [lo, hi])
	body.free()


func _test_surfaces() -> void:
	var body := _body()
	var names := {}
	var materials := {}
	for s in CartridgeColor.shell_surfaces(body):
		var mi := s["mesh"] as MeshInstance3D
		names[String(mi.name)] = true
		materials[mi.get_active_material(s["surface"]).resource_name] = true
	var got := names.keys()
	got.sort()
	var want := SHELL_PARTS.duplicate()
	want.sort()
	_ok(got == want, "surfaces/exactly the moulding", str(got))
	_ok(materials.has("SNES_Shell_Plastic_Ribbed"), "surfaces/the ribbed rear panel is part of it",
		str(materials.keys()))
	var halves := {}
	for s in CartridgeColor.shell_surfaces(body):
		halves[String((s["mesh"] as Node).name)] = s["half"]
	_ok(halves.get("Front_Shell") == CartridgeColor.Half.FRONT and halves.get("Rear_Shell") == CartridgeColor.Half.BACK
		and halves.get("Molded_Made_In_Japan") == CartridgeColor.Half.BACK,
		"surfaces/the halves, and the rear lettering with the rear", str(halves))
	body.free()


func _test_color() -> void:
	var a := _body()
	var b := _body()
	var grey := _preset(&"grey")
	_ok(CartridgeColor.apply_preset(a, &"grey", SnesCartShell.SYSTEMID) == OK, "color/grey applies")
	_ok(_as_model(a), "color/grey reproduces the model's own plastic")
	_ok(_near(grey.color, _source(a, "Front_Shell").albedo_color), "color/grey is the model's colour",
		str(_source(a, "Front_Shell").albedo_color))
	CartridgeColor.apply_preset(a, &"black", SnesCartShell.SYSTEMID)
	_ok(_painted(a, _preset(&"black").color), "color/black paints the whole moulding, ribbed panel included")
	var rear := _part(a, "Rear_Shell")
	var normals := true
	for i in rear.mesh.get_surface_count():
		var src := rear.mesh.surface_get_material(i) as BaseMaterial3D
		if (rear.get_active_material(i) as BaseMaterial3D).normal_texture != src.normal_texture:
			normals = false
	_ok(normals, "color/the grain and the baked ribs are carried")
	CartridgeColor.apply_color(a, Color(0.2, 0.4, 0.9))
	_ok(_painted(a, Color(0.2, 0.4, 0.9)), "color/a colour paints it, each surface keeping its roughness")
	_ok(_mat(b, "Rear_Shell") == _source(b, "Rear_Shell"), "color/another instance is untouched")
	_ok(CartridgeColor.reset_to_default(a) == OK
		and _part(a, "Rear_Shell").get_surface_override_material(0) == null, "color/reset restores the model")
	a.free()
	b.free()


func _test_kept() -> void:
	var cart := _body()
	var before := {}
	for part: String in KEPT_PARTS:
		before[part] = _materials(_part(cart, part))
	CartridgeColor.apply_preset(cart, &"black", SnesCartShell.SYSTEMID)
	CartridgeColor.apply_color(cart, Color(0, 1, 0))
	CartridgeColor.apply_flake(cart, Color(1, 0, 0), SnesCartShell.SYSTEMID)
	CartridgeColor.apply_color(cart, Color(0, 0, 1, 0.5))
	var changed := PackedStringArray()
	for part: String in KEPT_PARTS:
		if _materials(_part(cart, part)) != before[part]:
			changed.append(part)
	_ok(changed.is_empty(), "kept/label, sticker, board, clip and screws keep their materials", str(changed))
	# ModelMaterialFix.demetal must not flatten them.
	_ok(_source(cart, "Security_Screw_L").metallic > 0.5 and _source(cart, "Connector_Contacts").metallic > 0.5,
		"kept/the screws and contacts are authored metal")
	var brass := _source(cart, "Security_Screw_L").albedo_color
	_ok(brass.r - brass.b > 0.2, "kept/the screws are brass, as photographed", str(brass))
	cart.free()


func _test_lookup() -> void:
	var A := SnesCartShell.BODY_TYPE_A
	var B := SnesCartShell.BODY_TYPE_B
	var cases := [
		["a Japanese game", "", "jp", "19951020", BODY],
		["a European game", "", "eu", "19950101", BODY],
		["an Australian game", "", "au", "", BODY],
		["a US game still gets its own latch", "", "us", "19910823", A],
		["a US game from 1994 still gets Type B", "", "us", "19941101", B],
		["a game of no known market", "", "", "", ""],
		["the Super Famicom body forced on a US game", SnesCartShell.SFC, "us", "19910823", BODY],
		["the Super Famicom body forced on an unknown market", SnesCartShell.SFC, "", "", BODY],
		["Type A forced on a Japanese game", SnesCartShell.TYPE_A, "jp", "", A],
		["Type B forced on a PAL game", SnesCartShell.TYPE_B, "eu", "", B],
	]
	for c: Array in cases:
		var got := SnesCartShell.body_model(c[1], c[2], c[3])
		_ok(got == c[4], "lookup/%s spawns %s" % [c[0], c[4].get_file() if c[4] != "" else "no model"],
			"got %s" % got)
	# From a file: no scraped entry, so the header's destination byte decides.
	var files := [
		["jp.sfc", 0x00, BODY], ["pal.sfc", 0x02, BODY], ["de.sfc", 0x09, BODY], ["au.sfc", 0x11, BODY],
		["us.sfc", 0x01, A],
	]
	for f: Array in files:
		var path := _write_rom(f[0], _rom("GAME", f[1]))
		var got := SnesCartShell.body_model_for_rom("", SnesCartShell.SYSTEMID, path)
		_ok(got == f[2], "lookup/%s (destination 0x%02X) spawns %s" % [f[0], f[1], (f[2] as String).get_file()],
			"got %s" % got)


func _test_size() -> void:
	var sid := SnesCartShell.SYSTEMID
	_ok(MediaDimensions.cart_size(sid, "", BODY).distance_to(MODEL_SIZE) < 0.00001,
		"size/the Super Famicom body's size is the model's own", str(MediaDimensions.cart_size(sid, "", BODY)))
	for other: String in ["", SnesCartShell.BODY_TYPE_A, SnesCartShell.BODY_TYPE_B]:
		_ok(MediaDimensions.cart_size(sid, "", other) == MediaDimensions.CART_SIZES[sid],
			"size/%s keeps the North American size" % (other.get_file() if other != "" else "no model"))


func _test_cartridge() -> void:
	var img := Image.create(420, 145, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	_make_label_dir()
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))

	var jp := await _spawn(_write_rom(FIXTURE + ".sfc", _rom("SUPER MARIO RPG", 0x00)))
	var pal := await _spawn(_write_rom("pal.sfc", _rom("SUPER MARIO RPG", 0x02)))
	var us := await _spawn(_write_rom("us.sfc", _rom("SUPER MARIO RPG", 0x01)))
	var forced := await _spawn(_write_rom("forced.sfc", _rom("SUPER MARIO RPG", 0x01)), SnesCartShell.SFC)
	for c: Array in [["a Japanese ROM", jp], ["a PAL ROM", pal], ["the body forced on a US ROM", forced]]:
		var cart := c[1] as RetroCartridge
		var model := cart.get_node_or_null("CartModel") as Node3D
		_ok(model != null and model.scene_file_path == BODY, "cartridge/%s spawns the Super Famicom body" % c[0])
		if model == null:
			continue
		_ok(model.scale.distance_to(Vector3.ONE) < 0.003, "cartridge/%s: the model is not stretched" % c[0],
			str(model.scale))
		_ok(_bounds(model, cart).get_center().length() < 0.0005, "cartridge/%s: the model is centred" % c[0])
		# The body it rests on is the shell exactly; and so is the aim box.
		var box := (cart.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
		_ok(box.size.distance_to(MODEL_SIZE) < 0.00001,
			"cartridge/%s: the body is the Super Famicom shell's size" % c[0], str(box.size))
		var aim := (cart.get_node("PointerArea/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
		_ok(aim.size.distance_to(MODEL_SIZE) < 0.00001,
			"cartridge/%s: the aim box is the shell and no bigger" % c[0], str(aim.size))
		_ok(_as_model(model), "cartridge/%s: the standard grey" % c[0])
	var us_model := us.get_node_or_null("CartModel") as Node3D
	_ok(us_model != null and us_model.scene_file_path == SnesCartShell.BODY_TYPE_A,
		"cartridge/a US ROM still spawns Type A")
	var jp_model := jp.get_node_or_null("CartModel") as Node3D
	var label := CartridgeLabel.find_label(jp_model) if jp_model != null else null
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.name == "Label" and label.visible and art != null and art.get_width() == 420,
		"cartridge/the scraped label is painted on the label")
	_ok(jp.get_node_or_null("ModelLabelArt") == null and not (jp.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	_ok(jp_model != null and _mat(jp_model, "Connector_Contacts").metallic > 0.5
		and _mat(jp_model, "Security_Screw_L").metallic > 0.5, "cartridge/contacts and screws keep their metal")
	var pal_model := pal.get_node_or_null("CartModel") as Node3D
	var pal_label := CartridgeLabel.find_label(pal_model) if pal_model != null else null
	_ok(pal_label != null and pal_label.get_surface_override_material(0) == null
		and (pal.get_node("GameLabel") as Label3D).visible, "cartridge/no art: the blank label and the title")
	var black := await _spawn(_write_rom("black.sfc", _rom("SUPER MARIO RPG", 0x00)), "", &"black")
	_ok(black.get_node_or_null("CartModel") != null and _painted(black.get_node("CartModel"), _preset(&"black").color),
		"cartridge/a forced shell paints the Super Famicom body")
	for cart in [jp, pal, us, forced, black]:
		cart.queue_free()
	await get_tree().process_frame


func _spawn(rom: String, body := "", shell: StringName = &"") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = SnesCartShell.SYSTEMID
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.body_region = body
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
