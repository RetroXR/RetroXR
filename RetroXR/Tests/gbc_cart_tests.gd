## Game Boy Color cartridge self-tests: the clear Game Boy Color-only shell on its
## two boards, smoke and Pokemon Crystal's clear blue glitter, which ROMs get it,
## its size, and the spawned and forced cartridges.
##
##     "$godot" --headless --path RetroXR res://Tests/gbc_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/gbc_cart_tests.tscn -- --only=lookup
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one label fixture into the player's real gbc media/label folder
## (MediaDimensions derives the path from the ROM's name) and ROM fixtures under
## user://, and removes both at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__gbccart_selftest"
const UV_MIN_WIDTH := 0.00005

const BODIES := [GbcCartShell.BODY_LARGE, GbcCartShell.BODY_SMALL]
## The moulding: both halves, each with its stippled face, polished lettering and
## ridges, and their walls.
const SHELL_PARTS := ["Front_Shell", "Rear_Shell"]
const SHELL_MATERIALS := [&"GBC_Shell_Front", &"GBC_Shell_Rear", &"GBC_Shell_Smooth", &"GBC_Shell_Edge"]
## Parts a shell colour must never reach, on both boards.
const KEPT_PARTS := ["Label", "Contacts_32", "Security_Gamebit_Head", "Connector_PCB", "Interior_PCB_Components"]
## What frost blurs behind a clear shell: the photographed board and what is on it.
const FROSTED := ["Connector_PCB", "Interior_PCB_Components"]

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[gbccart] TIMEOUT")
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
	if _wants("clear"):
		_test_clear()
	if _wants("glitter"):
		_test_glitter()
	if _wants("kept"):
		_test_kept()
	if _wants("lookup"):
		_test_lookup()
	if _wants("size"):
		_test_size()
	if _wants("cartridge"):
		await _test_cartridge()
	if _wants("forced"):
		await _test_forced()
	if _wants("menu"):
		_test_menu()

	_clear_fixtures()
	await _settle_warm()
	print("[gbccart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[gbccart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[gbccart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _body(path: String = GbcCartShell.BODY_LARGE) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


## The surface of `part` whose imported material is `material`.
func _surface(root: Node, part: String, material: StringName) -> int:
	var mi := _part(root, part)
	for s in mi.mesh.get_surface_count():
		if StringName(mi.mesh.surface_get_material(s).resource_name) == material:
			return s
	return -1


func _active(root: Node, part: String, material: StringName) -> Material:
	return _part(root, part).get_active_material(_surface(root, part, material))


func _front(root: Node) -> Material:
	return _active(root, "Front_Shell", &"GBC_Shell_Front")


func _preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(GbcCartShell.PALETTE).find(id)


func _gb_preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(GbCartShell.SYSTEMID).find(id)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.003 and absf(a.g - b.g) < 0.003 and absf(a.b - b.b) < 0.003


## A 0x150-byte header: title, CGB flag, cartridge type, and Nintendo's licensee
## (the new code "01", as Crystal has) or another publisher's.
func _header(title: String, cgb := 0xC0, cart_type := 0x19, nintendo := true, japan := false) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(GbCartShell.HEADER_BYTES)
	for i in mini(title.length(), 15):
		h[GbCartShell.TITLE_AT + i] = title.unicode_at(i)
	h[GbCartShell.CGB_AT] = cgb
	h[GbcCartShell.CART_TYPE_AT] = cart_type
	h[GbCartShell.DESTINATION_AT] = GbCartShell.DESTINATION_JAPAN if japan else 0x01
	h[GbCartShell.OLD_LICENSEE_AT] = GbCartShell.OLD_LICENSEE_USE_NEW
	h[GbCartShell.NEW_LICENSEE_AT] = 0x30
	h[GbCartShell.NEW_LICENSEE_AT + 1] = 0x31 if nintendo else 0x38
	return h


func _crystal() -> PackedByteArray:
	return _header("PM_CRYSTAL", 0xC0, 0x10)


func _write_rom(file_name: String, header: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(header)
	f.close()
	return path


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(GbcCartShell.PALETTE).path_join("media").path_join("label")


func _clear_fixtures() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _spawn(rom: String, shell: StringName = &"", color := "", flake := false, body := "",
		systemid := "gbc") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = systemid
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


func _model_path(cart: RetroCartridge) -> String:
	var model := cart.get_node_or_null("CartModel")
	return model.scene_file_path if model != null else ""


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	for path in BODIES + [CartridgeColor.PALETTE_PATHS[GbcCartShell.PALETTE]]:
		_ok(ResourceLoader.exists(path), "resources/%s exists" % path.get_file())
	var palette := CartridgeColor.get_palette(GbcCartShell.PALETTE)
	_ok(palette != null and palette != CartridgeColor.get_palette(GbCartShell.SYSTEMID),
		"resources/the Game Boy Color shell has a palette of its own")
	_ok(Array(palette.ids()) == ["smoke", "crystal"], "resources/palette carries exactly the presets", str(palette.ids()))
	var smoke := palette.find(&"smoke")
	var crystal := palette.find(&"crystal")
	_ok(smoke.availability == CartridgeShellPreset.Availability.STANDARD
		and smoke.finish == CartridgeShellPreset.Finish.PLASTIC and smoke.opacity < 1.0,
		"resources/smoke is the standard shell, clear plastic")
	_ok(crystal.finish == CartridgeShellPreset.Finish.METAL_FLAKE and crystal.opacity < 1.0
		and crystal.flake_density > 0.0, "resources/Crystal is clear plastic with metal glitter")
	_ok(crystal.color.b > crystal.color.g and crystal.color.g > crystal.color.r,
		"resources/Crystal is blue", str(crystal.color))


func _test_model() -> void:
	for path: String in BODIES:
		var body := _body(path)
		var tag := path.get_file().get_basename()
		var missing := PackedStringArray()
		for part: String in SHELL_PARTS + KEPT_PARTS:
			if _part(body, part) == null:
				missing.append(part)
		_ok(missing.is_empty(), "model/%s has every part" % tag, str(missing))
		var ab := AABB()
		var first := true
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var box := (body.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			ab = box if first else ab.merge(box)
			first = false
		var size := MediaDimensions.CART_SIZE_GBC
		_ok(absf(ab.size.x - size.x) < 0.0002 and absf(ab.size.y - size.y) < 0.0002
			and absf(ab.size.z - size.z) < 0.0002, "model/%s is 57 x 65 x 9 mm, MediaDimensions' size" % tag, str(ab.size))
		var pcb := _part(body, "Connector_PCB")
		var label := _part(body, "Label")
		_ok(pcb.global_position.y + pcb.get_aabb().get_center().y < 0.0
			and label.get_aabb().get_center().z > 0.0, "model/%s: connector on -Y, label on +Z" % tag)
		# RetroXR makes the shell clear: the export is solid, one colour, no frost texture.
		var solid := SHELL_MATERIALS.all(func(m: StringName) -> bool:
			var part := "Rear_Shell" if m == &"GBC_Shell_Rear" else "Front_Shell"
			var s := _surface(body, part, m)
			if s < 0:
				return false
			var bm := _part(body, part).mesh.surface_get_material(s) as BaseMaterial3D
			return bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and bm.albedo_color.a == 1.0 \
				and bm.albedo_texture == null)
		_ok(solid, "model/%s: every moulding material is there, exported solid" % tag)
		body.free()
	var large := _body(GbcCartShell.BODY_LARGE)
	var small := _body(GbcCartShell.BODY_SMALL)
	_ok(_part(large, "Interior_Battery_Steel") != null and _part(small, "Interior_Battery_Steel") == null,
		"model/the large board carries the coin cell, the small one does not")
	large.free()
	small.free()


## The shipped bodies are the debranded ones: no logo mesh or material, and no
## normal map but the mould stipple.
func _test_branding() -> void:
	for path: String in BODIES:
		var body := _body(path)
		var marks := PackedStringArray()
		var maps := {}
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for word in ["nintendo", "logo", "game_boy", "gameboy", "engrav", "wordmark"]:
				if String(mi.name).containsn(word):
					marks.append(mi.name)
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null:
					continue
				for word in ["nintendo", "logo", "engrav", "wordmark"]:
					if m.resource_name.containsn(word):
						marks.append(m.resource_name)
				if m.normal_texture != null:
					maps[m.normal_texture.resource_path.get_file().trim_prefix(path.get_file().get_basename() + "_")] = true
				if m.albedo_texture != null and m.resource_name.begins_with("PCB_Back_Photo"):
					if not m.resource_name.ends_with("_clean"):
						marks.append(m.resource_name)
		var tag := path.get_file().get_basename()
		_ok(marks.is_empty(), "branding/%s: no logo, and the board photo without its wordmark" % tag, str(marks))
		_ok(maps.keys() == ["shell_stipple_normal.png"], "branding/%s: no normal map but the stipple" % tag,
			str(maps.keys()))
		body.free()


## Every triangle of a normal-mapped surface has area in UV space (see
## n64_cart_tests' uv group); export_retroxr.py's output went through
## Tools/glb/fix_unmapped_uvs.py.
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
		body.free()


func _test_surfaces() -> void:
	var body := _body()
	var found := PackedStringArray()
	for s in CartridgeColor.shell_surfaces(body):
		var mi := s["mesh"] as MeshInstance3D
		found.append("%s/%s" % [mi.name, mi.mesh.surface_get_material(s["surface"]).resource_name])
	found.sort()
	var want := PackedStringArray(["Front_Shell/GBC_Shell_Edge", "Front_Shell/GBC_Shell_Front",
		"Front_Shell/GBC_Shell_Smooth", "Rear_Shell/GBC_Shell_Edge", "Rear_Shell/GBC_Shell_Rear",
		"Rear_Shell/GBC_Shell_Smooth"])
	_ok(found == want, "surfaces/exactly the moulding, both halves", str(found))
	var halves := CartridgeColor.shell_surfaces(body).all(func(s: Dictionary) -> bool:
		var front := String((s["mesh"] as Node).name) == "Front_Shell"
		return s["half"] == (CartridgeColor.Half.FRONT if front else CartridgeColor.Half.BACK))
	_ok(halves, "surfaces/each half is its own")
	body.free()


func _test_clear() -> void:
	var cart := _body()
	var smoke := _preset(&"smoke")
	_ok(CartridgeColor.apply_preset(cart, &"smoke", GbcCartShell.PALETTE) == OK, "clear/smoke applies")
	var all_clear := CartridgeColor.shell_surfaces(cart).all(func(s: Dictionary) -> bool:
		var m := (s["mesh"] as MeshInstance3D).get_active_material(s["surface"]) as ShaderMaterial
		return (m != null and m.shader == CartridgeColor.CLEAR_SHADER
			and (m.next_pass as ShaderMaterial).shader == CartridgeColor.CLEAR_SURFACE_SHADER))
	_ok(all_clear, "clear/every moulding is on the filter pass with the surface pass after it")
	var front := _front(cart) as ShaderMaterial
	var surface := front.next_pass as ShaderMaterial
	_ok(front.get_shader_parameter("tint") == smoke.color
		and is_equal_approx(front.get_shader_parameter("density"), smoke.opacity * CartridgeColor.CLEAR_DENSITY),
		"clear/the preset's colour and opacity reach the filter")
	_ok(is_equal_approx(front.get_shader_parameter("flake_amount"), 0.0)
		and is_equal_approx(surface.get_shader_parameter("flake_amount"), 0.0), "clear/smoke has no glitter")
	_ok(surface.get_shader_parameter("texture_normal") != null
		and surface.get_shader_parameter("normal_enabled") == true, "clear/the stipple normal map is carried")
	var polished := _active(cart, "Front_Shell", &"GBC_Shell_Smooth") as ShaderMaterial
	_ok(polished != null and polished.shader == CartridgeColor.CLEAR_SHADER, "clear/the lettering and ridges go clear too")
	var frosted := FROSTED.all(func(p: String) -> bool:
		var mi := _part(cart, p)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as ShaderMaterial
			if m == null or m.shader != CartridgeColor.FROST_SHADER:
				return false
		return true)
	_ok(frosted, "clear/the board and its parts go out of focus behind it")
	var contacts := _part(cart, "Contacts_32").get_active_material(0)
	_ok(contacts is BaseMaterial3D, "clear/the gold contacts at the open mouth stay sharp")
	CartridgeColor.apply_color(cart, Color("#224488"))
	_ok(_front(cart) is BaseMaterial3D and (_front(cart) as BaseMaterial3D).albedo_color == Color("#224488")
		and _part(cart, "Connector_PCB").get_active_material(0) is BaseMaterial3D,
		"clear/a solid colour makes it solid, and the board comes back into focus")
	_ok(CartridgeColor.reset_to_default(cart) == OK
		and _part(cart, "Front_Shell").get_surface_override_material(_surface(cart, "Front_Shell", &"GBC_Shell_Front")) == null,
		"clear/reset restores the model")
	cart.free()


## Pokemon Crystal: clear plastic with metal glitter in it. A METAL_FLAKE preset
## below opacity 1 goes on the clear passes with flakes, not the solid flake shader.
func _test_glitter() -> void:
	var cart := _body()
	var crystal := _preset(&"crystal")
	_ok(CartridgeColor.apply_preset(cart, &"crystal", GbcCartShell.PALETTE) == OK, "glitter/Crystal applies")
	var front := _front(cart) as ShaderMaterial
	_ok(front != null and front.shader == CartridgeColor.CLEAR_SHADER, "glitter/Crystal is clear, not the solid flake shader")
	var surface := front.next_pass as ShaderMaterial
	_ok(front.get_shader_parameter("tint") == crystal.color
		and is_equal_approx(front.get_shader_parameter("density"), crystal.opacity * CartridgeColor.CLEAR_DENSITY),
		"glitter/its colour and opacity reach the filter")
	var both := [front, surface].all(func(m: ShaderMaterial) -> bool:
		return (is_equal_approx(m.get_shader_parameter("flake_amount"), crystal.flake_density)
			and is_equal_approx(m.get_shader_parameter("flake_size_mm"), crystal.flake_size_mm)))
	_ok(both, "glitter/the same flakes on both passes, so the filter blacks out what the surface lights")
	_ok(surface.get_shader_parameter("flake_color") == crystal.flake_color
		and is_equal_approx(surface.get_shader_parameter("flake_tilt"), crystal.flake_tilt),
		"glitter/flake colour and tilt reach the surface pass")
	_ok(_part(cart, "Connector_PCB").get_active_material(0) is ShaderMaterial, "glitter/Crystal frosts the board too")
	CartridgeColor.apply_preset(cart, &"smoke", GbcCartShell.PALETTE)
	_ok(is_equal_approx((_front(cart) as ShaderMaterial).get_shader_parameter("flake_amount"), 0.0)
		and is_equal_approx(((_front(cart) as ShaderMaterial).next_pass as ShaderMaterial).get_shader_parameter("flake_amount"), 0.0),
		"glitter/smoke after Crystal takes the glitter out again")
	# A flake colour mixed on the panel borrows Crystal's flakes but has no opacity.
	var mix := Color("#c0303a")
	CartridgeColor.apply_flake(cart, mix, GbcCartShell.PALETTE)
	var sm := _front(cart) as ShaderMaterial
	_ok(sm != null and sm.shader == CartridgeColor.FLAKE_SHADER and sm.get_shader_parameter("albedo") == mix
		and is_equal_approx(sm.get_shader_parameter("flake_density"), crystal.flake_density),
		"glitter/a mixed metal-flake colour is solid, with Crystal's flakes")
	_ok(crystal.opacity < 1.0, "glitter/and the palette's Crystal is still clear after lending them")
	cart.free()
	# The solid gold and silver of the Game Boy palette are unchanged by this.
	var gb := (load(GbCartShell.BODY) as PackedScene).instantiate() as Node3D
	add_child(gb)
	CartridgeColor.apply_preset(gb, &"gold", GbCartShell.SYSTEMID)
	_ok((_part(gb, "Front_Shell").get_active_material(0) as ShaderMaterial).shader == CartridgeColor.FLAKE_SHADER,
		"glitter/an opaque metal-flake preset stays on the solid flake shader")
	gb.free()


func _test_kept() -> void:
	for path: String in BODIES:
		var cart := _body(path)
		var before := {}
		for part: String in KEPT_PARTS:
			before[part] = _part(cart, part).get_active_material(0)
		for id in [&"smoke", &"crystal"]:
			CartridgeColor.apply_preset(cart, id, GbcCartShell.PALETTE)
		CartridgeColor.apply_color(cart, Color.GREEN)
		CartridgeColor.apply_flake(cart, Color.RED, GbcCartShell.PALETTE)
		CartridgeColor.reset_to_default(cart)
		var changed := PackedStringArray()
		for part: String in KEPT_PARTS:
			if _part(cart, part).get_active_material(0) != before[part]:
				changed.append(part)
		_ok(changed.is_empty(), "kept/%s: label, contacts, screw and board keep their materials" % path.get_file(),
			str(changed))
		var contacts := before["Contacts_32"] as BaseMaterial3D
		var screw := before["Security_Gamebit_Head"] as BaseMaterial3D
		_ok(contacts.metallic > 0.5 and screw.metallic > 0.5, "kept/%s: contacts and screw are metal" % path.get_file())
		cart.free()


func _test_lookup() -> void:
	var gb := GbCartShell.BODY
	var large := GbcCartShell.BODY_LARGE
	var small := GbcCartShell.BODY_SMALL
	# [case, body_region, shell_preset, header, body]
	var bodies := [
		["a GBC-only game, no save", "", &"", _header("SHREK"), small],
		["a GBC-only game that saves", "", &"", _header("ZELDA", 0xC0, 0x1B), large],
		["Pokemon Crystal", "", &"", _crystal(), large],
		["a GBC-only game from another publisher", "", &"", _header("SOMEGAME", 0xC0, 0x19, false), small],
		["a dual-mode game", "", &"", _header("ZELDA DX", 0x80, 0x03), gb],
		["a Game Boy game", "", &"", _header("TETRIS", 0x00, 0x00), gb],
		["the GBC-only Korean Pokemon Silver", "", &"", _header("POKEMON_SLVAAXK", 0xC0, 0x10), gb],
		["a short file", "", &"", PackedByteArray([1, 2, 3]), gb],
		["the clear body forced on a dual-mode game", GbcCartShell.BODY_GBC, &"", _header("ZELDA DX", 0x80, 0x03), large],
		["the Game Boy body forced on Crystal", GbcCartShell.BODY_GB, &"", _crystal(), gb],
		["Crystal's shell forced on a dual-mode game", "", &"crystal", _header("ZELDA DX", 0x80, 0x03), large],
		["smoke forced on a Game Boy game with no save", "", &"smoke", _header("TETRIS", 0x00, 0x00), small],
		["a Game Boy shell forced on Crystal", "", &"black", _crystal(), gb],
		["a forced body beats a forced shell", GbcCartShell.BODY_GB, &"crystal", _crystal(), gb],
		["an id neither palette holds", "", &"gold_silver", _crystal(), large],
	]
	for c: Array in bodies:
		var got := GbcCartShell.body_model_for(c[1], c[2], c[3])
		_ok(got == c[4], "lookup/%s: %s" % [c[0], str(c[4]).get_file()], "got %s" % got.get_file())
	var presets := [
		["Pokemon Crystal, USA and Europe", _crystal(), &"crystal"],
		["Pocket Monsters Crystal, Japan", _header("PM_CRYSTAL", 0xC0, 0x10, true, true), &"crystal"],
		["Crystal's title from another publisher", _header("PM_CRYSTAL", 0xC0, 0x10, false), &"smoke"],
		["any other GBC-only game", _header("ZELDA", 0xC0, 0x1B), &"smoke"],
		["a short file", PackedByteArray([1, 2, 3]), &"smoke"],
	]
	for c: Array in presets:
		var got := GbcCartShell.preset_for_header(c[1])
		_ok(got == c[2], "lookup/%s is %s" % [c[0], c[2]], "got %s" % got)
	_ok(GbcCartShell.preset_for_rom("user://missing.gbc") == GbcCartShell.DEFAULT_PRESET
		and GbcCartShell.body_model_for_rom("", &"", "user://missing.gbc") == gb,
		"lookup/no file is the Game Boy body, and smoke if forced clear")
	var every := GbcCartShell.TITLE_SHELLS.values() + [GbcCartShell.DEFAULT_PRESET]
	_ok(every.all(func(id: StringName) -> bool: return _preset(id) != null), "lookup/every answer is a palette preset")


func _test_size() -> void:
	for path: String in BODIES:
		_ok(MediaDimensions.cart_size("gbc", "", path) == MediaDimensions.CART_SIZE_GBC
			and MediaDimensions.cart_size("gb", "", path) == MediaDimensions.CART_SIZE_GBC,
			"size/%s is the Game Boy Color shell's size, from either system" % path.get_file())
	_ok(MediaDimensions.cart_size("gbc") == MediaDimensions.CART_SIZES["gb"]
		and MediaDimensions.cart_size("gbc", "", GbCartShell.BODY) == MediaDimensions.CART_SIZES["gb"],
		"size/the Game Boy body keeps the Game Boy's size")
	_ok(MediaDimensions.cart_size("snes", "", GbcCartShell.BODY_LARGE) == MediaDimensions.CART_SIZES["snes"],
		"size/another system is not sized by it")


func _test_cartridge() -> void:
	var img := Image.create(420, 370, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	DirAccess.make_dir_recursive_absolute(_label_dir())
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))

	var crystal := await _spawn(_write_rom(FIXTURE + ".gbc", _crystal()))
	var small := await _spawn(_write_rom("shrek.gbc", _header("SHREK")))
	var dual := await _spawn(_write_rom("dual.gbc", _header("ZELDA DX", 0x80, 0x03)))
	var from_gb := await _spawn(_write_rom("oracle.gbc", _header("ZELDA", 0xC0, 0x1B)), &"", "", false, "", "gb")
	var silver := await _spawn(_write_rom("silver_kr.gbc", _header("POKEMON_SLVAAXK", 0xC0, 0x10)))
	_ok(_model_path(crystal) == GbcCartShell.BODY_LARGE, "cartridge/Crystal spawns the clear shell on the large board")
	_ok(_model_path(small) == GbcCartShell.BODY_SMALL, "cartridge/a GBC-only game with no save gets the small board")
	_ok(_model_path(from_gb) == GbcCartShell.BODY_LARGE, "cartridge/the same from the gb system")
	_ok(_model_path(dual) == GbCartShell.BODY and _model_path(silver) == GbCartShell.BODY,
		"cartridge/dual-mode and the Korean Silver keep the Game Boy's shell")
	var model := crystal.get_node("CartModel")
	var front := _front(model) as ShaderMaterial
	_ok(front != null and front.get_shader_parameter("tint") == _preset(&"crystal").color
		and front.get_shader_parameter("flake_amount") > 0.0, "cartridge/Crystal is clear blue with glitter")
	var small_front := _front(small.get_node("CartModel")) as ShaderMaterial
	_ok(small_front != null and small_front.get_shader_parameter("tint") == _preset(&"smoke").color,
		"cartridge/any other GBC-only game is smoke")
	var dual_front := dual.get_node("CartModel").find_child("Front_Shell", true, false) as MeshInstance3D
	_ok((dual_front.get_active_material(0) as BaseMaterial3D).albedo_color == _gb_preset(&"black").color,
		"cartridge/a dual-mode game is still black")
	var silver_front := silver.get_node("CartModel").find_child("Front_Shell", true, false) as MeshInstance3D
	_ok(silver_front.get_active_material(0) is ShaderMaterial, "cartridge/the Korean Silver is still silver")
	var label := CartridgeLabel.find_label(model)
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 420,
		"cartridge/the scraped label is painted on the sticker")
	_ok(crystal.get_node_or_null("ModelLabelArt") == null and not (crystal.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	var scale := (model as Node3D).scale
	_ok(absf(scale.x - 1.0) < 0.005 and absf(scale.y - 1.0) < 0.005 and absf(scale.z - 1.0) < 0.005,
		"cartridge/the body is not stretched to MediaDimensions' size", str(scale))
	var box := (crystal.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_ok(box.size.is_equal_approx(MediaDimensions.CART_SIZE_GBC), "cartridge/the body box is the clear shell's size",
		str(box.size))
	var dual_box := (dual.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_ok(dual_box.size.is_equal_approx(MediaDimensions.CART_SIZES["gb"]), "cartridge/the Game Boy's is the Game Boy's")
	for cart in [crystal, small, dual, from_gb, silver]:
		cart.queue_free()
	await get_tree().process_frame


## What the spawn menu's hold sub-menu forces.
func _test_forced() -> void:
	var crystal_rom := _write_rom("forced_crystal.gbc", _crystal())
	var dual_rom := _write_rom("forced_dual.gbc", _header("ZELDA DX", 0x80, 0x03))
	var as_gb := await _spawn(crystal_rom, &"", "", false, GbcCartShell.BODY_GB)
	var dual_crystal := await _spawn(dual_rom, &"crystal")
	var crystal_black := await _spawn(crystal_rom, &"black")
	var crystal_smoke := await _spawn(crystal_rom, &"smoke")
	var mixed := await _spawn(crystal_rom, &"", "#3fa34d")
	var clear_dual := await _spawn(dual_rom, &"", "", false, GbcCartShell.BODY_GBC)
	_ok(_model_path(as_gb) == GbCartShell.BODY, "forced/the Game Boy body forced on Crystal")
	var gb_front := as_gb.get_node("CartModel").find_child("Front_Shell", true, false) as MeshInstance3D
	_ok(_near((gb_front.get_active_material(0) as BaseMaterial3D).albedo_color,
		(gb_front.mesh.surface_get_material(0) as BaseMaterial3D).albedo_color),
		"forced/and it is the Game Boy grey")
	_ok(_model_path(dual_crystal) == GbcCartShell.BODY_LARGE
		and (_front(dual_crystal.get_node("CartModel")) as ShaderMaterial).get_shader_parameter("flake_amount") > 0.0,
		"forced/Crystal's shell makes a dual-mode game a clear glitter cartridge")
	var black_front := crystal_black.get_node("CartModel").find_child("Front_Shell", true, false) as MeshInstance3D
	_ok(_model_path(crystal_black) == GbCartShell.BODY
		and (black_front.get_active_material(0) as BaseMaterial3D).albedo_color == _gb_preset(&"black").color,
		"forced/a Game Boy shell makes Crystal a black Game Boy cartridge")
	_ok((_front(crystal_smoke.get_node("CartModel")) as ShaderMaterial).get_shader_parameter("tint") == _preset(&"smoke").color,
		"forced/smoke beats Crystal's own")
	var mixed_front := _front(mixed.get_node("CartModel"))
	_ok(_model_path(mixed) == GbcCartShell.BODY_LARGE and mixed_front is BaseMaterial3D
		and (mixed_front as BaseMaterial3D).albedo_color == Color("#3fa34d"),
		"forced/a mixed colour is solid on the ROM's own clear body")
	_ok(_model_path(clear_dual) == GbcCartShell.BODY_LARGE
		and (_front(clear_dual.get_node("CartModel")) as ShaderMaterial).get_shader_parameter("tint") == _preset(&"smoke").color,
		"forced/the clear body forced on a dual-mode game is smoke")
	for cart in [as_gb, dual_crystal, crystal_black, crystal_smoke, mixed, clear_dual]:
		cart.queue_free()
	await get_tree().process_frame


## The hold sub-menu of a gb or gbc row: a Body choice, and both shells' palettes.
func _test_menu() -> void:
	var holder := Control.new()
	add_child(holder)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	var sent := {"options": null}
	var spawn := func(options: Dictionary) -> void: sent["options"] = options
	var press_text := func(text: String) -> bool:
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			if (b as Button).text.strip_edges() == text:
				(b as Button).pressed.emit()
				return true
		return false
	for systemid in ["gbc", "gb"]:
		view._show_cart_spawn_options(systemid, "Selftest", spawn)
		var texts := PackedStringArray()
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			texts.append((b as Button).text.strip_edges())
		_ok(texts.has("Game Boy Color (clear)") and texts.has("Game Boy"),
			"menu/%s: a Body choice of the two shells" % systemid)
		_ok(texts.has(_preset(&"crystal").display_name) and texts.has(_preset(&"smoke").display_name)
			and texts.has(_gb_preset(&"gold").display_name), "menu/%s: both palettes' swatches" % systemid)
		view._close_spawn_options_panel()
	view._show_cart_spawn_options("gbc", "Selftest", spawn)
	press_text.call(_preset(&"crystal").display_name)
	press_text.call("+  SPAWN")
	_ok(sent["options"] == {"shell_preset": "crystal"}, "menu/the Crystal swatch forces Crystal", str(sent["options"]))
	view._show_cart_spawn_options("gbc", "Selftest", spawn)
	press_text.call("Game Boy Color (clear)")
	press_text.call("+  SPAWN")
	_ok(sent["options"] == {"body_region": GbcCartShell.BODY_GBC}, "menu/the clear body can be forced",
		str(sent["options"]))
	holder.queue_free()
