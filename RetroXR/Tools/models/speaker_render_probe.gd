## Renders the surround loudspeakers and prints the facing of everything a lead or
## a voice attaches to.
##
##   godot --path RetroXR --resolution 900x700 --position 20,20 \
##     res://Tools/models/speaker_render_probe.tscn -- --out=<dir>
##
## WINDOWED, never --headless: the dummy renderer hands back a correctly sized
## blank, so a size oracle passes while the picture is empty.
##
## Drawn into a SubViewport with own_world_3d, because an uncomposited window
## swapchain reads back as clear colour only.
extends Node3D

const SAT := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const SUB := preload("res://Scenes/Objects/appliances/subwoofer.tscn")

## Unit directions to look FROM. The distance is derived from the subject so both
## cabinets fill the frame, rather than being a constant that suits one of them.
const VIEWS := [
	["baffle", Vector3(0.0, 0.18, 1.0)],
	["threequarter", Vector3(0.75, 0.42, 1.0)],
	["back", Vector3(-0.55, 0.30, -1.0)],
	["rear_on", Vector3(0.0, 0.0, -1.0)],
	["side_on", Vector3(1.0, 0.0, 0.0)],
]

var _out_dir := "res://probe_out"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.split("=")[1]
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	for spec in [["satellite", SAT], ["sub", SUB]]:
		var name: String = spec[0]
		var scene: PackedScene = spec[1]
		var obj := scene.instantiate() as Node3D
		add_child(obj)
		await get_tree().process_frame
		# A snap zone's ghost is visible in a bare instantiate — in the room the
		# zone only shows it while a compatible plug is held. Left on, a 30 mm
		# translucent cylinder stands out of the back panel and reads as geometry.
		for h in obj.find_children("SnapHighlight", "Node3D", true, false):
			(h as Node3D).visible = false
		_report(name, obj)
		for view in VIEWS:
			await _shoot("%s_%s" % [name, view[0]], obj, view[1])
		obj.queue_free()
		await get_tree().process_frame

	get_tree().quit(0)


## What a socket and a cone announce, printed rather than eyeballed: a recess is
## symmetric and reads the same either way round.
func _report(name: String, obj: Node3D) -> void:
	var cone := obj.find_child("ConeFront", true, false) as Node3D
	var port := obj.find_child("SpeakerIn", true, false) as Node3D
	print("[speaker] %s" % name)
	if cone != null:
		print("[speaker]   ConeFront at %.3v, +Z -> %.3v" % [cone.position, cone.transform.basis.z])
	if port != null:
		print("[speaker]   SpeakerIn at %.3v, +Z -> %.3v" % [port.position, port.transform.basis.z])
		print("[speaker]   channel=%d direction=%d" % [port.channel, port.direction])
	var aabb := _aabb_of(obj)
	print("[speaker]   aabb size=%.3v centre=%.3v" % [aabb.size, aabb.get_center()])


func _aabb_of(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _shoot(label: String, subject: Node3D, from: Vector3) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 700)
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 1.25
	env.environment = e
	sv.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_energy = 2.0
	sv.add_child(key)

	# Reparented rather than duplicated: the subject carries a snap zone and a
	# rope-less RcaPort, and a duplicate would register a second one in the room.
	var host := subject.get_parent()
	subject.get_parent().remove_child(subject)
	sv.add_child(subject)

	var box := _aabb_of(subject)
	var target := box.get_center()
	var cam := Camera3D.new()
	# 1.5 radii back along the view direction, so a 165 mm satellite and a 300 mm
	# subwoofer are framed the same rather than one of them being a speck.
	var radius: float = box.size.length() * 0.5
	cam.position = target + from.normalized() * radius * 2.6
	sv.add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true

	for _i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	var img := sv.get_texture().get_image()
	var path := "%s/speaker_%s.png" % [_out_dir, label]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[speaker] wrote %s" % path)

	sv.remove_child(subject)
	host.add_child(subject)
	sv.queue_free()
