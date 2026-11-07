## The AV switch in the bedroom, for its renders and the slide video: a real NES running BrickBreaker (MIT,
## Tools/room/roms) on INPUT 1, a Genesis switched OFF on INPUT 3 through its own A/V Cable, the RETRO XR set on TO TV.
## Writes hero.png (front, slide on 1, label 1 brightest, the set showing the NES), back.png (the leads seated),
## debug_tab.png (the switch's menu on its Debug tab) and frames/ for slide.mp4 (the slide 1 -> 2 -> 3 -> 4, labels and
## the set following), every frame rendered: run it with --fixed-fps 30.
##
## WINDOWED (headless draws nothing):
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 --fixed-fps 30 \
##         res://Tools/av/av_switch_probe.tscn -- --no-mods --out=/tmp/av_switch
## then encode frames/ with imageio (codec libx264, -crf 24, 30 fps). --stills writes the three stills only.
##
## Prints [avswitch-probe] lines; PASS needs the NES's picture on the set at slide 1 and gone at 2.
extends Node

const ROOM := preload("res://Scenes/BedroomScene.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const SWITCH_SCENE := preload("res://Scenes/Objects/appliances/av_switch.tscn")
const MONO_CABLE := preload("res://Scenes/Objects/cables/mono_composite_cable.tscn")
const CABLE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const GENESIS_AV_CABLE := preload("res://Scenes/Objects/system_models/genesis/genesis_av_cable.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const TABLE_SCENE := preload("res://Scenes/Objects/furniture/table.tscn")
const OUTLET_SCENE := preload("res://Scenes/Objects/room/wall_outlet.tscn")
const STRIP_SCENE := preload("res://Scenes/Objects/appliances/power_strip.tscn")
const BRICK_SCENE := preload("res://Scenes/Objects/power/power_brick.tscn")
const ROM := "res://Tools/room/roms/brix.nes"
const DESK_XZ := Vector2(-1.4, -1.5)
const SIZE := Vector2i(1280, 720)
## Frames held on each slide position in the video (at --fixed-fps 30: 1.6 s).
const HOLD := 48

var _out := ""
## --stills: the three stills only, no video.
var _stills := false
## --cord: power simulation ON, everything on a strip (the set's and the switch's own cords, the NES's adapter):
## cord_back.png (the switch's cord out of its strain relief into the strip) and cord_front.png (labels lit by it).
var _cord := false
var _sv: SubViewport
var _cam: Camera3D
var _frames := 0
var _recording := false
var _failed := false
var _top := 0.75
var _nes: RetroSystem
var _md: RetroSystem
var _tv: RetroTV
var _sw: AvSwitch


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--stills":
			_stills = true
		elif a == "--cord":
			_cord = true
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[avswitch-probe] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	var room := ROOM.instantiate()
	var rig := room.get_node_or_null("PlayerRig")
	if rig != null:
		room.remove_child(rig)
		rig.free()
	add_child(room)
	_sv = SubViewport.new()
	_sv.size = SIZE
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.near = 0.01
	_cam.fov = 50.0
	_sv.add_child(_cam)
	_cam.current = true
	var waited := 0
	while LoadingOverlay.is_active() and waited < 600:
		await get_tree().process_frame
		waited += 1
	LoadingOverlay.suspend()
	await _stage()
	if not _failed:
		await _shoot()
	print("[avswitch-probe] %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _put(node: Node3D, at: Vector3) -> Node3D:
	node.set("freeze", true)
	add_child(node)
	node.global_position = at
	node.add_to_group("spawned")
	return node


func _stage() -> void:
	var table := TABLE_SCENE.instantiate() as Node3D
	table.set("freeze", true)
	add_child(table)
	table.global_position = Vector3(DESK_XZ.x, 0.0, DESK_XZ.y)
	await _settle(10)
	_top = _surface_y(DESK_XZ)
	var base := Vector3(DESK_XZ.x, _top, DESK_XZ.y)
	_tv = TV_SCENE.instantiate() as RetroTV
	_tv.tv_model = "retroxr_crt"
	_put(_tv, base + Vector3(0.0, 0.0, -0.30))
	_sw = _put(SWITCH_SCENE.instantiate() as Node3D, base + Vector3(0.0, 0.0, 0.16)) as AvSwitch
	_nes = SYSTEM_SCENE.instantiate() as RetroSystem
	_nes.name = "NES"
	_nes.systemid = "nes"
	_nes.model_id = "nes"
	_nes.core_name = "fceumm"
	_put(_nes, base + Vector3(-0.42, 0.06, 0.12))
	_md = SYSTEM_SCENE.instantiate() as RetroSystem
	_md.name = "Genesis"
	_md.systemid = "genesis"
	_md.model_id = "genesis"
	_put(_md, base + Vector3(0.42, 0.06, 0.12))
	await _settle(120)
	for body: Node3D in [_tv, _sw, _nes, _md]:
		_rest_on(body, _top)
	await _settle(20)
	# Leads: the NES's mono lead into INPUT 1, the Genesis's own into INPUT 3, a stereo lead from TO TV into the set.
	var nes_lead := MONO_CABLE.instantiate() as Node3D
	var md_lead := GENESIS_AV_CABLE.instantiate() as Node3D
	var tv_lead := CABLE.instantiate() as Node3D
	for lead: Node3D in [nes_lead, md_lead, tv_lead]:
		add_child(lead)
		lead.global_position = base + Vector3(0, 0.2, 0.3)
	await _settle(20)
	_seat(_nes, "VideoOut", nes_lead, "PlugA0")
	_seat(_nes, "AudioLOut", nes_lead, "PlugA1")
	_seat(_sw, "Input1Video", nes_lead, "PlugB0")
	_seat(_sw, "Input1AudioL", nes_lead, "PlugB1")
	_seat(_md, "AvMultiOut", md_lead, "PlugA0")
	for c in 3:
		_seat(_sw, ["Input3Video", "Input3AudioL", "Input3AudioR"][c], md_lead, "PlugB%d" % c)
		_seat(_sw, ["VideoOut", "AudioLOut", "AudioROut"][c], tv_lead, "PlugA%d" % c)
		_seat(_tv, ["CompositePort", "AudioLIn", "AudioRIn"][c], tv_lead, "PlugB%d" % c)
	await _settle(90)
	if _cord:
		await _power_up(base)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.set("rom_path", ProjectSettings.globalize_path(ROM))
	cart.set("systemid", "nes")
	cart.set("game_label", "BrickBreaker")
	add_child(cart)
	_nes.restore_cartridge(cart)
	await _settle(60)
	if _nes.has_method("is_tray_down") and not _nes.is_tray_down():
		_nes.toggle_cart_tray()
		await _settle(60)
	(_nes.get_node("PowerButton") as VRButton).button_pressed.emit()
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not (_nes.is_powered_on and _nes.sends_video_to(_tv)
			and _nes.get_video_texture() != null):
		await get_tree().process_frame
	print("[avswitch-probe] NES on %s, picture to the set through the switch %s" % [_nes.is_powered_on,
		_nes.sends_video_to(_tv)])
	if not _nes.sends_video_to(_tv):
		_failed = true
		print("[avswitch-probe] FAIL the NES's picture does not reach the set at slide 1")
	await _wait(90)
	print("[avswitch-probe] %s" % _sw.describe_wiring())


## --cord: a wall outlet behind the desk, a strip on the desk, and into it the set's cord, the switch's own cord and the
## NES's AC adapter (its DC plug in the NES); then power simulation on.
func _power_up(base: Vector3) -> void:
	var outlet := OUTLET_SCENE.instantiate() as Node3D
	_put(outlet, base + Vector3(0.55, 0.05, -0.30))
	var strip := STRIP_SCENE.instantiate() as Node3D
	_put(strip, base + Vector3(0.30, 0.02, -0.05))
	var brick := BRICK_SCENE.instantiate() as PowerBrick
	brick.brick_id = "nes_ac_adapter"
	add_child(brick)
	brick.global_position = base + Vector3(-0.30, 0.05, -0.10)
	await _settle(30)
	_rest_on(strip, _top)
	var sockets: Array = strip.call("sockets")
	(outlet.get_node("TopPort") as PowerPort).pick_up_object(strip.get("wall_plug"))
	var tv_cord := _tv.power_input().captive as CaptiveMainsCord
	var sw_cord := _sw.power_input().captive as CaptiveMainsCord
	(sockets[0] as PowerPort).pick_up_object(sw_cord.wall_plug)
	(sockets[1] as PowerPort).pick_up_object(tv_cord.wall_plug)
	(sockets[2] as PowerPort).pick_up_object(brick.wall_plug)
	(_nes.find_child("PowerInlet", true, false) as XRToolsSnapZone).pick_up_object(brick.dc_plug)
	await _settle(30)
	AppPrefs.power_simulation = true
	MainsPower.changed(get_tree())
	await _settle(30)
	print("[avswitch-probe] --cord: switch %s (%s), set %s, NES %s" % [_sw.powered(), _sw.power_input().describe(),
		_tv.power_input().is_live(), PowerInput.of(_nes).is_live() if PowerInput.of(_nes) else "?"])
	if not _sw.powered():
		_failed = true
		print("[avswitch-probe] FAIL the switch has no supply with its cord in the strip")


func _shoot() -> void:
	if _cord:
		await _shoot_cord()
		return
	var front := _sw.global_position + Vector3(0, 0.03, 0)
	# Hero: front three-quarter, low, the set behind with its picture.
	_aim(front + Vector3(0.20, 0.13, 0.46), _sw.global_position + Vector3(0.02, 0.09, -0.16))
	await _wait(20)
	await _still("hero.png")
	# The back: over the set's shoulder, down onto the switch's jacks and the leads.
	_aim(_sw.global_position + Vector3(-0.34, 0.24, -0.26), _sw.global_position + Vector3(-0.02, 0.01, -0.05))
	await _wait(20)
	await _still("back.png")
	if _stills:
		return
	# The slide: the front with the set in frame, every frame recorded.
	_aim(front + Vector3(0.14, 0.14, 0.48), _sw.global_position + Vector3(0.02, 0.10, -0.16))
	await _wait(10)
	_recording = true
	await _wait(HOLD)
	var picture_at := []
	for k in [1, 2, 3, 0]:
		_sw.select(k)
		await _wait(HOLD)
		picture_at.append("%d:%s" % [k + 1, _nes.sends_video_to(_tv)])
	_recording = false
	print("[avswitch-probe] NES on the set per slide position %s" % ", ".join(picture_at))
	if picture_at[0] != "2:false":
		_failed = true
		print("[avswitch-probe] FAIL the NES stayed on the set with the slide on 2")
	# The menu's Debug tab.
	var panel := _sw.get_node("AvSwitchOptionsPanel") as AvSwitchOptionsPanel
	panel.show_for(_sw, _cam)
	await _wait(20)
	var ui := panel.ui_2d()
	if ui != null:
		ui.show_debug_tab()
		panel.refresh()
	await _wait(20)
	var p := panel.global_position
	_aim(p + Vector3(0, 0, 0.62), p)
	await _wait(30)
	await _still("debug_tab.png")
	print("[avswitch-probe] frames %d" % _frames)


func _shoot_cord() -> void:
	_sw._refresh_labels(true)
	_aim(_sw.global_position + Vector3(-0.30, 0.22, -0.30), _sw.global_position + Vector3(-0.08, 0.0, -0.06))
	await _wait(30)
	await _still("cord_back.png")
	var front := _sw.global_position + Vector3(0, 0.03, 0)
	_aim(front + Vector3(0.20, 0.13, 0.46), _sw.global_position + Vector3(0.02, 0.09, -0.16))
	await _wait(30)
	await _still("cord_front.png")
	print("[avswitch-probe] labels %s, the selected input %d" % [[_sw.label_state(0), _sw.label_state(1),
		_sw.label_state(2), _sw.label_state(3)], int(_sw.call("selected_index")) + 1 if _sw.has_method("selected_index") else -1])


func _seat(dev: Node, port_name: String, lead: Node, plug: String) -> void:
	var zone := dev.find_child(port_name, true, false) as XRToolsSnapZone
	var p := lead.get_node_or_null(plug) as Node3D
	if zone == null or p == null:
		_failed = true
		print("[avswitch-probe] FAIL cannot seat %s in %s.%s" % [plug, dev.name, port_name])
		return
	zone.pick_up_object(p)


func _aim(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)


func _rest_on(body: Node3D, y: float) -> void:
	var box := AABB()
	var first := true
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first:
		body.global_position.y += y - box.position.y


func _surface_y(xz: Vector2) -> float:
	var space := _cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 2.2, xz.y), Vector3(xz.x, -0.5, xz.y), 0xFFFFFFFF)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.75


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
		if _recording:
			_sv.get_texture().get_image().save_jpg(_out.path_join("frames/f_%05d.jpg" % _frames), 0.92)
			_frames += 1


func _still(name: String) -> void:
	await RenderingServer.frame_post_draw
	_sv.get_texture().get_image().save_png(_out.path_join(name))
	print("[avswitch-probe] wrote %s" % name)
