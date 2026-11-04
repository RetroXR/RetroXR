## Super Scope self-tests -- the scope, its receiver and its sight on a real Super
## NES, against the device lists snes9x declares. Headless, no core, no ROM: what
## the core is told of the port is read off the port table (`current_id`), what
## the gun sends off the scope's own record of its gate (`sent`).
##
##     "$godot" --headless --path RetroXR res://Tests/super_scope_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/super_scope_tests.tscn -- --only=gate
##
## Groups:
##   port/   the receiver's plug fits an SNES's sockets; in socket 2 it is snes9x's
##           SuperScope (260), in socket 1 NOTHING (snes9x lists no gun there), where
##           the generic gun, named nothing in particular, is still told a gun
##   pair/   the scope pairs with the nearest seated receiver and drives its port;
##           the receiver pulled, it lets go
##   gate/   with the switch OFF, a wall between the windows, the scope turned away
##           or too far, the console hears no button and the aim off the screen;
##           ON and in sight, a press gets through
##   turbo/  the hand's AUX_B never reaches the core; with the core running, the
##           switch to TURBO is ONE press of the core's toggle and back to ON one
##           more; nothing while the link is down; a stopped core starts again off
##   sight/  a fresh scope comes with its sight on the left clip; it goes on the right
##   bay/    six AA cells in the stock, its supply dead with none in
##   poke/   Fire, Pause and Cursor are caps a fingertip presses; Cursor goes in
##           sideways, toward the muzzle
##   save/   the scope (switch, sight and its side), the receiver (its socket) and
##           the sight are written, validate and come back
##   spawn/  the SNES card offers the scope, its receiver and AA cells, and each
##           token builds its object
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const SCOPE_SCENE := preload("res://Scenes/Objects/peripherals/super_scope.tscn")
const RX_SCENE := preload("res://Scenes/Objects/peripherals/super_scope_receiver.tscn")
const SIGHT_SCENE := preload("res://Scenes/Objects/peripherals/super_scope_sight.tscn")
const LIGHT_GUN_SCENE := preload("res://Scenes/Objects/peripherals/light_gun.tscn")

const NONE := 0
const LIGHTGUN := 4
const SUPER_SCOPE := 260

## snes9x's ports as it declares them (libretro/libretro.cpp, retro_set_environment):
## the guns are on its second port only.
const SNES9X_PORTS: Array = [
	{"port": 0, "controllers": [{"name": "None", "id": 0}, {"name": "SNES Joypad", "id": 1},
		{"name": "SNES Mouse", "id": 2}, {"name": "Multitap", "id": 257}]},
	{"port": 1, "controllers": [{"name": "None", "id": 0}, {"name": "SNES Joypad", "id": 1},
		{"name": "SNES Mouse", "id": 2}, {"name": "Multitap", "id": 257},
		{"name": "SuperScope", "id": 260}, {"name": "Justifier", "id": 516},
		{"name": "M.A.C.S. Rifle", "id": 1028}]},
	{"port": 2, "controllers": [{"name": "None", "id": 0}, {"name": "SNES Joypad", "id": 1},
		{"name": "Justifier (2P)", "id": 772}]},
]

## Where the receiver stands (its window looking +Z, at the player) and where the
## scope is held, 2 m in front of it, its muzzle (-Z) toward it.
const RX_AT := Vector3(0.6, 1.3, 0.0)
const SCOPE_AT := Vector3(0.6, 1.25, 2.0)

var _only := ""
var _spawned: Array[Node] = []
var _sim_before := false


func _ready() -> void:
	suite_tag = "scope"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[scope] TIMED OUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_sim_before = AppPrefs.power_simulation
	AppPrefs.power_simulation = false
	for group: String in ["port", "pair", "gate", "turbo", "sight", "bay", "poke", "save", "spawn"]:
		if _only.is_empty() or _only == group:
			await call("_group_" + group)
			await _clear()
	AppPrefs.power_simulation = _sim_before
	_finish()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Everything a group made, and what those made in turn (a fresh scope's sight,
## a bay's cover, a receiver's cord): all of it is a child of this root.
func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	for n: Node in get_children():
		n.queue_free()
	await _wait(3)


func _console() -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "snes"
	sys.position = Vector3(0, 1, 0)
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(20)
	sys.controller_ports().controller_info = SNES9X_PORTS.duplicate(true)
	return sys


func _make(scene: PackedScene, at: Vector3, basis := Basis.IDENTITY) -> Node3D:
	var obj := scene.instantiate() as Node3D
	obj.position = at
	obj.basis = basis
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	add_child(obj)
	_spawned.append(obj)
	return obj


## A receiver standing at RX_AT, its window toward +Z, its cord made.
func _receiver() -> SuperScopeReceiver:
	var rx := _make(RX_SCENE, RX_AT, Basis(Vector3.UP, PI)) as SuperScopeReceiver
	await _wait(3)
	return rx


## The cord's plug of `rx` seated in console socket `socket`.
func _seat(sys: RetroSystem, rx: SuperScopeReceiver, socket: int) -> void:
	sys.restore_controller_plug(socket, rx.get_plug())
	await _wait(4)


## A scope held at SCOPE_AT, switched ON.
func _scope() -> SuperScope:
	var scope := _make(SCOPE_SCENE, SCOPE_AT) as SuperScope
	await _wait(3)
	scope.set_power_switch(SuperScope.SWITCH_ON)
	return scope


func _settle() -> void:
	await _wait(SuperScope.LOOK_TICKS + 3)


func _ids(sys: RetroSystem) -> Array:
	var out: Array = [-1, -1, -1]
	for e: Dictionary in sys.controller_ports().controller_info:
		var p := int(e.get("port", -1))
		if p >= 0 and p < out.size():
			out[p] = int(e.get("current_id", -1))
	return out


func _fire_sent(scope: SuperScope) -> bool:
	return bool(scope.sent.get(ControllerBindings.LIGHTGUN_TRIGGER, false))


# ── port ──────────────────────────────────────────────────────────────────────

func _group_port() -> void:
	var sys := await _console()
	var rx := await _receiver()
	var plug := rx.get_plug()
	_ok(plug != null, "port/the receiver has a cord with a plug")
	if plug == null:
		return
	var zones: Array = sys.controller_ports().zones
	_ok((zones[1] as XRToolsSnapZone).snap_filter.call(plug), "port/the plug fits socket 2")
	_ok((zones[0] as XRToolsSnapZone).snap_filter.call(plug), "port/and socket 1, as an SNES plug does")
	await _seat(sys, rx, 1)
	_eq(rx.get_port_index(), 1, "port/seated in socket 2 it is on libretro port 1")
	_eq(_ids(sys)[1], SUPER_SCOPE, "port/and snes9x is told its SuperScope")
	_ok(rx.port_reads_scope(), "port/the receiver knows it is read there")
	(zones[1] as XRToolsSnapZone).drop_object()
	await _wait(3)
	_ok(not rx.is_plugged_in(), "port/pulled, it is in no console")
	await _seat(sys, rx, 0)
	_eq(rx.get_port_index(), 0, "port/in socket 1 it is on libretro port 0")
	_eq(_ids(sys)[0], NONE, "port/where snes9x lists no gun, so the port is told nothing")
	_ok(not rx.port_reads_scope(), "port/and the receiver knows nobody reads it")
	(zones[0] as XRToolsSnapZone).drop_object()
	await _wait(3)
	# The control: the generic gun names no device, so socket 1 still tells it a gun.
	var gun := _make(LIGHT_GUN_SCENE, Vector3(-0.5, 1, 0.5)) as LightGun
	await _wait(3)
	sys.restore_controller_plug(0, gun.get_plug())
	await _wait(4)
	_eq(_ids(sys)[0], LIGHTGUN, "port/the generic gun in socket 1 is still told a plain light gun")
	_eq(sys.core_device_id(LIGHTGUN, 1, PackedStringArray(["superscope"]), true), SUPER_SCOPE,
		"port/a strict name the port lists is announced as it")
	sys.controller_ports().controller_info = []
	_eq(sys.core_device_id(LIGHTGUN, 0, PackedStringArray(["superscope"]), true), LIGHTGUN,
		"port/a core that lists nothing is told the bare type")


# ── pair ──────────────────────────────────────────────────────────────────────

func _group_pair() -> void:
	var sys := await _console()
	var rx := await _receiver()
	var scope := await _scope()
	await _wait(2)
	_ok(scope.receiver() == null, "pair/no receiver seated, nothing to pair with")
	await _seat(sys, rx, 1)
	_ok(scope.receiver() == rx and rx.scope == scope, "pair/seated, the scope pairs with it")
	_eq(scope.get_port_index(), 1, "pair/and drives its port")
	_ok(scope.get_connected_system() == null, "pair/the port is the receiver's to save, not the scope's")
	var near_rx := _make(RX_SCENE, SCOPE_AT + Vector3(0.3, 0, -0.5), Basis(Vector3.UP, PI)) as SuperScopeReceiver
	await _wait(3)
	_ok(near_rx.scope == null, "pair/a receiver in no console is no one's")
	(sys.controller_ports().zones[1] as XRToolsSnapZone).drop_object()
	await _wait(4)
	_ok(scope.receiver() == null and scope.get_port_index() == -1, "pair/the receiver pulled, the scope lets go")


# ── gate ──────────────────────────────────────────────────────────────────────

func _group_gate() -> void:
	var sys := await _console()
	var rx := await _receiver()
	var scope := await _scope()
	await _seat(sys, rx, 1)
	scope.set_external_button(ControllerBindings.LIGHTGUN_TRIGGER, true)
	await _settle()
	_ok(scope.link_up(), "gate/ON, 2 m in front of the receiver, the link is up")
	_ok(_fire_sent(scope), "gate/and FIRE gets through")
	var lib := sys.get_libretro_node()
	scope._set_aim(lib, 1000, 2000, false)
	_ok(not scope.sent_offscreen, "gate/and the aim")

	scope.set_power_switch(SuperScope.SWITCH_OFF)
	await _settle()
	_ok(not scope.link_up() and not _fire_sent(scope), "gate/switched OFF, the console hears nothing pressed")
	scope._set_aim(lib, 1000, 2000, false)
	_ok(scope.sent_offscreen, "gate/and the gun off the screen")
	scope.set_power_switch(SuperScope.SWITCH_ON)
	await _settle()
	_ok(scope.link_up() and _fire_sent(scope), "gate/ON again, it gets through")

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.05)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	_spawned.append(wall)
	wall.global_position = Vector3(RX_AT.x, RX_AT.y, 1.0)
	await _settle()
	_ok(not scope.link_up() and not _fire_sent(scope), "gate/a wall between the windows cuts it")
	wall.global_position = Vector3(5, 1, 1)
	await _settle()
	_ok(scope.link_up(), "gate/taken away, the link is back")

	scope.global_basis = Basis(Vector3.UP, PI * 0.5)
	await _settle()
	_ok(not scope.link_up(), "gate/turned 90 degrees away, out of the beam")
	scope.global_basis = Basis.IDENTITY
	scope.global_position = Vector3(RX_AT.x, SCOPE_AT.y, SuperScope.RANGE_MAX + 0.5)
	await _settle()
	_ok(not scope.link_up(), "gate/past its range, nothing")
	scope.global_position = SCOPE_AT
	# Behind the receiver: in its own beam, but at the receiver's back.
	scope.global_position = Vector3(RX_AT.x, RX_AT.y, -2.0)
	scope.global_basis = Basis(Vector3.UP, PI)
	await _settle()
	_ok(not scope.link_up(), "gate/behind the receiver, its window cannot see the scope")
	scope.global_basis = Basis.IDENTITY
	scope.global_position = SCOPE_AT
	await _settle()
	_ok(scope.link_up(), "gate/in front again, up")
	scope.set_external_button(ControllerBindings.LIGHTGUN_TRIGGER, false)


# ── turbo ─────────────────────────────────────────────────────────────────────

func _group_turbo() -> void:
	var aux_b := ControllerBindings.LIGHTGUN_AUX_B
	var sys := await _console()
	var rx := await _receiver()
	var scope := await _scope()
	await _seat(sys, rx, 1)
	await _settle()
	_ok(not scope._told(aux_b, true), "turbo/the hand's AUX_B never reaches the core")
	sys.is_powered_on = true
	await _wait(3)
	var presses := await _count_turbo_presses(scope, SuperScope.SWITCH_TURBO, 40)
	_eq(presses, 1, "turbo/the switch to TURBO is one press of the core's toggle")
	_ok(scope.core_turbo(), "turbo/and the core is believed to be at turbo")
	presses = await _count_turbo_presses(scope, SuperScope.SWITCH_TURBO, 30)
	_eq(presses, 0, "turbo/left there, nothing more")
	presses = await _count_turbo_presses(scope, SuperScope.SWITCH_ON, 40)
	_eq(presses, 1, "turbo/back to ON, one more press")
	_ok(not scope.core_turbo(), "turbo/and the core is believed off")
	# OFF sends nothing: the switch at OFF is the link down.
	presses = await _count_turbo_presses(scope, SuperScope.SWITCH_OFF, 30)
	_eq(presses, 0, "turbo/OFF is no press")
	scope.set_power_switch(SuperScope.SWITCH_TURBO)
	await _wait(40)
	_ok(scope.core_turbo(), "turbo/straight from OFF to TURBO, the core is told")
	sys.is_powered_on = false
	await _wait(3)
	_ok(not scope.core_turbo(), "turbo/the core stopped, the next run starts off")
	sys.is_powered_on = true
	presses = await _count_turbo_presses(scope, SuperScope.SWITCH_TURBO, 40)
	_eq(presses, 1, "turbo/and the switch still at TURBO is told again")
	sys.is_powered_on = false


## Set the switch to `position` and count AUX_B's rising edges over `frames`.
func _count_turbo_presses(scope: SuperScope, position: int, frames: int) -> int:
	scope.set_power_switch(position)
	var was := bool(scope.sent.get(ControllerBindings.LIGHTGUN_AUX_B, false))
	var count := 0
	for i in frames:
		await get_tree().process_frame
		var now := bool(scope.sent.get(ControllerBindings.LIGHTGUN_AUX_B, false))
		if now and not was:
			count += 1
		was = now
	return count


# ── sight ─────────────────────────────────────────────────────────────────────

func _group_sight() -> void:
	var scope := _make(SCOPE_SCENE, SCOPE_AT) as SuperScope
	scope.add_to_group("spawned")
	await _wait(4)
	var sight := scope.get_sight()
	_ok(sight != null, "sight/a fresh scope comes with its sight")
	_eq(scope.sight_side(), "left", "sight/on the left clip")
	if sight == null:
		return
	_spawned.append(sight)
	var left := scope.get_node("SightClipL") as XRToolsSnapZone
	var right := scope.get_node("SightClipR") as XRToolsSnapZone
	left.drop_object()
	await _wait(2)
	_eq(scope.sight_side(), "", "sight/taken off, no side")
	right.pick_up_object(sight)
	await _wait(2)
	_eq(scope.sight_side(), "right", "sight/it goes on the right")
	_ok(sight.global_position.x > scope.global_position.x, "sight/and stands on the scope's right (+X)")


# ── bay ───────────────────────────────────────────────────────────────────────

func _group_bay() -> void:
	var scope := _make(SCOPE_SCENE, SCOPE_AT) as SuperScope
	await _wait(3)
	var bay := CellSlots.of(scope)
	_eq(bay.seats().size() if bay != null else 0, 6, "bay/six cells")
	_eq(CellSlots.size_of_seat(bay.seats()[0]) if bay != null and not bay.seats().is_empty() else "",
		"AA", "bay/AA cells")
	var supply := PowerInput.of(scope)
	_ok(supply != null and not bool(supply.own_supply()["supplied"]), "bay/with none in, its own supply is dead")


# ── poke ──────────────────────────────────────────────────────────────────────

func _group_poke() -> void:
	var scope := _make(SCOPE_SCENE, SCOPE_AT) as SuperScope
	await _wait(3)
	var lids: Array = []
	var cursor_dir := Vector3.ZERO
	for e: Dictionary in scope._anim_btns:
		lids.append(int(e["lid"]))
		if int(e["lid"]) == ControllerBindings.LIGHTGUN_AUX_A:
			cursor_dir = e.get("dir", Vector3.DOWN)
	lids.sort()
	_eq(lids, [ControllerBindings.LIGHTGUN_TRIGGER, ControllerBindings.LIGHTGUN_AUX_A,
		ControllerBindings.LIGHTGUN_START], "poke/Fire, Cursor and Pause are caps")
	_ok(cursor_dir.z < -0.9, "poke/Cursor presses toward the muzzle (-Z), not down")
	var sw := scope.get_node_or_null("PowerSwitch") as VRSlider
	_ok(sw != null and sw.steps == 3, "poke/the power switch is a three-position slide")


# ── save ──────────────────────────────────────────────────────────────────────

func _group_save() -> void:
	var sys := await _console()
	var rx := await _receiver()
	var scope := await _scope()
	scope.add_to_group("spawned")
	scope.call("_seed_sight")
	await _seat(sys, rx, 1)
	var sight := scope.get_sight()
	_ok(sight != null, "save/the scope has its sight")
	if sight == null:
		return
	_spawned.append(sight)
	(scope.get_node("SightClipL") as XRToolsSnapZone).drop_object()
	await _wait(2)
	(scope.get_node("SightClipR") as XRToolsSnapZone).pick_up_object(sight)
	await _wait(2)
	scope.set_power_switch(SuperScope.SWITCH_TURBO)
	var sp := ScenePersistence.new()
	var ids := {sys: 7, scope: 1, rx: 2, sight: 3}
	var srec: Dictionary = sp.serialize_node(scope, 1, ids)
	var rrec: Dictionary = sp.serialize_node(rx, 2, ids)
	var grec: Dictionary = sp.serialize_node(sight, 3, ids)
	_eq(str(srec.get("type", "")), "super_scope", "save/the scope has an entry of its own")
	_eq(int(srec.get("power_switch", -1)), SuperScope.SWITCH_TURBO, "save/with its switch")
	_ok(srec.get("sight") == 3 and str(srec.get("sight_side", "")) == "right", "save/and its sight, on the right")
	_ok(not srec.has("port_index"), "save/and no port: that is the receiver's")
	_eq(str(rrec.get("type", "")), "super_scope_receiver", "save/the receiver has an entry")
	_ok(rrec.get("system") == 7 and int(rrec.get("port_index", -1)) == 1, "save/naming its console and socket 2")
	_eq(str(grec.get("type", "")), "super_scope_sight", "save/the sight has an entry")
	var room: Array = [srec, rrec, grec, sp.serialize_node(sys, 7, ids)]
	_eq(ScenePersistence._objects_validation_error(room), "", "save/and the room's entries validate")

	(sys.controller_ports().zones[1] as XRToolsSnapZone).drop_object()
	await _wait(3)
	var back_scope := sp.deserialize_object(srec) as SuperScope
	var back_rx := sp.deserialize_object(rrec) as SuperScopeReceiver
	var back_sight := sp.deserialize_object(grec) as SuperScopeSight
	_ok(back_scope != null and back_rx != null and back_sight != null, "save/all three are rebuilt")
	if back_scope == null or back_rx == null or back_sight == null:
		return
	_eq(back_scope.power_switch, SuperScope.SWITCH_TURBO, "save/the switch set before it is in the room")
	# As ScenePersistence._spawn_entry marks everything it brings back.
	for n: Node in [back_scope, back_rx, back_sight]:
		n.set_meta(CoverSlots.RESTORING, true)
		add_child(n)
		_spawned.append(n)
	scope.queue_free()
	rx.queue_free()
	sight.queue_free()
	await _wait(4)
	_eq(back_scope.sight_side(), "", "save/a restored scope grows no sight of its own")
	sp._restore_super_scope(self, 1, back_scope, {3: back_sight}, srec)
	sp._restore_super_scope_receiver(self, 2, back_rx, {7: sys}, rrec)
	await _wait(6)
	_eq(back_scope.sight_side(), "right", "save/its sight back on the right")
	_ok(back_rx.is_plugged_in() and back_rx.get_port_index() == 1, "save/the receiver back in socket 2")
	_ok(back_scope.receiver() == back_rx, "save/and the scope pairs with it")
	var slider := back_scope.get_node("PowerSwitch") as VRSlider
	_ok(slider != null and is_equal_approx(slider.value, 1.0), "save/the slide stands at TURBO")


# ── spawn ─────────────────────────────────────────────────────────────────────

func _group_spawn() -> void:
	var tokens: Array = []
	for item: Dictionary in SpawnCatalog.items_for("snes"):
		tokens.append(str(item.get("spawn", "")))
	for token: String in ["super_scope", "super_scope_receiver", "battery_aa"]:
		_ok(tokens.has(token), "spawn/the SNES card offers %s" % token)
	var scope := ScenePersistence.instantiate("super_scope")
	_ok(scope is SuperScope, "spawn/super_scope builds the scope")
	var rx := ScenePersistence.instantiate("super_scope_receiver")
	_ok(rx is SuperScopeReceiver, "spawn/super_scope_receiver builds the receiver")
	for n: Node in [scope, rx]:
		if n != null:
			n.free()
