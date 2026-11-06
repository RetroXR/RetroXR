## Films an NES-001 being hooked up in the bedroom, for the welcome page's second page
## (Welcome2D.HOOKUP_CLIP): the AV lead into the console and the set, a pad into port
## 1, the flap up, a cartridge laid in the tray and pressed down, the flap shut, POWER,
## and START on the pad -- every step through the same calls a hand's own makes
## (snap zones' pick_up_object, the model's flap and tray, the POWER VRButton), with a
## real core running a real homebrew ROM on the set at the end.
##
## Its own camera in a SubViewport, captions drawn over it, and the frames taken on
## the WALL clock at FPS (a slow frame is repeated, never stretched), because the core
## runs on its own thread in real time and a game-time video would show it fast or
## slow. The bedroom's PlayerRig is taken out, as bedroom_probe's --empty-room does:
## it is what restores the player's saved room, and no welcome page or menu belongs in
## the film. Mods off (--no-mods), so it is the stock NES.
##
## WINDOWED (headless draws nothing):
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 \
##         res://Tools/room/nes_hookup_probe.tscn -- --no-mods --out=/tmp/hookup \
##         [--rom=res://Tools/room/roms/brix.nes] [--core=fceumm] [--layout]
##     python Tools/art/encode_welcome_clip.py /tmp/hookup --clip hookup
##
## --layout places everything already connected and saves a still from each framing,
## to tune the stage by; nothing is recorded. --rope-trace (with --layout, and once
## mid-film) logs the AV lead's middle point tick by tick; --old-seat carries the plugs
## the old way, a step a rendered frame in a straight line, as the control leg for the
## cord jerk every carry logs (docs/dev/welcome.md, "Cords on film").
extends Node

const ROOM := preload("res://Scenes/BedroomScene.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/mono_composite_cable.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_controller.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const TABLE_SCENE := preload("res://Scenes/Objects/furniture/table.tscn")

## BrickBreaker by Aleff Correa, MIT (roms/LICENSE-brix.txt).
const DEFAULT_ROM := "res://Tools/room/roms/brix.nes"
const GAME_LABEL := "BrickBreaker"
const START_BIT := 1 << 3

const FPS := 30
## How far over the higher of its two ends a carried plug is lifted on the way.
const ARC_LIFT := 0.12
## How far out from its socket each of the AV lead's plugs is laid on the table.
const LAY_OUT := 0.16
const SIZE := Vector2i(1280, 720)

## The stage: a table out from the wall with the string lights, its top found by
## casting down. The console and the set side by side, both facing the camera; the
## table stands 0.35 m clear of the wall so a camera fits behind the set, where its
## inputs are. The pad, the cart and the lead lie in front.
const DESK_XZ := Vector2(-1.4, -1.5)

var _out := ""
var _layout := false
var _rope_trace := false
## The old carry, one step a RENDERED frame, as the control leg for the cord jerk.
var _old_seat := false
var _watching := false
var _rom := ""
var _core := "fceumm"
var _sv: SubViewport = null
var _cam: Camera3D = null
var _caption: Label = null
var _caption_box: PanelContainer = null
var _t0 := -1
var _frames := 0
var _recording := false
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_t := 1.0
var _cam_len := 1.0
var _failed := false

var _sys: RetroSystem = null
var _tv: RetroTV = null
var _cable: Node3D = null
var _pad: Node3D = null
var _cart: Node3D = null
var _top := 0.75
## The console's front, level, once it is turned to the camera.
var _front := Vector3.BACK


func _ready() -> void:
	_rom = ProjectSettings.globalize_path(DEFAULT_ROM)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--layout":
			_layout = true
		elif a == "--rope-trace":
			_rope_trace = true
		elif a == "--old-seat":
			_old_seat = true
		elif a.begins_with("--rom="):
			_rom = ProjectSettings.globalize_path(a.trim_prefix("--rom="))
		elif a.begins_with("--core="):
			_core = a.trim_prefix("--core=")
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("[hookup] TIMEOUT")
		get_tree().quit(1))
	print("[hookup] rom %s (exists %s), core %s" % [_rom, FileAccess.file_exists(_rom), _core])
	_run()


func _run() -> void:
	var room := ROOM.instantiate()
	var rig := room.get_node_or_null("PlayerRig")
	if rig != null:
		room.remove_child(rig)
		rig.free()
	add_child(room)
	_build_camera()
	var waited := 0
	while LoadingOverlay.is_active() and waited < 600:
		await get_tree().process_frame
		waited += 1
	LoadingOverlay.suspend()
	await _stage()
	if _failed:
		_end()
		return
	if _layout:
		for body: Node3D in [_sys, _tv]:
			var c := _world_bounds(body).get_center()
			var parts := 0
			for vis: Node in body.find_children("*", "GeometryInstance3D", true, false):
				var g := vis as GeometryInstance3D
				if g.is_visible_in_tree() and not _under_pickable(g, body):
					parts += 1
			print("[hookup] self-check: the middle of %s reads inside %s (%d drawn parts counted)" % [body.name, _inside_body(c), parts])
		await _connect_all_now()
		if _rope_trace:
			await _trace_rope(240, 24)
		for shot: String in ["wide", "jacks", "tv_back", "front", "slot", "tv"]:
			_frame_on(shot, 0.0)
			await _tick(10)
			await _save_still("layout_%s.png" % shot)
		_end()
		return
	await _film()
	_end()


# ── the stage ─────────────────────────────────────────────────────────────────

func _stage() -> void:
	var table := TABLE_SCENE.instantiate() as Node3D
	table.set("freeze", true)
	add_child(table)
	table.global_position = Vector3(DESK_XZ.x, 0.0, DESK_XZ.y)
	await _settle(10)
	_top = _surface_y(DESK_XZ)
	print("[hookup] table top at %.3f m" % _top)
	var base := Vector3(DESK_XZ.x, _top, DESK_XZ.y)
	_tv = TV_SCENE.instantiate() as RetroTV
	_tv.tv_model = "retroxr_crt"
	_tv.freeze = true
	add_child(_tv)
	_tv.global_position = base + Vector3(0.12, 0.0, -0.08)
	_tv.add_to_group("spawned")

	_sys = SYSTEM_SCENE.instantiate() as RetroSystem
	_sys.systemid = "nes"
	_sys.model_id = "nes"
	_sys.core_name = _core
	_sys.freeze = true
	add_child(_sys)
	_sys.global_position = base + Vector3(-0.36, 0.06, -0.05)
	_sys.add_to_group("spawned")

	_cart = CART_SCENE.instantiate() as Node3D
	_cart.set("rom_path", _rom)
	_cart.set("systemid", "nes")
	_cart.set("game_label", GAME_LABEL)
	_cart.set("freeze", true)
	add_child(_cart)
	_cart.global_position = base + Vector3(-0.08, 0.03, 0.25)
	_cart.rotation_degrees = Vector3(-90, 0, 0)

	_pad = PAD_SCENE.instantiate() as Node3D
	_pad.set("freeze", true)
	add_child(_pad)
	_pad.global_position = base + Vector3(-0.62, 0.03, 0.27)
	_pad.add_to_group("spawned")

	await _settle(200)
	# The console's front to the camera, the way the set faces. The front is the
	# console's own axis nearest its controller ports: the ports sit right of the
	# middle, so aiming at them turned it 37 deg off.
	var front := _front_axis()
	_sys.rotate_y(-atan2(front.x, front.z))
	print("[hookup] console turned %.0f deg so its front faces the camera"
		% rad_to_deg(atan2(front.x, front.z)))
	await _settle(10)
	# Both stood ON the table: placed by their origins they were not (the set's
	# origin is not its underside, and it sat sunk into the top).
	_rest_on(_tv, _top)
	_rest_on(_sys, _top)
	await _settle(30)
	_front = _front_axis()
	await _lay_cable()
	await _lay_pad_cord()
	print("[hookup] staged: console %s, set %s, pad plug %s" % [_sys.global_position,
		_tv.global_position, _pad.call("get_plug") if _pad.has_method("get_plug") else null])
	for need: Array in [["VideoOut", _sys], ["AudioLOut", _sys], ["CompositePort", _tv],
			["AudioLIn", _tv], ["ControllerPort1", _sys], ["CartridgeSlot", _sys], ["PowerButton", _sys]]:
		if (need[1] as Node).find_child(need[0], true, false) == null:
			_fail("no %s on %s" % [need[0], (need[1] as Node).name])


## The AV lead laid out on the table, each plug a hand's width out from its own
## socket: the A pair behind the console, the B pair behind the set, each pair in its
## sockets' order. Dropped anywhere, the lead slid off the table and its B end lay on
## the FLOOR, a metre from the set, so every plug was hauled up over the table's edge
## and the cord jolted on film; and the B pair lay crossed, swapping sides on the way.
func _lay_cable() -> void:
	_cable = CABLE_SCENE.instantiate() as Node3D
	# One offset per END, so a pair lies side by side in its sockets' order.
	var ends := [[["PlugA0", _sys, "VideoOut"], ["PlugA1", _sys, "AudioLOut"]],
		[["PlugB0", _tv, "CompositePort"], ["PlugB1", _tv, "AudioLIn"]]]
	for pair: Array in ends:
		var zones: Array[XRToolsSnapZone] = []
		for e: Array in pair:
			var z := _port(e[1], e[2])
			if z == null or _cable.get_node_or_null(e[0]) == null:
				_fail("cannot lay %s by %s" % [e[0], e[2]])
				return
			zones.append(z)
		var offset := _lay_offset(zones)
		if offset == Vector3.INF:
			_fail("nowhere on the table clear of the console and the set for %s" % pair[0][0])
			return
		for k in pair.size():
			var at := zones[k].global_position + offset
			at.y = _top + 0.012
			(_cable.get_node(pair[k][0]) as Node3D).position = at  # the lead's root is at the origin
			print("[hookup] %s laid at %s, %.0f mm from %s" % [pair[k][0], at,
				Vector2(offset.x, offset.z).length() * 1000.0, pair[k][2]])
	add_child(_cable)
	await _settle(240)


## The pad's cord laid in ONE bend on the table, never crossing itself: the plug a
## hand's width out from port 1, the cord a circular arc of its own length from the
## pad to it. Dropped, the cord lay in loops over each other, and such a loop never
## quite sleeps (docs/dev/rope.md): it twitched all through the film. An arc crosses
## itself only once it closes a full circle, so a long cord bends further round (up to
## 330 deg) rather than the pad being moved (moved out to fit half a circle, it fell
## off the table). Whichever way round has every point on the table and clear of the
## console and the set.
func _lay_pad_cord() -> void:
	var rope := _rope_of("ControllerCable")
	var plug := _pad.call("get_plug") as RigidBody3D if _pad.has_method("get_plug") else null
	var port := _port(_sys, "ControllerPort1")
	if rope == null or plug == null or port == null:
		_fail("cannot lay the pad's cord (rope %s, plug %s, port %s)" % [rope, plug, port])
		return
	var y := _top + 0.006
	var plug_at := port.global_position + _out_of(port) * LAY_OUT
	plug_at.y = y
	var pad_at := _pad.global_position
	pad_at.y = y
	var count := int(rope.call("point_count"))
	var length := float(rope.get("segment_length")) * (count - 1)
	var a: Vector3 = rope.call("point_position", 0)
	var plug_first := a.distance_to(plug.global_position) < a.distance_to(_pad.global_position)
	var along := pad_at - plug_at
	along.y = 0.0
	var chord := along.length()
	var dir := along.normalized()
	if length <= chord:
		_fail("the pad's cord (%.2f m) is shorter than the way to its port (%.2f m)" % [length, chord])
		return
	# The arc's angle: L / d = t / (2 sin(t / 2)), which grows from 1 to infinity on (0, 2 pi).
	var lo := 0.01
	var hi := TAU - 0.01
	for k in 80:
		var mid := (lo + hi) * 0.5
		if mid / (2.0 * sin(mid / 2.0)) * chord > length:
			hi = mid
		else:
			lo = mid
	var t := (lo + hi) * 0.5
	if t > deg_to_rad(330.0):
		_fail("the pad's cord needs %.0f deg of arc: put the pad further from the port" % rad_to_deg(t))
		return
	var radius := chord / (2.0 * sin(t / 2.0))
	var best := PackedVector3Array()
	var best_bad := 1 << 30
	var best_side := ""
	for sgn: float in [1.0, -1.0]:
		var bow := dir.cross(Vector3.UP) * sgn
		var centre := (plug_at + pad_at) * 0.5 - bow * radius * cos(t / 2.0)
		var pts := PackedVector3Array()
		var bad := 0
		for i in count:
			var f := float(i) / (count - 1)
			if not plug_first:
				f = 1.0 - f
			var ang := -t / 2.0 + f * t
			var at := centre + (bow * cos(ang) + dir * sin(ang)) * radius
			at.y = y
			if absf(_surface_y(Vector2(at.x, at.z)) - _top) > 0.02 or not _inside_body(at, 0.01).is_empty():
				bad += 1
			pts.append(at)
		if bad < best_bad:
			best = pts
			best_bad = bad
			best_side = "toward the camera" if bow.dot(_front) > 0.0 else "away from the camera"
	plug.global_position = plug_at + Vector3.UP * 0.004
	plug.linear_velocity = Vector3.ZERO
	var laid: bool = rope.call("restore_points", best)
	print("[hookup] pad cord (%.2f m) laid in one bend %s: chord %.2f m, %.0f deg of arc, radius %.2f m, %d of %d points off the table or in a body, %s" % [
		length, best_side, chord, rad_to_deg(t), radius, best_bad, count, "laid" if laid else "REFUSED by the rope"])
	if not laid:
		_fail("the pad's cord would not take its lay")
	await _settle(240)


## Where on the table a pair is laid, as an offset from each socket: straight out
## from the socket first, then along the socket panel's own side. Every plug of the
## pair must lie ON the table and clear of the console and the set (a plug laid under
## the set's back went up through it on its way in). INF when nowhere is.
func _lay_offset(zones: Array[XRToolsSnapZone]) -> Vector3:
	var out := _out_of(zones[0])
	var side := out.cross(Vector3.UP).normalized()
	var tries: Array[Vector3] = []
	for d: float in [LAY_OUT, 0.20, 0.24, 0.12]:
		tries.append(out * d)
	for sd: float in [0.10, 0.14, 0.18, 0.24, 0.30]:
		for sgn: float in [1.0, -1.0]:
			tries.append(out * 0.06 + side * sd * sgn)
	for off: Vector3 in tries:
		var good := true
		for z: XRToolsSnapZone in zones:
			var at := z.global_position + off
			at.y = _top + 0.012
			if absf(_surface_y(Vector2(at.x, at.z)) - _top) > 0.02 or not _inside_body(at, 0.03).is_empty():
				good = false
				break
		if good:
			return off
	return Vector3.INF


## Whether `at` is within `margin` of the console's or the set's DRAWN parts, each
## part's box taken in its own frame: its name, or "" when clear. Not the collision:
## the console's shapes reach well past its shell (a point 16 cm out from a jack was
## "inside"), and not one axis-aligned box: both bodies are turned.
func _inside_body(at: Vector3, margin := 0.0) -> String:
	for body: Node3D in [_sys, _tv]:
		for vis: Node in body.find_children("*", "GeometryInstance3D", true, false):
			var g := vis as GeometryInstance3D
			if not g.is_visible_in_tree() or _under_pickable(g, body):
				continue
			var local := g.global_transform.affine_inverse() * at
			if g.get_aabb().grow(margin).has_point(local):
				return str(body.name)
	return ""


## Straight out of the jack `zone` sits in: across, from the middle of the thing it is
## on, through the jack. The jack's own Z is not it (on the console's jacks it points
## up, and the plugs came down through the console's lid on their way in).
func _out_of(zone: XRToolsSnapZone) -> Vector3:
	for body: Node3D in [_sys, _tv]:
		if body.is_ancestor_of(zone):
			var d := zone.global_position - _world_bounds(body).get_center()
			d.y = 0.0
			if d.length() > 0.001:
				return d.normalized()
	return zone.global_basis.z.normalized()


## The way a plug is carried from `from` to `back` (just out from its socket, which
## faces `out`): up off the table, round to a point straight out behind the socket,
## and in, as waypoints for _along. Raised over the console or the set wherever the
## way would meet one (the B pair, laid beside the set, went up through its back to
## sockets behind it). The cartridge (`direct`) goes straight over to its tray.
func _carry_path(from: Vector3, back: Vector3, out: Vector3, direct: bool) -> PackedVector3Array:
	var high := maxf(from.y, back.y) + ARC_LIFT
	if direct:
		var mid := (from + back) * 0.5
		mid.y = high
		return PackedVector3Array([from, mid, back])
	var behind := back + out * 0.06
	for i in 8:
		var pts := PackedVector3Array([from, Vector3(from.x, high, from.z),
			Vector3(behind.x, high, behind.z), behind, back])
		var hits := 0
		for k in 41:
			if not _inside_body(_along(pts, k / 40.0), 0.012).is_empty():
				hits += 1
		if hits == 0:
			return pts
		high += 0.05
	var where: Array[String] = []
	var last := PackedVector3Array([from, Vector3(from.x, high, from.z), Vector3(behind.x, high, behind.z), behind, back])
	for k in 41:
		var hit := _inside_body(_along(last, k / 40.0), 0.012)
		if not hit.is_empty():
			where.append("%.2f" % (k / 40.0))
	print("[hookup] no clear way found over the bodies from %s; the highest tried is used. Meets a body at u %s; behind %s, back %s, seat-side point clear: %s" % [
		from, " ".join(where), _inside_body(behind, 0.012), _inside_body(back, 0.012), _inside_body(back, 0.0)])
	return PackedVector3Array([from, Vector3(from.x, high, from.z), Vector3(behind.x, high, behind.z), behind, back])


## A point `u` (0 to 1) of the way along `pts`, on a Catmull-Rom curve through them:
## smooth, so the plug never turns a corner its cord would be jerked by.
func _along(pts: PackedVector3Array, u: float) -> Vector3:
	var n := pts.size() - 1
	var f := clampf(u, 0.0, 1.0) * n
	var i := mini(int(f), n - 1)
	var t := f - i
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, n)]
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)


## Everything connected at once, no motion: for --layout.
func _connect_all_now() -> void:
	_port(_sys, "VideoOut").pick_up_object(_plug("PlugA0"))
	_port(_sys, "AudioLOut").pick_up_object(_plug("PlugA1"))
	_port(_tv, "CompositePort").pick_up_object(_plug("PlugB0"))
	_port(_tv, "AudioLIn").pick_up_object(_plug("PlugB1"))
	_port(_sys, "ControllerPort1").pick_up_object(_pad.call("get_plug"))
	_sys.restore_cartridge(_cart)
	await _settle(60)


# ── the film ──────────────────────────────────────────────────────────────────

func _film() -> void:
	_recording = true
	_t0 = Time.get_ticks_msec()
	_capture()
	_say("The NES, a TV, an AV lead, a pad and a cartridge")
	_frame_on("wide", 0.0)
	await _hold(2.0)
	_report_ropes("staged")

	_say("1  The AV lead into the console: yellow is the picture, red the sound")
	_frame_on("jacks", 1.2)
	await _hold(1.2)
	await _seat_all([_plug("PlugA0"), _plug("PlugA1")],
		[_port(_sys, "VideoOut"), _port(_sys, "AudioLOut")], 1.6)
	await _hold(0.6)
	_report_ropes("console end in")

	_say("2  ...and into the TV's inputs, yellow to yellow, red to red")
	_frame_on("tv_back", 1.2)
	await _hold(1.2)
	await _seat_all([_plug("PlugB0"), _plug("PlugB1")],
		[_port(_tv, "CompositePort"), _port(_tv, "AudioLIn")], 1.8)
	await _hold(0.6)
	_report_ropes("set end in")

	_say("3  A controller into port 1")
	_frame_on("front", 1.2)
	await _hold(1.0)
	await _seat(_pad.call("get_plug") as Node3D, _port(_sys, "ControllerPort1"), 1.2)
	await _hold(0.6)
	_report_ropes("pad in")
	if _rope_trace:
		await _trace_rope(0, 24)

	var model := _sys.get_model()
	_frame_on("slot", 1.0)
	await _hold(1.0)
	_say("4  Lift the flap")
	model.call("play_open")
	await _hold(1.0)
	_say("5  Lay the cartridge in the tray...")
	var slot := _port(_sys, "CartridgeSlot")
	await _seat(_cart, slot, 1.4, "preview")
	await _hold(0.6)
	_say("6  ...and press it down until it clicks")
	_sys.toggle_cart_tray()
	await _hold(1.2)
	_say("7  Shut the flap")
	model.call("play_close")
	await _hold(1.0)
	print("[hookup] tray down %s, reading %s" % [_sys.is_tray_down(), _sys.get_snapped_cartridge() == _cart])
	if not _sys.is_tray_down():
		_fail("the tray did not latch down")

	_report_ropes("cartridge in")
	_say("8  Press POWER")
	await _hold(0.6)
	(_sys.get_node("PowerButton") as VRButton).button_pressed.emit()
	await _hold(1.0)
	_frame_on("tv", 1.4)
	var shown := await _wait_for_picture(12.0)
	print("[hookup] powered %s, picture on the set %s" % [_sys.is_powered_on, shown])
	if not shown:
		_fail("no picture on the set")
	_say("The game is on. Press START on the controller to play")
	await _hold(3.0)

	_say("9  START")
	var before := _snapshot()
	var poke := PressPoke.new(_pad)
	_pad.set("_poke", poke)
	poke.held = START_BIT
	await _hold(0.35)
	poke.held = 0
	await _hold(2.0)
	var changed := _changed(before, _snapshot())
	print("[hookup] the game changed after START: %s" % changed)
	if not changed:
		_fail("START changed nothing on the set")
	# BrickBreaker's first START shows its instructions; the second starts play.
	_say("10  START again, and play")
	poke.held = START_BIT
	await _hold(0.35)
	poke.held = 0
	await _hold(3.0)
	_say("That is all there is to it. Every console in the room works the same way")
	await _hold(3.0)
	_recording = false
	print("[hookup] wrote %d frames (%.1f s)" % [_frames, float(_frames) / FPS])


## Move `obj` to just off `zone`'s seat (or its preview perch) over `seconds`, then
## seat it with the zone's own pick_up_object, as a hand letting go there does.
func _seat(obj: Node3D, zone: XRToolsSnapZone, seconds: float, aim := "seat") -> void:
	await _seat_all([obj], [zone], seconds, aim)


## _seat for several things at once, each to its own zone, carried side by side: the
## AV lead's yellow and red plugs, as a hand holds the pair. One at a time, the first
## seated held its end of the lead's short fork while the second was carried away
## from it, and the fork snapped taut (an 81-111 mm jolt in one tick, _watch_cord).
func _seat_all(objs: Array, zones: Array, seconds: float, aim := "seat") -> void:
	var plan: Array[Dictionary] = []
	for i in objs.size():
		var obj := objs[i] as Node3D
		var zone := zones[i] as XRToolsSnapZone
		if obj == null or zone == null:
			_fail("nothing to seat (%s into %s)" % [obj, zone])
			return
		var seat := zone.preview_pose_for(obj) if aim == "preview" else zone.snap_pose_for(obj)
		# Just off the seat, back along the way it goes in and a little above, so the
		# last stretch reads as pushing it home.
		var out := _out_of(zone) if aim != "preview" else seat.basis.z.normalized()
		var back := seat.origin + out * 0.06 + Vector3.UP * 0.01
		var start := obj.global_transform
		plan.append({"obj": obj, "zone": zone, "seat": seat, "back": back, "start": start, "out": out})
		if obj is RigidBody3D:
			(obj as RigidBody3D).freeze = true
	for p: Dictionary in plan:
		p["path"] = _carry_path((p["start"] as Transform3D).origin, p["back"], p["out"], aim == "preview")
	if plan.size() == 2:
		var lie: Vector3 = (plan[0]["start"] as Transform3D).origin - (plan[1]["start"] as Transform3D).origin
		var goes: Vector3 = (plan[0]["back"] as Vector3) - (plan[1]["back"] as Vector3)
		print("[hookup] pair %s/%s: %.0f mm apart lying, %.0f mm apart at the sockets, %s" % [
			plan[0]["obj"].name, plan[1]["obj"].name, lie.length() * 1000.0, goes.length() * 1000.0,
			"same order" if lie.dot(goes) > 0.0 else "CROSSED (they swap sides on the way)"])
		for p: Dictionary in plan:
			print("[hookup]   %s from %s to %s" % [p["obj"].name, (p["start"] as Transform3D).origin, p["back"]])
	_watching = true
	var carrying := "+".join(objs.map(func(o: Node3D) -> String: return str(o.name)))
	_watch_cord(carrying)
	_watch_cord(carrying, "ControllerCable")
	if _old_seat:
		# The control leg: one step a RENDERED frame, in a straight line.
		var n := maxi(1, int(seconds * FPS))
		for i in n:
			var k := smoothstep(0.0, 1.0, float(i + 1) / n)
			for p: Dictionary in plan:
				var st: Transform3D = p["start"]
				var se: Transform3D = p["seat"]
				var bk: Vector3 = p["back"]
				(p["obj"] as Node3D).global_transform = Transform3D(st.basis.slerp(se.basis, k),
					st.origin.lerp(bk, k) if k < 0.85 else bk.lerp(se.origin, (k - 0.85) / 0.15))
			await _tick(1)
	else:
		# A step every PHYSICS tick, timed on the wall clock: the cord's solver reads
		# the plug each tick, and moved once a rendered frame (three ticks at the
		# film's rate) the cord was yanked in steps and swung back and forth on film.
		var began := Time.get_ticks_msec()
		var t := 0.0
		while t < 1.0:
			await get_tree().physics_frame
			t = clampf((Time.get_ticks_msec() - began) / (seconds * 1000.0), 0.0, 1.0)
			var k := smoothstep(0.0, 1.0, t)
			for p: Dictionary in plan:
				var st: Transform3D = p["start"]
				var se: Transform3D = p["seat"]
				var bk: Vector3 = p["back"]
				var at: Vector3
				var push := 0.0
				if k < 0.85:
					at = _along(p["path"], k / 0.85)
				else:
					push = (k - 0.85) / 0.15
					at = bk.lerp(se.origin, push)
				# Through the console or the set on the way is what the film must not show:
				# counted, and a carry that does it fails the run. The push home is watched
				# too (coming down onto a jack from above went through the console's lid
				# there), all but its last quarter, where the tip is meant to go in.
				if aim != "preview" and push < 0.75:
					var inside := _inside_body(at)
					if not inside.is_empty():
						p["inside"] = int(p.get("inside", 0)) + 1
						p["inside_of"] = inside
				(p["obj"] as Node3D).global_transform = Transform3D(st.basis.slerp(se.basis, k), at)
	_watching = false
	for p: Dictionary in plan:
		if int(p.get("inside", 0)) > 0:
			_fail("%s went through the %s on its way in (%d ticks)" % [p["obj"].name, p["inside_of"], p["inside"]])
		elif aim != "preview" and not _old_seat:
			print("[hookup] %s carried clear of the console and the set" % p["obj"].name)
		(p["zone"] as XRToolsSnapZone).pick_up_object(p["obj"])
	await _hold(0.3)


func _wait_for_picture(seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _sys.is_powered_on and _sys.sends_video_to(_tv) and _sys.get_video_texture() != null:
			return true
		await _tick(1)
	return false


func _snapshot() -> Image:
	var tex := _sys.get_video_texture()
	return tex.get_image() if tex != null else null


func _changed(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return a != b
	return a.get_data() != b.get_data()


# ── camera, captions, frames ──────────────────────────────────────────────────

func _build_camera() -> void:
	_sv = SubViewport.new()
	_sv.size = SIZE
	_sv.own_world_3d = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.near = 0.02
	_cam.fov = 55.0
	_sv.add_child(_cam)
	_cam.current = true
	_caption_box = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.1, 0.78)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 22
	bg.content_margin_right = 22
	bg.content_margin_top = 10
	bg.content_margin_bottom = 12
	_caption_box.add_theme_stylebox_override("panel", bg)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_caption_box.add_child(_caption)
	_sv.add_child(_caption_box)
	_caption_box.visible = false


func _say(text: String) -> void:
	_caption.text = text
	_caption_box.visible = true
	_caption_box.reset_size()
	_caption_box.position = Vector2((SIZE.x - _caption_box.get_combined_minimum_size().x) * 0.5, SIZE.y - 86)
	print("[hookup] %s" % text)


## Point the camera at a part of the stage, easing there over `seconds`.
func _frame_on(shot: String, seconds: float) -> void:
	var target := Vector3.ZERO
	var eye := Vector3.ZERO
	match shot:
		"wide":
			target = (_sys.global_position + _tv.global_position) * 0.5 + Vector3(0, 0.1, 0)
			eye = target + Vector3(0.2, 0.5, 1.15)
		"jacks":
			# The console's jack side, which faces the set.
			target = _port(_sys, "VideoOut").global_position
			eye = target + Vector3.BACK * 0.42 + Vector3.UP * 0.24 + Vector3.RIGHT * 0.12
		"tv_back":
			# The set's inputs are on its back, against the window: looked down on
			# from above its right shoulder.
			# From behind the set, looking down at its input panel: the table stands
			# clear of the wall for this.
			target = _port(_tv, "CompositePort").global_position
			var tv_back := -_tv.global_transform.basis.z
			tv_back.y = 0.0
			eye = target + tv_back.normalized() * 0.26 + Vector3.UP * 0.3 + Vector3.RIGHT * 0.12
		"front":
			target = (_port(_sys, "ControllerPort1").global_position
				+ _port(_sys, "ControllerPort2").global_position) * 0.5
			eye = target + _front * 0.5 + Vector3.UP * 0.28 + Vector3.LEFT * 0.08
		"slot":
			target = _port(_sys, "CartridgeSlot").global_position
			eye = target + _front * 0.38 + Vector3.UP * 0.34
		"tv":
			# Aimed below the screen's middle, so the set sits high in the frame and
			# the caption bar under it covers table, not picture.
			var tv_front := _tv.global_transform.basis.z.normalized()
			target = _tv.global_position + Vector3(0, -0.02, 0) + tv_front * 0.12
			eye = target + tv_front * 0.75 + Vector3.UP * 0.12
	var to := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	if seconds <= 0.0:
		_cam.global_transform = to
		_cam_t = 1.0
		return
	_cam_from = _cam.global_transform
	_cam_to = to
	_cam_len = seconds
	_cam_t = 0.0


## Lift or lower `body` so the lowest point it draws sits at `y`.
func _rest_on(body: Node3D, y: float) -> void:
	var box := _world_bounds(body)
	if box.size.length() < 0.001:
		print("[hookup] %s draws nothing to stand on; left where it is" % body.name)
		return
	body.global_position.y += y - box.position.y
	print("[hookup] %s stood on the table (its underside was %+.3f m off it)"
		% [body.name, box.position.y - y])


## Everything `node` draws, in world space. A cord or plug hanging off it is not
## part of it, so pickables under it are skipped.
func _world_bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for vis: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var g := vis as GeometryInstance3D
		if not g.is_visible_in_tree() or _under_pickable(g, node):
			continue
		var b := g.global_transform * g.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _under_pickable(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p is XRToolsPickable:
			return true
		p = p.get_parent()
	return false


## The console's front, level: whichever of its own four sides the controller
## ports are on.
func _front_axis() -> Vector3:
	var mid := (_port(_sys, "ControllerPort1").global_position
		+ _port(_sys, "ControllerPort2").global_position) * 0.5
	var b := _sys.global_transform.basis.orthonormalized()
	var local := b.inverse() * (mid - _sys.global_position)
	var axis := Vector3(signf(local.x), 0, 0) if absf(local.x) > absf(local.z) \
		else Vector3(0, 0, signf(local.z))
	var world := b * axis
	world.y = 0.0
	return world.normalized()


## Which way is "out" from `body` at `point`, level.
func _outward(body: Node3D, point: Vector3) -> Vector3:
	var d := point - body.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.BACK


func _process(delta: float) -> void:
	if _cam_t < 1.0 and _cam != null:
		_cam_t = minf(1.0, _cam_t + delta / _cam_len)
		var k := smoothstep(0.0, 1.0, _cam_t)
		_cam.global_transform = Transform3D(_cam_from.basis.slerp(_cam_to.basis, k),
			_cam_from.origin.lerp(_cam_to.origin, k))


## `n` rendered frames.
func _tick(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


## Takes the film while _recording: every drawn frame, each written as many times as
## the wall clock says it is owed. Its own loop, so whatever the film is doing
## (a plug carried tick by tick, a wait) never decides when a frame is taken.
func _capture() -> void:
	while _recording:
		await RenderingServer.frame_post_draw
		if not _recording:
			return
		var owed := int((Time.get_ticks_msec() - _t0) * FPS / 1000.0) + 1
		if owed <= _frames:
			continue
		var img := _sv.get_texture().get_image()
		var first := _out.path_join("f_%05d.jpg" % _frames)
		img.save_jpg(first, 0.92)
		_frames += 1
		while _frames < owed:
			DirAccess.copy_absolute(first, _out.path_join("f_%05d.jpg" % _frames))
			_frames += 1


## The AV lead's middle point, tick by tick, after `wait` ticks of settling: a cord at
## rest moves a vanishing amount each tick; one that flips between two shapes moves
## the same distance back and forth. For --layout --rope-trace.
func _trace_rope(wait: int, ticks: int) -> void:
	var rope: Node = null
	for n: Node in _cable.find_children("*", "", true, false):
		if n.get_class() == "VerletRope":
			rope = n
	if rope == null:
		_fail("no rope on the AV lead to trace")
		return
	await _settle(wait)
	var mid := int(rope.call("point_count")) / 2
	var prev: Vector3 = rope.call("point_position", mid)
	var steps: Array[String] = []
	for i in ticks:
		await get_tree().physics_frame
		var at: Vector3 = rope.call("point_position", mid)
		steps.append("%+.2f" % ((at - prev).length() * 1000.0 * signf((at - prev).y if absf((at - prev).y) > 1e-7 else 1.0)))
		prev = at
	_report_ropes("traced")
	print("[hookup] rope mid point %d of %d, mm moved each tick (sign of y): %s" % [mid,
		int(rope.call("point_count")), " ".join(steps)])


## The VerletRope of the cord node named `cord_name` under the probe (the AV lead
## "MonoCompositeCable", the pad's "ControllerCable", the set's "TVMainsCord"), or null.
func _rope_of(cord_name: String) -> Node:
	var cord := get_node_or_null(cord_name)
	if cord == null:
		return null
	for n: Node in cord.find_children("*", "", true, false):
		if n.get_class() == "VerletRope":
			return n
	return null


## While a plug is carried (_watching): the AV lead's points next to each end, every
## physics tick. A cord led smoothly moves by about the same step tick after tick; one
## yanked in steps moves in jolts. Reports the largest change of step (jerk, mm) and
## its mean, for each end.
func _watch_cord(what: String, cord_name := "MonoCompositeCable") -> void:
	var rope := _rope_of(cord_name)
	if rope == null:
		print("[hookup] no %s rope to watch carrying %s" % [cord_name, what])
		return
	var count := int(rope.call("point_count"))
	var ids := [3, count - 4]
	var prev := {}
	var step := {}
	var worst := {3: 0.0, count - 4: 0.0}
	var worst_at := {3: -1, count - 4: -1}
	var total := {3: 0.0, count - 4: 0.0}
	var ticks := 0
	while _watching:
		await get_tree().physics_frame
		for id: int in ids:
			var at: Vector3 = rope.call("point_position", id)
			if prev.has(id):
				var d: Vector3 = at - prev[id]
				if step.has(id):
					var jerk: float = (d - step[id]).length() * 1000.0
					if jerk > worst[id]:
						worst[id] = jerk
						worst_at[id] = ticks
					total[id] += jerk
				step[id] = d
			prev[id] = at
		ticks += 1
	var n := maxi(1, ticks - 2)
	print("[hookup] %s jerk carrying %s (%s, %d ticks): start end max %.2f (tick %d) mean %.3f mm, far end max %.2f (tick %d) mean %.3f mm" % [
		cord_name, what, "per frame" if _old_seat else "per tick", ticks, worst[ids[0]], worst_at[ids[0]], total[ids[0]] / n,
		worst[ids[1]], worst_at[ids[1]], total[ids[1]] / n])


## Every cord in the shot: asleep or not, and how fast its fastest point and the
## whole of it are still moving, so a cord that shimmers on film can be told from
## one that settled.
func _report_ropes(when: String) -> void:
	var parts: Array[String] = []
	for cord_name: String in ["MonoCompositeCable", "ControllerCable", "TVMainsCord"]:
		var n := _rope_of(cord_name)
		if n != null:
			var m: Dictionary = n.call("get_sleep_metrics")
			parts.append("%s asleep %s max %.4f rms %.4f still %d" % [cord_name,
				n.call("is_sleeping"), float(m.get("max_velocity", -1.0)),
				float(m.get("rms_velocity", -1.0)), int(m.get("still_frames", -1))])
	print("[hookup] ropes %s: %s" % [when, "; ".join(parts) if not parts.is_empty() else "none found"])

func _hold(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await _tick(1)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _save_still(name: String) -> void:
	await RenderingServer.frame_post_draw
	_sv.get_texture().get_image().save_png(_out.path_join(name))
	print("[hookup] wrote %s" % name)


func _surface_y(xz: Vector2) -> float:
	var space := _cam.get_world_3d().direct_space_state
	# Every layer: furniture is not on the world layer the room's walls and floor are.
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 2.2, xz.y), Vector3(xz.x, -0.5, xz.y),
		0xFFFFFFFF)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _port(body: Node, port_name: String) -> XRToolsSnapZone:
	return body.find_child(port_name, true, false) as XRToolsSnapZone


func _plug(plug_name: String) -> Node3D:
	return _cable.get_node_or_null(plug_name) as Node3D


func _fail(why: String) -> void:
	_failed = true
	print("[hookup] FAIL %s" % why)


func _end() -> void:
	print("[hookup] %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


## A fingertip on the pad that holds whatever bits `held` names: the pad merges it
## into what it sends (AnimatedController._send_joypad), so the core reads it and
## the cap is drawn down, as a real finger's press is.
class PressPoke extends ControlPoke:
	var held := 0

	func poll() -> Dictionary:
		return {"btn": held, "lstick": Vector2.ZERO, "rstick": Vector2.ZERO}
