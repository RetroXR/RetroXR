## A video of the RETRO XR surround receiver being cabled to six speakers, windowed, one PNG a frame at a fixed
## 30 fps step:
##   godot --path RetroXR res://Tools/av/amp_speakers_video_probe.tscn --resolution 320x240 --position 20,20 --fixed-fps 30 -- --out=<dir>
## Each lead's near plug is carried to a SPEAKERS jack on the back and pushed in along the socket, then its far plug
## into the cabinet's terminal; the display's speaker map lights a lamp per cabled channel. Encode frames/ with imageio.
extends Node

const AMP := preload("res://Scenes/Objects/appliances/surround_amp.tscn")
const LEAD := preload("res://Scenes/Objects/cables/speaker_cable.tscn")
const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const SUB := preload("res://Scenes/Objects/appliances/subwoofer.tscn")
## Out name, cabinet, floor position (m). A 5.1 room: the receiver on the floor before the front wall, its back to
## the wall; L / C / R and the sub along the wall, the surrounds out to the sides nearer the listener (+Z).
const LISTENER := Vector3(0, 0, 1.6)
const LAYOUT := [
	["SpeakerOutL", "sat", Vector3(-0.85, 0, -0.75)], ["SpeakerOutR", "sat", Vector3(0.85, 0, -0.75)],
	["SpeakerOutC", "sat", Vector3(0.0, 0, -0.9)], ["SpeakerOutLfe", "sub", Vector3(1.35, 0, -0.85)],
	["SpeakerOutSl", "sat", Vector3(-1.35, 0, 0.75)], ["SpeakerOutSr", "sat", Vector3(1.35, 0, 0.75)],
]

var _out := ""
var _view: SubViewport
var _cam: Camera3D
var _n := 0
var _t := 0.0
var _amp: SurroundAmp


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	_stage()
	await _run()
	print("[probe] %d frames" % _n)
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.20)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 1.1
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 200, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	_view.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	floor_mesh.add_child(floor_body)
	_view.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 42
	_view.add_child(_cam)
	_cam.current = true


## The camera on a circle round the receiver: azimuth 0 = in front (+Z), 180 = behind it.
var _az := 200.0
var _height := 1.35
var _radius := 2.0
var _look := Vector3(0, 0.0, -0.2)


func _frame() -> void:
	await get_tree().process_frame
	_t += 1.0 / 30.0
	var a := deg_to_rad(_az)
	_cam.look_at_from_position(_look + Vector3(sin(a) * _radius, _height, cos(a) * _radius), _look)
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_view.get_texture().get_image().save_png(_out.path_join("frames/f_%04d.png" % _n))
	_n += 1


func _frames(count: int) -> void:
	for i in count:
		await _frame()


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


## Carry `plug` from `start` to the socket's mouth and push it in along the socket, then let the socket take it.
func _plug_in(plug: RigidBody3D, port: RcaPort, start: Vector3, frames: int) -> void:
	port.pick_up_object(plug)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seated := plug.global_transform
	port.drop_object()
	plug.freeze = true
	var mouth := seated.origin + port.global_basis.z * 0.07
	var carry := frames * 2 / 3
	for i in frames:
		var p: Vector3
		if i < carry:
			p = start.lerp(mouth, _ease(float(i) / float(carry - 1)))
		else:
			p = mouth.lerp(seated.origin, _ease(float(i - carry) / float(frames - carry - 1)))
		plug.global_transform = Transform3D(seated.basis, p)
		await _frame()
	port.pick_up_object(plug)


func _run() -> void:
	_amp = AMP.instantiate() as SurroundAmp
	_amp.freeze = true
	_view.add_child(_amp)
	var cabs := {}
	for row: Array in LAYOUT:
		var cab := (SATELLITE if row[1] == "sat" else SUB).instantiate() as RigidBody3D
		cab.freeze = true
		_view.add_child(cab)
		cab.global_position = row[2]
		cab.look_at(Vector3(LISTENER.x, cab.global_position.y, LISTENER.z), Vector3.UP, true)
		cabs[row[0]] = cab
	for i in 8:
		await get_tree().process_frame
	await _frames(30)
	var k := 0
	for row: Array in LAYOUT:
		var port := _amp.get_node(String(row[0])) as RcaPort
		var cab: RigidBody3D = cabs[row[0]]
		var lead := LEAD.instantiate() as CompositeCable
		# Cut to the run, as someone wiring a room would, not the 3 m off the reel: set BEFORE the rope is in the tree
		# (it lays its points in _ready; a live rope must never be lengthened).
		var term_at := (cab.get_node("SpeakerIn") as Node3D).global_position
		var run := port.global_position.distance_to(term_at) + 0.25
		var rope := lead.get_node("VerletRope")
		rope.set("segment_count", int(ceil(run / float(rope.get("segment_length")))))
		_view.add_child(lead)
		var a_plug := lead.get_node("PlugA0") as RigidBody3D
		var b_plug := lead.get_node("PlugB0") as RigidBody3D
		var hand := port.global_position + Vector3(0, 0.25, -0.25)
		a_plug.freeze = true
		b_plug.freeze = true
		a_plug.global_position = hand
		b_plug.global_position = hand + Vector3(0.04, -0.02, -0.05)
		await get_tree().process_frame
		_az = 205.0 - 50.0 * float(k) / float(LAYOUT.size())
		await _plug_in(a_plug, port, hand, 30)
		var term := cab.get_node("SpeakerIn") as RcaPort
		await _plug_in(b_plug, term, b_plug.global_position, 36)
		await _frames(8)
		k += 1
		var lit: Array[String] = []
		for j in SurroundAmp.SPEAKER_OUT_NAMES.size():
			if _amp.vfd_lamp_lit(j):
				lit.append(str(SurroundAmp.VFD_LAMPS[j][0]))
		print("[probe] %s cabled at frame %d, lead %.2f m; lamps lit: %s" % [row[0], _n, run, ", ".join(lit)])
	await _frames(20)
	# Round the side to the front: the room from the listener, then the display with all six lamps.
	for i in 90:
		var u := _ease(float(i) / 89.0)
		_az = lerpf(155.0, 18.0, u)
		_height = lerpf(1.35, 0.45, u)
		_radius = lerpf(2.0, 1.1, u)
		_look = Vector3(0, 0.0, -0.2).lerp(Vector3(0, 0.06, 0.1), u)
		await _frame()
	for i in 45:
		var u := _ease(float(i) / 44.0)
		_radius = lerpf(1.1, 0.55, u)
		_height = lerpf(0.45, 0.16, u)
		await _frame()
	await _frames(40)
