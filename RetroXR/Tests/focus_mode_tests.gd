## focus_mode_tests — VR focus mode: a device's picture on a floating screen while
## the room is hidden around it.
##
##   godot --headless --path RetroXR res://Tests/focus_mode_tests.tscn [-- --only=<group>]
##
## The hands, pointers and pickups are stand-ins answering the names FocusMode and
## FocusScreen read; the devices are real.
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

const HAND_SRC := """extends Node3D
var inputs := {}
func get_float(n: String) -> float: return float(inputs.get(n, 0.0))
func get_vector2(n: String) -> Vector2: return inputs.get(n, Vector2.ZERO)
"""
const POINTER_SRC := "extends Node3D\nvar collision_mask := 1048576\nvar last_target: Node3D = null\n"
const PICKUP_SRC := "extends Node\nvar picked_up_object: Node3D = null\n"
const PLUG_SRC := "extends Node3D\nvar controller: Node3D = null\nfunc get_controller() -> Node3D: return controller\n"
const LEAD_SRC := "extends Node3D\nvar bus: Array = []\nfunc linked_machines() -> Array: return bus\n"
const LINK_PLUG_SRC := "extends Node3D\nvar cable: Node3D = null\n"

var _checks := 0
var _failed := 0
var _only := ""

var _rig: Node3D
var _camera: Camera3D
var _left: Node3D
var _right: Node3D
var _left_pointer: Node3D
var _right_pointer: Node3D
var _right_pickup: Node
var _loco: LocomotionManager
var _menu: Node3D
var _fm: FocusMode


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[test] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[test] %d checks, %d failures" % [_checks, _failed])
	print("[test] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[test] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ── fixtures ──────────────────────────────────────────────────────────────────


func _run() -> void:
	_build_rig()
	if _want("enter"):
		await _enter_cases()
	if _want("room"):
		await _room_cases()
	if _want("keep"):
		await _keep_cases()
	if _want("suspend"):
		await _suspend_cases()
	if _want("controls"):
		await _controls_cases()
	if _want("view"):
		await _view_cases()
	if _want("toggle"):
		await _toggle_cases()
	if _want("screen"):
		await _screen_cases()
	if _want("audio"):
		await _audio_cases()
	if _want("life"):
		await _life_cases()


func _stub(source: String, node: Node) -> Node:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	node.set_script(script)
	return node


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.5, 2.0)
	_rig.add_child(_camera)
	_camera.current = true
	_left = _hand("LeftController")
	_right = _hand("RightController")
	_left_pointer = _left.get_node("FunctionPointer")
	_right_pointer = _right.get_node("FunctionPointer")
	var left_pickup := _stub(PICKUP_SRC, Node.new())
	_left.add_child(left_pickup)
	_right_pickup = _stub(PICKUP_SRC, Node.new())
	_right.add_child(_right_pickup)
	_loco = LocomotionManager.new()
	_rig.add_child(_loco)
	_menu = Node3D.new()
	_menu.visible = false
	_rig.add_child(_menu)
	_fm = FocusMode.new()
	_rig.add_child(_fm)
	var hands: Array[Node3D] = [_left, _right]
	var pointers: Array[Node] = [_left_pointer, _right_pointer]
	var pickups: Array[Node] = [left_pickup, _right_pickup]
	_fm.configure(_camera, _right, hands, pointers, pickups, _loco, _menu)


func _hand(hand_name: String) -> Node3D:
	var hand := _stub(HAND_SRC, Node3D.new()) as Node3D
	hand.name = hand_name
	_rig.add_child(hand)
	hand.global_position = _camera.global_position + Vector3(0.2, -0.3, -0.3)
	var pointer := _stub(POINTER_SRC, Node3D.new()) as Node3D
	pointer.name = "FunctionPointer"
	hand.add_child(pointer)
	return hand


func _set_input(hand: Node3D, input_name: String, value: Variant) -> void:
	(hand.get("inputs") as Dictionary)[input_name] = value


func _prop(prop_name: String) -> Node3D:
	var prop := Node3D.new()
	prop.name = prop_name
	prop.position = Vector3(-3, 1, -1)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	prop.add_child(mesh)
	add_child(prop)
	return prop


## A pickable room child, the shape a card, pak or cartridge has.
func _pickable(prop_name: String) -> XRToolsPickable:
	var pickable := XRToolsPickable.new()
	pickable.name = prop_name
	pickable.position = Vector3(-3, 1, 1)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	pickable.add_child(mesh)
	add_child(pickable)
	return pickable


## `obj` seated in a real socket on `host`.
func _seat(host: Node3D, obj: Node3D) -> void:
	var zone := SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	host.add_child(zone)
	zone.pick_up_object(obj)


func _tv() -> RetroTV:
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.position = Vector3(3, 1.5, 0)
	tv.freeze = true
	add_child(tv)
	await _wait(5)
	return tv


func _handheld(systemid: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = Vector3(3, 1.5, 1.5)
	sys.freeze = true
	add_child(sys)
	await _wait(30)
	return sys


## Video out of the machine into the set's first composite socket.
func _cable(sys: RetroSystem, tv: RetroTV) -> Node3D:
	var cable := CABLE_SCENE.instantiate() as Node3D
	cable.position = Vector3(3, 1.5, 0.8)
	add_child(cable)
	await _wait(20)
	var from := sys.get_node_or_null("VideoOut") as RcaPort
	var to := tv.get_node_or_null("CompositePort") as RcaPort
	if from != null and to != null:
		from.pick_up_object(cable.get_node("PlugA0") as RcaPlug)
		to.pick_up_object(cable.get_node("PlugB0") as RcaPlug)
	await _wait(30)
	return cable


# ── cases ─────────────────────────────────────────────────────────────────────


func _enter_cases() -> void:
	var tv := await _tv()
	var chair := _prop("Chair")
	_ok(not _fm.is_active(), "enter/idle until asked")
	_ok(not _fm.enter(null), "enter/nothing is refused")
	_ok(not _fm.enter(chair), "enter/a thing with no picture is refused")
	_ok(_fm.enter(tv), "enter/a television is taken")
	var screen := _fm.screen()
	_ok(_fm.is_active() and screen != null and screen.get_parent() == _fm,
		"enter/the screen hangs off the rig, not the room")
	_ok(not _fm.enter(tv), "enter/a second enter while focused is refused")
	_fm.leave()
	_ok(not _fm.is_active() and not is_instance_valid(screen), "enter/leaving frees the screen")
	_fm.leave()
	_ok(not _fm.is_active(), "enter/a second leave is harmless")
	tv.free()
	chair.free()
	await _wait(2)


func _room_cases() -> void:
	var tv := await _tv()
	var shown := _prop("Shown")
	var hidden := _prop("AlreadyHidden")
	hidden.visible = false
	_fm.enter(tv)
	_ok(not shown.visible, "room/a prop stops being drawn")
	_ok(not tv.visible, "room/the focused set is hidden too; its picture is on the screen")
	_ok(_rig.visible and _camera.is_visible_in_tree(), "room/the rig stays drawn")
	var late := _prop("Late")
	await _wait(1)
	_ok(not late.visible, "room/something arriving while focused is hidden")
	shown.visible = true
	_fm._process(0.0)
	_ok(not shown.visible, "room/a hidden prop that shows itself is hidden again")
	_fm.leave()
	_ok(shown.visible and late.visible, "room/leaving draws the room again")
	_ok(not hidden.visible, "room/what was hidden before focus stays hidden after")
	tv.free()
	shown.free()
	hidden.free()
	late.free()
	await _wait(2)


func _keep_cases() -> void:
	var gb := await _handheld("game_boy")
	var pad := _prop("Pad")
	var pad_cable := _prop("PadCable")
	var plug := _stub(PLUG_SRC, Node3D.new()) as Node3D
	plug.set("controller", pad)
	pad_cable.add_child(plug)
	plug.add_to_group("controller_plug")

	var lead_root := _prop("LinkLead")
	var far := _prop("FarMachine")
	var lead := _stub(LEAD_SRC, Node3D.new()) as Node3D
	lead_root.add_child(lead)
	var link_plug := _stub(LINK_PLUG_SRC, Node3D.new()) as Node3D
	link_plug.set("cable", lead)
	lead_root.add_child(link_plug)
	link_plug.add_to_group("link_plug")

	var other_root := _prop("OtherLead")
	var other := _stub(LEAD_SRC, Node3D.new()) as Node3D
	other.set("bus", [{"machine": far}, {"machine": pad}])
	other_root.add_child(other)
	var other_plug := _stub(LINK_PLUG_SRC, Node3D.new()) as Node3D
	other_plug.set("cable", other)
	other_root.add_child(other_plug)
	other_plug.add_to_group("link_plug")

	var loose := _prop("Loose")
	gb._port_controllers[1] = pad
	lead.set("bus", [{"machine": gb, "port": 0}, {"machine": far, "port": 0}])

	var card := _pickable("Card")
	var pak := _pickable("Pak")
	var cart := _pickable("Cart")
	var shelf := _prop("Shelf")
	var shelved := _pickable("Shelved")
	# Inner socket first, so one pass over the sockets in order would miss the cartridge.
	_seat(pak, cart)
	_seat(pad, card)
	_seat(pad, pak)
	_seat(shelf, shelved)
	await _wait(2)

	_fm.enter(gb)
	_ok(gb.visible, "keep/the focused handheld stays in view")
	_ok(pad.visible, "keep/a pad in the machine's port stays in view")
	_ok(pad_cable.visible, "keep/and the cord its plug hangs on")
	_ok(card.visible, "keep/a card seated in that pad stays in view with it")
	_ok(card.enabled, "keep/and can still be pulled out")
	_ok(pak.visible and cart.visible, "keep/a pak in the pad, and the cartridge in the pak")
	_ok(not shelf.visible and not shelved.visible,
		"keep/something seated in a hidden thing is hidden with it")
	_ok(lead_root.visible and far.visible,
		"keep/a link lead to the machine, and the machine at its far end")
	_ok(not other_root.visible, "keep/a lead between two other machines is hidden")
	_ok(not loose.visible, "keep/a loose prop is hidden")
	_right_pickup.set("picked_up_object", loose.get_child(0))
	_fm._refresh_room()
	_ok(loose.visible, "keep/something held is drawn, found from the part the hand has")
	_right_pickup.set("picked_up_object", null)
	_fm._refresh_room()
	_ok(loose.visible, "keep/and stays drawn once let go, so it can be picked up again")
	gb._port_controllers[1] = null
	_fm._refresh_room()
	_ok(not pad.visible and not pad_cable.visible,
		"keep/a pad no longer in the port is hidden with its cord")
	_ok(not card.visible and not cart.visible, "keep/and with what is seated in it")
	_fm.leave()
	_ok(card.visible and cart.visible and shelved.visible, "keep/leaving draws the seated things again")
	# Sockets before what they hold, a frame apart: a release defers an escape check
	# on the body, and a body freed in the same frame reaches it as a freed object.
	for node: Node in [pad, shelf, pad_cable, lead_root, far, other_root, loose]:
		node.free()
	await _wait(2)
	pak.free()
	await _wait(2)
	for node: Node in [card, cart, shelved]:
		node.free()
	gb.free()
	await _wait(2)

	# On a set, the machine on its selected input is the one whose ports count.
	var tv := await _tv()
	var console := await _handheld("nes")
	var cable := await _cable(console, tv)
	var nes_pad := _prop("NesPad")
	console._port_controllers[0] = nes_pad
	_fm.enter(tv)
	_ok(nes_pad.visible, "keep/on a set, the pad in the machine it is showing stays in view")
	_ok(not console.visible, "keep/while that machine itself is hidden")
	_fm.leave()
	console._port_controllers[0] = null
	nes_pad.free()
	tv.free()
	await _wait(2)
	console.free()
	await _wait(2)
	cable.free()
	await _wait(2)


func _suspend_cases() -> void:
	var tv := await _tv()
	var shelf := _prop("Shelf")
	var pickable := XRToolsPickable.new()
	shelf.add_child(pickable)
	var locked := XRToolsPickable.new()
	locked.enabled = false
	shelf.add_child(locked)
	var button := VRButton.new()
	var cap := MeshInstance3D.new()
	cap.name = "ButtonMesh"
	cap.mesh = BoxMesh.new()
	button.add_child(cap)
	shelf.add_child(button)
	var held := _prop("Held")
	var held_pickable := XRToolsPickable.new()
	held.add_child(held_pickable)
	await _wait(2)
	_right_pickup.set("picked_up_object", held)
	_ok(button.is_processing(), "suspend/a poke widget polls while the room is drawn")
	_fm.enter(tv)
	_ok(not pickable.enabled, "suspend/a hidden pickable cannot be picked up")
	_ok(not button.is_processing(), "suspend/a hidden poke widget stops polling for a hand")
	_ok(held_pickable.enabled, "suspend/what is kept is left alone")
	_fm.leave()
	_right_pickup.set("picked_up_object", null)
	_ok(pickable.enabled and button.is_processing(), "suspend/both come back on leaving")
	_ok(not locked.enabled, "suspend/a pickable already disabled stays disabled")
	tv.free()
	shelf.free()
	held.free()
	await _wait(2)


func _controls_cases() -> void:
	var tv := await _tv()
	var before: int = _right_pointer.get("collision_mask")
	_fm.enter(tv)
	_ok(int(_right_pointer.get("collision_mask")) == FocusScreen.LAYER
		and int(_left_pointer.get("collision_mask")) == FocusScreen.LAYER,
		"controls/both lasers see only the screen")
	_ok(_loco.is_blocked(LocomotionManager.CHANNEL_LEFT)
		and _loco.is_blocked(LocomotionManager.CHANNEL_RIGHT),
		"controls/walking and turning are blocked")
	_fm.leave()
	_ok(int(_right_pointer.get("collision_mask")) == before
		and int(_left_pointer.get("collision_mask")) == before,
		"controls/the lasers get their own mask back")
	_ok(not _loco.is_blocked(LocomotionManager.CHANNEL_ALL), "controls/locomotion is released")
	tv.free()
	await _wait(2)


func _view_cases() -> void:
	var tv := await _tv()
	var was_lights: bool = QualityManager.screen_lights_enabled
	QualityManager.screen_lights_enabled = true
	_camera.environment = null
	_fm.enter(tv)
	var env := _camera.environment
	_ok(env != null and env.background_mode == Environment.BG_COLOR
		and env.background_color == Color.BLACK, "view/the camera draws a black void")
	_ok(env != null and not env.glow_enabled and not env.ssao_enabled,
		"view/with no full-frame effects")
	_ok(_fm.get_node_or_null("FocusLight") is DirectionalLight3D,
		"view/a light, so what is held is not black")
	_ok(not QualityManager.screen_lights_enabled, "view/screen lights are off")
	_fm.leave()
	_ok(_camera.environment == null, "view/the room's environment is back in charge")
	_ok(_fm.get_node_or_null("FocusLight") == null, "view/the light goes")
	_ok(QualityManager.screen_lights_enabled, "view/screen lights come back on")

	var own := Environment.new()
	_camera.environment = own
	QualityManager.screen_lights_enabled = false
	_fm.enter(tv)
	_fm.leave()
	_ok(_camera.environment == own, "view/a camera's own environment comes back as the same one")
	_ok(not QualityManager.screen_lights_enabled, "view/screen lights that were off stay off")
	_camera.environment = null
	QualityManager.screen_lights_enabled = was_lights
	tv.free()
	await _wait(2)


func _toggle_cases() -> void:
	var tv := await _tv()
	var lamp := _prop("Lamp")
	_fm.toggle_from(null)
	_ok(not _fm.is_active(), "toggle/pointing at nothing does nothing")
	_fm.toggle_from(lamp.get_child(0))
	_ok(not _fm.is_active(), "toggle/pointing at a lamp does nothing")
	_fm.toggle_from(tv.screen_mesh())
	_ok(_fm.is_active(), "toggle/pointing at a set's glass enters")
	_fm.toggle_from(lamp.get_child(0))
	_ok(_fm.is_active(), "toggle/while focused, anything but the screen is ignored")
	_fm.toggle_from(_fm.screen().get_node("Body"))
	_ok(not _fm.is_active(), "toggle/pointing at the screen leaves")
	tv.free()
	lamp.free()
	await _wait(2)


func _screen_cases() -> void:
	var tv := await _tv()
	_fm.enter(tv)
	var screen := _fm.screen()
	var cam := _camera.global_position
	_ok(is_equal_approx(screen.width(), FocusScreen.START_WIDTH)
		and is_equal_approx(screen.height(), FocusScreen.START_WIDTH / RetroTV.ASPECT_4_3),
		"screen/a set's picture starts at 4:3")
	_ok(absf(screen.global_position.distance_to(cam) - FocusScreen.DISTANCE) < 0.01
		and screen.global_transform.basis.z.normalized().dot(
			(cam - screen.global_position).normalized()) > 0.99,
		"screen/placed ahead of the player, picture side toward them")
	tv.widescreen = true
	screen._process(0.0)
	_ok(is_equal_approx(screen.height(), screen.width() / RetroTV.ASPECT_16_9),
		"screen/the widescreen button reshapes it")
	tv.widescreen = false
	screen.set_width(100.0)
	_ok(is_equal_approx(screen.width(), FocusScreen.MAX_WIDTH), "screen/size clamps at the top")
	screen.set_width(0.0)
	_ok(is_equal_approx(screen.width(), FocusScreen.MIN_WIDTH), "screen/and at the bottom")
	screen.set_width(FocusScreen.START_WIDTH)
	screen._process(0.0)
	var box := (screen.get_node("Body").get_child(0) as CollisionShape3D).shape as BoxShape3D
	_ok(is_equal_approx(box.size.x, screen.width()) and is_equal_approx(box.size.y, screen.height()),
		"screen/the laser target is the picture's size")

	# The corner handle, dragged by a laser from the eye.
	var pointer := Node3D.new()
	add_child(pointer)
	var w0 := screen.width()
	var aspect := w0 / screen.height()
	var corner := screen.to_global(Vector3(w0 * 0.5, -screen.height() * 0.5, 0.0))
	var further := screen.to_global(Vector3(w0 * 0.7, -screen.height() * 0.7, 0.0))
	pointer.look_at_from_position(cam, corner, Vector3.UP)
	screen.resize_begin(pointer)
	pointer.look_at_from_position(cam, further, Vector3.UP)
	screen._process(0.0)
	_ok(absf(screen.width() - w0 * 1.4) < 0.01 and absf(screen.width() / screen.height() - aspect) < 0.001,
		"screen/dragging the corner outwards grows it with the corner, aspect held")
	screen.resize_end()
	var w1 := screen.width()
	pointer.look_at_from_position(cam, corner, Vector3.UP)
	screen._process(0.0)
	_ok(is_equal_approx(screen.width(), w1), "screen/let go, the laser moving changes nothing")
	pointer.free()

	# Carried along a hand's ray.
	screen.set_width(FocusScreen.START_WIDTH)
	var body := screen.get_node("Body")
	_right.global_position = cam + Vector3(0.2, -0.3, -0.3)
	_right.look_at(screen.global_position, Vector3.UP)
	_right_pointer.set("last_target", body)
	_set_input(_right, "grip", 1.0)
	screen._process(0.0)
	var reach := _right.global_position.distance_to(screen.global_position)
	_right.global_position += Vector3(0.5, 0.0, 0.0)
	screen._process(0.0)
	var along := _right.global_position - _right.global_transform.basis.z * reach
	_ok(screen.global_position.distance_to(along) < 0.001,
		"screen/gripped with the laser on it, it rides that hand's ray")
	_set_input(_right, "primary", Vector2(0.0, 1.0))
	screen._process(0.5)
	_set_input(_right, "primary", Vector2.ZERO)
	screen._process(0.0)
	_ok(absf(_right.global_position.distance_to(screen.global_position)
		- (reach + FocusScreen.DEPTH_SPEED * 0.5)) < 0.01, "screen/stick forward pushes it away")
	_set_input(_right, "grip", 0.0)
	screen._process(0.0)
	var parked := screen.global_position
	_right.global_position += Vector3(0.0, 0.5, 0.0)
	screen._process(0.0)
	_ok(screen.global_position.is_equal_approx(parked), "screen/let go, it stays where it was put")

	_right_pointer.set("last_target", null)
	_set_input(_right, "grip", 1.0)
	screen._process(0.0)
	_right_pointer.set("last_target", body)
	screen._process(0.0)
	_ok(screen._grab_hand == null, "screen/a grip already closed when the laser arrives does not grab")
	_set_input(_right, "grip", 0.0)
	screen._process(0.0)
	_right_pointer.visible = false
	_set_input(_right, "grip", 1.0)
	screen._process(0.0)
	_ok(screen._grab_hand == null, "screen/a hand whose laser is off for what it holds cannot grab")
	_right_pointer.visible = true
	_set_input(_right, "grip", 0.0)
	screen._process(0.0)
	_right_pointer.set("last_target", null)
	_fm.leave()
	tv.free()
	await _wait(2)

	var ds := await _handheld("nds")
	_fm.enter(ds)
	screen = _fm.screen()
	var quads := screen.find_children("*", "MeshInstance3D", false, false)
	_ok(quads.size() == 2, "screen/a DS gets two panels")
	if quads.size() == 2:
		var top := quads[0] as MeshInstance3D
		var bottom := quads[1] as MeshInstance3D
		_ok(top.position.y > bottom.position.y and is_equal_approx(
			top.position.y - bottom.position.y, (top.mesh as QuadMesh).size.y),
			"screen/top over bottom, touching")
		var rect: Vector4 = (bottom.material_override as ShaderMaterial).get_shader_parameter("source_rect")
		_ok(rect.is_equal_approx(Vector4(0.0, 0.5, 1.0, 0.5)),
			"screen/the bottom panel samples the lower half of the frame")
	_fm.leave()
	ds.free()
	await _wait(2)

	# A device describing its own panel: mirrored, with a texture it swaps.
	var device := _stub("extends Node3D\nvar panels: Array = []\nfunc fullscreen_panels() -> Array: return panels\n",
		Node3D.new()) as Node3D
	add_child(device)
	var glass := MeshInstance3D.new()
	glass.mesh = QuadMesh.new()
	device.add_child(glass)
	var tex_a := ImageTexture.create_from_image(Image.create(48, 32, false, Image.FORMAT_RGB8))
	var tex_b := ImageTexture.create_from_image(Image.create(48, 32, false, Image.FORMAT_RGB8))
	var shown: Array[Texture2D] = [tex_a]
	device.set("panels", [{
		"mesh": glass,
		"texture_fn": func() -> Texture2D: return shown[0],
		"region": Rect2(0, 0, 1, 1),
		"aspect_fn": func() -> float: return 1.5,
		"fit_fn": func() -> Vector2: return Vector2.ONE,
		"flip_h": true,
	}])
	_ok(_fm.enter(device), "screen/a device with fullscreen_panels is taken")
	screen = _fm.screen()
	var mat := (screen.find_children("*", "MeshInstance3D", false, false)[0] as MeshInstance3D) \
		.material_override as ShaderMaterial
	_ok(mat.get_shader_parameter("flip_h") == true, "screen/a panel stored mirrored is drawn flipped")
	_ok(mat.get_shader_parameter("source_tex") == tex_a, "screen/it samples the device's own texture")
	shown[0] = tex_b
	screen._process(0.0)
	_ok(mat.get_shader_parameter("source_tex") == tex_b, "screen/and follows it when the device swaps")
	_fm.leave()
	device.free()
	await _wait(2)


func _audio_cases() -> void:
	var gb := await _handheld("game_boy")
	_fm.enter(gb)
	_fm._process(0.0)
	var at := _fm.screen().speaker_positions()
	_ok(gb._audio._head_lock, "audio/a focused machine's sound is held")
	var held: Dictionary = gb._audio.resolve_emission(Vector3(9, 9, 9), Vector3(9, 9, 8), Vector3.FORWARD)
	_ok((held["left"] as Vector3).distance_to(at[0]) < 0.001
		and (held["right"] as Vector3).distance_to(at[1]) < 0.001,
		"audio/its two channels sound from the screen's two edges")
	_ok(at[0].distance_to(at[1]) > 1.0, "audio/as far apart as the screen is wide")
	_fm.leave()
	_ok(not gb._audio._head_lock, "audio/leaving hands the sound back to the room")
	gb.free()
	await _wait(2)


func _life_cases() -> void:
	var tv := await _tv()
	_fm.enter(tv)
	tv.free()
	_fm._process(0.0)
	_ok(not _fm.is_active() and _camera.environment == null
		and not _loco.is_blocked(LocomotionManager.CHANNEL_ALL),
		"life/the device going away puts everything back")

	tv = await _tv()
	_menu.visible = true
	_fm.enter(tv)
	_fm._process(0.0)
	_ok(_fm.is_active(), "life/a menu already open when focus starts does not end it")
	_menu.visible = false
	_fm._process(0.0)
	_menu.visible = true
	_fm._process(0.0)
	_ok(not _fm.is_active(), "life/opening the menu ends focus")
	_menu.visible = false
	tv.free()
	await _wait(2)
