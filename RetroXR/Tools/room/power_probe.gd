extends Node3D
## Power (docs/dev/power.md), seen: a wall outlet, a RETRO XR set on its own cord, a
## Famicom on its HVC-002 wall wart, with "Enable Power Simulation" on. Renders the
## room unplugged (the set dark), plugged in (the set lit), the set's own cord leaving its
## back, a Game Boy's back with its bay shut, open and with
## four cells in, the set's System tab, and an mp4 of the set's plug being pulled.
## Windowed only (headless draws nothing):
##
##     godot --path RetroXR res://Tools/room/power_probe.tscn --resolution 640x360 --position 20,20 -- --out=<dir>
##
## Renders through its own SubViewport + camera, as tv_model_probe does.

const TV := preload("res://Scenes/Objects/tv.tscn")
const OUTLET := preload("res://Scenes/Objects/room/wall_outlet.tscn")
const SYSTEM := preload("res://Scenes/Objects/system.tscn")
const BRICK := preload("res://Scenes/Objects/power/power_brick.tscn")
const CELL := preload("res://Scenes/Objects/batteries/battery_aa.tscn")
const TV_UI := preload("res://Scenes/UI/tv_options_2d.tscn")

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://power_probe"
var _fails := 0
var _sim_before := false


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func(): print("[powerprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_sim_before = AppPrefs.power_simulation
	AppPrefs.power_simulation = true
	AppPrefs.mains_region = MainsRegions.DEFAULT
	_stage()
	var plate := OUTLET.instantiate() as WallOutlet
	plate.position = Vector3(0.0, 0.3, -0.6)
	add_child(plate)
	var tv := TV.instantiate() as RetroTV
	tv.tv_model = "retroxr_crt"
	tv.position = Vector3(0.35, 0.0, -0.25)
	tv.freeze = true
	add_child(tv)
	tv.add_to_group("spawned")
	var fc := SYSTEM.instantiate() as RetroSystem
	fc.systemid = "famicom"
	fc.model_id = "famicom"
	fc.position = Vector3(-0.35, 0.0, -0.3)
	fc.freeze = true
	add_child(fc)
	fc.add_to_group("spawned")
	var wart := BRICK.instantiate() as PowerBrick
	wart.brick_id = "hvc_ac_adapter"
	wart.variant = "jpn"
	wart.position = Vector3(-0.15, 0.05, 0.0)
	add_child(wart)
	wart.add_to_group("spawned")
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 45
	_vp.add_child(_cam)
	fc.core_start_stand_in = func() -> void: pass
	await _frames(20)
	# tv.tscn's origin is not its bottom (tv_model_probe lowers its floor for it): stand
	# the set ON the floor, by its drawn bounds, before anything is plugged in.
	var bottom := ApplianceModel.node_bounds(tv, tv, ["PowerInlet"]).position.y
	tv.position.y -= bottom
	print("[powerprobe] the set stood on the floor (its origin %.3f m above its bottom)" % -bottom)
	await _frames(4)

	# The set's own cord, out of its model's PowerCordExit as a deck's is.
	var lead := tv.power_input().captive as CaptiveMainsCord
	_check(lead != null, "the set has a cord of its own")
	await _frames(4)
	_cam.look_at_from_position(Vector3(0.15, 0.75, 1.05), Vector3(0.0, 0.15, -0.35))
	tv.set_power(true)
	fc.toggle_power()
	await _frames(10)
	_check(not tv.is_on() and not fc.is_powered_on, "unplugged: the set dark, the Famicom refuses")
	await _shot("1_unplugged")

	(plate.get_node("BottomPort") as PowerPort).pick_up_object(lead.wall_plug)
	(fc.get_node("PowerInlet") as DcPort).pick_up_object(wart.dc_plug)
	(plate.get_node("TopPort") as PowerPort).pick_up_object(wart.wall_plug)
	await _frames(10)
	fc.toggle_power()
	await _frames(30)
	_check(tv.is_on() and fc.is_powered_on, "plugged in: the set on, the Famicom running")
	await _shot("2_plugged_in")
	_cam.look_at_from_position(Vector3(-0.15, 0.55, 0.2), Vector3(0.0, 0.25, -0.6))
	await _shot("3_outlet_close")

	# The set's plug pulled, filmed.
	_cam.look_at_from_position(Vector3(0.15, 0.75, 1.05), Vector3(0.0, 0.15, -0.35))
	var frames: Array[Image] = []
	for i in 20:
		await _frames(2)
		frames.append(_vp.get_texture().get_image())
	var port := plate.get_node("BottomPort") as PowerPort
	port.drop_object()
	lead.wall_plug.global_position += Vector3(0.0, 0.0, 0.25)
	for i in 40:
		await _frames(2)
		frames.append(_vp.get_texture().get_image())
	_check(not tv.is_on(), "pulled: the set goes dark")
	for i in frames.size():
		frames[i].save_png(_out.path_join("pull_%03d.png" % i))
	print("[powerprobe] wrote %d pull frames" % frames.size())

	(plate.get_node("BottomPort") as PowerPort).pick_up_object(lead.wall_plug)
	await _frames(10)
	_check(tv.is_on(), "plugged back in: the set is on")
	_cam.look_at_from_position(Vector3(0.75, 0.62, -0.57), Vector3(0.42, 0.1, -0.47))
	await _shot("4_tv_cord_back")

	# A Game Boy's back: the bay shut, open, and with its four cells.
	var gb := SYSTEM.instantiate() as RetroSystem
	gb.systemid = "gb"
	gb.model_id = "game_boy_primitive"
	gb.position = Vector3(0.0, 0.6, 0.6)
	gb.rotation_degrees = Vector3(0, 0, 180)
	gb.freeze = true
	add_child(gb)
	gb.add_to_group("spawned")
	await _frames(20)
	_cam.look_at_from_position(Vector3(0.0, 0.85, 0.75), Vector3(0.0, 0.62, 0.6))
	await _shot("5_gb_bay_shut")
	var covers := CoverSlots.of(gb)
	var slots := CellSlots.of(gb)
	_check(covers != null and slots != null and slots.seats().size() == 4, "the Game Boy has its bay")
	if covers != null and slots != null:
		var zone := covers.slot(covers.sockets()[0])
		var cover := zone.picked_up_object as Node3D
		zone.drop_object()
		if cover != null:
			cover.global_position = Vector3(0.25, 0.6, 0.6)
			(cover as RigidBody3D).freeze = true
		await _frames(10)
		await _shot("6_gb_bay_open")
		for seat: String in slots.seats():
			var cell := CELL.instantiate() as Node3D
			add_child(cell)
			cell.add_to_group("spawned")
			slots.slot(seat).pick_up_object(cell)
		await _frames(10)
		_check(PowerInput.of(gb).is_live(), "four cells: the Game Boy has power")
		await _shot("7_gb_cells_in")

	# The set's System tab.
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := TV_UI.instantiate() as Control
	ui.size = Vector2(640, 520)
	var host := SubViewport.new()
	host.size = Vector2i(640, 520)
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(host)
	host.add_child(ui)
	await _frames(4)
	PowerMenuRows.ensure_in(ui, tv.power_input())
	var tabs := ui.find_children("*", "TabContainer", true, false)
	if not tabs.is_empty():
		var tc := tabs[0] as TabContainer
		for i in tc.get_tab_count():
			if tc.get_tab_title(i) == "System":
				tc.current_tab = i
	await _frames(8)
	host.get_texture().get_image().save_png(_out.path_join("8_tv_system_tab.png"))
	print("[powerprobe] wrote 8_tv_system_tab.png")

	AppPrefs.power_simulation = _sim_before
	print("[powerprobe] ---- %d failed ----" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.57)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(6, 0.1, 6)
	fshape.shape = fbox
	fshape.position.y = -0.05
	floor_body.add_child(fshape)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mesh.mesh = pm
	floor_body.add_child(floor_mesh)
	add_child(floor_body)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(4, 2.5, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.74, 0.66)
	wm.material = mat
	wall.mesh = wm
	wall.position = Vector3(0, 1.25, -0.65)
	add_child(wall)


func _check(ok: bool, what: String) -> void:
	print("[powerprobe] %s: %s" % ["OK" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(10)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[powerprobe] wrote ", path)
