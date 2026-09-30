## NES cartridge self-tests — the model, its shells, and the spawned cartridge that wears them.
##
##     "$godot" --headless --path RetroXR res://Tests/nes_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/nes_cart_tests.tscn -- --only=shell
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one label fixture into the player's real nes media/label folder
## (MediaDimensions derives the path from the ROM's name) and removes it at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const SYSTEMID := "nes"
const FIXTURE := "__nescart_selftest"
const UV_MIN_WIDTH := 0.00005

## Every part of the molding, the sticker, the connector and the fasteners.
const PARTS := ["Front_Shell", "Rear_Shell", "Label", "Label_Fold", "Caution_Label", "Connector_PCB",
	"Connector_Contacts", "Security_Screw_C", "Security_Screw_L", "Security_Screw_R"]
## The shell's paintable materials, and the mouth's black, which is never painted.
const SHELL_MATERIALS := ["NES_Shell_Plastic", "NES_Shell_Smooth", "NES_Plaque_Baked"]
const INTERIOR := "NES_Shell_Interior"

## The measured sticker: 55 mm wide, 90 mm down the front, 7 mm over the top.
const LABEL_W := 0.055
const LABEL_FRONT := 0.090
const LABEL_FOLD := 0.007
## The mouth: 20 mm deep; the first 3 mm of its walls are the shell's plastic.
const MOUTH_DEPTH := 0.020
const MOUTH_LIP := 0.003

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[nescart] TIMEOUT")
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
	if _wants("shell"):
		_test_shell()
	if _wants("paint"):
		_test_paint()
	if _wants("cartridge"):
		await _test_cartridge()

	_clear_fixture()
	await _settle_warm()
	print("[nescart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[nescart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[nescart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


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


## Every surface of `root` whose material is named `material_name`: [mesh, surface].
func _surfaces(root: Node, material_name: String) -> Array:
	var out := []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null and m.resource_name == material_name:
				out.append([mi, s])
	return out


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(SYSTEMID).path_join("media").path_join("label")


func _clear_fixture() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	_ok(ResourceLoader.exists(_path()), "resources/%s exists" % _path().get_file())
	_ok(FileAccess.file_exists(_path().get_base_dir().path_join("LICENSE-nes-cart.txt")),
		"resources/LICENSE-nes-cart.txt beside it")
	var palette := CartridgeColor.get_palette(SYSTEMID)
	_ok(palette != null and ResourceLoader.exists(CartridgeColor.PALETTE_PATHS[SYSTEMID]),
		"resources/the NES has a palette of its own")
	if palette == null:
		return
	_ok(Array(palette.ids()) == ["grey", "gold"], "resources/palette carries grey and gold", str(palette.ids()))
	var grey := palette.find(&"grey")
	var gold := palette.find(&"gold")
	_ok(grey.availability == CartridgeShellPreset.Availability.STANDARD
		and grey.finish == CartridgeShellPreset.Finish.PLASTIC, "resources/grey is the standard plastic")
	_ok(gold.finish == CartridgeShellPreset.Finish.METALLIZED and is_equal_approx(gold.opacity, 1.0)
		and gold.color.r > gold.color.g and gold.color.g > gold.color.b,
		"resources/gold is a solid metallized gold")
	# Grey is the model's own plastic, and the GBA's Classic NES Series grey matches it.
	var body := _body()
	var plastic: Array = _surfaces(body, "NES_Shell_Plastic")
	var own: Color = (plastic[0][0].mesh.surface_get_material(plastic[0][1]) as BaseMaterial3D).albedo_color \
		if not plastic.is_empty() else Color.BLACK
	body.free()
	_ok(own.is_equal_approx(grey.color) or own.to_html(false) == grey.color.to_html(false),
		"resources/grey is the model's own plastic", "%s vs %s" % [grey.color, own])


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
	_ok(size.is_equal_approx(Vector3(0.120, 0.134, 0.017)), "model/MediaDimensions holds the measured 120 x 134 x 17 mm",
		str(size))
	var center := ab.get_center()
	var label := _box(_part(body, "Label"))
	var board := _box(_part(body, "Connector_PCB"))
	_ok(board.get_center().y < center.y and label.get_center().z > center.z, "model/connector on -Y, label on +Z")
	_ok(absf(ab.position.y) < 0.0002 and board.position.y > 0.006 and board.end.y < MOUTH_DEPTH + 0.001,
		"model/the mouth is y = 0 and the board sits inside it", str(board))
	for part in ["Security_Screw_C", "Security_Screw_L", "Security_Screw_R", "Caution_Label"]:
		if _box(_part(body, part)).get_center().z >= center.z:
			missing.append(part)
	_ok(missing.is_empty(), "model/the screws and the caution sticker are on the back", str(missing))
	# The mouth: black and unlit from 3 mm in to its 20 mm floor, in both halves.
	var inside: Array = _surfaces(body, INTERIOR)
	var lo := INF
	var hi := -INF
	var black := not inside.is_empty()
	for entry: Array in inside:
		var mi: MeshInstance3D = entry[0]
		var m := mi.mesh.surface_get_material(entry[1]) as BaseMaterial3D
		black = black and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			and m.albedo_color.srgb_to_linear().get_luminance() < 0.02
		for v in (mi.mesh.surface_get_arrays(entry[1])[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var p := mi.transform * v
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	_ok(inside.size() == 2 and black, "model/the mouth is unlit black in both halves", str(inside.size()))
	_ok(absf(hi - MOUTH_DEPTH) < 0.0002 and absf(lo - MOUTH_LIP) < 0.0002,
		"model/the black runs from 3 mm in to the 20 mm floor", "%.4f..%.4f" % [lo, hi])
	body.free()


## Debranded, as RetroXR's NES cart has always shipped: no Nintendo mesh or
## material, the plaque map without the wordmark, the sticker without its line.
func _test_branding() -> void:
	var body := _body()
	var marks := PackedStringArray()
	var maps := {}
	var sticker := ""
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for word in ["nintendo", "logo", "wordmark", "marks"]:
			if String(mi.name).containsn(word):
				marks.append(mi.name)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			for word in ["nintendo", "logo", "wordmark", "marks"]:
				if m.resource_name.containsn(word):
					marks.append(m.resource_name)
			var prefix := _path().get_file().get_basename() + "_"
			if m.normal_texture != null:
				maps[m.normal_texture.resource_path.get_file().trim_prefix(prefix)] = true
			if m.resource_name == "NES_Caution_Label" and m.albedo_texture != null:
				sticker = m.albedo_texture.resource_path.get_file().trim_prefix(prefix)
	_ok(marks.is_empty(), "branding/no logo mesh or material", str(marks))
	var keys := maps.keys()
	keys.sort()
	_ok(keys == ["plaque_normal_clean_1024.png", "plastic_normal.png"],
		"branding/normal maps are the stipple and the plaque without its wordmark", str(keys))
	_ok(sticker == "caution_label_clean.png", "branding/the caution sticker is the one without its Nintendo line", sticker)
	body.free()


## Every triangle of a normal-mapped surface has area in UV space; see
## n64_cart_tests' uv group. The export runs Tools/glb/fix_unmapped_uvs.py.
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
## from the front (+Z, so -X is left and +Y is up). ScreenScraper's NES labels are
## front scans (365 x 600), so the art covers the 90 mm front and the 7 mm fold
## over the top is its own plain mesh.
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
		"label/is the measured 55 x 90 mm front of the sticker", str(ab.size))
	_ok(label.mesh.get_surface_count() == 1, "label/is one surface, as CartridgeLabel needs")
	var fold := _box(_part(body, "Label_Fold"))
	var top := _bounds(body).end.y
	_ok(fold.position.y >= ab.end.y - 0.0002 and absf(fold.end.y - top) < 0.0006
		and fold.size.z > LABEL_FOLD - 0.0035,
		"label/the fold goes over the top, above the front", "%s" % fold)
	_ok(CartridgeLabel.find_label(body) == label, "label/CartridgeLabel paints the front, not the fold")
	body.free()


## Which shell a ROM gets: gold for a Zelda outside Japan, grey for everything else.
func _test_shell() -> void:
	var cases := [
		["Legend of Zelda, The (USA)", "", &"gold"],
		["Legend of Zelda, The (USA) (Rev A)", "us", &"gold"],
		["The Legend of Zelda", "", &"gold"],
		["Zelda II - The Adventure of Link (Europe)", "eu", &"gold"],
		["Zelda no Densetsu 1 - The Hyrule Fantasy (Japan)", "jp", &"grey"],
		["Super Mario Bros. (World)", "", &"grey"],
		["Zeldas (Hack)", "", &"grey"],
		["", "", &"grey"],
	]
	var wrong := []
	for c: Array in cases:
		if NesCartShell.preset_for_name(c[0], c[1]) != c[2]:
			wrong.append(c)
	_ok(wrong.is_empty(), "shell/Zelda is gold, a Japanese release and every other game grey", str(wrong))
	_ok(NesCartShell.normalized("Legend of Zelda, The (USA) [!].nes") == "legend of zelda the nes",
		"shell/names are compared lower case without tags or punctuation",
		NesCartShell.normalized("Legend of Zelda, The (USA) [!].nes"))
	_ok(NesCartShell.preset_for_rom("/roms/nes/Zelda II - The Adventure of Link (USA).nes") == &"gold"
		and NesCartShell.preset_for_rom("/roms/nes/Zelda no Densetsu 1 - The Hyrule Fantasy (Japan).nes") == &"grey"
		and NesCartShell.preset_for_rom("/roms/nes/Metroid (USA).nes") == &"grey",
		"shell/a ROM with no scraped name goes by its file name and region tag")


## The gold coat and back: every shell surface metallic, each molding's own
## roughness scaled and its maps kept; the label, sticker, board and mouth untouched.
func _test_paint() -> void:
	var body := _body()
	var gold := CartridgeColor.get_palette(SYSTEMID).find(&"gold")
	_ok(CartridgeColor.apply_preset(body, &"gold", SYSTEMID) == OK, "paint/gold applies")
	var surfaces := CartridgeColor.shell_surfaces(body)
	var halves := {}
	var bad := []
	for s: Dictionary in surfaces:
		var mi: MeshInstance3D = s["mesh"]
		var source := mi.mesh.surface_get_material(s["surface"]) as BaseMaterial3D
		var m := mi.get_active_material(s["surface"]) as BaseMaterial3D
		halves[s["half"]] = true
		if not SHELL_MATERIALS.has(String(source.resource_name)) or m == source or m.metallic < 0.999 \
				or m.metallic_texture != null or not m.albedo_color.is_equal_approx(gold.color) \
				or not is_equal_approx(m.roughness, source.roughness * gold.roughness) \
				or m.normal_texture != source.normal_texture or m.roughness_texture != source.roughness_texture:
			bad.append("%s/%s" % [mi.name, source.resource_name])
	_ok(not surfaces.is_empty() and bad.is_empty() and halves.size() == 2,
		"paint/gold coats every shell surface of both halves, keeping each molding's maps", str(bad))
	var untouched := []
	for part in ["Label", "Label_Fold", "Caution_Label", "Connector_PCB", "Connector_Contacts", "Security_Screw_C"]:
		var mi := _part(body, part)
		for s in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(s) != null:
				untouched.append(part)
	for entry: Array in _surfaces(body, INTERIOR):
		if (entry[0] as MeshInstance3D).get_surface_override_material(entry[1]) != null:
			untouched.append(INTERIOR)
	_ok(untouched.is_empty(), "paint/the label, sticker, board, screws and the mouth's black keep their own", str(untouched))
	CartridgeColor.apply_preset(body, &"grey", SYSTEMID)
	var metal := []
	for s: Dictionary in CartridgeColor.shell_surfaces(body):
		var mi: MeshInstance3D = s["mesh"]
		var source := mi.mesh.surface_get_material(s["surface"]) as BaseMaterial3D
		var m := mi.get_active_material(s["surface"]) as BaseMaterial3D
		if m.metallic != source.metallic or m.metallic_texture != source.metallic_texture \
				or not is_equal_approx(m.roughness, source.roughness):
			metal.append(String(source.resource_name))
	_ok(metal.is_empty(), "paint/grey after gold puts the plastic's metalness and roughness back", str(metal))
	body.free()


func _test_cartridge() -> void:
	var img := Image.create(365, 600, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	DirAccess.make_dir_recursive_absolute(_label_dir())
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))
	var with_art := await _spawn("/roms/%s/%s.nes" % [SYSTEMID, FIXTURE])
	var zelda := await _spawn("/roms/%s/Legend of Zelda, The (USA).nes" % SYSTEMID)
	var forced_gold := await _spawn("/roms/%s/plain.nes" % SYSTEMID, &"gold")
	var forced_grey := await _spawn("/roms/%s/Zelda II - The Adventure of Link (USA).nes" % SYSTEMID, &"grey")
	var mixed := await _spawn("/roms/%s/plain.nes" % SYSTEMID, &"", "#2255aa")
	var model := with_art.get_node_or_null("CartModel")
	_ok(model != null and model.scene_file_path == _path(), "cartridge/an NES ROM spawns the model")
	var label := CartridgeLabel.find_label(model) if model != null else null
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 365,
		"cartridge/the scraped label is painted on the sticker")
	var fold := _part(model, "Label_Fold") if model != null else null
	_ok(fold != null and fold.get_surface_override_material(0) == null, "cartridge/the fold keeps its plain paper")
	_ok(with_art.get_node_or_null("ModelLabelArt") == null
		and not (with_art.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	var contacts := _part(model, "Connector_Contacts").get_active_material(0) as BaseMaterial3D if model != null else null
	var screw := _part(model, "Security_Screw_L").get_active_material(0) as BaseMaterial3D if model != null else null
	_ok(contacts != null and contacts.metallic > 0.5 and screw != null and screw.metallic > 0.5,
		"cartridge/contacts and screws keep their metal")
	var scale := (model as Node3D).scale if model != null else Vector3.ZERO
	_ok(absf(scale.x - 1.0) < 0.005 and absf(scale.y - 1.0) < 0.005 and absf(scale.z - 1.0) < 0.005,
		"cartridge/the body is not stretched to MediaDimensions' size", str(scale))
	_ok(_shell_metallic(with_art) == 0.0 and _shell_metallic(zelda) == 1.0,
		"cartridge/a Zelda ROM spawns gold, any other grey")
	_ok(_shell_metallic(forced_gold) == 1.0 and _shell_metallic(forced_grey) == 0.0,
		"cartridge/a shell forced at spawn wins over the ROM's own")
	var shell := _front_plastic(mixed)
	_ok(shell != null and shell.albedo_color.to_html(false) == "2255aa" and shell.metallic == 0.0,
		"cartridge/a color mixed at spawn paints the shell")
	for cart in [with_art, zelda, forced_gold, forced_grey, mixed]:
		cart.queue_free()
	await get_tree().process_frame


func _front_plastic(cart: RetroCartridge) -> BaseMaterial3D:
	var front := _part(cart.get_node_or_null("CartModel"), "Front_Shell") if cart.has_node("CartModel") else null
	if front == null:
		return null
	for s in front.mesh.get_surface_count():
		if front.mesh.surface_get_material(s).resource_name == "NES_Shell_Plastic":
			return front.get_active_material(s) as BaseMaterial3D
	return null


## The front shell's stippled plastic's metalness, or -1 without a model.
func _shell_metallic(cart: RetroCartridge) -> float:
	var m := _front_plastic(cart)
	return m.metallic if m != null else -1.0


func _spawn(rom: String, shell_preset := &"", shell_color := "") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = SYSTEMID
	cart.rom_path = rom
	cart.game_label = "Selftest"
	cart.shell_preset = shell_preset
	cart.shell_color = shell_color
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
