## Game Boy Advance cartridge self-tests — the tintable model, its solid and
## translucent shells, the header lookup that picks one per ROM, and the spawned
## cartridge that uses them.
##
##     "$godot" --headless --path RetroXR res://Tests/gba_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/gba_cart_tests.tscn -- --only=lookup
##
## Exits 0 when everything passes, 1 otherwise. Writes ROM fixtures under user://
## and removes them at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__gbacart_selftest"

## The two halves of the moulding, each one surface.
const SHELL_PARTS := ["Front_Shell", "Rear_Shell"]
## Parts a shell colour must never reach: the label, the screw, and the board
## seen through a clear shell (its contact strip, chips and battery).
const KEPT_PARTS := ["Label", "Opaque_Internal_Details", "Connector_PCB", "Interior_PCB",
	"Interior_ROM_Chip", "Interior_RTC_Chip", "Interior_Save_Battery"]
const CLEAR := [&"ruby", &"sapphire", &"emerald", &"fire_red", &"leaf_green"]

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[gbacart] TIMEOUT")
		get_tree().quit(1))
	_clear_fixtures()

	if _wants("resources"):
		_test_resources()
	if _wants("model"):
		_test_model()
	if _wants("surfaces"):
		_test_surfaces()
	if _wants("color"):
		_test_color()
	if _wants("clear"):
		_test_clear()
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
	print("[gbacart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[gbacart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[gbacart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _body() -> Node3D:
	var node := (load(GbaCartShell.BODY) as PackedScene).instantiate() as Node3D
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
	return CartridgeColor.get_palette(GbaCartShell.SYSTEMID).find(id)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.003 and absf(a.g - b.g) < 0.003 and absf(a.b - b.b) < 0.003


func _solid(m: BaseMaterial3D) -> bool:
	return m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(m.albedo_color.a, 1.0)


## Painted in `preset` as clear plastic: the filter pass in its colour at its
## opacity, then the surface pass with the half's normal map.
func _clear_in(root: Node, preset: CartridgeShellPreset) -> bool:
	for p: String in SHELL_PARTS:
		if not _is_clear(root, p, preset.color, preset.opacity):
			return false
	return true


func _is_clear(root: Node, part: String, color: Color, opacity: float) -> bool:
	var cm := _part(root, part).get_active_material(0) as ShaderMaterial
	if cm == null or cm.shader != CartridgeColor.CLEAR_SHADER:
		return false
	var surface := cm.next_pass as ShaderMaterial
	return surface != null and surface.shader == CartridgeColor.CLEAR_SURFACE_SHADER 		and _near(cm.get_shader_parameter("tint"), color) 		and is_equal_approx(cm.get_shader_parameter("density"), opacity * CartridgeColor.CLEAR_DENSITY) 		and surface.get_shader_parameter("texture_normal") == _source(root, part).normal_texture 		and surface.get_shader_parameter("normal_enabled") == true


## Both halves as imported: the model's colour, solid, with its own culling.
func _as_model(root: Node) -> bool:
	for p: String in SHELL_PARTS:
		var m := _mat(root, p)
		var src := _source(root, p)
		if not (_near(m.albedo_color, src.albedo_color) and _solid(m) and m.cull_mode == src.cull_mode):
			return false
	return true


## Both halves keep the imported roughness and its map.
func _own_roughness(root: Node) -> bool:
	for p: String in SHELL_PARTS:
		var m := _mat(root, p)
		var src := _source(root, p)
		if not (is_equal_approx(m.roughness, src.roughness) and m.roughness_texture == src.roughness_texture):
			return false
	return true


## A 0xC0-byte cartridge header: title, game code and maker code.
func _header(title: String, code: String, maker := "01") -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(GbaCartShell.HEADER_BYTES)
	for i in mini(title.length(), GbaCartShell.TITLE_BYTES):
		h[GbaCartShell.TITLE_AT + i] = title.unicode_at(i)
	for i in mini(code.length(), GbaCartShell.GAME_CODE_BYTES):
		h[GbaCartShell.GAME_CODE_AT + i] = code.unicode_at(i)
	for i in mini(maker.length(), 2):
		h[GbaCartShell.MAKER_CODE_AT + i] = maker.unicode_at(i)
	h[0xB2] = 0x96
	return h


func _write_rom(file_name: String, header: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(header)
	f.close()
	return path


func _clear_fixtures() -> void:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	for path in [GbaCartShell.BODY, CartridgeColor.PALETTE_PATHS[GbaCartShell.SYSTEMID]]:
		_ok(ResourceLoader.exists(path), "resources/%s exists" % path.get_file())
	var palette := CartridgeColor.get_palette(GbaCartShell.SYSTEMID)
	_ok(palette != null and palette != CartridgeColor.get_palette(GbCartShell.SYSTEMID),
		"resources/the Game Boy Advance has a palette of its own")
	var wanted := ["grey", "ruby", "sapphire", "emerald", "fire_red", "leaf_green"]
	_ok(Array(palette.ids()) == wanted, "resources/palette carries exactly the presets", str(palette.ids()))
	_ok(palette.find(&"grey").availability == CartridgeShellPreset.Availability.STANDARD
		and is_equal_approx(palette.find(&"grey").opacity, 1.0), "resources/grey is the standard, solid shell")
	var clear := true
	for id: StringName in CLEAR:
		var p := palette.find(id)
		clear = clear and p.finish == CartridgeShellPreset.Finish.PLASTIC and p.opacity > 0.5 and p.opacity < 0.95
	_ok(clear, "resources/the Pokemon shells are translucent plastic")
	_ok(is_equal_approx(CartridgeShellPreset.new().opacity, 1.0), "resources/a preset is solid unless it says")


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
	_ok(absf(ab.size.x - 0.060) < 0.0005 and absf(ab.size.y - 0.035) < 0.0005 and absf(ab.size.z - 0.009) < 0.0005,
		"model/60 x 35 x 9 mm", str(ab.size))
	var label := _part(body, "Label")
	_ok((label.transform * label.get_aabb()).get_center().z > 0.0, "model/label on +Z")
	_ok(_solid(_source(body, "Front_Shell")) and _solid(_source(body, "Rear_Shell")),
		"model/the imported shell is solid: a cartridge is only clear when painted so")
	body.free()


func _test_surfaces() -> void:
	var body := _body()
	var names := PackedStringArray()
	for s in CartridgeColor.shell_surfaces(body):
		names.append(String((s["mesh"] as Node).name))
	names.sort()
	_ok(names == PackedStringArray(SHELL_PARTS), "surfaces/exactly the two halves", str(names))
	body.free()


func _test_color() -> void:
	var a := _body()
	var b := _body()
	var grey := _preset(&"grey")
	_ok(CartridgeColor.apply_preset(a, &"grey", GbaCartShell.SYSTEMID) == OK, "color/grey applies")
	_ok(_as_model(a), "color/grey reproduces the model's own solid plastic")
	_ok(_near(grey.color, _source(a, "Front_Shell").albedo_color), "color/grey is the model's colour")
	_ok(_own_roughness(a), "color/each half keeps its baked roughness")
	_ok(_mat(a, "Front_Shell").normal_texture == _source(a, "Front_Shell").normal_texture
		and _source(a, "Front_Shell").normal_texture != null, "color/the normal map is carried")
	CartridgeColor.apply_color(a, Color(0.2, 0.4, 0.9))
	_ok(_near(_mat(a, "Rear_Shell").albedo_color, Color(0.2, 0.4, 0.9)) and _solid(_mat(a, "Rear_Shell")),
		"color/an opaque colour is solid")
	CartridgeColor.apply_color(a, Color(0.2, 0.4, 0.9, 0.6))
	_ok(_is_clear(a, "Rear_Shell", Color(0.2, 0.4, 0.9), 0.6), "color/a colour's alpha makes it clear")
	_ok(_mat(b, "Front_Shell") == _source(b, "Front_Shell"), "color/another instance is untouched")
	_ok(_solid(_source(a, "Front_Shell")), "color/the imported material is untouched")
	_ok(CartridgeColor.apply_preset(a, &"red", GbaCartShell.SYSTEMID) == ERR_DOES_NOT_EXIST,
		"color/a Game Boy preset is not a Game Boy Advance one")
	_ok(CartridgeColor.reset_to_default(a) == OK
		and _part(a, "Front_Shell").get_surface_override_material(0) == null, "color/reset restores the model")
	a.free()
	b.free()


func _test_clear() -> void:
	var cart := _body()
	for id: StringName in CLEAR:
		_ok(CartridgeColor.apply_preset(cart, id, GbaCartShell.SYSTEMID) == OK and _clear_in(cart, _preset(id)),
			"clear/%s is clear plastic in its colour at its opacity" % id)
	# Multiply and add commute: the two halves, and shells over each other, give
	# the same picture in any draw order. An alpha blend would not.
	var filter_code := CartridgeColor.CLEAR_SHADER.code
	var surface_code := CartridgeColor.CLEAR_SURFACE_SHADER.code
	_ok(filter_code.contains("blend_mul") and filter_code.contains("depth_draw_never")
		and surface_code.contains("blend_add") and surface_code.contains("depth_draw_never"),
		"clear/the filter multiplies and the surface adds, neither writing depth")
	CartridgeColor.apply_preset(cart, &"grey", GbaCartShell.SYSTEMID)
	_ok(_as_model(cart), "clear/repainting grey makes it solid again, with the model's culling")
	cart.free()


func _test_kept() -> void:
	var cart := _body()
	var before := {}
	for part: String in KEPT_PARTS:
		before[part] = _materials(_part(cart, part))
	for id in CLEAR + [&"grey"]:
		CartridgeColor.apply_preset(cart, id, GbaCartShell.SYSTEMID)
	CartridgeColor.apply_color(cart, Color(0, 1, 0, 0.5))
	CartridgeColor.reset_to_default(cart)
	CartridgeColor.apply_preset(cart, &"ruby", GbaCartShell.SYSTEMID)
	var changed := PackedStringArray()
	for part: String in KEPT_PARTS:
		if _materials(_part(cart, part)) != before[part]:
			changed.append(part)
	_ok(changed.is_empty(), "kept/label, contacts and the board inside keep their materials", str(changed))
	var see_through := PackedStringArray()
	for part: String in KEPT_PARTS:
		for m: Material in before[part]:
			if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				see_through.append(part)
	_ok(see_through.is_empty(), "kept/everything inside is solid", str(see_through))
	# The contact strip wears the same two photos as the board above it, so the
	# silkscreen and the contacts run on across the join.
	for part: String in ["Interior_PCB", "Connector_PCB"]:
		var board := _part(cart, part)
		var photos := {}
		for i in board.mesh.get_surface_count():
			var m := board.get_active_material(i) as BaseMaterial3D
			if m != null and m.albedo_texture != null and m.albedo_texture.get_width() <= 1024:
				photos[m.albedo_texture] = true
		_ok(photos.size() == 2, "kept/%s carries both photos, at most 1024 wide" % part, str(photos.size()))
	var upper := _part(cart, "Interior_PCB")
	var lower := _part(cart, "Connector_PCB")
	_ok(upper.get_active_material(0) == lower.get_active_material(0), "kept/board and contact strip share the photo material")
	cart.free()


func _test_lookup() -> void:
	var cases := [
		["Pokemon Ruby, USA", _header("POKEMON RUBY", "AXVE"), &"ruby"],
		["Pokemon Sapphire, USA", _header("POKEMON SAPP", "AXPE"), &"sapphire"],
		["Pokemon Emerald, USA", _header("POKEMON EMER", "BPEE"), &"emerald"],
		["Pokemon FireRed, USA", _header("POKEMON FIRE", "BPRE"), &"fire_red"],
		["Pokemon LeafGreen, USA", _header("POKEMON LEAF", "BPGE"), &"leaf_green"],
		["Pocket Monsters Ruby, Japan", _header("POKEMON RUBY", "AXVJ"), &"ruby"],
		["Pokemon Saphir, Germany", _header("POKEMON SAPP", "AXPD"), &"sapphire"],
		["Pokemon Smeraldo, Italy", _header("POKEMON EMER", "BPEI"), &"emerald"],
		["Pokemon Rouge Feu, France", _header("POKEMON FIRE", "BPRF"), &"fire_red"],
		["Pokemon Verde Hoja, Spain", _header("POKEMON LEAF", "BPGS"), &"leaf_green"],
		["a Nintendo game", _header("ZELDA MINISH", "BZME"), &"grey"],
		["a Pokemon game code from another maker", _header("POKEMON RUBY", "AXVE", "08"), &"grey"],
		["a homebrew with no game code", _header("HOMEBREW", "", ""), &"grey"],
		["a short file", PackedByteArray([1, 2, 3]), &"grey"],
	]
	for c: Array in cases:
		var got := GbaCartShell.preset_for_header(c[1])
		_ok(got == c[2], "lookup/%s is %s" % [c[0], c[2]], "got %s" % got)
	_ok(GbaCartShell.game_code(_header("POKEMON RUBY", "AXVE")) == "AXVE", "lookup/the game code is read at 0xAC")
	_ok(GbaCartShell.preset_for_rom("") == &"grey" and GbaCartShell.preset_for_rom("user://missing.gba") == &"grey",
		"lookup/no file is grey")
	var every := PackedStringArray()
	for id: StringName in GbaCartShell.GAME_SHELLS.values() + [GbaCartShell.DEFAULT_PRESET]:
		if _preset(id) == null:
			every.append(id)
	_ok(every.is_empty(), "lookup/every answer is a palette preset", str(every))


func _test_cartridge() -> void:
	var ruby := await _spawn(_write_rom("ruby.gba", _header("POKEMON RUBY", "AXVE")))
	var fire := await _spawn(_write_rom("fire.gba", _header("POKEMON FIRE", "BPRE")))
	var plain := await _spawn(_write_rom("plain.gba", _header("ZELDA MINISH", "BZME")))
	var ruby_model := ruby.get_node_or_null("CartModel")
	_ok(ruby_model != null and ruby_model.scene_file_path == GbaCartShell.BODY,
		"cartridge/a Game Boy Advance ROM spawns the model")
	_ok(ruby_model != null and _clear_in(ruby_model, _preset(&"ruby")), "cartridge/Pokemon Ruby spawns clear red")
	var fire_model := fire.get_node_or_null("CartModel")
	_ok(fire_model != null and _clear_in(fire_model, _preset(&"fire_red")),
		"cartridge/Pokemon FireRed spawns clear orange-red")
	var plain_model := plain.get_node_or_null("CartModel")
	_ok(plain_model != null and _as_model(plain_model), "cartridge/any other game spawns solid grey")
	for cart in [ruby, fire, plain]:
		cart.queue_free()
	await get_tree().process_frame


## What the spawn menu's hold sub-menu forces. Pokemon Ruby is the fixture
## because its own answer is clear red, so a forced shell cannot pass by being
## the default.
func _test_forced() -> void:
	var rom := _write_rom("forced.gba", _header("POKEMON RUBY", "AXVE"))
	var sapphire := await _spawn(rom, &"sapphire")
	var grey := await _spawn(rom, &"grey")
	var gb_only := await _spawn(rom, &"gold")
	var own := await _spawn(rom)
	_ok(_clear_in(sapphire.get_node("CartModel"), _preset(&"sapphire")), "forced/a forced shell beats the ROM's own")
	_ok(_solid(_mat(grey.get_node("CartModel"), "Front_Shell")), "forced/a forced grey Ruby is solid")
	_ok(_clear_in(gb_only.get_node("CartModel"), _preset(&"ruby")),
		"forced/an id the Game Boy Advance palette lacks keeps the ROM's own")
	_ok(_clear_in(own.get_node("CartModel"), _preset(&"ruby")), "forced/nothing forced is the ROM's own")
	for cart in [sapphire, grey, gb_only, own]:
		cart.queue_free()
	await get_tree().process_frame


func _spawn(rom: String, shell: StringName = &"") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = GbaCartShell.SYSTEMID
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
