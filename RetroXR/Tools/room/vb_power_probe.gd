extends Node3D
## The Virtual Boy's power (docs/dev/power.md), seen: the controller face down with its
## battery pack on, the pack off with its lid off and six cells in, and the AC adapter
## tap in the pack's place with the Super NES adapter's plug in it. Windowed only
## (headless draws nothing):
##
##     godot --path RetroXR res://Tools/room/vb_power_probe.tscn --resolution 320x240 --position 20,20 -- --out=<dir>

const PAD := preload("res://Scenes/Objects/controllers/vb/vb_controller.tscn")
const TAP := preload("res://Scenes/Objects/power/vb_ac_tap.tscn")
const BRICK := preload("res://Scenes/Objects/power/power_brick.tscn")
const CELL := preload("res://Scenes/Objects/batteries/battery_aa.tscn")

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://vb_power_probe"
var _fails := 0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): print("[vbpower] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	AppPrefs.mains_region = MainsRegions.DEFAULT
	_stage()
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 30
	_vp.add_child(_cam)

	# Face down, so its back -- and the pack on it -- looks up at the camera.
	var pad := PAD.instantiate() as VbController
	pad.freeze = true
	pad.transform = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, 0.075, 0))
	add_child(pad)
	pad.add_to_group("spawned")
	await _frames(12)
	var pack := pad.get_power_unit()
	_check(pack != null and pack.kind == "pack", "a fresh controller wears its battery pack")
	if pack == null:
		_finish()
		return
	_aim(pad.global_position + Vector3(0, 0.0, 0.0), Vector3(0.16, 0.24, 0.3))
	await _shot("vb_1_pack_on")

	# The pack off, on the floor beside it, lid off and full.
	var mount := pad.get_node("PackMount") as XRToolsSnapZone
	mount.drop_object()
	await _frames(2)
	pack.freeze = true
	pack.process_mode = Node.PROCESS_MODE_DISABLED
	_place(pack, Transform3D(Basis.IDENTITY, Vector3(0.22, VbPowerUnit.SIZE.y * 0.5, 0.02)))
	var covers := CoverSlots.of(pack)
	var lid := covers.slot(VbPowerUnit.LID_SOCKET).picked_up_object as RigidBody3D
	covers.slot(VbPowerUnit.LID_SOCKET).drop_object()
	await _frames(2)
	if lid != null:
		lid.freeze = true
		lid.process_mode = Node.PROCESS_MODE_DISABLED
		_place(lid, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.22, 0.002, 0.09)))
	var cells := CellSlots.of(pack)
	for seat: String in cells.seats():
		var cell := CELL.instantiate() as Node3D
		add_child(cell)
		cell.add_to_group("spawned")
		cells.slot(seat).pick_up_object(cell)
	await _frames(6)
	_check(cells.cells().size() == 6, "six cells in the pack")
	_check(bool(pack.input.own_supply()["supplied"]), "a full pack is a supply")
	_aim(Vector3(0.22, 0.017, 0.02), Vector3(0.07, 0.07, 0.16))
	await _shot("vb_2_pack_open_cells_in")

	# The tap in its place, the SNS-002's plug in its jack.
	var tap := TAP.instantiate() as VbPowerUnit
	tap.freeze = true
	tap.position = Vector3(-0.2, 0.05, 0.0)
	add_child(tap)
	await _frames(3)
	mount.pick_up_object(tap)
	# Its lid off, as one opens it to plug the adapter in.
	var tap_lid_slot := CoverSlots.of(tap).slot(VbPowerUnit.TAP_LID_SOCKET)
	var tap_lid := tap_lid_slot.picked_up_object as RigidBody3D
	tap_lid_slot.drop_object()
	await _frames(2)
	if tap_lid != null:
		tap_lid.freeze = true
		tap_lid.process_mode = Node.PROCESS_MODE_DISABLED
		_place(tap_lid, Transform3D(Basis.IDENTITY, Vector3(-0.12, 0.009, 0.12)))
	var snes := BRICK.instantiate() as PowerBrick
	snes.brick_id = "snes_ac_adapter"
	snes.variant = "usa"
	snes.position = Vector3(-0.25, 0.05, 0.15)
	add_child(snes)
	snes.add_to_group("spawned")
	await _frames(6)
	_check(tap.jack != null and tap.jack.can_preview(snes.dc_plug), "the SNS-002's plug fits the tap")
	tap.jack.pick_up_object(snes.dc_plug)
	await _frames(40)
	_check(pad.get_power_unit() == tap, "the tap is on the controller")
	_aim(pad.global_position, Vector3(-0.14, 0.26, 0.3))
	await _shot("vb_3_tap_snes_plug")
	_finish()


func _finish() -> void:
	print("[vbpower] ---- %d failed ----" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


static func _place(body: RigidBody3D, xf: Transform3D) -> void:
	body.global_transform = xf
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)


func _aim(at: Vector3, from_offset: Vector3) -> void:
	_cam.look_at_from_position(at + from_offset, at)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.environment.ambient_light_energy = 1.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.8
	add_child(fill)
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
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.72, 0.68, 0.6)
	pm.material = fm
	floor_mesh.mesh = pm
	floor_body.add_child(floor_mesh)
	add_child(floor_body)


func _check(ok: bool, what: String) -> void:
	print("[vbpower] %s: %s" % ["OK" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(10)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[vbpower] wrote ", path)
