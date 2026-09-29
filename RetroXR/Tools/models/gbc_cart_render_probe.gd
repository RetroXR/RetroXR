## Game Boy Color cartridge probe: fits the clear shells' colours to photographs,
## and renders the carts the spawn menu makes.
##
##     "$godot" --path RetroXR --resolution 1600x900 --position 20,20 \
##         res://Tools/models/gbc_cart_render_probe.tscn -- --out=<dir> \
##         [--fit] [--smoke-label=<png>] [--crystal-label=<png>] \
##         [--smoke=r,g,b[,opacity,frost]] [--crystal=r,g,b[,opacity,frost]]
##
## Windowed: the headless renderer returns a blank image at the right size.
##
## --fit lays each clear preset on the large board, label up, on white under flat
## light, and renders it from straight above with an orthographic camera at 10 px/mm
## (near/far 0.1-0.3 m, or the recess floor wins the depth test and tints the
## label). It prints the per-channel median of the shell outside the label recess,
## in linear light, divided by the median of the label's pale side strips: they are
## the exposure and white-balance reference, so each preset wears the scraped label
## of the cartridge photographed (--smoke-label, --crystal-label). The same numbers
## from the photo, rectified to the same 57 x 65 mm frame, are the target;
## --smoke/--crystal try a colour (and opacity and frost) without editing the
## palette. See docs/dev/gb-cartridges.md.
##
## Without --fit it renders smoke on both boards, Crystal, Crystal forced onto a
## dual-mode ROM, a mixed metal-flake colour on the clear body, and a dual-mode game
## in the Game Boy's black shell, front, back and close.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__gbccart_render"
const PX_PER_MM := 10.0

var out_dir := ""
var _created_dirs: Array[String] = []
var _labels: Array[String] = []
var _overrides := {}


func _ready() -> void:
	out_dir = OS.get_user_data_dir().path_join(FIXTURE)
	var fit := false
	var label_src := {}
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
		elif a == "--fit":
			fit = true
		elif a.begins_with("--smoke-label="):
			label_src["smoke"] = a.trim_prefix("--smoke-label=").replace("\\", "/")
		elif a.begins_with("--crystal-label="):
			label_src["crystal"] = a.trim_prefix("--crystal-label=").replace("\\", "/")
		elif a.begins_with("--smoke=") or a.begins_with("--crystal="):
			var kv := a.trim_prefix("--").split("=")
			_overrides[StringName(kv[0])] = Array(kv[1].split(",")).map(func(v: String) -> float: return float(v))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[gbcrender] TIMEOUT")
		_cleanup()
		get_tree().quit(1))
	var palette := CartridgeColor.get_palette(GbcCartShell.PALETTE)
	for id: StringName in _overrides:
		var v: Array = _overrides[id]
		var preset := palette.find(id)
		preset.color = Color(v[0], v[1], v[2])
		if v.size() >= 5:
			preset.opacity = v[3]
			preset.frost = v[4]
		print("[gbcrender] %s colour %s opacity %.2f frost %.2f" % [id, preset.color, preset.opacity, preset.frost])
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	if fit:
		await _fit(label_src)
	else:
		await _review(label_src)
	_cleanup()
	get_tree().quit(0)


# ── fit ──────────────────────────────────────────────────────────────────────


func _fit(label_src: Dictionary) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.5, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	# Flat light, tilted so its mirror image in the glossy shell misses the camera.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-65, 20, 0)
	key.light_energy = 0.35
	add_child(key)
	var carts := [
		["smoke", _header("ZELDA", 0xC0, 0x1B, true), 0.0],
		["crystal", _header("PM_CRYSTAL", 0xC0, 0x10, true), 0.2],
	]
	var spawned: Array[RetroCartridge] = []
	for c: Array in carts:
		_label_for(str(c[0]) + ".gbc", label_src.get(c[0], ""))
		var cart := _spawn(str(c[0]) + ".gbc", c[1])
		# Label up: cart +Z to world +Y, its top (+Y) to world -Z.
		cart.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(c[2], 0, 0))
		spawned.append(cart)
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.15, 0.15)
		floor_mesh.mesh = plane
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.9, 0.9, 0.9)
		white.roughness = 0.9
		floor_mesh.material_override = white
		add_child(floor_mesh)
		floor_mesh.global_position = Vector3(c[2], -MediaDimensions.CART_SIZE_GBC.z * 0.5 - 0.0002, 0)
	await _settle()
	var sv := _viewport(Vector2i(570, 650))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = 0.065
	cam.near = 0.1
	cam.far = 0.3
	sv.add_child(cam)
	for i in 60:
		await get_tree().process_frame
	for i in carts.size():
		var c: Array = carts[i]
		cam.look_at_from_position(Vector3(c[2], 0.2, 0), Vector3(c[2], 0, 0), Vector3.FORWARD)
		cam.current = true
		for f in 10:
			await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out_dir.path_join("fit_%s.png" % c[0]))
		var shell := _median(img, true)
		var strips := _median(img, false)
		print("[gbcrender] fit %s shell %s strips %s ratio (%.4f, %.4f, %.4f)" % [c[0], shell, strips,
			shell.r / strips.r, shell.g / strips.g, shell.b / strips.b])


## Per-channel median, in linear light, of the shell outside the label recess (1 mm
## clear of it and 2 mm in from the outline), or of the label's side strips.
func _median(img: Image, shell: bool) -> Color:
	var chans: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for py in img.get_height():
		var y := 32.5 - (py + 0.5) / PX_PER_MM
		for px in img.get_width():
			var x := (px + 0.5) / PX_PER_MM - 28.5
			var in_recess := absf(x) <= 23.0 and absf(y + 8.0) <= 20.55
			var take := false
			if shell:
				take = not in_recess and absf(x) <= 26.5 and absf(y) <= 30.5
			else:
				take = absf(x) >= 17.8 and absf(x) <= 20.2 and absf(y + 8.0) <= 14.0
			if take:
				var c := img.get_pixel(px, py).srgb_to_linear()
				chans[0].append(c.r)
				chans[1].append(c.g)
				chans[2].append(c.b)
	var out := Color()
	for k in 3:
		var a := chans[k]
		a.sort()
		out[k] = a[a.size() / 2] if a.size() > 0 else 0.0
	return out


# ── review ───────────────────────────────────────────────────────────────────


func _review(label_src: Dictionary) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.6
	add_child(fill)
	# [file, header, forced preset, mixed colour, flake]
	var carts := [
		["smoke_small.gbc", _header("SHREK", 0xC0, 0x19, false), "", "", false],
		["smoke.gbc", _header("ZELDA", 0xC0, 0x1B, true), "", "", false],
		["crystal.gbc", _header("PM_CRYSTAL", 0xC0, 0x10, true), "", "", false],
		["forced.gbc", _header("ZELDA DX", 0x80, 0x03, true), "crystal", "", false],
		["flake.gbc", _header("SHREK", 0xC0, 0x19, false), "", "#c0303a", true],
		["dual.gbc", _header("ZELDA DX", 0x80, 0x03, true), "", "", false],
	]
	for i in carts.size():
		var c: Array = carts[i]
		var key_name := "smoke" if str(c[0]) == "smoke.gbc" else ("crystal" if str(c[0]) == "crystal.gbc" else "")
		if not key_name.is_empty():
			_label_for(str(c[0]), label_src.get(key_name, ""))
		var cart := _spawn(str(c[0]), c[1], StringName(c[2]), str(c[3]), bool(c[4]))
		cart.global_position = Vector3((i - 2.5) * 0.075, 0.0, 0.0)
		var model := cart.get_node_or_null("CartModel")
		print("[gbcrender] %s: %s" % [c[0], model.scene_file_path.get_file() if model != null else "no model"])
	await _settle()
	var sv := _viewport(Vector2i(1600, 900))
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.01
	sv.add_child(cam)
	for i in 60:
		await get_tree().process_frame
	await _shot(sv, cam, Vector3(0, 0.02, 0.85), Vector3.ZERO, "front.png")
	await _shot(sv, cam, Vector3(0, 0.02, -0.85), Vector3.ZERO, "back.png")
	await _shot(sv, cam, Vector3(-0.02, 0.07, 0.19), Vector3(0.0375, 0.0, 0.0), "crystal_close.png")
	await _shot(sv, cam, Vector3(-0.10, 0.07, 0.19), Vector3(-0.0375, 0.0, 0.0), "smoke_close.png")
	await _shot(sv, cam, Vector3(0.02, 0.07, -0.19), Vector3(0.0375, 0.0, 0.0), "crystal_back_close.png")


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, file: String) -> void:
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join(file))
	print("[gbcrender] wrote %s" % out_dir.path_join(file))


# ── shared ───────────────────────────────────────────────────────────────────


## A SubViewport of the same world, as genesis_render_probe does: the root
## viewport carries the boot overlay.
func _viewport(size: Vector2i) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = size
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	return sv


func _settle() -> void:
	for i in 6:
		await get_tree().physics_frame


func _spawn(file_name: String, header: PackedByteArray, preset := &"", color := "", flake := false) -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = GbcCartShell.PALETTE
	cart.rom_path = _write_rom(FIXTURE + "_" + file_name, header)
	cart.shell_preset = preset
	cart.shell_color = color
	cart.shell_flake = flake
	cart.game_label = file_name.get_basename()
	cart.freeze = true
	add_child(cart)
	return cart


## A 0x150-byte header: `title`, CGB flag, cartridge type, and Nintendo's licensee
## (new code "01") or none.
func _header(title: String, cgb: int, cart_type: int, nintendo: bool) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(GbCartShell.HEADER_BYTES)
	for i in mini(title.length(), 11):
		h[GbCartShell.TITLE_AT + i] = title.unicode_at(i)
	h[GbCartShell.CGB_AT] = cgb
	h[GbcCartShell.CART_TYPE_AT] = cart_type
	h[GbCartShell.DESTINATION_AT] = 0x01
	if nintendo:
		h[GbCartShell.OLD_LICENSEE_AT] = GbCartShell.OLD_LICENSEE_USE_NEW
		h[GbCartShell.NEW_LICENSEE_AT] = 0x30
		h[GbCartShell.NEW_LICENSEE_AT + 1] = 0x31
	return h


func _write_rom(file_name: String, bytes: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


## Copies `src` in as the scraped label of fixture ROM `file_name`, for this run.
func _label_for(file_name: String, src: String) -> void:
	if src.is_empty():
		return
	var img := Image.load_from_file(src)
	if img == null:
		push_error("[gbcrender] cannot read %s" % src)
		return
	_make_label_dir()
	var path := _label_dir().path_join(FIXTURE + "_" + file_name.get_basename() + ".png")
	img.save_png(path)
	_labels.append(path)


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(GbcCartShell.PALETTE).path_join("media").path_join("label")


func _make_label_dir() -> void:
	var missing: Array[String] = []
	var d := _label_dir()
	while not DirAccess.dir_exists_absolute(d):
		missing.push_front(d)
		d = d.get_base_dir()
	DirAccess.make_dir_recursive_absolute(_label_dir())
	missing.reverse()
	_created_dirs.append_array(missing)


func _cleanup() -> void:
	for p in _labels:
		DirAccess.remove_absolute(p)
	_labels.clear()
	for d in _created_dirs:
		DirAccess.remove_absolute(d)
	_created_dirs.clear()
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gbc"):
				DirAccess.remove_absolute(dir.path_join(f))
