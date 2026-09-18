## N64 cartridge self-tests — the regional bodies, the shell colour helper, the
## coloured-cartridge lookup and the spawned cartridge that uses all three.
##
##     "$godot" --headless --path RetroXR res://Tests/n64_cart_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/n64_cart_tests.tscn -- --only=two_tone
##
## Exits 0 when everything passes, 1 otherwise.
##
## How the flake shader LOOKS needs a GPU and lives in
## Tools/models/n64_cart_color_demo.tscn; this suite checks what reaches it.
##
## Writes one label fixture into the player's real nintendo_64 media/label folder
## (MediaDimensions derives the path from the ROM's name) and a scratch
## __n64cart_selftest system folder under the roms root, and removes both at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__n64cart_selftest"
const SCRATCH_SYSTEM := "__n64cart_selftest"

## Every exterior part of the moulding, and the half it belongs to.
const SHELL_PARTS := {
	"Front_Shell": CartridgeColor.Half.FRONT,
	"Rear_Shell": CartridgeColor.Half.BACK,
	"Bottom_Latch_Tongue": CartridgeColor.Half.BACK,
	"Bottom_Latch_Tongue_001": CartridgeColor.Half.BACK,
}
## Parts a shell colour must never reach.
const KEPT_PARTS := ["Label", "Rear_Label", "Connector_PCB", "Contact", "Contact_061",
	"Security_Screw", "Security_Screw_001", "Mouth_Black", "Mouth_Shield"]

## Header keys whose answers the table must give, from the generated table.
const OOT_USA := "EC7011B7-7616D72B"

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[n64cart] TIMEOUT")
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
	if _wants("two_tone"):
		_test_two_tone()
	if _wants("kept"):
		_test_kept()
	if _wants("flake"):
		_test_flake()
	if _wants("switch"):
		_test_switch()
	if _wants("reset"):
		_test_reset()
	if _wants("label"):
		_test_label()
	if _wants("lookup"):
		_test_lookup()
	if _wants("region"):
		await _test_region()
	if _wants("cartridge"):
		await _test_cartridge()
	if _wants("forced"):
		await _test_forced()

	_clear_fixtures()
	await _settle_warm()
	print("[n64cart] ---- %d passed, %d failed ----" % [_pass, _fail])
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
		print("[n64cart] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[n64cart] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


func _body(region: String) -> Node3D:
	var path := N64CartShell.BODY_JPN if region == "jpn" else N64CartShell.BODY_USA
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _part(root: Node, part: String) -> MeshInstance3D:
	return root.find_child(part, true, false) as MeshInstance3D


func _albedo(root: Node, part: String) -> Color:
	var m := _part(root, part).get_active_material(0)
	if m is ShaderMaterial:
		return (m as ShaderMaterial).get_shader_parameter("albedo")
	return (m as BaseMaterial3D).albedo_color


func _preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette().find(id)


## A 64-byte N64 header in .z64 order with this CRC pair and country code.
func _header(crc: String, country: String) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(N64CartShell.HEADER_BYTES)
	for i in 4:
		h[i] = N64SaveDb.MAGIC_Z64[i]
	var hex := crc.replace("-", "")
	for i in 8:
		h[0x10 + i] = hex.substr(i * 2, 2).hex_to_int()
	h[N64CartShell.COUNTRY_AT] = country.unicode_at(0)
	return h


## The same header in .v64 (16-bit swapped) or .n64 (32-bit reversed) order.
func _reorder(h: PackedByteArray, order: String) -> PackedByteArray:
	var out := h.duplicate()
	if order == "v64":
		for i in range(0, out.size(), 2):
			out[i] = h[i + 1]
			out[i + 1] = h[i]
	elif order == "n64":
		for i in range(0, out.size(), 4):
			for j in 4:
				out[i + j] = h[i + 3 - j]
	return out


func _write_rom(file_name: String, header: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(header)
	f.store_buffer(PackedByteArray([0, 0, 0, 0]))
	f.close()
	return path


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system("nintendo_64").path_join("media").path_join("label")


func _clear_fixtures() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	var scratch := RomLibrary.rom_dir_for_system(SCRATCH_SYSTEM)
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)


# ── groups ────────────────────────────────────────────────────────────────────


func _test_resources() -> void:
	for path in [N64CartShell.BODY_USA, N64CartShell.BODY_JPN, CartridgeColor.PALETTE_PATH,
			"res://Shaders/cartridge_flake_plastic.gdshader"]:
		_ok(ResourceLoader.exists(path), "resources/%s exists" % path.get_file())
	var palette := CartridgeColor.get_palette()
	_ok(palette != null and palette.presets.size() > 0, "resources/palette loads")
	var wanted := ["grey", "black", "blue", "yellow", "red", "green", "emerald_green", "pink",
		"beige", "dark_grey", "medium_grey", "gold", "silver", "gold_silver"]
	var missing := wanted.filter(func(id: String) -> bool: return palette.find(id) == null)
	_ok(missing.is_empty(), "resources/palette carries every preset", str(missing))
	var released := palette.with_availability(CartridgeShellPreset.Availability.RELEASED)
	var offered := palette.with_availability(CartridgeShellPreset.Availability.OFFERED_ONLY)
	_ok(released.map(func(p: CartridgeShellPreset) -> String: return String(p.id)).has("blue")
		and offered.map(func(p: CartridgeShellPreset) -> String: return String(p.id)) \
			== ["emerald_green", "pink", "beige", "dark_grey", "medium_grey"],
		"resources/released colours are told apart from ones only offered")
	_ok(palette.find(&"grey").availability == CartridgeShellPreset.Availability.STANDARD,
		"resources/grey is the standard shell")
	var both := palette.find(&"gold_silver")
	_ok(both.is_two_tone() and palette.find(both.front) != null and palette.find(both.back) != null
		and not palette.find(both.front).is_two_tone(), "resources/gold_silver names two single presets")
	var unknown := PackedStringArray()
	for table in [N64CartColorsTable.SHELL_MD5, N64CartColorsTable.SHELL_CRC,
			N64CartColorsTable.AUSTRALIA_MD5, N64CartColorsTable.AUSTRALIA_CRC]:
		for id: String in table.values():
			if palette.find(id) == null and not unknown.has(id):
				unknown.append(id)
	_ok(unknown.is_empty(), "resources/every table colour is a palette preset", str(unknown))


func _test_model() -> void:
	for region in ["usa", "jpn"]:
		var body := _body(region)
		var names := PackedStringArray()
		for part: String in SHELL_PARTS:
			if _part(body, part) == null:
				names.append(part)
		for part: String in KEPT_PARTS:
			if _part(body, part) == null:
				names.append(part)
		_ok(names.is_empty(), "model/%s has every part" % region, str(names))
		body.free()
	_ok(N64CartShell.body_model("jp") == N64CartShell.BODY_JPN, "model/Japan takes the Japanese body")
	for m in ["us", "eu", "au", ""]:
		_ok(N64CartShell.body_model(m) == N64CartShell.BODY_USA, "model/'%s' takes the USA body" % m)


## The shipped bodies carry no mark: no logo mesh or material, and no normal map but
## the plastic grain.
func _test_branding() -> void:
	for region in ["usa", "jpn"]:
		var body := _body(region)
		var marks := PackedStringArray()
		var maps := {}
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if String(mi.name).containsn("nintendo") or String(mi.name).containsn("logo"):
				marks.append(mi.name)
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				if m == null:
					continue
				if m.resource_name.containsn("nintendo") or m.resource_name.containsn("logo"):
					marks.append(m.resource_name)
				if m.normal_texture != null:
					maps[m.normal_texture.resource_path.get_file()] = true
		_ok(marks.is_empty(), "branding/%s has no logo mesh or material" % region, str(marks))
		_ok(maps.keys() == ["n64_cartridge_%s_plastic_normal.png" % region],
			"branding/%s has no normal map but the plastic grain" % region, str(maps.keys()))
		body.free()


## Every triangle of a normal-mapped surface has area in UV space. One with none
## gets no tangent, and on a face whose normal runs along X the fallback tangent is
## parallel to it: the face takes ambient light only, a dark band down the side.
## Tools/glb/fix_unmapped_uvs.py repairs a body that fails this.
func _test_uv() -> void:
	for region in ["usa", "jpn"]:
		var body := _body(region)
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
					if (verts[b] - verts[a]).cross(verts[c] - verts[a]).length_squared() < 1e-24:
						continue
					if absf((uvs[b] - uvs[a]).cross(uvs[c] - uvs[a])) < 1e-12:
						count += 1
				if count > 0:
					unmapped[String(mi.name)] = count
		_ok(unmapped.is_empty(), "uv/%s has no unmapped triangle on a normal-mapped surface" % region,
			str(unmapped))
		body.free()


func _test_surfaces() -> void:
	for region in ["usa", "jpn"]:
		var body := _body(region)
		var halves := {}
		for s in CartridgeColor.shell_surfaces(body):
			halves[String((s["mesh"] as Node).name)] = s["half"]
		_ok(halves == SHELL_PARTS, "surfaces/%s: exactly the moulding, each on its half" % region, str(halves))
		body.free()


func _test_color() -> void:
	var a := _body("usa")
	var b := _body("usa")
	var source := _part(a, "Front_Shell").mesh.surface_get_material(0) as BaseMaterial3D
	var authored := source.albedo_color
	var blue := Color("#24479a")
	_ok(CartridgeColor.apply_color(a, blue) == OK, "color/apply_color succeeds")
	var all_blue := SHELL_PARTS.keys().all(func(p: String) -> bool: return _albedo(a, p) == blue)
	_ok(all_blue, "color/every shell part takes the colour")
	_ok(_albedo(b, "Front_Shell") == authored and _albedo(b, "Rear_Shell") == authored,
		"color/another instance is untouched")
	_ok(source.albedo_color == authored, "color/the imported material is untouched")
	_ok(_part(a, "Front_Shell").get_active_material(0) != _part(a, "Rear_Shell").get_active_material(0),
		"color/each half has a material of its own")
	_ok((_part(a, "Front_Shell").get_active_material(0) as BaseMaterial3D).normal_texture == source.normal_texture
		and (_part(a, "Rear_Shell").get_active_material(0) as BaseMaterial3D).normal_texture
			== source.normal_texture and source.normal_texture != null,
		"color/the grain normal map is carried on both halves")
	_ok(CartridgeColor.apply_preset(b, &"red") == OK and _albedo(b, "Rear_Shell") == _preset(&"red").color
		and _albedo(a, "Rear_Shell") == blue, "color/a preset on one cart leaves the other")
	_ok(CartridgeColor.apply_preset(a, &"no_such_colour") == ERR_DOES_NOT_EXIST
		and _albedo(a, "Front_Shell") == blue, "color/an unknown preset changes nothing")
	var bare := Node3D.new()
	add_child(bare)
	_ok(CartridgeColor.apply_color(bare, blue) == ERR_DOES_NOT_EXIST, "color/a node with no shell is refused")
	bare.free()
	a.free()
	b.free()


func _test_two_tone() -> void:
	for region in ["usa", "jpn"]:
		var cart := _body(region)
		var front := Color.RED
		var back := Color.BLUE
		_ok(CartridgeColor.apply_two_tone(cart, front, back) == OK, "two_tone/%s applies" % region)
		_ok(_albedo(cart, "Front_Shell") == front, "two_tone/%s front shell" % region)
		for part in ["Rear_Shell", "Bottom_Latch_Tongue", "Bottom_Latch_Tongue_001"]:
			_ok(_albedo(cart, part) == back, "two_tone/%s %s matches the rear" % [region, part])
		_ok(CartridgeColor.apply_two_tone(cart, &"black", &"yellow") == OK
			and _albedo(cart, "Front_Shell") == _preset(&"black").color
			and _albedo(cart, "Bottom_Latch_Tongue") == _preset(&"yellow").color,
			"two_tone/%s takes preset ids" % region)
		_ok(CartridgeColor.apply_two_tone(cart, &"gold_silver", Color.RED) == ERR_INVALID_PARAMETER,
			"two_tone/%s refuses a two-tone preset as one half" % region)
		cart.free()


func _test_kept() -> void:
	var cart := _body("usa")
	var before := {}
	for part: String in KEPT_PARTS:
		before[part] = _part(cart, part).get_active_material(0)
	var screw := before["Security_Screw"] as BaseMaterial3D
	var contact := before["Contact"] as BaseMaterial3D
	CartridgeColor.apply_preset(cart, &"gold_silver")
	CartridgeColor.apply_color(cart, Color.GREEN)
	CartridgeColor.apply_two_tone(cart, &"silver", Color.PINK)
	CartridgeColor.reset_to_default(cart)
	CartridgeColor.apply_preset(cart, &"gold")
	var changed := PackedStringArray()
	for part: String in KEPT_PARTS:
		if _part(cart, part).get_active_material(0) != before[part]:
			changed.append(part)
	_ok(changed.is_empty(), "kept/labels, board, contacts and screws keep their materials", str(changed))
	_ok(screw.metallic > 0.5 and contact.metallic > 0.5, "kept/screws and contacts are still metal")
	cart.free()


func _test_flake() -> void:
	var cart := _body("usa")
	var gold := _preset(&"gold")
	_ok(CartridgeColor.apply_preset(cart, &"gold") == OK, "flake/gold applies")
	var front := _part(cart, "Front_Shell").get_active_material(0) as ShaderMaterial
	var rear := _part(cart, "Rear_Shell").get_active_material(0) as ShaderMaterial
	var latch := _part(cart, "Bottom_Latch_Tongue").get_active_material(0) as ShaderMaterial
	_ok(front != null and rear != null and latch != null, "flake/every shell part is on the flake shader")
	var src_front := _part(cart, "Front_Shell").mesh.surface_get_material(0) as BaseMaterial3D
	var src_rear := _part(cart, "Rear_Shell").mesh.surface_get_material(0) as BaseMaterial3D
	_ok(front.get_shader_parameter("texture_normal") == src_front.normal_texture
		and front.get_shader_parameter("normal_enabled") == true, "flake/plastic grain normal map carried")
	_ok(rear.get_shader_parameter("texture_normal") == src_rear.normal_texture
		and rear.get_shader_parameter("normal_enabled") == true, "flake/the rear half carries it too")
	_ok(latch.get_shader_parameter("normal_enabled") == false, "flake/a part with no normal map gets none")
	_ok(front.get_shader_parameter("albedo") == gold.color
		and front.get_shader_parameter("flake_density") == gold.flake_density
		and front.get_shader_parameter("flake_size_mm") == gold.flake_size_mm
		and front.get_shader_parameter("flake_color") == gold.flake_color
		and front.get_shader_parameter("roughness") == gold.roughness,
		"flake/preset values reach the shader")
	_ok(is_equal_approx(front.get_shader_parameter("specular"), src_front.metallic_specular),
		"flake/specular carried")
	_ok(CartridgeColor.apply_preset(cart, &"gold_silver") == OK
		and (_part(cart, "Front_Shell").get_active_material(0) as ShaderMaterial).get_shader_parameter("albedo")
			== gold.color
		and (_part(cart, "Rear_Shell").get_active_material(0) as ShaderMaterial).get_shader_parameter("albedo")
			== _preset(&"silver").color
		and (_part(cart, "Bottom_Latch_Tongue").get_active_material(0) as ShaderMaterial) \
			.get_shader_parameter("albedo") == _preset(&"silver").color,
		"flake/Pokemon Stadium 2: gold front, silver back and latches")
	_ok(_part(cart, "Front_Shell").get_active_material(0) != _part(cart, "Rear_Shell").get_active_material(0),
		"flake/the halves do not share a shader material")
	cart.free()


func _test_switch() -> void:
	var cart := _body("jpn")
	var front := _part(cart, "Front_Shell")
	var source := front.mesh.surface_get_material(0)
	var plain: Material = null
	var flake: Material = null
	var stable := true
	for round_i in 4:
		CartridgeColor.apply_preset(cart, &"blue")
		plain = front.get_active_material(0) if plain == null else plain
		stable = stable and front.get_active_material(0) == plain and _albedo(cart, "Front_Shell") == _preset(&"blue").color
		CartridgeColor.apply_preset(cart, &"silver")
		flake = front.get_active_material(0) if flake == null else flake
		stable = stable and front.get_active_material(0) == flake and flake is ShaderMaterial
		CartridgeColor.apply_color(cart, Color.YELLOW)
		stable = stable and front.get_active_material(0) == plain and _albedo(cart, "Front_Shell") == Color.YELLOW
	_ok(stable, "switch/plain and flake alternate, reusing one material of each")
	var clean := true
	for round_i in 3:
		CartridgeColor.apply_preset(cart, &"gold_silver")
		CartridgeColor.reset_to_default(cart)
		for part: String in SHELL_PARTS:
			var mi := _part(cart, part)
			clean = clean and mi.get_surface_override_material(0) == null \
				and mi.get_active_material(0) == mi.mesh.surface_get_material(0)
		CartridgeColor.apply_preset(cart, &"pink")
		CartridgeColor.reset_to_default(cart)
	_ok(clean and front.get_active_material(0) == source, "switch/every reset lands on the imported materials")
	cart.free()


func _test_reset() -> void:
	var cart := _body("usa")
	var front := _part(cart, "Front_Shell")
	var own := (front.mesh.surface_get_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
	own.albedo_color = Color(0.3, 0.3, 0.3)
	front.set_surface_override_material(0, own)
	CartridgeColor.apply_preset(cart, &"gold")
	CartridgeColor.apply_color(cart, Color.RED)
	_ok(CartridgeColor.reset_to_default(cart) == OK, "reset/succeeds")
	_ok(front.get_surface_override_material(0) == own, "reset/restores an override set before painting")
	_ok(_part(cart, "Rear_Shell").get_surface_override_material(0) == null, "reset/clears the other half")
	_ok(CartridgeColor.reset_to_default(cart) == OK, "reset/twice is harmless")
	cart.free()


func _test_label() -> void:
	var cart := _body("usa")
	var label := CartridgeLabel.find_label(cart)
	var img := Image.create(109, 125, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.9))
	var tex := ImageTexture.create_from_image(img)
	CartridgeColor.apply_preset(cart, &"gold_silver")
	_ok(CartridgeLabel.apply_texture(cart, tex) == OK, "label/applies to a painted cart")
	var painted := _part(cart, "Front_Shell").get_active_material(0)
	_ok((label.get_active_material(0) as BaseMaterial3D).albedo_texture == tex, "label/the art is on the label")
	_ok(_part(cart, "Front_Shell").get_active_material(0) == painted, "label/the shell is untouched by it")
	var labelled := label.get_active_material(0)
	CartridgeColor.apply_preset(cart, &"black")
	CartridgeColor.reset_to_default(cart)
	_ok(label.get_active_material(0) == labelled, "label/recolour and reset leave the label")
	var path := ProjectSettings.globalize_path("user://" + FIXTURE + "_label.png")
	img.save_png(path)
	_ok(CartridgeLabel.apply_file(cart, path) == OK
		and (label.get_active_material(0) as BaseMaterial3D).albedo_texture.get_width() == 109,
		"label/apply_file still loads a PNG")
	_ok(CartridgeLabel.apply_file(cart, path + ".missing") != OK
		and (label.get_active_material(0) as BaseMaterial3D).albedo_texture.get_width() == 109,
		"label/a failed load keeps the previous label")
	DirAccess.remove_absolute(path)
	var other := _body("usa")
	_ok(CartridgeLabel.find_label(other).get_active_material(0) != label.get_active_material(0),
		"label/another instance keeps its own")
	cart.free()
	other.free()


func _test_lookup() -> void:
	var oot_us := _header(OOT_USA, "E")
	_ok(N64CartShell.preset_for_header(oot_us) == &"gold", "lookup/Ocarina of Time USA is gold")
	_ok(N64CartShell.preset_for_header(_header(OOT_USA, "J")) == &"grey",
		"lookup/the same CRC pair from Japan is grey")
	for order in ["v64", "n64"]:
		_ok(N64CartShell.preset_for_header(_reorder(oot_us, order)) == &"gold",
			"lookup/a %s dump reads the same" % order)
		_ok(N64CartShell.header_market(_reorder(_header(OOT_USA, "J"), order)) == "jp",
			"lookup/a %s dump's country byte" % order)
	_ok(N64CartShell.preset_for_header(PackedByteArray([1, 2, 3])) == &"grey",
		"lookup/a short header is grey")
	# The generated table's own rows, spot-checked by title in the generator's --check.
	var au_key := ""
	for key: String in N64CartColorsTable.AUSTRALIA_CRC:
		if not N64CartColorsTable.SHELL_CRC.has(key):
			au_key = key
			break
	_ok(not au_key.is_empty(), "lookup/the table has a PAL release coloured only in Australia")
	var crc := au_key.get_slice(":", 0)
	var au := str(N64CartColorsTable.AUSTRALIA_CRC.get(au_key, ""))
	_ok(N64CartShell.preset_for_header(_header(crc, "P")) == &"grey", "lookup/that release is grey in Europe")
	_ok(N64CartShell.preset_for_header(_header(crc, "U"), "au") == StringName(au),
		"lookup/and %s in Australia" % au)
	_ok(N64CartShell.preset_for_header(_header(crc, "P"), "au") == StringName(au),
		"lookup/a scraped Australian region takes it too")
	var md5 := ""
	for key: String in N64CartColorsTable.SHELL_MD5:
		if N64CartColorsTable.SHELL_MD5[key] == "gold_silver":
			md5 = key
			break
	_ok(N64CartShell.preset_for_md5(md5.to_upper()) == &"gold_silver", "lookup/by MD5, either case")
	_ok(N64CartShell.preset_for_md5("00000000000000000000000000000000") == &"grey", "lookup/an unknown MD5 is grey")
	var rom := _write_rom("oot.v64", _reorder(oot_us, "v64"))
	_ok(N64CartShell.preset_for_rom(rom) == &"gold", "lookup/a file on disk")
	_ok(N64CartShell.preset_for_rom(rom + ".missing") == &"grey", "lookup/a missing file is grey")


func _test_region() -> void:
	for pair in [["USA", "us"], ["Japan", "jp"], ["europe", "eu"], [" Australia ", "au"], ["Germany", "eu"],
			["World", ""], ["", ""]]:
		_ok(N64CartShell.market_of_region(pair[0]) == pair[1], "region/'%s' -> '%s'" % pair)
	var dir := RomLibrary.rom_dir_for_system(SCRATCH_SYSTEM)
	DirAccess.make_dir_recursive_absolute(dir)
	var rom := dir.path_join("Game (USA).z64")
	var f := FileAccess.open(rom, FileAccess.WRITE)
	f.store_buffer(_header(OOT_USA, "E"))
	f.close()
	_ok(N64CartShell.market(SCRATCH_SYSTEM, rom) == "us", "region/no gamelist: the header's country")
	var gl := FileAccess.open(dir.path_join("gamelist.json"), FileAccess.WRITE)
	gl.store_string(JSON.stringify({"games": [{"game_id": "ss:1", "name": "Game",
		"roms": [{"path": "./Game (USA).z64", "region": "Japan"}]}]}))
	gl.close()
	_ok(N64CartShell.scraped_region(SCRATCH_SYSTEM, rom) == "Japan", "region/reads the scraped region")
	_ok(N64CartShell.market(SCRATCH_SYSTEM, rom) == "jp", "region/the scraper outranks the header")
	# The stamp is a whole second; a rewrite within it would read the cached list.
	await get_tree().create_timer(1.1).timeout
	gl = FileAccess.open(dir.path_join("gamelist.json"), FileAccess.WRITE)
	gl.store_string(JSON.stringify({"games": [{"game_id": "ss:1", "name": "Game",
		"roms": [{"path": "./Game (USA).z64", "region": "Australia"}]}]}))
	gl.close()
	_ok(N64CartShell.market(SCRATCH_SYSTEM, rom) == "au", "region/a rewritten gamelist is read again")


func _test_cartridge() -> void:
	var img := Image.create(522, 600, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	DirAccess.make_dir_recursive_absolute(_label_dir())
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))

	var usa := await _spawn(_write_rom(FIXTURE + ".z64", _header(OOT_USA, "E")))
	var jpn := await _spawn(_write_rom("japan.z64", _header(OOT_USA, "J")))
	var usa_model := usa.get_node_or_null("CartModel")
	var jpn_model := jpn.get_node_or_null("CartModel")
	_ok(usa_model != null and usa_model.scene_file_path == N64CartShell.BODY_USA,
		"cartridge/a USA ROM spawns the USA body")
	_ok(jpn_model != null and jpn_model.scene_file_path == N64CartShell.BODY_JPN,
		"cartridge/a Japanese ROM spawns the Japanese body")
	_ok(usa_model != null and (_part(usa_model, "Front_Shell").get_active_material(0) as ShaderMaterial) != null
		and (_part(usa_model, "Front_Shell").get_active_material(0) as ShaderMaterial) \
			.get_shader_parameter("albedo") == _preset(&"gold").color,
		"cartridge/Ocarina of Time USA spawns gold")
	_ok(jpn_model != null and _albedo(jpn_model, "Front_Shell") == _preset(&"grey").color,
		"cartridge/its Japanese release spawns grey")
	var label := CartridgeLabel.find_label(usa_model) if usa_model != null else null
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 522,
		"cartridge/the scraped label is painted on the front sticker")
	_ok(usa.get_node_or_null("ModelLabelArt") == null and not (usa.get_node("GameLabel") as Label3D).visible,
		"cartridge/no quad and no title over the art")
	var jpn_label := CartridgeLabel.find_label(jpn_model) if jpn_model != null else null
	_ok(jpn_label != null and jpn_label.get_surface_override_material(0) == null
		and (jpn.get_node("GameLabel") as Label3D).visible, "cartridge/no art: the blank sticker and the title")
	var screw := _part(usa_model, "Security_Screw").get_active_material(0) as BaseMaterial3D
	var contact := _part(usa_model, "Contact").get_active_material(0) as BaseMaterial3D
	_ok(screw.metallic > 0.5 and contact.metallic > 0.5, "cartridge/screws and contacts keep their metal")
	var scale := (usa_model as Node3D).scale
	_ok(absf(scale.x - 1.0) < 0.005 and absf(scale.y - 1.0) < 0.005 and absf(scale.z - 1.0) < 0.005,
		"cartridge/the body is not stretched to MediaDimensions' size", str(scale))
	usa.queue_free()
	jpn.queue_free()
	await get_tree().process_frame


## What the spawn menu's hold sub-menu forces: a shell and a body that are not
## the ROM's own. Ocarina of Time USA is the fixture because its own answer is
## gold on a USA body, so neither forced value can pass by being the default.
func _test_forced() -> void:
	var rom := _write_rom("forced.z64", _header(OOT_USA, "E"))
	var blue := await _spawn(rom, &"blue")
	var blue_model := blue.get_node_or_null("CartModel")
	_ok(blue_model != null and _albedo(blue_model, "Front_Shell") == _preset(&"blue").color,
		"forced/a forced shell beats the one the ROM shipped in")
	_ok(blue_model != null and blue_model.scene_file_path == N64CartShell.BODY_USA,
		"forced/and leaves the body the ROM's own")

	var unknown := await _spawn(rom, &"no_such_shell")
	var unknown_model := unknown.get_node_or_null("CartModel")
	var flake := _part(unknown_model, "Front_Shell").get_active_material(0) as ShaderMaterial 		if unknown_model != null else null
	_ok(flake != null and flake.get_shader_parameter("albedo") == _preset(&"gold").color,
		"forced/a shell the palette does not hold falls back to the ROM's")

	var jpn := await _spawn(rom, &"", N64CartShell.REGION_JPN)
	var jpn_model := jpn.get_node_or_null("CartModel")
	_ok(jpn_model != null and jpn_model.scene_file_path == N64CartShell.BODY_JPN,
		"forced/a forced Japanese body on a USA ROM")
	var jpn_flake := _part(jpn_model, "Front_Shell").get_active_material(0) as ShaderMaterial 		if jpn_model != null else null
	_ok(jpn_flake != null and jpn_flake.get_shader_parameter("albedo") == _preset(&"gold").color,
		"forced/keeps the colour of the market the ROM really has")
	var usa := await _spawn(_write_rom("forced_j.z64", _header(OOT_USA, "J")), &"",
		N64CartShell.REGION_USA)
	var usa_model := usa.get_node_or_null("CartModel")
	_ok(usa_model != null and usa_model.scene_file_path == N64CartShell.BODY_USA,
		"forced/a forced USA body on a Japanese ROM")

	var persistence := ScenePersistence.new()
	var both := await _spawn(rom, &"red", N64CartShell.REGION_JPN)
	var entry: Dictionary = persistence._serialize_node(both, 1, {})
	_ok(entry.get("shell_preset", "") == "red" and entry.get("body_region", "") == "jpn",
		"forced/both are written to the save entry", str(entry))
	_ok(ScenePersistence._entry_validation_error(entry, {}).is_empty(),
		"forced/and the entry validates", ScenePersistence._entry_validation_error(entry, {}))
	var back := persistence._deserialize_object(entry) as RetroCartridge
	_ok(back != null and back.shell_preset == &"red" and back.body_region == "jpn",
		"forced/and read back before the cartridge enters the tree")
	if back != null:
		back.freeze = true
		add_child(back)
		for i in 4:
			await get_tree().physics_frame
		var back_model := back.get_node_or_null("CartModel")
		_ok(back_model != null and back_model.scene_file_path == N64CartShell.BODY_JPN
			and _albedo(back_model, "Front_Shell") == _preset(&"red").color,
			"forced/a restored cartridge wears them")
		back.queue_free()
	var auto := await _spawn(rom)
	var auto_entry: Dictionary = persistence._serialize_node(auto, 3, {})
	_ok(not auto_entry.has("shell_preset") and not auto_entry.has("body_region"),
		"forced/an untouched cartridge writes neither key")
	for cart: Node in [blue, unknown, jpn, usa, both, auto]:
		cart.queue_free()
	await get_tree().process_frame


func _spawn(rom: String, shell: StringName = &"", body := "") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "nintendo_64"
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.body_region = body
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart
