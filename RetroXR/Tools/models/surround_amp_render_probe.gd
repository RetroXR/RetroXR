## Renders the surround amplifier — its face in both decoder modes and lit, its back
## panel and legend, and a wired back with real leads seated — and prints the facing
## of every socket.
##
##   godot --path RetroXR --resolution 1400x900 --position 20,20 \
##     res://Tools/models/surround_amp_render_probe.tscn -- --out=<dir>
##
## WINDOWED, never --headless: the dummy renderer hands back a correctly sized
## blank, and AvLegend only bakes its plates on a real renderer.
##
## Drawn into a SubViewport with own_world_3d, because an uncomposited window
## swapchain reads back as clear colour only — and everything is BUILT inside it, with
## only the camera moving between shots. The speaker probe reparents its subject into
## a fresh viewport per shot, which is fine for a bare cabinet; here it pulled every
## seated lead (a snap zone leaving the tree lets go of what it holds), and the first
## wired picture showed plugs lying where they had been seated rather than seated.
extends Node3D

const AMP := preload("res://Scenes/Objects/appliances/surround_amp.tscn")
const LEAD := preload("res://Scenes/Objects/cables/speaker_cable.tscn")
const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")

const SIZE := Vector2i(1400, 900)

var _out_dir := "res://probe_out"
var _sv: SubViewport = null
var _cam: Camera3D = null
var _key: DirectionalLight3D = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.split("=")[1]
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_build_world()

	var amp := AMP.instantiate() as SurroundAmp
	amp.freeze = true
	_sv.add_child(amp)
	# AvLegend bakes its plates a frame after it is built, through a SubViewport of
	# its own.
	for _i in 6:
		await get_tree().process_frame
	_hide_ghosts(_sv)
	_report(amp)

	# The RETRO XR receiver is 115 mm tall: its centre is 57.5 mm up.
	await _shoot("front", Vector3(0.0, 0.09, 0.62), Vector3(0.0, 0.06, 0.17))
	await _shoot("threequarter", Vector3(0.45, 0.30, 0.55), Vector3(0.0, 0.055, 0.0))
	await _shoot("back", Vector3(0.0, 0.09, -0.62), Vector3(0.0, 0.06, -0.17))
	# Close enough that the printed legend is legible: it spans x -0.03 .. 0.175.
	await _shoot("legend", Vector3(0.072, 0.07, -0.38), Vector3(0.072, 0.06, -0.18))
	amp.cycle_mode()
	await _shoot("front_dolby", Vector3(0.0, 0.09, 0.62), Vector3(0.0, 0.06, 0.17))
	amp.cycle_mode()

	# Leads in AUDIO IN and three of the six, the far ends parked behind the unit, so
	# the view shows whether a plug lands IN the jack or floats off it. The FL, C and SR
	# leads end in real cabinets, which is what lights the display — and those three of
	# its six speaker lamps — for the last shots.
	var cabs := {}
	var spot := 0
	for out_name in ["SpeakerOutL", "SpeakerOutC", "SpeakerOutSr"]:
		var cab := SATELLITE.instantiate() as Loudspeaker
		cab.freeze = true
		_sv.add_child(cab)
		cab.global_position = Vector3(0.45 - 0.45 * spot, 0.0, -0.4)
		cabs[out_name] = cab
		spot += 1
	var seats: Array[RcaPort] = [amp.get_node("AudioInL") as RcaPort,
		amp.get_node("AudioInR") as RcaPort, amp.get_node("SpeakerOutL") as RcaPort,
		amp.get_node("SpeakerOutC") as RcaPort, amp.get_node("SpeakerOutSr") as RcaPort]
	var i := 0
	for port in seats:
		var lead := LEAD.instantiate() as CompositeCable
		_sv.add_child(lead)
		await get_tree().process_frame
		var far := lead.get_node("PlugB0") as RigidBody3D
		port.pick_up_object(lead.get_node("PlugA0") as Node3D)
		if cabs.has(port.name):
			(cabs[port.name].get_node("SpeakerIn") as RcaPort).pick_up_object(far)
		else:
			far.freeze = true
			far.global_position = Vector3(port.position.x, 0.02 + 0.01 * i, -0.45)
		i += 1
	for _k in 30:
		await get_tree().process_frame
	_hide_ghosts(_sv)
	var seated := 0
	for port in seats:
		if port.seated_plug() != null:
			seated += 1
	print("[amp] %d of %d leads seated, speakers cabled: %s" % [seated, seats.size(),
		amp.has_cabled_speakers()])
	var lamps: Array[String] = []
	for k in SurroundAmp.SPEAKER_OUT_NAMES.size():
		if amp.vfd_lamp_lit(k):
			lamps.append(str(SurroundAmp.VFD_LAMPS[k][0]))
	print("[amp] display lamps lit: %s" % ", ".join(lamps))
	await _shoot("wired", Vector3(-0.25, 0.28, -0.55), Vector3(0.05, 0.065, -0.18))
	await _shoot("front_lit", Vector3(0.0, 0.09, 0.62), Vector3(0.0, 0.06, 0.17))
	await _shoot("threequarter_lit", Vector3(0.40, 0.26, 0.55), Vector3(0.0, 0.055, 0.05))
	# The display at a hand's length: the decoder's name, the level and the map.
	await _shoot("vfd_close", Vector3(-0.02, 0.09, 0.42), Vector3(-0.02, 0.075, 0.17))

	get_tree().quit(0)


func _build_world() -> void:
	_sv = SubViewport.new()
	_sv.size = SIZE
	_sv.own_world_3d = true
	_sv.transparent_bg = false
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 1.25
	env.environment = e
	_sv.add_child(env)

	_key = DirectionalLight3D.new()
	_key.light_energy = 2.0
	_sv.add_child(_key)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_sv.add_child(_cam)
	_cam.current = true


## A snap zone's ghost is visible in a bare instantiate; in the room it only shows
## while a compatible plug is held. Left on, it reads as geometry.
func _hide_ghosts(root: Node) -> void:
	for h in root.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false


## Printed rather than eyeballed: a recess is symmetric and reads the same either way
## round, so only the basis can say which way a socket opens.
func _report(amp: SurroundAmp) -> void:
	for n in ["AudioInL", "AudioInR"] + SurroundAmp.SPEAKER_OUT_NAMES:
		var p := amp.get_node(n) as RcaPort
		print("[amp] %-14s at %.3v  +Z -> %.3v  channel=%s direction=%s" % [n, p.position,
			p.transform.basis.z, RcaPort.CHANNEL_NAMES[p.channel],
			"IN" if p.direction == RcaPort.Direction.IN else "OUT"])
	for n in ["AvLegendIn", "AvLegendSpeakers"]:
		var legend := amp.get_node_or_null(n) as Node3D
		print("[amp] %s %s" % [n, "built" if legend != null else "MISSING"])


func _shoot(label: String, eye: Vector3, target: Vector3) -> void:
	# The key light comes over the shoulder of whichever side is being shot.
	_key.rotation_degrees = Vector3(-38.0, 28.0 if eye.z >= 0.0 else 208.0, 0.0)
	_cam.position = eye
	_cam.look_at(target, Vector3.UP)
	for _i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := _sv.get_texture().get_image()
	var path := "%s/amp_%s.png" % [_out_dir, label]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[amp] wrote %s" % path)
