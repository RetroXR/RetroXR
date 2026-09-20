extends Node

## Xbox Memory Unit render probe -- the unit on its own, face and back, and two of
## them seated in a pad's slots, from above AND from behind.
##
## Wants no core and no ROM. What it is for is the one thing no headless suite
## can say: whether a unit seated in a socket authored for a VMU actually SITS in
## it. A seat places an object's origin, and a body whose origin is in the wrong
## place floats short of the slot or buries itself in the shell (a Jump Pack did
## the first). So the pad is filmed from behind as well, where a floating unit
## shows daylight between its connector and the pad's rear face.
##
## Each seated unit's basis and origin are PRINTED too, in the pad's frame, so the
## facing is settled by numbers and not only by eye: +Y (the connector end) must
## point into the pad, along the pad's +Z.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/xbox_mu_render_probe.tscn
##
## Windowed, never headless: the dummy renderer returns a blank image.

const OUT_DIR := "res://probe_out"
const UNIT := preload("res://Scenes/Objects/controllers/xbox/xbox_mu.tscn")
const PAD := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const VMU := preload("res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _shot_units()
	await _shot_pad()
	get_tree().quit(0)


func _stage(size: Vector2i) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = size
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.33, 0.35, 0.40)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.70)
	e.ambient_light_energy = 0.7
	env.environment = e
	sv.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-48, -30, 0)
	sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-20, 150, 0)
	sv.add_child(fill)
	return sv


func _save(sv: SubViewport, name: String) -> void:
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := OUT_DIR.path_join(name)
	print("[probe] saved %s err=%d" % [path, img.save_png(path)])


## The unit beside a VMU, for scale: face on, and turned to show the back.
func _shot_units() -> void:
	var sv := _stage(Vector2i(960, 540))
	var items := [[UNIT, Vector3(-0.085, 0, 0), -10.0], [UNIT, Vector3(-0.025, 0, 0), 195.0],
		[VMU, Vector3(0.05, -0.015, 0), -10.0]]
	for it: Array in items:
		var n: Node3D = (it[0] as PackedScene).instantiate()
		if "card_id" in n:
			n.set("card_id", "__render_probe")
			n.set("card_label", "Halo saves")
		sv.add_child(n)
		n.position = it[1]
		# A unit is stood CONNECTOR DOWN, the way its face reads and the way a hand
		# holds one to push it into a pad; the VMU beside it reads connector up.
		n.rotation_degrees = Vector3(0, float(it[2]), 180.0 if it[0] == UNIT else 0.0)
		if n is RigidBody3D:
			(n as RigidBody3D).freeze = true
	var cam := Camera3D.new()
	cam.position = Vector3(-0.01, 0.012, 0.30)
	cam.fov = 34
	sv.add_child(cam)
	cam.current = true
	await _save(sv, "xbox_mu_units.png")
	sv.queue_free()


## Two units in one pad's slots: the console's 1A and 1B.
func _shot_pad() -> void:
	var sv := _stage(Vector2i(960, 1080))
	var pad := PAD.instantiate() as Node3D
	sv.add_child(pad)
	if pad is RigidBody3D:
		(pad as RigidBody3D).freeze = true
	for i in range(4):
		await get_tree().process_frame
	var units: Array[Node3D] = []
	for slot in 2:
		var unit := UNIT.instantiate() as Node3D
		unit.set("card_id", "__render_probe_%d" % slot)
		unit.set("card_label", "Unit %s" % ("A" if slot == 0 else "B"))
		sv.add_child(unit)
		units.append(unit)
	await get_tree().process_frame
	for slot in 2:
		pad.call("restore_vmu", units[slot], slot)
	for i in range(6):
		await get_tree().process_frame
	for slot in 2:
		var local := pad.global_transform.affine_inverse() * units[slot].global_transform
		print("[probe] slot %d: seated=%s origin=%s  unit +Y (connector end) in pad space=%s  +Z (face)=%s" % [
			slot + 1, pad.call("get_vmu_device", slot) == units[slot],
			local.origin.snapped(Vector3.ONE * 0.0001), local.basis.y.snapped(Vector3.ONE * 0.01),
			local.basis.z.snapped(Vector3.ONE * 0.01)])

	# Top half of the sheet: above and in front, as a player holds it. Bottom
	# half: from BEHIND and a little above, looking at the edge the units go in.
	var top := Camera3D.new()
	sv.add_child(top)
	top.look_at_from_position(Vector3(0.0, 0.26, 0.13), Vector3(0, 0, -0.03), Vector3.UP)
	top.fov = 40
	top.current = true
	await _save(sv, "xbox_mu_pad_above.png")
	var rear := Camera3D.new()
	sv.add_child(rear)
	rear.look_at_from_position(Vector3(0.10, 0.10, -0.28), Vector3(0, 0, -0.05), Vector3.UP)
	rear.fov = 40
	rear.current = true
	await _save(sv, "xbox_mu_pad_behind.png")
	var side := Camera3D.new()
	sv.add_child(side)
	side.look_at_from_position(Vector3(0.30, 0.02, -0.06), Vector3(0, 0, -0.06), Vector3.UP)
	side.fov = 30
	side.current = true
	await _save(sv, "xbox_mu_pad_side.png")
