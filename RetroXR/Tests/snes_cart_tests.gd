## Super NES cartridge self-tests — the two North American bodies, their shell
## colours, the header lookup that picks one per ROM, the body the player picks,
## and the spawned cartridge that uses them.
##
##     "$godot" --headless --path RetroXR res://Tests/snes_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/snes_cart_tests.tscn -- --only=lookup
##
## Exits 0 when everything passes, 1 otherwise. Writes ROM fixtures under user://
## and removes them at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__snescart_selftest"
const BODIES := [SnesCartShell.BODY_TYPE_A, SnesCartShell.BODY_TYPE_B]

## The moulding a shell colour paints: both halves and the bezel round the rear
## sticker.
const SHELL_PARTS := ["Front_Shell", "Rear_Shell", "Label_Bezel"]
## Parts a shell colour must never reach.
const KEPT_PARTS := ["Label", "Label_Fold", "Rear_Sticker", "Connector_PCB", "Connector_Contacts",
	"Security_Screw_L", "Security_Screw_R"]
## A triangle narrower than this, relative to its longest edge, has no area to map.
const UV_MIN_WIDTH := 0.00005
## Measured bounds of both bodies, metres: 135.5 wide, 87 high, 20 thick plus the
## rear bezel's 0.15.
const MODEL_SIZE := Vector3(0.1355, 0.087, 0.02015)
## Where the rear sticker art had "Rd. (M) (C)1991 NINTENDO", and where MODEL NO.
## still is (pixels, top-left origin, of the 1588 x 617 art).
const COPYRIGHT_RECT := Rect2i(896, 30, 376, 43)
const MODEL_NO_RECT := Rect2i(578, 30, 292, 43)

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[snescart] TIMEOUT")
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
	if _wants("cartridge"):
		await _test_cartridge()
	if _wants("forced"):
		await _test_forced()

	_clear_fixtures()
	await _settle_warm()
	print("[snescart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[snescart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[snescart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _body(path := SnesCartShell.BODY_TYPE_A) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


func _mat(root: Node, part: String) -> BaseMaterial3D:
	return _part(root, part).get_active_material(0) as BaseMaterial3D


func _source(root: Node, part: String) -> BaseMaterial3D:
	return _part(root, part).mesh.surface_get_material(0) as BaseMaterial3D


func _materials(mi: MeshInstance3D) -> Array[Material]:
	var out: Array[Material] = []
	for i in mi.mesh.get_surface_count():
		out.append(mi.get_active_material(i))
	return out


func _preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(SnesCartShell.SYSTEMID).find(id)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.003 and absf(a.g - b.g) < 0.003 and absf(a.b - b.b) < 0.003


## The moulding as imported: the model's colour and roughness, solid.
func _as_model(root: Node) -> bool:
	for p: String in SHELL_PARTS:
		var m := _mat(root, p)
		var src := _source(root, p)
		if not (_near(m.albedo_color, src.albedo_color) and is_equal_approx(m.roughness, src.roughness)
				and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED):
			return false
	return true


## The moulding painted `color`, each part keeping its own roughness.
func _painted(root: Node, color: Color) -> bool:
	for p: String in SHELL_PARTS:
		var m := _mat(root, p)
		if not (_near(m.albedo_color, color) and is_equal_approx(m.roughness, _source(root, p).roughness)):
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
## 0xFFC0 HiROM) for `destination` (0x01 North America), `size` bytes, after
## `copier` bytes of copier header.
func _rom(title: String, at := 0xFFC0, size := 0x10000, copier := 0, checksum_ok := true,
		destination := 0x01) -> PackedByteArray:
	var rom := PackedByteArray()
	rom.resize(copier + size)
	var h := copier + at
	for i in SnesCartShell.TITLE_BYTES:
		rom[h + i] = title.unicode_at(i) if i < title.length() else 0x20
	rom[h + SnesCartShell.DESTINATION_AT] = destination
	var checksum := 0x5A3C
	rom.encode_u16(h + SnesCartShell.CHECKSUM_AT, checksum)
	rom.encode_u16(h + SnesCartShell.CHECKSUM_COMPLEMENT_AT, (~checksum & 0xFFFF) if checksum_ok else 0x1234)
	return rom


## The internal header SnesCartShell finds in `bytes`, skipping a copier header
## by the size, as it does for a file.
func _header_of(bytes: PackedByteArray) -> PackedByteArray:
	var skip := SnesCartShell.COPIER_BYTES if bytes.size() % 0x400 == SnesCartShell.COPIER_BYTES else 0
	return SnesCartShell.header_in(bytes, skip)


func _write_rom(file_name: String, bytes: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


## The scraped-label folder the cartridge reads: the REAL roms root, as
## gb_cart_tests uses. Folders this suite had to create there are removed again.
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
	for path in BODIES + [CartridgeColor.PALETTE_PATHS[SnesCartShell.SYSTEMID]]:
		_ok(ResourceLoader.exists(path), "resources/%s exists" % path.get_file())
	var palette := CartridgeColor.get_palette(SnesCartShell.SYSTEMID)
	_ok(palette != null and palette != CartridgeColor.get_palette(GbaCartShell.SYSTEMID),
		"resources/the Super NES has a palette of its own")
	_ok(Array(palette.ids()) == ["grey", "black", "red"], "resources/palette carries exactly the presets",
		str(palette.ids()))
	_ok(palette.find(&"grey").availability == CartridgeShellPreset.Availability.STANDARD,
		"resources/grey is the standard shell")


func _test_model() -> void:
	var sizes := {}
	for path: String in BODIES:
		var body := _body(path)
		var missing := PackedStringArray()
		for part: String in SHELL_PARTS + KEPT_PARTS:
			if _part(body, part) == null:
				missing.append(part)
		_ok(missing.is_empty(), "model/%s has every part" % path.get_file(), str(missing))
		var ab := _bounds(body)
		sizes[path] = ab.size
		_ok(ab.size.distance_to(MODEL_SIZE) < 0.0003, "model/%s is 135.5 x 87 x 20.15 mm" % path.get_file(),
			str(ab.size))
		var label := _part(body, "Label")
		var lab := (label.transform * label.get_aabb())
		_ok(lab.get_center().z > 0.0 and lab.get_center().y > ab.get_center().y,
			"model/%s: the label is on the front (+Z), in the upper half" % path.get_file())
		var connector := _part(body, "Connector_PCB")
		_ok((connector.transform * connector.get_aabb()).get_center().y < ab.get_center().y,
			"model/%s: the connector is at the bottom (-Y)" % path.get_file())
		body.free()
	# MediaDimensions sizes the cartridge to the model's own, so it is not stretched.
	var s := MediaDimensions.cart_size(SnesCartShell.SYSTEMID)
	var a: Vector3 = sizes[SnesCartShell.BODY_TYPE_A]
	_ok(absf(s.x / a.x - 1.0) < 0.002 and absf(s.y / a.y - 1.0) < 0.002 and absf(s.z / a.z - 1.0) < 0.002,
		"model/MediaDimensions' snes size is the model's own", str(s))
	# The two bodies differ only at the front latch.
	var ta := _body(SnesCartShell.BODY_TYPE_A)
	var tb := _body(SnesCartShell.BODY_TYPE_B)
	var rear_a := _part(ta, "Rear_Shell").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var rear_b := _part(tb, "Rear_Shell").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	_ok(rear_a == rear_b, "model/Type A and Type B share one rear shell")
	var front_a := _part(ta, "Front_Shell").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var front_b := _part(tb, "Front_Shell").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	_ok(front_a != front_b, "model/their front shells differ")
	ta.free()
	tb.free()


func _test_branding() -> void:
	for path: String in BODIES:
		var body := _body(path)
		var marks := PackedStringArray()
		var maps := {}
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for word in ["nintendo", "logo", "wordmark", "molded", "emblem"]:
				if String(mi.name).containsn(word):
					marks.append(mi.name)
			for sm in mi.mesh.get_surface_count():
				var m := mi.get_active_material(sm) as BaseMaterial3D
				if m == null:
					continue
				for word in ["nintendo", "logo", "wordmark", "emblem"]:
					if m.resource_name.containsn(word):
						marks.append(m.resource_name)
				if m.normal_texture != null:
					maps[m.normal_texture.resource_path.get_file().trim_prefix(path.get_file().get_basename() + "_")] = true
		_ok(marks.is_empty(), "branding/%s: no logo mesh or material" % path.get_file(), str(marks))
		_ok(maps.keys() == ["abs_grain_normal.png"], "branding/%s: no normal map but the plastic grain" % path.get_file(),
			str(maps.keys()))
		# The rear sticker keeps its warning text and MODEL NO., not the copyright line.
		var art := _source(body, "Rear_Sticker").albedo_texture
		var img := art.get_image() if art != null else null
		if img != null and img.is_compressed():
			img.decompress()
		_ok(img != null and img.get_width() == 1588 and _spread(img, COPYRIGHT_RECT) < 0.05
			and _spread(img, MODEL_NO_RECT) > 0.3,
			"branding/%s: the rear sticker has MODEL NO. and no Nintendo copyright line" % path.get_file())
		body.free()


## Every triangle of a normal-mapped surface has area in UV space; see
## n64_cart_tests' uv group. A triangle with none shades black on some faces.
func _test_uv() -> void:
	for path: String in BODIES:
		var body := _body(path)
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
		_ok(unmapped.is_empty(), "uv/%s: no unmapped triangle on a normal-mapped surface" % path.get_file(),
			str(unmapped))
		# The scraped art is a scan of the sticker's front face, so the front face
		# alone spans the image: top left at the label's top left.
		var label := _part(body, "Label")
		var uvs: PackedVector2Array = label.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var verts: PackedVector3Array = label.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lo := Vector2(INF, INF)
		var hi := -lo
		var top_left := true
		for i in uvs.size():
			lo = lo.min(uvs[i])
			hi = hi.max(uvs[i])
			# Image top (v 0) is the label's top edge, image left (u 0) its left.
			if uvs[i].y < 0.01 and verts[i].y < 0.08:
				top_left = false
			if uvs[i].x < 0.01 and verts[i].x > 0.0:
				top_left = false
		_ok(lo.distance_to(Vector2.ZERO) < 0.01 and hi.distance_to(Vector2.ONE) < 0.01 and top_left,
			"uv/%s: the label's front covers the art 0-1, top left at top left" % path.get_file(), "%s..%s" % [lo, hi])
		body.free()


func _test_surfaces() -> void:
	var body := _body()
	var names := PackedStringArray()
	for s in CartridgeColor.shell_surfaces(body):
		names.append(String((s["mesh"] as Node).name))
	names.sort()
	var want := PackedStringArray(SHELL_PARTS)
	want.sort()
	_ok(names == want, "surfaces/exactly the moulding", str(names))
	body.free()


func _test_color() -> void:
	var a := _body()
	var b := _body()
	var grey := _preset(&"grey")
	_ok(CartridgeColor.apply_preset(a, &"grey", SnesCartShell.SYSTEMID) == OK, "color/grey applies")
	_ok(_as_model(a), "color/grey reproduces the model's own plastic")
	_ok(_near(grey.color, _source(a, "Front_Shell").albedo_color), "color/grey is the model's colour",
		str(_source(a, "Front_Shell").albedo_color))
	_ok(_mat(a, "Front_Shell").normal_texture == _source(a, "Front_Shell").normal_texture
		and _source(a, "Front_Shell").normal_texture != null, "color/the grain normal map is carried")
	CartridgeColor.apply_preset(a, &"black", SnesCartShell.SYSTEMID)
	_ok(_painted(a, _preset(&"black").color), "color/black paints the whole moulding, bezel included")
	CartridgeColor.apply_color(a, Color(0.2, 0.4, 0.9))
	_ok(_painted(a, Color(0.2, 0.4, 0.9)), "color/a colour paints it, each part keeping its roughness")
	_ok(_mat(b, "Front_Shell") == _source(b, "Front_Shell"), "color/another instance is untouched")
	_ok(CartridgeColor.apply_preset(a, &"ruby", SnesCartShell.SYSTEMID) == ERR_DOES_NOT_EXIST,
		"color/a Game Boy Advance preset is not a Super NES one")
	_ok(CartridgeColor.reset_to_default(a) == OK
		and _part(a, "Front_Shell").get_surface_override_material(0) == null, "color/reset restores the model")
	a.free()
	b.free()


func _test_kept() -> void:
	for path: String in BODIES:
		var cart := _body(path)
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
		_ok(changed.is_empty(), "kept/%s: label, sticker, board and screws keep their materials" % path.get_file(),
			str(changed))
		# ModelMaterialFix.demetal must not flatten them: the screws and contacts are metal.
		_ok(_source(cart, "Security_Screw_L").metallic > 0.5 and _source(cart, "Connector_Contacts").metallic > 0.5,
			"kept/%s: the screws and contacts are authored metal" % path.get_file())
		cart.free()
	# Type A's screws are nickel, Type B's brass, as photographed.
	var ta := _body(SnesCartShell.BODY_TYPE_A)
	var tb := _body(SnesCartShell.BODY_TYPE_B)
	var nickel := _source(ta, "Security_Screw_L").albedo_color
	var brass := _source(tb, "Security_Screw_L").albedo_color
	_ok(absf(nickel.r - nickel.b) < 0.05 and brass.r - brass.b > 0.2, "kept/Type A's screws are nickel, Type B's brass",
		"%s / %s" % [nickel, brass])
	ta.free()
	tb.free()


func _test_lookup() -> void:
	var cases := [
		["Killer Instinct, a HiROM", _rom("KILLER INSTINCT"), &"black"],
		["Killer Instinct behind a copier header", _rom("KILLER INSTINCT", 0xFFC0, 0x10000, 0x200), &"black"],
		["a LoROM game", _rom("SUPER MARIOWORLD", 0x7FC0, 0x8000), &"grey"],
		["a HiROM game", _rom("DONKEY KONG COUNTRY"), &"grey"],
		["a header whose checksum does not pair", _rom("KILLER INSTINCT", 0xFFC0, 0x10000, 0, false), &"grey"],
		["a short file", PackedByteArray([1, 2, 3]), &"grey"],
	]
	for c: Array in cases:
		var got := SnesCartShell.preset_for_title(SnesCartShell.title_of(_header_of(c[1])))
		_ok(got == c[2], "lookup/%s is %s" % [c[0], c[2]], "got %s" % got)
	_ok(SnesCartShell.title_of(_header_of(_rom("SUPER MARIOWORLD", 0x7FC0, 0x8000))) == "SUPER MARIOWORLD",
		"lookup/the title is read, trailing spaces trimmed")
	var markets := [
		["North America", 0x01, "us"], ["Canada", 0x0F, "us"], ["Japan", 0x00, "jp"],
		["Europe", 0x02, "eu"], ["Germany", 0x09, "eu"], ["Australia", 0x11, "au"], ["Korea", 0x0D, ""],
	]
	for m: Array in markets:
		var got := SnesCartShell.header_market(_header_of(_rom("GAME", 0xFFC0, 0x10000, 0, true, m[1])))
		_ok(got == m[2], "lookup/destination %s is market \"%s\"" % [m[0], m[2]], "got \"%s\"" % got)
	_ok(SnesCartShell.header_market(PackedByteArray()) == "", "lookup/no header, no market")
	# The coloured shells, by title and market: only the North American Doom and
	# Maximum Carnage were red; Killer Instinct was black wherever it was sold.
	var shells := [
		["DOOM", "us", &"red"], ["DOOM", "eu", &"grey"], ["DOOM", "jp", &"grey"], ["DOOM", "", &"grey"],
		["MAXIMUM CARNAGE", "us", &"red"], ["MAXIMUM CARNAGE", "eu", &"grey"],
		["KILLER INSTINCT", "us", &"black"], ["KILLER INSTINCT", "eu", &"black"],
		["DOOM TROOPERS", "us", &"grey"], ["SUPER MARIOWORLD", "us", &"grey"],
	]
	for c: Array in shells:
		var got := SnesCartShell.preset_for_title(c[0], c[1])
		_ok(got == c[2], "lookup/%s in market \"%s\" is %s" % [c[0], c[1], c[2]], "got %s" % got)
	# The file name's region tag: No-Intro's, then GoodTools'.
	var tags := [
		["Doom (USA).sfc", "us"], ["Doom (Japan) (En).sfc", "jp"], ["Flashback (Europe) (En,Fr).sfc", "eu"],
		["Tetris Attack (Germany).sfc", "eu"], ["Street Racer (Australia).sfc", "au"],
		["X Zone (Japan, USA).sfc", "us"], ["Doom (U) [!].smc", "us"], ["Super Mario World (JU).smc", "us"],
		["Doom (E).smc", "eu"], ["Game (Rev 1) (USA).sfc", "us"], ["Game (PAL).sfc", ""],
		["Game (Beta).sfc", ""], ["no tags.sfc", ""],
	]
	for t: Array in tags:
		var got := SnesCartShell.filename_market("Z:/roms/snes/" + t[0])
		_ok(got == t[1], "lookup/file name %s is market \"%s\"" % [t[0], t[1]], "got \"%s\"" % got)
	# The tag outranks a wrong destination byte (Pinocchio (USA) says Japan).
	var pinocchio := _write_rom("Pinocchio (USA).sfc", _rom("PINOCCHIO", 0x7FC0, 0x8000, 0, true, 0x00))
	_ok(SnesCartShell.market(SnesCartShell.SYSTEMID, pinocchio) == "us"
		and SnesCartShell.body_model_for_rom("", SnesCartShell.SYSTEMID, pinocchio) == SnesCartShell.BODY_TYPE_A,
		"lookup/a USA-tagged file with a Japanese header byte is a US cartridge")
	var untagged := _write_rom("untagged.sfc", _rom("PINOCCHIO", 0x7FC0, 0x8000, 0, true, 0x00))
	_ok(SnesCartShell.market(SnesCartShell.SYSTEMID, untagged) == "jp", "lookup/with no tag the header byte decides")
	var copier := _write_rom("copier.smc", _rom("KILLER INSTINCT", 0xFFC0, 0x10000, 0x200))
	_ok(SnesCartShell.preset_for_rom(copier) == &"black", "lookup/a file's copier header is skipped by its size")
	_ok(SnesCartShell.preset_for_rom("") == &"grey" and SnesCartShell.preset_for_rom("user://missing.sfc") == &"grey",
		"lookup/no file is grey")
	var every := PackedStringArray()
	var answers: Array[StringName] = [SnesCartShell.DEFAULT_PRESET]
	for entry: Array in SnesCartShell.TITLE_SHELLS.values():
		answers.append(entry[0])
	for id: StringName in answers:
		if _preset(id) == null:
			every.append(id)
	_ok(every.is_empty(), "lookup/every answer is a palette preset", str(every))
	var A := SnesCartShell.BODY_TYPE_A
	var B := SnesCartShell.BODY_TYPE_B
	var bodies := [
		["a US game from 1991 (Super Mario World)", "", "us", "19910823", A],
		["a US game from late 1993", "", "us", "19931231", A],
		["a US game from 1994 (Bubsy II)", "", "us", "19941101", B],
		["a US game with no known date", "", "us", "", A],
		["a Japanese game", "", "jp", "19910823", SnesCartShell.BODY_SFC],
		["a PAL game", "", "eu", "19950101", SnesCartShell.BODY_SFC],
		["a game of no known market", "", "", "", ""],
		["Type B forced on an early US game", SnesCartShell.TYPE_B, "us", "19910823", B],
		["Type A forced on a late US game", SnesCartShell.TYPE_A, "us", "19950101", A],
		["Type B forced on a Japanese game", SnesCartShell.TYPE_B, "jp", "", B],
		["an N64 region forced", N64CartShell.REGION_JPN, "us", "19950101", B],
	]
	for c: Array in bodies:
		var got := SnesCartShell.body_model(c[1], c[2], c[3])
		_ok(got == c[4], "lookup/%s spawns %s" % [c[0], c[4].get_file() if c[4] != "" else "no model"],
			"got %s" % got)
	var dates := [["1994-11-01", "19941101"], ["19941101T000000", "19941101"], ["1994", ""], ["", ""]]
	for d: Array in dates:
		_ok(SnesCartShell.date_digits(d[0]) == d[1], "lookup/scraped date \"%s\" reads \"%s\"" % [d[0], d[1]])


func _test_cartridge() -> void:
	var img := Image.create(420, 186, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	_make_label_dir()
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))

	var ki := await _spawn(_write_rom(FIXTURE + ".sfc", _rom("KILLER INSTINCT")))
	var plain := await _spawn(_write_rom("plain.sfc", _rom("SUPER MARIOWORLD", 0x7FC0, 0x8000)))
	var jp := await _spawn(_write_rom("jp.sfc", _rom("SUPER MARIOWORLD", 0x7FC0, 0x8000, 0, true, 0x00)))
	var doom_us := await _spawn(_write_rom("Doom (USA).sfc", _rom("DOOM", 0x7FC0, 0x80000, 0, true, 0x01)))
	var doom_jp := await _spawn(_write_rom("Doom (Japan) (En).sfc", _rom("DOOM", 0x7FC0, 0x80000, 0, true, 0x00)))
	_ok(doom_us.get_node_or_null("CartModel") != null and _painted(doom_us.get_node("CartModel"), _preset(&"red").color),
		"cartridge/Doom (USA) spawns red")
	var doom_jp_model := doom_jp.get_node_or_null("CartModel") as Node3D
	_ok(doom_jp_model != null and doom_jp_model.scene_file_path == SnesCartShell.BODY_SFC
		and not _near(_mat(doom_jp_model, "Front_Shell").albedo_color, _preset(&"red").color),
		"cartridge/Doom (Japan) spawns the grey Super Famicom shell, not red")
	_ok(jp.get_node_or_null("CartModel") != null
		and jp.get_node("CartModel").scene_file_path == SnesCartShell.BODY_SFC,
		"cartridge/a Japanese ROM spawns the Super Famicom shell, not the US one")
	var ki_model := ki.get_node_or_null("CartModel") as Node3D
	_ok(ki_model != null and ki_model.scene_file_path == SnesCartShell.BODY_TYPE_A,
		"cartridge/a Super NES ROM spawns the Type A model")
	_ok(ki_model != null and _painted(ki_model, _preset(&"black").color), "cartridge/Killer Instinct spawns black")
	var label := CartridgeLabel.find_label(ki_model) if ki_model != null else null
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 420,
		"cartridge/the scraped label is painted on the sticker")
	_ok(ki.get_node_or_null("ModelLabelArt") == null and not (ki.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	_ok(ki_model != null and _mat(ki_model, "Connector_Contacts").metallic > 0.5
		and _mat(ki_model, "Security_Screw_L").metallic > 0.5, "cartridge/contacts and screws keep their metal")
	var plain_model := plain.get_node_or_null("CartModel") as Node3D
	_ok(plain_model != null and _as_model(plain_model), "cartridge/any other game spawns the model's grey")
	var plain_label := CartridgeLabel.find_label(plain_model) if plain_model != null else null
	_ok(plain_label != null and plain_label.get_surface_override_material(0) == null
		and (plain.get_node("GameLabel") as Label3D).visible, "cartridge/no art: the blank sticker and the title")
	_ok(plain_model != null and plain_model.scale.distance_to(Vector3.ONE) < 0.003,
		"cartridge/the model is not stretched", str(plain_model.scale if plain_model else null))
	_ok(plain_model != null and _bounds(plain_model, plain).get_center().length() < 0.0005,
		"cartridge/the model is centred on the cartridge")
	# The scraped sticker is painted onto the model's own Label, and only it.
	var tex := ImageTexture.create_from_image(Image.create(8, 4, false, Image.FORMAT_RGB8))
	_ok(plain_model != null and CartridgeLabel.apply_texture(plain_model, tex) == OK
		and _mat(plain_model, "Label").albedo_texture == tex
		and _mat(plain_model, "Label_Fold").albedo_texture != tex,
		"cartridge/the label art paints the front label, not the fold")
	_ok(SpawnMenuSpawnView._has_spawn_options(SnesCartShell.SYSTEMID),
		"cartridge/a held Super NES ROM row opens the spawn options")
	for cart in [ki, plain, jp, doom_us, doom_jp]:
		cart.queue_free()
	await get_tree().process_frame


## What the spawn menu's hold sub-menu forces. Killer Instinct is the fixture
## because its own answer is black, so a forced shell cannot pass by being the
## default.
func _test_forced() -> void:
	var rom := _write_rom("forced.sfc", _rom("KILLER INSTINCT"))
	var type_b := await _spawn(rom, &"", "", false, SnesCartShell.TYPE_B)
	var type_a := await _spawn(rom, &"", "", false, SnesCartShell.TYPE_A)
	var grey := await _spawn(rom, &"grey")
	var gba_only := await _spawn(rom, &"ruby")
	var jp_rom := _write_rom("forced_jp.sfc", _rom("SUPER MARIOWORLD", 0x7FC0, 0x8000, 0, true, 0x00))
	var jp_b := await _spawn(jp_rom, &"", "", false, SnesCartShell.TYPE_B)
	_ok(jp_b.get_node_or_null("CartModel") != null
		and jp_b.get_node("CartModel").scene_file_path == SnesCartShell.BODY_TYPE_B,
		"forced/a body forced on a Japanese ROM is spawned")
	_ok(type_b.get_node("CartModel").scene_file_path == SnesCartShell.BODY_TYPE_B,
		"forced/Type B picks the broad-recess body")
	_ok(_painted(type_b.get_node("CartModel"), _preset(&"black").color),
		"forced/a forced body keeps the ROM's own shell")
	_ok(type_a.get_node("CartModel").scene_file_path == SnesCartShell.BODY_TYPE_A, "forced/Type A is the groove body")
	_ok(_as_model(grey.get_node("CartModel")), "forced/a forced shell beats the ROM's own")
	_ok(_painted(gba_only.get_node("CartModel"), _preset(&"black").color),
		"forced/an id the Super NES palette lacks keeps the ROM's own")
	var mix := Color("#d0417e")
	var mixed := await _spawn(rom, &"grey", "#d0417e")
	_ok(_painted(mixed.get_node("CartModel"), mix), "forced/a mixed colour beats a forced shell")
	var sparkle := await _spawn(rom, &"", "#d0417e", true)
	var sm := _part(sparkle.get_node("CartModel"), "Front_Shell").get_active_material(0) as ShaderMaterial
	var n64_gold := CartridgeColor.get_palette().find(&"gold")
	_ok(sm != null and sm.shader == CartridgeColor.FLAKE_SHADER and sm.get_shader_parameter("albedo") == mix
		and is_equal_approx(sm.get_shader_parameter("flake_density"), n64_gold.flake_density),
		"forced/a mixed flake shell borrows the N64 gold's flakes, having none of its own")
	for cart in [type_b, type_a, grey, gba_only, jp_b, mixed, sparkle]:
		cart.queue_free()
	await get_tree().process_frame


func _spawn(rom: String, shell: StringName = &"", color := "", flake := false, body := "") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = SnesCartShell.SYSTEMID
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.shell_color = color
	cart.shell_flake = flake
	cart.body_region = body
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
