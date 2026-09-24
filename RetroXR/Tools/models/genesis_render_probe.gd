## Renders the Genesis (Model 2) with a cartridge seated and both pads plugged in,
## and prints the numbers a picture cannot settle.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/genesis_render_probe.tscn -- --out=<dir> [--room]
##
## Windowed: the headless renderer returns a blank image at the right size.
##
## `--room` stands it on the bedroom desk under the room's own lighting instead of
## on a bare desk in a flat grey studio. The studio's grey reflections make a
## black shell read mid-grey, so judge its COLOUR only from the room.
##
## `--buttons --rom=<path>` films POWER and RESET doing their jobs: a set behind the
## console, the ROM in a seated cartridge, then POWER, RESET and POWER again,
## pressed through VRButton.pointer_event — the desktop reticle's path into the
## same button_pressed signal a finger fires. Each frame is the wide shot beside a
## close-up of the caps, written to <out>/frames/; the machine's own state after
## every press is printed. Needs the Genesis core installed; runs a real core, so
## one run per process.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const AV_LEAD_SCENE := preload("res://Scenes/Objects/system_models/genesis/genesis_av_cable.tscn")
const ROOM_SCENE := "res://Scenes/BedroomScene.tscn"
## Straight above the desk the bedroom probe frames; the console lands on
## whatever a ray down from here meets first.
const DESK_ABOVE := Vector3(-1.50, 1.60, -1.80)
## What QualityManager gives the ceiling light at run time (bedroom_probe.gd).
const GLOBE_ENERGY := 0.6

var out_dir := ""
var _desk: Node3D = null


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	# Made here for every mode: save_png into a folder that does not exist fails
	# without a word, and each shot still logs that it was written.
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[mdrender] TIMEOUT")
		get_tree().quit(1))
	if OS.get_cmdline_user_args().has("--buttons"):
		_run_buttons()
	elif OS.get_cmdline_user_args().has("--insert"):
		_run_insert()
	else:
		_run()


func _wait(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _run() -> void:
	var in_room := OS.get_cmdline_user_args().has("--room")
	var base := Vector3.ZERO
	if in_room:
		add_child(load(ROOM_SCENE).instantiate())
		for i in range(30):
			await get_tree().process_frame
		var globe := get_tree().root.find_child("FanGlobeLight", true, false) as OmniLight3D
		if globe != null:
			globe.light_energy = GLOBE_ENERGY
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(DESK_ABOVE, DESK_ABOVE + Vector3.DOWN * 1.5))
		base = hit.get("position", DESK_ABOVE + Vector3.DOWN * 0.85)
		print("[mdrender] desk top at %s" % base)
	else:
		_build_studio()

	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "genesis"
	add_child(sys)
	sys.global_position = base
	sys.freeze = true
	await _wait(10)
	var model: Node = sys._model
	print("[mdrender] model %s, own shell %s" % [model.get_script().get_global_name(),
		model.has_baked_shell()])

	var sv := SubViewport.new()
	sv.size = Vector2i(1400, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.02
	sv.add_child(cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	# Long enough for every shader the first shot needs to have compiled; shot
	# straight away, the first two frames came out black.
	for i in range(60):
		await get_tree().process_frame

	var b := sys.global_transform.basis.orthonormalized()
	var up := b.y
	var mid := sys.global_position + up * 0.025
	# Empty first: the flaps shut, and all three marks painted out.
	await _shot(sv, cam, mid + b.z * 0.40 + up * 0.28 - b.x * 0.14, mid, up, "genesis_front_empty.png")
	await _shot(sv, cam, mid + up * 0.50 + b.z * 0.06, mid, -b.z, "genesis_top_empty.png")
	if not in_room:
		# From underneath, where the desk would be in the way: the sticker's SEGA
		# logo is the third mark this model had to lose.
		_desk.visible = false
		await _shot(sv, cam, mid - up * 0.45 + b.z * 0.02, mid, b.z, "genesis_bottom.png")
		_desk.visible = true

	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "genesis"
	cart.game_label = "PROBE"
	add_child(cart)
	cart.global_position = base + Vector3(0.4, 0.3, 0)
	await _wait(10)
	sys.restore_cartridge(cart)
	await _wait(10)
	model.play_cartridge_insert(cart, null)
	await _wait(30)
	var cb := sys.global_transform.affine_inverse() * cart.global_transform
	print("[mdrender] cart origin %s, up %s, label faces %s" % [cb.origin, cb.basis.y, cb.basis.z])
	print("[mdrender] cart bottom y %.4f (connector top 0.028), centre z %.4f (slot -0.0319)"
		% [cb.origin.y - MediaDimensions.cart_size("genesis").y * 0.5, cb.origin.z])
	for flap in ["SlotFlapFront", "SlotFlapRear"]:
		var f := model.find_child(flap, true, false) as Node3D
		print("[mdrender] %s rotation.x %.1f deg" % [flap, rad_to_deg(f.rotation.x) if f else NAN])

	var pads: Array = []
	for i in range(2):
		var pad := PAD_SCENE.instantiate()
		pad.set("systemid", "genesis")
		add_child(pad)
		pad.global_position = base + Vector3(-0.15 + 0.3 * i, 0.02, 0.35)
		pads.append(pad)
	await _wait(4)
	for i in range(2):
		pads[i].restore_port_connection(sys, i)
	await _wait(240)
	for i in range(2):
		var zone: Node3D = sys._port_zones[i]
		var plug = pads[i].get("_cable_plug")
		print("[mdrender] port %d at %s, zone +Z %s, plug seated %s" % [i + 1, zone.position,
			zone.transform.basis.z, is_instance_valid(plug) and zone.get("picked_up_object") == plug])
	print("[mdrender] power button at %s, reset at %s" % [
		sys.to_local(sys._power_button.global_position), sys.to_local(sys._reset_button.global_position)])

	# The A/V lead: a loose object now, not a captive cord. Photographed lying on the
	# desk first, then with its mini-DIN seated in the A/V OUT.
	var multi := sys.find_child("AvMultiOut", true, false) as RcaPort
	print("[mdrender] A/V socket %s (%s), captive lead %s" % [multi != null,
		multi.get_script().get_global_name() if multi != null else "-",
		sys._channels[0].plug != null])
	var lead := AV_LEAD_SCENE.instantiate() as Node3D
	add_child(lead)
	lead.global_position = base + Vector3(0.0, 0.03, -0.30)
	await _wait(200)
	# The bare plug mesh, upright and head-on, high above the desk with its own light:
	# the one framing where the pin layout can be checked against the mini-DIN-9
	# drawing (3-4-2, pin 1 lower left, keyway at the TOP) without the lead's roll
	# turning the face.
	var bare := MeshInstance3D.new()
	bare.mesh = load("res://Scenes/Objects/system_models/genesis/genesis_av_plug.res")
	add_child(bare)
	bare.global_position = Vector3(0.0, 2.0, 0.0)
	var key := OmniLight3D.new()
	add_child(key)
	key.global_position = bare.global_position + Vector3(0.02, 0.03, 0.06)
	key.omni_range = 0.3
	key.light_energy = 0.12
	await _shot(sv, cam, bare.global_position + Vector3(0.0, 0.0, 0.028),
		bare.global_position + Vector3(0.0, 0.0, 0.005), Vector3.UP, "genesis_av_face_upright.png")
	bare.queue_free()
	key.queue_free()

	# Face-on down the connector's own +Z, so the shield and its nine pins read the
	# way the lead is photographed; then from the side for the head and boot.
	var loose := lead.get_node("PlugA0") as Node3D
	var face := loose.global_transform.basis.z.normalized()
	var side := loose.global_transform.basis.x.normalized()
	await _shot(sv, cam, loose.global_position + face * 0.045 + Vector3.UP * 0.012,
		loose.global_position, Vector3.UP, "genesis_av_face.png")
	await _shot(sv, cam, loose.global_position + side * 0.07 + face * 0.02 + Vector3.UP * 0.03,
		loose.global_position - face * 0.012, Vector3.UP, "genesis_av_loose.png")
	if multi != null:
		multi.pick_up_object(lead.get_node("PlugA0") as RcaPlug)
		await _wait(200)
		var plug := lead.get_node("PlugA0") as Node3D
		var pl := sys.global_transform.affine_inverse() * plug.global_transform
		print("[mdrender] seated plug at %s, connector +Z %s (into the case is +Z)" % [
			pl.origin, pl.basis.z])

	await _shot(sv, cam, mid + b.z * 0.42 + up * 0.26 + b.x * 0.16, mid, up, "genesis_front_seated.png")
	await _shot(sv, cam, mid + b.z * 0.30 + up * 0.08, mid + b.z * 0.08, up, "genesis_ports.png")
	var rear := sys.global_position + up * 0.02
	await _shot(sv, cam, rear - b.z * 0.36 + up * 0.18 - b.x * 0.10, rear, up, "genesis_rear.png")
	var av := sys.global_position + Vector3(-0.0398, 0.0166, -0.1043)
	await _shot(sv, cam, av - b.z * 0.09 + up * 0.035 - b.x * 0.05, av, up, "genesis_av_seated.png")
	var phonos := (lead.get_node("PlugB1") as Node3D).global_position
	await _shot(sv, cam, phonos + Vector3(0.06, 0.08, 0.10), phonos, Vector3.UP, "genesis_av_phonos.png")
	var strip := sys.global_position + up * 0.034 + b.z * 0.066
	await _shot(sv, cam, strip + up * 0.16 + b.z * 0.10, strip, up, "genesis_buttons.png")
	get_tree().quit(0)


var _frame := 0
var _wide: SubViewport = null
var _close: SubViewport = null
var _resets := 0


func _run_buttons() -> void:
	var rom := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--rom="):
			rom = str(arg).trim_prefix("--rom=").replace("\\", "/")
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[mdrender] FAIL --buttons needs --rom=<an existing Genesis ROM> (got '%s')" % rom)
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
	_build_studio()

	var tv := TV_SCENE.instantiate() as RetroTV
	tv.freeze = true
	add_child(tv)
	tv.global_position = Vector3(0.0, 0.27, -0.50)
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "genesis"
	add_child(sys)
	sys.freeze = true
	await _wait(30)

	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "genesis"
	cart.rom_path = rom
	cart.game_label = rom.get_file().get_basename()
	add_child(cart)
	cart.global_position = Vector3(0.4, 0.3, 0)
	await _wait(10)
	sys.restore_cartridge(cart)
	await _wait(10)

	# The real A/V lead, seated the way a player seats it: the mini-DIN in the A/V OUT,
	# yellow, white and red in the set's first composite input. No stand-in wiring —
	# if the lead does not carry the picture, the film shows a blue screen.
	var lead := AV_LEAD_SCENE.instantiate() as Node3D
	add_child(lead)
	lead.global_position = Vector3(0.1, 0.03, -0.25)
	await _wait(30)
	var multi := sys.find_child("AvMultiOut", true, false) as RcaPort
	multi.pick_up_object(lead.get_node("PlugA0") as RcaPlug)
	await _wait(6)
	var ins := ["CompositePort", "AudioLIn", "AudioRIn"]
	for c in 3:
		(tv.get_node(ins[c]) as RcaPort).pick_up_object(lead.get_node("PlugB%d" % c) as RcaPlug)
		await _wait(6)
	await _wait(60)
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	print("[mdrender] lead seated: console feeds %s" % sys.connected_tv)
	if not tv.is_on():
		tv.remote_power_toggle()
	sys._reset_button.button_pressed.connect(func() -> void: _resets += 1)

	_wide = _viewport(Vector2i(960, 720))
	_close = _viewport(Vector2i(640, 720))
	(_wide.get_child(0) as Camera3D).look_at_from_position(
		Vector3(0.30, 0.34, 0.62), Vector3(0.0, 0.14, -0.22), Vector3.UP)
	var strip := sys.global_position + Vector3(0.0, 0.034, 0.066)
	(_close.get_child(0) as Camera3D).look_at_from_position(
		strip + Vector3(0.0, 0.13, 0.19), strip, Vector3.UP)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in range(60):
		await get_tree().process_frame

	var power := sys._power_button
	var reset := sys._reset_button
	var cap := sys._model.find_child("ButtonPower", true, false) as Node3D
	var cap_rest := cap.position.y
	_state(sys, "start", cap, cap_rest)
	await _film(30)

	await _press(power)
	# A fixed stretch, not "until the set has a texture": it has one while off (the
	# blue no-signal screen), so that wait ends at once.
	await _film(180)
	_state(sys, "after POWER", cap, cap_rest)

	await _press(reset)
	await _film(150)
	_state(sys, "after RESET (reset fired %d time(s))" % _resets, cap, cap_rest)

	await _press(power)
	await _film(60)
	_state(sys, "after POWER again", cap, cap_rest)
	print("[mdrender] frames=%d" % _frame)
	get_tree().quit(0)


func _viewport(size: Vector2i) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = size
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	sv.add_child(cam)
	cam.current = true
	return sv


## Down, held for a third of a second so the cap is seen travelling, then up.
func _press(btn: VRButton) -> void:
	var hand := Node3D.new()
	add_child(hand)
	var at := btn.global_position
	btn.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.ENTERED, hand, btn, at, at))
	btn.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, hand, btn, at, at))
	await _film(20)
	btn.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, hand, btn, at, at))
	btn.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.EXITED, hand, btn, at, at))
	hand.queue_free()


func _state(sys: RetroSystem, when: String, cap: Node3D, cap_rest: float) -> void:
	print("[mdrender] %s: powered %s, POWER cap %.1f mm below rest" % [when, sys.is_powered_on,
		(cap_rest - cap.position.y) * 1000.0])


func _film(n: int) -> void:
	for i in range(n):
		await RenderingServer.frame_post_draw
		var a := _wide.get_texture().get_image()
		var b := _close.get_texture().get_image()
		a.convert(Image.FORMAT_RGB8)
		b.convert(Image.FORMAT_RGB8)
		var out := Image.create(a.get_width() + b.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
		out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
		out.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width(), 0))
		out.save_png(out_dir.path_join("frames/%04d.png" % _frame))
		_frame += 1
		await get_tree().process_frame


## `--insert`: the A/V lead's mini-DIN going into the A/V OUT, and whether it lines up.
##
## Films the real lead's plug sliding in along its own axis from 40 mm out, from a rear
## three-quarter view beside a side view, then hands it to the socket the way a hand
## does. Then the alignment check, which a film cannot settle: the socket face-on from
## outside, and the SEATED plug's face from inside the case (console hidden) with the
## same framing mirrored left-right — the view an observer outside would have through
## the case — blended over it. Pins that land on the socket's contacts line up.
func _run_insert() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
	_build_studio()
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "genesis"
	add_child(sys)
	sys.freeze = true
	await _wait(30)
	var multi := sys.find_child("AvMultiOut", true, false) as XRToolsSnapZone
	var lead := AV_LEAD_SCENE.instantiate() as Node3D
	add_child(lead)
	lead.global_position = Vector3(-0.05, 0.03, -0.35)
	await _wait(60)
	var plug := lead.get_node("PlugA0") as RigidBody3D

	# Learn the seated pose by seating it once, then take it back out.
	multi.pick_up_object(plug)
	await _wait(10)
	var seated := plug.global_transform
	var local := sys.global_transform.affine_inverse() * seated
	print("[mdrender] seated plug origin %s  +X %s  +Y %s  +Z %s" % [
		local.origin, local.basis.x, local.basis.y, local.basis.z])
	multi.drop_object()
	plug.freeze = true
	await _wait(5)

	var av := sys.global_transform * Vector3(-0.0398, 0.0166, -0.1043)
	var light := OmniLight3D.new()
	add_child(light)
	light.global_position = av + Vector3(-0.04, 0.04, -0.08)
	light.omni_range = 0.4
	light.light_energy = 0.6

	_wide = _viewport(Vector2i(800, 600))
	_close = _viewport(Vector2i(800, 600))
	(_wide.get_child(0) as Camera3D).look_at_from_position(
		av + Vector3(-0.10, 0.06, -0.13), av + Vector3(0.0, 0.0, -0.015), Vector3.UP)
	(_close.get_child(0) as Camera3D).look_at_from_position(
		av + Vector3(-0.11, 0.012, -0.022), av + Vector3(0.0, 0.0, -0.022), Vector3.UP)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in range(60):
		await get_tree().process_frame

	# Slide in along the plug's own +Z (its connector axis) from 40 mm out.
	var axis := seated.basis.z.normalized()
	plug.global_transform = Transform3D(seated.basis, seated.origin - axis * 0.040)
	await _film(30)
	for i in range(1, 91):
		var t := float(i) / 90.0
		var ease_t := 1.0 - pow(1.0 - t, 2.0)
		plug.global_transform = Transform3D(seated.basis, seated.origin - axis * 0.040 * (1.0 - ease_t))
		await _film(1)
	plug.freeze = false
	multi.pick_up_object(plug)
	await _film(60)
	var after := sys.global_transform.affine_inverse() * plug.global_transform
	print("[mdrender] after seating: origin %s, off the learnt pose by %.2f mm, zone holds it %s" % [
		after.origin, (plug.global_transform.origin - seated.origin).length() * 1000.0,
		multi.picked_up_object == plug])

	# ── Alignment: socket face-on from outside, plug face from inside, mirrored. ──
	var cam := (_close.get_child(0) as Camera3D)
	var out_eye := av + Vector3(0.0, 0.0, -0.035)
	var in_eye := av + Vector3(0.0, 0.0, 0.035)
	lead.visible = false
	light.global_position = av + Vector3(0.01, 0.015, -0.05)
	cam.look_at_from_position(out_eye, av, Vector3.UP)
	# ORTHOGRAPHIC, not perspective. The socket's contacts sit 37 mm from their camera
	# and the plug's pin tips 29 mm from theirs, so under a perspective lens the plug
	# came out 1.27x larger and every outer pin looked off its contact. 9.2 mm tall,
	# 600 px: 15.35 um a pixel on both shots, whatever the depth.
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ALIGN_VIEW_M
	await _snap(_close, "genesis_socket_face.png")
	lead.visible = true
	sys.visible = false
	light.global_position = av + Vector3(0.01, 0.015, 0.05)
	cam.look_at_from_position(in_eye, av, Vector3.UP)
	await _snap(_close, "genesis_plug_face_seated.png")
	sys.visible = true
	print("[mdrender] frames=%d" % _frame)
	get_tree().quit(0)


## Height of the orthographic alignment view, in metres.
const ALIGN_VIEW_M := 0.00921


func _snap(sv: SubViewport, file: String) -> void:
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join(file))
	print("[mdrender] wrote %s" % file)


## The flat grey studio: good for positions, NOT for judging the shell's colour.
func _build_studio() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_energy = 1.6
	add_child(sun)
	_add_desk()


func _add_desk() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.06, 0.9)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.34, 0.26)
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	body.global_position = Vector3(0, -0.03, 0)
	_desk = body


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, up: Vector3,
		file: String) -> void:
	cam.look_at_from_position(eye, target, up)
	cam.current = true
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var path := out_dir.path_join(file)
	# FORMAT_RGB8 first: the frame carries an alpha channel nothing fills, and a
	# straight save writes a picture every viewer paints as a blank rectangle.
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("[mdrender] wrote %s" % path)
