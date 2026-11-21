## What inputs a cabinet builds from its layout (TvInputKinds), and where. Prints every
## input's sockets and, for the Panasonic CT-20D10B mod (it re-seats its sockets by
## NAME onto its model's markers after the set is ready), checks each landed on its
## marker: the regression check for that mod across the 2026-11-21 inputs refactor.
## Probes keep the player's installed mods mounted. Windowed for the photo:
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 \
##     res://DevTools/av/tv_layout_probe.tscn -- [--shell=<tv_model>] [--out=<dir>]
##
## --shell= "" is the stock body; retroxr_crt, crt_plain, xenu.panasonic:ct20d10b.
## Exits 1 when a check fails.
extends Node3D

const PANASONIC := "xenu.panasonic:ct20d10b"
## The mod's own table (panasonic.gd _finish_fit): socket name -> model marker.
const PANASONIC_SEATS := {
	"CompositePort": "PortVideoIn", "AudioLIn": "PortAudioInL", "AudioRIn": "PortAudioInR",
	"CompositePort2": "PortFrontVideoIn", "AudioLIn2": "PortFrontAudioInL",
	"AudioRIn2": "PortFrontAudioInR", "RfPort": "PortRF",
}

var _out := ""
var _shell := PANASONIC
var _failed := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--shell="):
			_shell = a.substr(8)
	if _out.is_empty():
		_out = OS.get_user_data_dir()
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[tv-layout] timed out")
		get_tree().quit(2))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.21, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 160, 0)
	add_child(light)
	var tv := preload("res://Scenes/Objects/tv.tscn").instantiate() as RetroTV
	tv.tv_model = _shell
	tv.freeze = true
	add_child(tv)
	await _frames(60)
	print("[tv-layout] shell '%s' -> %s" % [_shell, tv.shell().get_class() if tv.shell() != null else "stock body"])
	for id: int in tv.panel().input_ids():
		var names: PackedStringArray = []
		for port: RcaPort in tv.panel()._av_ports[id]:
			names.append("%s%s @ %s" % [port.name, "" if port.enabled and port.is_visible_in_tree() else " (OFF)",
				_v(port.position)])
		print("[tv-layout] %d %s: %s" % [id, TvInputKinds.osd_name(id), ", ".join(names)])
	print("[tv-layout] SOURCE order %s" % [tv.available_sources()])
	if _shell == PANASONIC:
		_check_panasonic(tv)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _frames(60)
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.make_current()
	var back := tv.global_transform.basis.z * -1.0
	var target := tv.global_position + Vector3(0, -0.12, 0) + back * 0.2
	for shot in [["back", target + back * 0.55 + Vector3(-0.15, 0.15, 0)], ["front", tv.global_position + Vector3(0.2, 0.1, 1.0)]]:
		cam.global_position = shot[1]
		cam.look_at(target if shot[0] == "back" else tv.global_position)
		await _frames(4)
		await RenderingServer.frame_post_draw
		var path := _out.path_join("tv_layout_%s_%s.png" % [_shell.replace(":", "_") if not _shell.is_empty() else "stock", shot[0]])
		get_viewport().get_texture().get_image().save_png(path)
		print("[tv-layout] wrote %s" % path)
	print("[tv-layout] %s" % ("PASS" if _failed == 0 else "FAIL %d" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)


func _check_panasonic(tv: RetroTV) -> void:
	var shell := tv.shell()
	if shell == null or not shell.has_method("_port_pose"):
		_fail("the Panasonic mod is not installed or not enabled")
		return
	_expect(Array(tv.panel().input_ids()) == [0, 1, 5], "its inputs are Composite 1, 2 and RF: %s" % [tv.panel().input_ids()])
	for socket: String in PANASONIC_SEATS:
		var port := tv.get_node_or_null(socket) as RcaPort
		if port == null:
			_fail("%s is missing" % socket)
			continue
		var want: Transform3D = shell.call("_port_pose", PANASONIC_SEATS[socket])
		_expect(port.transform.origin.distance_to(want.origin) < 0.0005
			and port.transform.basis.z.dot(want.basis.z) > 0.999,
			"%s sits on %s (%s vs %s)" % [socket, PANASONIC_SEATS[socket], _v(port.transform.origin), _v(want.origin)])
		_expect(port.enabled and port.is_visible_in_tree(), "%s is live" % socket)
	for gone in ["CompositePort3", "VgaPort", "HdmiPort", "SvideoIn", "ComponentY", "ScartIn"]:
		_expect(tv.get_node_or_null(gone) == null, "no %s on it" % gone)
	for legend in tv.find_children("AvLegend*", "", false, false):
		_expect(not (legend as Node3D).visible, "%s hidden (its texture prints them)" % legend.name)


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("[tv-layout] ok    %s" % what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failed += 1
	print("[tv-layout] FAIL  %s" % what)


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
