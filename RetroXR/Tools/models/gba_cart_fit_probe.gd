## Fits the Game Boy Advance clear Pokemon shells to their photographs: each preset
## on its cartridge, lying label up on white under flat light, ortho from above
## (near/far 0.1-0.3 m), and the per-channel median sRGB colour of the shell outside
## the label (the board showing through), printed beside the photo's (TARGETS).
##
##     "$godot" --path RetroXR --resolution 800x600 --position 20,20 ##         res://Tools/models/gba_cart_fit_probe.tscn -- [--ruby=r,g,b ...]
##
## Windowed: the headless renderer returns a blank image. `--<preset>=r,g,b` tries
## a colour without editing the palette; scale it until the median meets the
## target, then write it into Resources/gba_cartridge_shells.tres. Re-run whenever
## the cartridge's interior or the clear shaders change (see gba-cartridges.md).
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__gbacartfit"
var out_dir := OS.get_user_data_dir().path_join(FIXTURE)
## Photographed shell colour, sRGB: Ruby from a flat scan, the rest from photos.
const TARGETS := {"ruby": "653634", "sapphire": "2c3aa6", "emerald": "2cbf3c",
	"fire_red": "e45a4c", "leaf_green": "4d9a5c"}
const GAMES := [["ruby", "AXVE"], ["sapphire", "AXPE"], ["emerald", "BPEE"], ["fire_red", "BPRE"], ["leaf_green", "BPGE"]]


func _ready() -> void:
	var palette := CartridgeColor.get_palette("gba")
	for arg in OS.get_cmdline_user_args():
		var kv := str(arg).trim_prefix("--").split("=")
		if kv.size() == 2 and palette.find(StringName(kv[0])) != null:
			var c := kv[1].split(",")
			palette.find(StringName(kv[0])).color = Color(float(c[0]), float(c[1]), float(c[2]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(150.0).timeout.connect(func() -> void: get_tree().quit(1))
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
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
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-65, 20, 0)
	key.light_energy = 0.35
	add_child(key)
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var carts: Array[RetroCartridge] = []
	for i in GAMES.size():
		var h := PackedByteArray()
		h.resize(0xC0)
		var code: String = GAMES[i][1]
		for k in 4:
			h[0xAC + k] = code.unicode_at(k)
		h[0xB0] = 0x30
		h[0xB1] = 0x31
		var rom := dir.path_join("%s.gba" % GAMES[i][0])
		var f := FileAccess.open(rom, FileAccess.WRITE)
		f.store_buffer(h)
		f.close()
		var cart := CART_SCENE.instantiate() as RetroCartridge
		cart.systemid = "gba"
		cart.rom_path = rom
		cart.freeze = true
		add_child(cart)
		cart.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(i * 0.1, 0, 0))
		carts.append(cart)
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.09, 0.09)
		floor_mesh.mesh = plane
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.9, 0.9, 0.9)
		floor_mesh.material_override = white
		add_child(floor_mesh)
		floor_mesh.global_position = Vector3(i * 0.1, -0.0047, 0)
	for i in 6:
		await get_tree().physics_frame
	var sv := SubViewport.new()
	sv.size = Vector2i(640, 640)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.064
	cam.near = 0.1
	cam.far = 0.3
	sv.add_child(cam)
	for i in 60:
		await get_tree().process_frame
	for i in GAMES.size():
		var cart := carts[i]
		var shells: Array[ShaderMaterial] = []
		for n in cart.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as ShaderMaterial
				if m != null and m.shader == CartridgeColor.CLEAR_SHADER:
					shells.append(m)
		var label := CartridgeLabel.find_label(cart)
		cam.look_at_from_position(Vector3(i * 0.1, 0.2, 0), Vector3(i * 0.1, 0, 0), Vector3.FORWARD)
		cam.current = true
		var line := "[gbacartfit] %s target #%s" % [GAMES[i][0], TARGETS[GAMES[i][0]]]
		for k in 8:
			await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out_dir.path_join("%s.png" % GAMES[i][0]))
		var med := _median(img, cam, cart, label)
		line += " median #%s %f %f %f" % [med.to_html(false), med.r, med.g, med.b]
		print(line)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	get_tree().quit(0)


## Median sRGB colour of the cart's pixels that are neither floor nor label: inside
## the body's screen rect, 2 mm in, outside the label's rect grown by 1 mm.
func _median(img: Image, cam: Camera3D, cart: RetroCartridge, label: MeshInstance3D) -> Color:
	var body := _rect(cam, cart, null).grow(-0.002 * 10000.0)
	var lab := _rect(cam, cart, label).grow(0.001 * 10000.0)
	var ch: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for y in range(int(body.position.y), int(body.end.y)):
		for x in range(int(body.position.x), int(body.end.x)):
			if lab.has_point(Vector2(x, y)):
				continue
			var c := img.get_pixel(x, y)
			ch[0].append(c.r)
			ch[1].append(c.g)
			ch[2].append(c.b)
	var out := Color()
	for k in 3:
		ch[k].sort()
		out[k] = ch[k][ch[k].size() / 2]
	return out


## Screen rect (pixels, 10 px per mm) of the cart's model or of one mesh.
func _rect(cam: Camera3D, cart: RetroCartridge, only: MeshInstance3D) -> Rect2:
	var r := Rect2()
	var first := true
	var meshes: Array = [only] if only != null else cart.get_node("CartModel").find_children("*", "MeshInstance3D", true, false)
	for n in meshes:
		var mi := n as MeshInstance3D
		var ab := mi.get_aabb()
		for k in 8:
			var p := cam.unproject_position(mi.global_transform * ab.get_endpoint(k))
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r
