## Game Boy cartridge self-tests — the model, its shell colours, the header
## lookup that picks one per ROM, and the spawned cartridge that uses them.
##
##     "$godot" --headless --path RetroXR res://Tests/gb_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/gb_cart_tests.tscn -- --only=lookup
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one label fixture into the player's real gb media/label folder
## (MediaDimensions derives the path from the ROM's name) and ROM fixtures under
## user://, and removes both at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__gbcart_selftest"
const UV_MIN_WIDTH := 0.00005

## Every exterior part of the moulding.
const SHELL_PARTS := ["Front_Shell", "Rear_Shell", "Smooth_Plastic", "Label_Rim"]
## Parts a shell colour must never reach.
const KEPT_PARTS := ["Label", "Connector_PCB", "Contacts", "Security_Screw", "Cavity_Black"]

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[gbcart] TIMEOUT")
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
	if _wants("flake"):
		_test_flake()
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
	print("[gbcart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[gbcart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[gbcart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _body() -> Node3D:
	var node := (load(GbCartShell.BODY) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


func _albedo(root: Node, part: String) -> Color:
	var m := _part(root, part).get_active_material(0)
	if m is ShaderMaterial:
		return (m as ShaderMaterial).get_shader_parameter("albedo")
	return (m as BaseMaterial3D).albedo_color


func _roughness(root: Node, part: String) -> float:
	var m := _part(root, part).get_active_material(0)
	if m is ShaderMaterial:
		return (m as ShaderMaterial).get_shader_parameter("roughness")
	return (m as BaseMaterial3D).roughness


func _source(root: Node, part: String) -> BaseMaterial3D:
	return _part(root, part).mesh.surface_get_material(0) as BaseMaterial3D


func _preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(GbCartShell.SYSTEMID).find(id)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.003 and absf(a.g - b.g) < 0.003 and absf(a.b - b.b) < 0.003


## A 0x150-byte cartridge header: title, CGB flag, destination and licensee.
func _header(title: String, cgb := 0x00, japan := false, licensee := "nintendo") -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(GbCartShell.HEADER_BYTES)
	for i in mini(title.length(), 16):
		h[GbCartShell.TITLE_AT + i] = title.unicode_at(i)
	if cgb != 0:
		h[GbCartShell.CGB_AT] = cgb
	h[GbCartShell.DESTINATION_AT] = GbCartShell.DESTINATION_JAPAN if japan else 0x01
	match licensee:
		"nintendo":
			h[GbCartShell.OLD_LICENSEE_AT] = 0x01
		"nintendo_new":
			h[GbCartShell.OLD_LICENSEE_AT] = 0x33
			h[GbCartShell.NEW_LICENSEE_AT] = 0x30
			h[GbCartShell.NEW_LICENSEE_AT + 1] = 0x31
		_:
			h[GbCartShell.OLD_LICENSEE_AT] = 0x33
			h[GbCartShell.NEW_LICENSEE_AT] = 0x30
			h[GbCartShell.NEW_LICENSEE_AT + 1] = 0x38
	return h


func _write_rom(file_name: String, header: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(header)
	f.close()
	return path


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(GbCartShell.SYSTEMID).path_join("media").path_join("label")


func _clear_fixtures() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	for path in [GbCartShell.BODY, CartridgeColor.PALETTE_PATHS[GbCartShell.SYSTEMID]]:
		_ok(ResourceLoader.exists(path), "resources/%s exists" % path.get_file())
	var palette := CartridgeColor.get_palette(GbCartShell.SYSTEMID)
	_ok(palette != null and palette != CartridgeColor.get_palette(), "resources/the Game Boy has a palette of its own")
	var wanted := ["grey", "black", "red", "blue", "yellow", "gold", "silver"]
	_ok(Array(palette.ids()) == wanted, "resources/palette carries exactly the presets", str(palette.ids()))
	_ok(palette.find(&"grey").availability == CartridgeShellPreset.Availability.STANDARD,
		"resources/grey is the standard shell")
	_ok(palette.find(&"gold").finish == CartridgeShellPreset.Finish.METAL_FLAKE
		and palette.find(&"silver").finish == CartridgeShellPreset.Finish.METAL_FLAKE,
		"resources/gold and silver are metal flake")
	_ok(CartridgeColor.get_palette("snes") == null, "resources/a system with no palette gets none")


func _test_model() -> void:
	var body := _body()
	var missing := PackedStringArray()
	for part: String in SHELL_PARTS + KEPT_PARTS:
		if _part(body, part) == null:
			missing.append(part)
	_ok(missing.is_empty(), "model/has every part", str(missing))
	var ab := AABB()
	var first := true
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.transform * mi.get_aabb()
		ab = box if first else ab.merge(box)
		first = false
	var size := MediaDimensions.cart_size(GbCartShell.SYSTEMID)
	_ok(absf(ab.size.x - size.x) < 0.0002 and absf(ab.size.y - size.y) < 0.0002
		and absf(ab.size.z - size.z) < 0.0002, "model/57 x 65 x 7.5 mm, MediaDimensions' size", str(ab.size))
	var pcb := _part(body, "Connector_PCB")
	var label := _part(body, "Label")
	_ok((pcb.transform * pcb.get_aabb()).get_center().y < 0.0
		and (label.transform * label.get_aabb()).get_center().z > 0.0,
		"model/connector on -Y, label on +Z")
	body.free()


## The shipped body carries no mark: no logo or text mesh or material, and no
## normal map but the plastic grain.
func _test_branding() -> void:
	var body := _body()
	var marks := PackedStringArray()
	var maps := {}
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for word in ["nintendo", "logo", "game_boy", "gameboy", "engraving", "lettering", "wordmark"]:
			if String(mi.name).containsn(word):
				marks.append(mi.name)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			for word in ["nintendo", "logo", "engraving", "lettering", "wordmark"]:
				if m.resource_name.containsn(word):
					marks.append(m.resource_name)
			if m.normal_texture != null:
				maps[m.normal_texture.resource_path.get_file()] = true
	_ok(marks.is_empty(), "branding/no logo mesh or material", str(marks))
	_ok(maps.keys() == ["gb_cart_plastic_grain_normal.png"], "branding/no normal map but the plastic grain",
		str(maps.keys()))
	body.free()


## Every triangle of a normal-mapped surface has area in UV space; see
## n64_cart_tests' uv group. The export left the rear shell unmapped and
## Tools/glb/fix_unmapped_uvs.py gave it UVs.
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
	var red := _preset(&"red")
	_ok(CartridgeColor.apply_preset(a, &"red", GbCartShell.SYSTEMID) == OK, "color/red applies")
	_ok(_albedo(a, "Front_Shell") == red.color and _albedo(a, "Rear_Shell") == red.color,
		"color/front and rear take the colour")
	_ok(_near(_albedo(a, "Smooth_Plastic"), red.color * 1.03)
		and _near(_albedo(a, "Label_Rim"), Color(red.color.r * 0.65, red.color.g * 0.65, red.color.b * 0.65)),
		"color/the rails and the recess rim keep their shade of it")
	var kept_rough := ["Front_Shell", "Rear_Shell", "Smooth_Plastic", "Label_Rim"].all(
		func(p: String) -> bool: return is_equal_approx(_roughness(a, p), _source(a, p).roughness))
	_ok(kept_rough, "color/each moulding keeps its own roughness")
	var grey := _body()
	CartridgeColor.apply_preset(grey, &"grey", GbCartShell.SYSTEMID)
	var faithful := SHELL_PARTS.all(func(p: String) -> bool:
		return _near(_albedo(grey, p), _source(grey, p).albedo_color))
	_ok(faithful, "color/grey reproduces the model's own plastic")
	grey.free()
	_ok(_albedo(b, "Front_Shell") == _source(b, "Front_Shell").albedo_color, "color/another instance is untouched")
	_ok(_source(a, "Front_Shell").albedo_color != red.color, "color/the imported material is untouched")
	_ok((_part(a, "Front_Shell").get_active_material(0) as BaseMaterial3D).normal_texture
		== _source(a, "Front_Shell").normal_texture and _source(a, "Front_Shell").normal_texture != null,
		"color/the grain normal map is carried")
	_ok(CartridgeColor.apply_preset(a, &"gold_silver", GbCartShell.SYSTEMID) == ERR_DOES_NOT_EXIST
		and _albedo(a, "Front_Shell") == red.color, "color/an N64 preset is not a Game Boy one")
	_ok(CartridgeColor.reset_to_default(a) == OK
		and _part(a, "Front_Shell").get_surface_override_material(0) == null, "color/reset restores the model")
	a.free()
	b.free()


func _test_flake() -> void:
	var cart := _body()
	var gold := _preset(&"gold")
	_ok(CartridgeColor.apply_preset(cart, &"gold", GbCartShell.SYSTEMID) == OK, "flake/gold applies")
	var on_shader := SHELL_PARTS.all(func(p: String) -> bool:
		return _part(cart, p).get_active_material(0) is ShaderMaterial)
	_ok(on_shader, "flake/every shell part is on the flake shader")
	var front := _part(cart, "Front_Shell").get_active_material(0) as ShaderMaterial
	_ok(front.get_shader_parameter("albedo") == gold.color
		and front.get_shader_parameter("flake_color") == gold.flake_color
		and front.get_shader_parameter("flake_density") == gold.flake_density,
		"flake/preset values reach the shader")
	_ok(front.get_shader_parameter("texture_normal") == _source(cart, "Front_Shell").normal_texture
		and front.get_shader_parameter("normal_enabled") == true, "flake/plastic grain normal map carried")
	var rim := _part(cart, "Label_Rim").get_active_material(0) as ShaderMaterial
	_ok(_near(rim.get_shader_parameter("albedo"), Color(gold.color.r * 0.65, gold.color.g * 0.65, gold.color.b * 0.65)),
		"flake/the recess rim keeps its shade")
	CartridgeColor.apply_preset(cart, &"silver", GbCartShell.SYSTEMID)
	_ok(_albedo(cart, "Rear_Shell") == _preset(&"silver").color, "flake/silver replaces it")
	cart.free()


func _test_kept() -> void:
	var cart := _body()
	var before := {}
	for part: String in KEPT_PARTS:
		before[part] = _part(cart, part).get_active_material(0)
	for id in [&"red", &"gold", &"black", &"silver"]:
		CartridgeColor.apply_preset(cart, id, GbCartShell.SYSTEMID)
	CartridgeColor.apply_color(cart, Color.GREEN)
	CartridgeColor.reset_to_default(cart)
	CartridgeColor.apply_preset(cart, &"blue", GbCartShell.SYSTEMID)
	var changed := PackedStringArray()
	for part: String in KEPT_PARTS:
		if _part(cart, part).get_active_material(0) != before[part]:
			changed.append(part)
	_ok(changed.is_empty(), "kept/label, board, contacts, screw and mouth keep their materials", str(changed))
	var contacts := before["Contacts"] as BaseMaterial3D
	var screw := before["Security_Screw"] as BaseMaterial3D
	_ok(contacts.metallic > 0.5 and screw.metallic > 0.5, "kept/contacts and screw are metal")
	cart.free()


func _test_lookup() -> void:
	var cases := [
		["Pokemon Red, overseas", _header("POKEMON RED"), &"red"],
		["Pokemon Blue, overseas", _header("POKEMON BLUE"), &"blue"],
		["Pocket Monsters Red, Japan", _header("POKEMON RED", 0, true), &"grey"],
		["Pocket Monsters Blue, Japan", _header("POKEMON BLUE", 0, true), &"grey"],
		["Pocket Monsters Green", _header("POKEMON GREEN", 0, true), &"grey"],
		["Pokemon Gold, USA", _header("POKEMON_GLDAAUE", 0x80), &"gold"],
		["Pokemon Silver, USA", _header("POKEMON_SLVAAXE", 0x80), &"silver"],
		["Pocket Monsters Gold, Japan", _header("POKEMON_GLDAAUJ", 0x80, true), &"gold"],
		["Pocket Monsters Silver, Korea", _header("POKEMON_SLVAAXK", 0xC0), &"silver"],
		["Pokemon Gold, new licensee code", _header("POKEMON_GLDAAUD", 0x80, false, "nintendo_new"), &"gold"],
		["a dual-mode game", _header("ZELDA DXAZ7E", 0x80, false, "nintendo_new"), &"black"],
		["a third-party dual-mode game", _header("SOMEGAME", 0x80, false, "other"), &"black"],
		["Pokemon Yellow, dual-mode", _header("POKEMON YELLOW", 0x80), &"yellow"],
		["Pokemon Yellow, Spain", _header("POKEMON YELAPSS", 0x80), &"yellow"],
		["Pocket Monsters Pikachu, Japan", _header("POKEMON YELLOW", 0, true), &"grey"],
		["a GBC-only game", _header("PM_CRYSTAL", 0xC0), &"grey"],
		["a Game Boy game", _header("TETRIS"), &"grey"],
		["a Pokemon title from another publisher", _header("POKEMON RED", 0, false, "other"), &"grey"],
		["a short file", PackedByteArray([1, 2, 3]), &"grey"],
	]
	for c: Array in cases:
		var got := GbCartShell.preset_for_header(c[1])
		_ok(got == c[2], "lookup/%s is %s" % [c[0], c[2]], "got %s" % got)
	_ok(GbCartShell.header_title(_header("POKEMON_GLDAAUE", 0x80)) == "POKEMON_GLDAAUE",
		"lookup/the title stops before the CGB flag")
	_ok(GbCartShell.preset_for_rom("") == &"grey" and GbCartShell.preset_for_rom("user://missing.gb") == &"grey",
		"lookup/no file is grey")
	var every := PackedStringArray()
	for table in [GbCartShell.TITLE_SHELLS, GbCartShell.OVERSEAS_TITLE_SHELLS]:
		for id: StringName in table.values():
			if _preset(id) == null:
				every.append(id)
	for id in [GbCartShell.DEFAULT_PRESET, GbCartShell.BLACK_PRESET]:
		if _preset(id) == null:
			every.append(id)
	_ok(every.is_empty(), "lookup/every answer is a palette preset", str(every))


func _test_cartridge() -> void:
	var img := Image.create(420, 370, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	DirAccess.make_dir_recursive_absolute(_label_dir())
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))

	var red := await _spawn(_write_rom(FIXTURE + ".gb", _header("POKEMON RED")))
	var dual := await _spawn(_write_rom("dual.gbc", _header("ZELDA DXAZ7E", 0x80, false, "nintendo_new")))
	var plain := await _spawn(_write_rom("plain.gb", _header("TETRIS")))
	var yellow := await _spawn(_write_rom("yellow.gb", _header("POKEMON YELLOW", 0x80)))
	var red_model := red.get_node_or_null("CartModel")
	_ok(red_model != null and red_model.scene_file_path == GbCartShell.BODY, "cartridge/a Game Boy ROM spawns the model")
	_ok(red_model != null and _albedo(red_model, "Front_Shell") == _preset(&"red").color,
		"cartridge/Pokemon Red spawns red")
	var dual_model := dual.get_node_or_null("CartModel")
	_ok(dual_model != null and _albedo(dual_model, "Front_Shell") == _preset(&"black").color,
		"cartridge/a dual-mode .gbc spawns black")
	var yellow_model := yellow.get_node_or_null("CartModel")
	_ok(yellow_model != null and _albedo(yellow_model, "Front_Shell") == _preset(&"yellow").color,
		"cartridge/Pokemon Yellow spawns yellow, not black")
	var plain_model := plain.get_node_or_null("CartModel")
	_ok(plain_model != null and _near(_albedo(plain_model, "Front_Shell"), _source(plain_model, "Front_Shell").albedo_color),
		"cartridge/a Game Boy game spawns grey")
	var label := CartridgeLabel.find_label(red_model) if red_model != null else null
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 420,
		"cartridge/the scraped label is painted on the sticker")
	_ok(red.get_node_or_null("ModelLabelArt") == null and not (red.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	var plain_label := CartridgeLabel.find_label(plain_model) if plain_model != null else null
	_ok(plain_label != null and plain_label.get_surface_override_material(0) == null
		and (plain.get_node("GameLabel") as Label3D).visible, "cartridge/no art: the blank sticker and the title")
	var contacts := _part(red_model, "Contacts").get_active_material(0) as BaseMaterial3D
	_ok(contacts.metallic > 0.5, "cartridge/contacts keep their metal")
	var scale := (red_model as Node3D).scale
	_ok(absf(scale.x - 1.0) < 0.005 and absf(scale.y - 1.0) < 0.005 and absf(scale.z - 1.0) < 0.005,
		"cartridge/the body is not stretched to MediaDimensions' size", str(scale))
	for cart in [red, dual, plain, yellow]:
		cart.queue_free()
	await get_tree().process_frame


## What the spawn menu's hold sub-menu forces: a shell that is not the ROM's
## own. Pokemon Red is the fixture because its own answer is red, so a forced
## shell cannot pass by being the default.
func _test_forced() -> void:
	var rom := _write_rom("forced.gb", _header("POKEMON RED"))
	var blue := await _spawn(rom, &"blue")
	var gold := await _spawn(rom, &"gold")
	var n64_only := await _spawn(rom, &"gold_silver")
	var own := await _spawn(rom)
	var blue_model := blue.get_node_or_null("CartModel")
	var gold_model := gold.get_node_or_null("CartModel")
	_ok(blue_model != null and _albedo(blue_model, "Front_Shell") == _preset(&"blue").color,
		"forced/a forced shell beats the ROM's own")
	_ok(gold_model != null and gold_model.find_child("Front_Shell", true, false).get_active_material(0) is ShaderMaterial,
		"forced/a forced flake shell is on the flake shader")
	_ok(_albedo(n64_only.get_node("CartModel"), "Front_Shell") == _preset(&"red").color,
		"forced/an id the Game Boy palette lacks keeps the ROM's own")
	_ok(_albedo(own.get_node("CartModel"), "Front_Shell") == _preset(&"red").color,
		"forced/nothing forced is the ROM's own")
	for cart in [blue, gold, n64_only, own]:
		cart.queue_free()
	await get_tree().process_frame


func _spawn(rom: String, shell: StringName = &"") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = GbCartShell.SYSTEMID
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
