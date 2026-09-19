extends Node3D

## Photographs the RXR-004 aerial: standing on a set, its lead in the coax socket,
## and then in the ANT socket of an RF switch whose pigtail is in that socket.
##
## Windowed, not --headless — the dummy renderer returns a blank image:
##   godot --path RetroXR --resolution 900x700 --position 20,20 \
##     res://Tools/av/antenna_probe.tscn
##
## Four PNGs land in res://probe_out/ (gitignored): antenna_front, antenna_back,
## antenna_menu (its own Tab menu, opened through the base the way the pointer's walk
## finds it) and antenna_switch. Each prints what the set believes at the time, so a picture of a
## lead that LOOKS seated cannot stand in for one that is: the log line beside
## antenna_switch.png has to say the set found the aerial through the switch.
##
## The aerial receives a fixed sample lineup (no network), so the dial line is the
## same on every machine.

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const ANTENNA_SCENE := preload("res://Scenes/Objects/appliances/antenna.tscn")
const RF_SWITCH_SCENE := preload("res://Scenes/Objects/appliances/rf_switch.tscn")

## The sample lineup: a TVLineup with the network taken out.
class SampleLineup extends TVLineup:
	func _ready() -> void:
		pass

	func is_loaded() -> bool:
		return true

	func reload_channels() -> void:
		pass


var _sv: SubViewport = null
var _cam: Camera3D = null
var _tv: RetroTV = null
var _antenna: Antenna = null


func _ready() -> void:
	get_tree().create_timer(80.0).timeout.connect(func() -> void:
		print("[antenna] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(900, 700)
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.31, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.87, 0.95)
	e.ambient_light_energy = 0.7
	env.environment = e
	_sv.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	key.light_energy = 1.3
	_sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 160.0, 0.0)
	fill.light_energy = 0.8
	_sv.add_child(fill)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_sv.add_child(_cam)
	_cam.current = true

	_tv = TV_SCENE.instantiate() as RetroTV
	_tv.freeze = true
	_sv.add_child(_tv)
	await _frames(30)

	# Stood on the set: the cabinet's top, plus half the base.
	var top := maxf(HeldHint.visual_top(_tv), 0.2)
	_antenna = ANTENNA_SCENE.instantiate() as Antenna
	var lineup := SampleLineup.new()
	lineup.name = "TVLineup"
	_antenna._lineup = lineup
	_antenna.add_child(lineup)
	_antenna.position = Vector3(0.0, top + 0.016, 0.0)
	(_antenna.get_node("Body") as RigidBody3D).freeze = true
	_sv.add_child(_antenna)
	for n: String in ["2.1", "4.1", "10.2"]:
		lineup.channels.append({"number": n, "name": "STATION %s" % n,
			"url": "stub://%s" % n, "source": "stub"})
	lineup.channels_changed.emit()
	await _frames(20)

	var rf := _tv.get_node("RfPort") as RcaPort
	var plug := _antenna.get_node("PlugB0") as RcaPlug
	print("[antenna] body basis x=%s y=%s z=%s" % [
		(_antenna.get_node("Body") as Node3D).global_transform.basis.x,
		(_antenna.get_node("Body") as Node3D).global_transform.basis.y,
		(_antenna.get_node("Body") as Node3D).global_transform.basis.z])
	print("[antenna] coax socket at %s, facing %s" % [rf.global_position,
		rf.global_transform.basis.z])
	rf.pick_up_object(plug)
	await _frames(90)                       # let the lead hang

	_tv.set_source(RetroTV.Source.RF)
	_report("direct")
	_look(Vector3(0.75, top + 0.30, 1.25), Vector3(0.0, top * 0.55, 0.0))
	await _shoot("antenna_front")

	var back: Vector3 = rf.global_position
	_look(back + Vector3(0.55, 0.30, -0.75), back + Vector3(0.0, 0.10, 0.10))
	await _shoot("antenna_back")

	# ── its own menu, opened the way Tab opens it ──
	# Through the BASE, which is the node the pointer's walk actually finds. Asked of
	# the live panel afterwards: a menu that opened but never populated looks fine
	# in a thumbnail.
	var base := _antenna.get_node("Body") as Node3D
	base.call("toggle_options_ui", _cam)
	await _frames(40)
	var menu := base.get_node_or_null("AntennaOptionsPanel") as AntennaOptionsPanel
	var ui: AntennaOptions2D = menu._get_ui() if menu != null else null
	print("[antenna] menu: opened=%s visible=%s link='%s' rows=%d" % [menu != null,
		menu != null and menu.visible,
		ui._link_status.text if ui != null else "", ui._channels.size() if ui != null else -1])
	_look(Vector3(0.55, top + 0.62, 1.55), Vector3(0.0, top + 0.45, 0.0))
	await _shoot("antenna_menu")
	base.call("toggle_options_ui", _cam)
	await _frames(6)
	print("[antenna] menu: closed again=%s" % (menu != null and not menu.visible))

	# ── through the switch ──
	rf.enabled = false
	rf.drop_object()
	await _frames(6)
	var switch := RF_SWITCH_SCENE.instantiate() as RfSwitch
	switch.position = back + Vector3(0.28, -0.05, -0.22)
	(switch.get_node("Body") as RigidBody3D).freeze = true
	_sv.add_child(switch)
	(switch.get_node("PlugA0") as RigidBody3D).freeze = true
	await _frames(20)
	rf.enabled = true
	rf.pick_up_object(switch.get_node("PlugB0") as RcaPlug)
	await _frames(10)
	switch.ant_port().pick_up_object(plug)
	await _frames(90)
	_report("via switch")
	var box: Vector3 = (switch.get_node("Body") as Node3D).global_position
	_look(box + Vector3(0.30, 0.26, -0.42), box + Vector3(-0.06, 0.02, 0.06))
	await _shoot("antenna_switch")

	print("[antenna] done")
	get_tree().quit(0)


## What the set believes, which is the part a photograph cannot show.
func _report(how: String) -> void:
	var found := _tv.aerial()
	var labels: Array = []
	for stop: Dictionary in _tv.rf_dial():
		labels.append(str(stop["ch"]) if stop["kind"] == "rf"
			else str(found.lineup().channels[int(stop["index"])].get("number", "")))
	print("[antenna] %s: set has aerial=%s via_switch=%s dial=%s" % [how,
		found == _antenna, _antenna.via_switch(), labels])


func _look(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)


func _shoot(shot: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://probe_out")
	_sv.get_texture().get_image().save_png("res://probe_out/%s.png" % shot)
	print("[antenna] saved probe_out/%s.png" % shot)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
