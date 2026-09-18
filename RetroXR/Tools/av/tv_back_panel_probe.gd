## Renders the television's back panel and prints what every socket on it announces.
##
##   godot --path RetroXR --resolution 1100x800 --position 20,20 \
##     res://Tools/av/tv_back_panel_probe.tscn -- --out=<dir>
##
## WINDOWED, never --headless. Two reasons, and the second is specific to this panel:
## the dummy renderer hands back a correctly sized blank, and AvLegend only BAKES its
## printing when there is a rendering device — headless keeps the Label3D build, so a
## headless run measures a layout nobody sees.
extends Node3D

const TV := preload("res://Scenes/Objects/tv.tscn")

## Direction to look FROM in the set's own frame (the back panel is at -Z), and how
## far back in metres. Zero derives the distance from the cabinet's own AABB; the
## close views name it outright, because a distance derived from the 90 mm socket row
## puts the camera inside the cabinet.
const VIEWS := [
	["rear_on", Vector3(0.0, 0.0, -1.0), 0.0],
	["rear_threequarter", Vector3(-0.55, 0.30, -1.0), 0.0],
	["rows", Vector3(0.0, 0.0, -1.0), 0.30],
	["speaker_row", Vector3(0.0, 0.0, -1.0), 0.17],
	["speaker_row_angled", Vector3(-0.35, 0.22, -1.0), 0.20],
	# Raking and close, along the row rather than across it. The angle a player
	# reads the panel from when they are reaching into it, and the one that shows
	# a thin baked rule breaking up.
	["divider_raking", Vector3(-0.9, 0.18, -0.45), 0.22],
	["divider_raking_far", Vector3(-0.9, 0.18, -0.45), 0.6],
]

var _out_dir := "res://probe_out"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.split("=")[1]
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var tv := TV.instantiate() as RetroTV
	add_child(tv)
	# A set is an XRToolsPickable, so with no floor under it the cabinet falls — and
	# every framing here is measured off its sockets, so successive shots aimed at
	# where it used to be. The first run put the close views 600 mm below the panel.
	tv.freeze = true
	for _i in range(20):
		await get_tree().process_frame
	# A snap zone's ghost is visible on a bare instantiate; in the room it only shows
	# while a compatible plug is held, so left on it reads as geometry in the socket.
	for h in tv.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_report(tv)
	for view in VIEWS:
		await _shoot(tv, view[0], view[1], view[2])
	get_tree().quit(0)


func _report(tv: RetroTV) -> void:
	var panel := tv.panel()
	print("[panel] has_speaker_outs=%s  outs=%d" % [panel.has_speaker_outs(),
		panel.speaker_outs().size()])
	for out: RcaPort in panel.speaker_outs():
		print("[panel]   %-14s at %.3v  channel=%d %-7s direction=%d  +Z -> %.3v" % [
			out.name, out.position, out.channel, out.channel_name(), out.direction,
			out.transform.basis.z])
	for legend in tv.find_children("AvLegend*", "Node3D", true, false):
		print("[panel] legend %s at %.3v" % [legend.name, (legend as Node3D).position])


## World AABB of the speaker row alone, so the close view frames what it is named for
## rather than the whole cabinet.
func _row_aabb(tv: RetroTV) -> AABB:
	var out := AABB()
	var first := true
	for port: RcaPort in tv.panel().speaker_outs():
		var box := AABB(port.global_position, Vector3.ZERO)
		out = box if first else out.merge(box)
		first = false
	return out.grow(0.02)


func _aabb_of(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var box := mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _shoot(tv: RetroTV, label: String, from: Vector3, dist: float) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1100, 800)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.58, 0.60, 0.65)
	e.ambient_light_energy = 1.3
	env.environment = e
	sv.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 200.0, 0.0)
	key.light_energy = 1.8
	sv.add_child(key)

	# Reparented rather than duplicated: the set carries live snap zones, and a
	# duplicate would register a second bank of sockets in the room.
	var host := tv.get_parent()
	host.remove_child(tv)
	sv.add_child(tv)

	var wide := is_zero_approx(dist)
	var box := _aabb_of(tv) if wide else _row_aabb(tv)
	var target := box.get_center()
	var cam := Camera3D.new()
	cam.position = target + from.normalized() * (box.size.length() * 1.25 if wide else dist)
	sv.add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true
	print("[panel] %s: cam %.3v -> %.3v" % [label, cam.position, target])

	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	var path := "%s/tvpanel_%s.png" % [_out_dir, label]
	sv.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[panel] wrote %s" % path)

	sv.remove_child(tv)
	host.add_child(tv)
	sv.queue_free()
