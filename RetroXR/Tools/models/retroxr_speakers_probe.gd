## The RETRO XR loudspeakers in the game, windowed, one shot per process:
##   godot --path RetroXR res://Tools/models/retroxr_speakers_probe.tscn --resolution 320x240 --position 20,20 \
##       -- --shot=items|set51|desk|jacks|orbit --out=<dir>
##   items  each item alone, front and back (satellite, subwoofer, both stands, the computer pair)
##   set51  a 5.1 room: the RETRO XR receiver, the fronts and surrounds on stands, the centre, the sub, every lead seated
##   jacks  leads seated in the satellites' phono jacks, and the sub's plate (LINE IN, rocker, cord)
##   desk   the computer pair on a table beside the RETRO XR set, cabled to a Game Boy's PHONES (the set has no 3.5 mm
##          out: the RETRO XR cabinet has no PhonesSeat)
##   orbit  set51, then one turn round it at 30 fps: frames/ for an mp4 (encode with imageio)
## The SubViewport has no world of its own: it renders the main one, where a captive mains cord hangs (it is a child
## of the current scene).
extends Node3D

const AMP := preload("res://Scenes/Objects/appliances/surround_amp.tscn")
const LEAD := preload("res://Scenes/Objects/cables/speaker_cable.tscn")
const TRS := preload("res://Scenes/Objects/cables/trs_cable.tscn")
const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const SUB := preload("res://Scenes/Objects/appliances/subwoofer.tscn")
const STAND_100 := preload("res://Scenes/Objects/appliances/speaker_stand_100.tscn")
const STAND_120 := preload("res://Scenes/Objects/appliances/speaker_stand_120.tscn")
const PAIR := preload("res://Scenes/Objects/appliances/speaker_pair.tscn")
const TABLE := preload("res://Scenes/Objects/furniture/table.tscn")
const TV := preload("res://Scenes/Objects/tv.tscn")
const SYSTEM := preload("res://Scenes/Objects/system.tscn")

const LISTENER := Vector3(0, 0, 2.2)
## Out, cabinet, stand (0 none), floor position.
const LAYOUT := [
	["SpeakerOutL", "sat", 120, Vector3(-1.0, 0, -0.7)], ["SpeakerOutR", "sat", 120, Vector3(1.0, 0, -0.7)],
	["SpeakerOutC", "sat", 0, Vector3(0.0, 0, -0.55)], ["SpeakerOutLfe", "sub", 0, Vector3(1.55, 0, -0.85)],
	["SpeakerOutSl", "sat", 100, Vector3(-1.6, 0, 1.3)], ["SpeakerOutSr", "sat", 100, Vector3(1.6, 0, 1.3)],
]

var _out := ""
var _shot := "items"
var _view: SubViewport
var _cam: Camera3D
var _n := 0


func _ready() -> void:
	get_tree().create_timer(500.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	get_tree().current_scene = self
	_stage()
	match _shot:
		"items":
			await _items()
		"set51":
			await _set51(true)
		"jacks":
			await _jacks()
		"desk":
			await _desk()
		"orbit":
			await _orbit()
	print("[probe] done: %s, %d frames" % [_shot, _n])
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1600, 1000)
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.17, 0.18, 0.20)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.environment.ambient_light_energy = 1.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 28, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 9.0
	sun.shadow_bias = 0.01
	sun.shadow_normal_bias = 0.4
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-35, 200, 0)
	back.light_energy = 0.9
	add_child(back)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.42, 0.44)
	fm.roughness = 0.85
	floor_mesh.material_override = fm
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	floor_mesh.add_child(floor_body)
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 40
	_view.add_child(_cam)
	_cam.current = true


func _snap(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for h in find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	var path := _out.path_join(name + ".png")
	_view.get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)


func _look(from: Vector3, at: Vector3, fov := 40.0) -> void:
	_cam.fov = fov
	_cam.look_at_from_position(from, at)


func _settle(frames := 30) -> void:
	for i in frames:
		await get_tree().physics_frame


func _add(packed: PackedScene, at: Vector3, yaw_deg := 0.0) -> Node3D:
	var n := packed.instantiate() as Node3D
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true
	add_child(n)
	n.global_position = at
	n.rotation_degrees.y = yaw_deg
	return n


# ── items ────────────────────────────────────────────────────────────────────

func _items() -> void:
	var rows := [["satellite", SATELLITE, 0.08, 0.55], ["subwoofer", SUB, 0.15, 1.1], ["stand_100", STAND_100, 0.5, 2.6],
		["stand_120", STAND_120, 0.6, 3.0], ["computer_pair", PAIR, 0.08, 1.0]]
	for row: Array in rows:
		var item := _add(row[1], Vector3.ZERO)
		if item is SpeakerPair:
			(item.get_node("SpeakerL") as Node3D).position = Vector3(-0.12, 0, 0)
			(item.get_node("SpeakerR") as Node3D).position = Vector3(0.12, 0, 0)
			(item.get_node("SpeakerL") as RigidBody3D).freeze = true
			(item.get_node("SpeakerR") as RigidBody3D).freeze = true
		await _settle(45)
		print("[probe] %s: lowest drawn point %.4f m above the floor" % [row[0],
			ApplianceModel.node_bounds(item, self).position.y])
		var y: float = row[2]
		var r: float = row[3]
		_look(Vector3(r * 0.45, y + r * 0.32, r), Vector3(0, y, 0), 30.0)
		await _snap("%s_front" % row[0])
		_look(Vector3(-r * 0.5, y + r * 0.3, -r), Vector3(0, y, 0), 30.0)
		await _snap("%s_back" % row[0])
		item.queue_free()
		for c in get_children():
			if c is CaptiveMainsCord:
				c.queue_free()
		await _settle(4)


# ── the 5.1 room ─────────────────────────────────────────────────────────────

func _build51() -> Dictionary:
	var amp := _add(AMP, Vector3(0, 0, 0.15)) as SurroundAmp
	var cabs := {}
	for row: Array in LAYOUT:
		var at: Vector3 = row[3]
		var yaw := rad_to_deg(atan2(LISTENER.x - at.x, LISTENER.z - at.z))
		var cab := _add(SATELLITE if row[1] == "sat" else SUB, at, yaw) as Loudspeaker
		if int(row[2]) > 0:
			var stand := _add(STAND_120 if int(row[2]) == 120 else STAND_100, at, yaw) as SpeakerStand
			stand.seat().pick_up_object(cab)
		cabs[row[0]] = cab
	await _settle(10)
	for row: Array in LAYOUT:
		var port := amp.get_node(String(row[0])) as RcaPort
		var cab: Loudspeaker = cabs[row[0]]
		var term := cab.get_node("SpeakerIn") as RcaPort
		var lead := LEAD.instantiate() as CompositeCable
		var rope := lead.get_node("VerletRope")
		var run := port.global_position.distance_to(term.global_position) * 1.25 + 0.35
		rope.set("segment_count", int(ceil(run / float(rope.get("segment_length")))))
		add_child(lead)
		var a := lead.get_node("PlugA0") as RigidBody3D
		var b := lead.get_node("PlugB0") as RigidBody3D
		a.global_position = port.global_position + port.global_basis.z * 0.05
		b.global_position = term.global_position + term.global_basis.z * 0.05
		await get_tree().physics_frame
		port.pick_up_object(a)
		term.pick_up_object(b)
		print("[probe] %s -> %s, lead %.2f m" % [row[0], cab.name, run])
	await _settle(240)
	return {"amp": amp, "cabs": cabs}


func _set51(stills: bool) -> void:
	var rig := await _build51()
	var amp: SurroundAmp = rig["amp"]
	var lit: Array[String] = []
	for j in SurroundAmp.SPEAKER_OUT_NAMES.size():
		if amp.vfd_lamp_lit(j):
			lit.append(str(SurroundAmp.VFD_LAMPS[j][0]))
	print("[probe] receiver lamps lit: %s" % ", ".join(lit))
	if not stills:
		return
	_look(Vector3(0.6, 1.7, 3.6), Vector3(0, 0.55, 0), 52)
	await _snap("set51_front")
	_look(Vector3(-2.2, 1.6, -2.4), Vector3(0, 0.45, 0.1), 52)
	await _snap("set51_back")
	_look(Vector3(2.6, 0.9, 0.4), Vector3(0.6, 0.45, -0.3), 46)
	await _snap("set51_side")


func _orbit() -> void:
	await _set51(false)
	for i in 240:
		var a := deg_to_rad(20.0 + 360.0 * float(i) / 240.0)
		var h := 1.5 + 0.25 * sin(a * 2.0)
		_look(Vector3(sin(a) * 3.4, h, cos(a) * 3.4 + 0.2), Vector3(0, 0.5, 0.2), 50)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_view.get_texture().get_image().save_png(_out.path_join("frames/f_%04d.png" % _n))
		_n += 1


# ── the jacks ────────────────────────────────────────────────────────────────

func _jacks() -> void:
	var rig := await _build51()
	var cabs: Dictionary = rig["cabs"]
	for spec: Array in [["SpeakerOutSl", "jack_surround_left"], ["SpeakerOutL", "jack_front_left"],
			["SpeakerOutC", "jack_centre"]]:
		var cab: Loudspeaker = cabs[spec[0]]
		var jack := (cab.get_node("SpeakerIn") as Node3D).global_position
		var back := -cab.global_basis.z
		_look(jack + back * 0.32 + cab.global_basis.x * 0.1 + Vector3(0, 0.1, 0), jack, 38)
		await _snap(spec[1])
	var sub: Loudspeaker = cabs["SpeakerOutLfe"]
	var c := sub.global_position + Vector3(0, 0.16, 0)
	var sback := -sub.global_basis.z
	_look(c + sback * 0.7 + sub.global_basis.x * 0.25 + Vector3(0, 0.18, 0), c + sback * 0.15, 40)
	await _snap("jack_subwoofer_plate")


# ── the desk ─────────────────────────────────────────────────────────────────

func _desk() -> void:
	var table := _add(TABLE, Vector3.ZERO)
	await _settle(4)
	var top := ApplianceModel.node_bounds(table, self).end.y
	var tv := TV.instantiate() as Node3D
	tv.set("tv_model", "retroxr_crt")
	if tv is RigidBody3D:
		(tv as RigidBody3D).freeze = true
	add_child(tv)
	tv.global_position = Vector3(0, top, -0.05)
	await _settle(8)
	var tv_box := ApplianceModel.node_bounds(tv, tv)
	var pair := PAIR.instantiate() as SpeakerPair
	add_child(pair)
	pair.global_position = Vector3(0, top, 0.05)
	var half := tv_box.size.x * 0.5 + 0.11
	for spec: Array in [["SpeakerL", -half], ["SpeakerR", half]]:
		var box := pair.get_node(String(spec[0])) as RigidBody3D
		box.freeze = true
		box.global_position = Vector3(float(spec[1]), top, 0.05)
		box.rotation_degrees.y = 8.0 if float(spec[1]) < 0.0 else -8.0
	await _settle(10)
	# The source: a Game Boy lying in front of the set, its PHONES jack into the pair's LINE IN.
	var gb := SYSTEM.instantiate() as RetroSystem
	gb.systemid = "gb"
	gb.model_id = "game_boy_primitive"
	gb.freeze = true
	add_child(gb)
	gb.global_position = Vector3(0.12, top + 0.02, 0.32)
	gb.rotation_degrees = Vector3(-90, -15, 0)
	await _settle(8)
	var phones := gb.find_child("PhonesOut", true, false) as Node3D
	var line_in := pair.get_node("SpeakerR/LineIn") as Node3D
	print("[probe] desk: table top %.3f m, set %s mm, PhonesOut %s, LINE IN %s" % [top,
		(tv_box.size * 1000.0).round(), phones != null, line_in != null])
	if phones != null and line_in != null and phones.has_method("pick_up_object"):
		var lead := TRS.instantiate() as Node3D
		var rope := lead.get_node_or_null("VerletRope")
		if rope != null:
			var run := phones.global_position.distance_to(line_in.global_position) * 1.3 + 0.3
			rope.set("segment_count", int(ceil(run / float(rope.get("segment_length")))))
		add_child(lead)
		var a := lead.get_node("PlugA0") as RigidBody3D
		var b := lead.get_node("PlugB0") as RigidBody3D
		a.global_position = phones.global_position + phones.global_basis.z * 0.05
		b.global_position = line_in.global_position + line_in.global_basis.z * 0.05
		await get_tree().physics_frame
		phones.call("pick_up_object", a)
		line_in.call("pick_up_object", b)
		print("[probe] desk: the Game Boy's PHONES -> the pair's LINE IN")
	await _settle(240)
	_look(Vector3(0.5, top + 0.45, 1.5), Vector3(0, top + 0.18, 0), 40)
	await _snap("desk_front")
	_look(Vector3(-0.9, top + 0.5, -1.2), Vector3(0, top + 0.12, 0), 40)
	await _snap("desk_back")
	var right := pair.get_node("SpeakerR") as Node3D
	_look(right.global_position + Vector3(0.12, 0.12, 0.32), right.global_position + Vector3(0, 0.05, 0), 34)
	await _snap("desk_knob_led")
