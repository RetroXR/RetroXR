## LightGun — pickable light gun that plugs into a RetroSystem controller port.
## While held and plugged in: casts a ray from the barrel to the TV screen each
## frame and reports the hit position as libretro lightgun coordinates.
## Button mappings are data-driven via ControllerBindings.
##
## Desktop mode (grabbed by DesktopHand group):
##   desktop_fps_snap = true  → desktop_pickup.gd locks the gun to the camera
##   lower-right (FPS weapon view).  Aiming uses the camera centre ray so the
##   crosshair reticle always matches where the gun is pointing.
##   Trigger  = left mouse button  (trigger_left action)
##   Aux/dpad = RETRO_JOYPAD_* keyboard actions
class_name LightGun
extends XRToolsPickable


const CONTROLLER_CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")
const RETRO_DEVICE_LIGHTGUN := 4
const DPAD_THRESHOLD := 0.35

## Input thresholds per XRController float input name.
const INPUT_THRESHOLDS: Dictionary = {
	"trigger":       0.3,
	"grip":          0.3,
	"ax_button":     0.5,
	"by_button":     0.5,
	"primary_click": 0.5,
}

## Desktop lightgun button map: Godot action name → LIGHTGUN_* id.
const DESKTOP_LIGHTGUN_BUTTONS: Dictionary = {
	"trigger_left":        ControllerBindings.LIGHTGUN_TRIGGER,
	"RETRO_JOYPAD_A":      ControllerBindings.LIGHTGUN_AUX_A,
	"RETRO_JOYPAD_B":      ControllerBindings.LIGHTGUN_AUX_B,
	"RETRO_JOYPAD_X":      ControllerBindings.LIGHTGUN_AUX_C,
	"RETRO_JOYPAD_Y":      ControllerBindings.LIGHTGUN_RELOAD,
	"RETRO_JOYPAD_START":  ControllerBindings.LIGHTGUN_START,
	"RETRO_JOYPAD_SELECT": ControllerBindings.LIGHTGUN_SELECT,
}

## The lightgun d-pad, in the order _stick_dpad() reads the stick.
const DPAD_IDS: Array[int] = [
	ControllerBindings.LIGHTGUN_DPAD_UP, ControllerBindings.LIGHTGUN_DPAD_DOWN,
	ControllerBindings.LIGHTGUN_DPAD_LEFT, ControllerBindings.LIGHTGUN_DPAD_RIGHT,
]

## Set true so desktop_pickup.gd uses FPS-snap positioning instead of ray-hold.
var desktop_fps_snap: bool = true

## The console this gun was made for, as a pad names its own: its plug is that
## console's controller port (Connectors.CONTROLLER_PORTS -- a GunCon's fits a
## PlayStation 2 as well), and the spawn card lists it on that console's card.
## Empty, with no `connector`, fits every console's port, which is right for the
## game's own gun, a stand-in for whichever console it is offered on.
@export var systemid: String = ""

## The plug on this gun's cord, when it is not its console's port. See Connectors.
@export var connector: String = ""

## The plug's own model, as a pad's plug_mesh_path: a scene or mesh in the
## game's plug frame (connector +Z, origin on the mating plane, a CordExit
## marker). Empty keeps the generic moulding.
@export var plug_mesh_path: String = ""

## Height of the drop hint above the gun, in metres.
const HINT_HEIGHT := 0.16
var _hint: HeldHint = null

## libretro device type reported to the system when plugged in.
var device_type: int = RETRO_DEVICE_LIGHTGUN
## What this gun is called in a core's own device list, lower case, when it is
## one particular gun and not the generic one: ["zapper"], ["guncon"]. A core
## that offers several guns on a port is then told this one and not whichever
## it lists first (RetroSystem.core_device_id). Empty, the generic gun's, takes
## the core's first.
var device_names: PackedStringArray = PackedStringArray()

## Whether to show the laser-dot aim indicator on the screen.
var show_laser_dot: bool = false

# Active bindings (loaded from ControllerBindings on plug-in)
var _lightgun_map: Dictionary = ControllerBindings.DEFAULT_LIGHTGUN_MAP.duplicate()

# Port connection state
var _connected_system: RetroSystem = null
var _port_index: int = -1


## The console this peripheral is plugged into, or null. Part of the port-
## peripheral contract ScenePersistence and NetObjectSync ask for by method
## rather than by field name.
func get_connected_system() -> RetroSystem:
	return _connected_system if is_instance_valid(_connected_system) else null


## Which port of that console it occupies, or -1 when unplugged.
func get_port_index() -> int:
	return _port_index

# Cable
var _cable_instance: Node3D = null


## The captive cable spawned for this gun, or null. Parented to the scene root
## rather than to the gun, as a pad's is (RetroController.cable_instance): the
## storage box asks for it so the plug leaves its port and the cord goes with
## the gun instead of staying behind on a freed anchor.
func cable_instance() -> Node3D:
	return _cable_instance
var _cable_plug: ControllerPlug = null
var _cable_rope: VerletRope = null
var _max_rope_length: float = 0.0

## The cord's rest length, 0 for the scene's own. A cabinet's gun hangs on a cord of its own.
@export var cable_length: float = 0.0

## True for a gun the machine is WIRED to rather than socketed for: an arcade cabinet's guns
## hang in their holsters on a cord that goes into the cabinet, with no plug to pull. Built
## with the machine and freed with it, so it stays out of the "spawned" group that
## persistence and object sync sweep (a save would otherwise bring back a SECOND gun on
## every load). Set before add_child, so this gun's own _ready never joins the group.
var captive := false

## The path this gun's cord takes at rest, in WORLD space, from the gun to the machine's
## cord entry. RetroSystem hands one to a captive gun before the cord exists; empty
## elsewhere, which leaves the rope its straight lay. See CaptiveCord.
var captive_cord_route: PackedVector3Array = PackedVector3Array()

## The holster this captive gun came out of (a snap zone the machine built round it). Let go, it goes
## back in by itself: a cabinet's gun does not lie on the floor on its cord.
var captive_well: XRToolsSnapZone = null


# ── on a swivel mount ─────────────────────────────────────────────────────────

## The pivot a gun on a swivel mount turns about, or null for a gun that can be carried. Silent Scope's rifle and
## Operation Wolf's Uzi are FIXED to their cabinets (a post, a ball joint or a yoke) and only turn in their
## housing, as the real ones do: a hand takes hold and swings the gun about the pivot, and nothing it does takes the gun
## off the cabinet. A Marker3D on the cabinet whose own basis is the way the gun faces at rest (-Z, at the screen).
var mount: Node3D = null
## Where the pivot is in the gun's own frame: ahead of the grip, under the forestock, where the yoke is.
var mount_pivot := Vector3.ZERO
## A VR hand turns the gun by where it is (the lever of a long stock: the barrel points from the hand through the
## pivot); false takes the way the hand points. A hand too close to the pivot to tell by falls back to pointing.
var mount_lever := false
## How far it turns: either way about the vertical, and down and up (radians), in the mount's own frame.
const MOUNT_YAW_LIMIT := deg_to_rad(40.0)
const MOUNT_PITCH_LIMIT := Vector2(deg_to_rad(-12.0), deg_to_rad(28.0))
## A hand nearer the pivot than this (metres) says nothing of which way the lever points.
const MOUNT_LEVER_MIN := 0.18
var _mount_yaw := 0.0
var _mount_pitch := 0.0


## Fix this gun to `pivot` (a marker on a cabinet) so it turns about it and goes nowhere else. `local` is the pivot's
## place in the gun's own frame. It is frozen where it stands, never falls, and is taken only by a hand that is near.
func fix_to_mount(pivot: Node3D, local: Vector3, by_lever: bool) -> void:
	mount = pivot
	mount_pivot = local
	mount_lever = by_lever
	release_mode = XRToolsPickable.ReleaseMode.FROZEN
	ranged_grab_method = XRToolsPickable.RangedMethod.NONE
	second_hand_grab = XRToolsPickable.SecondHandGrab.IGNORE
	freeze = true
	global_transform = mount_transform()


func is_mounted() -> bool:
	return mount != null and is_instance_valid(mount)


## The mount's own heading and the gun's turn now, as (yaw, pitch) in radians.
func mount_turn() -> Vector2:
	return Vector2(_mount_yaw, _mount_pitch)


## Where the gun is for a turn about its pivot: the pivot fixed on the mount, the gun turned by yaw (about the
## mount's up) then pitch (about its right).
func mount_transform() -> Transform3D:
	var turn := Basis(Vector3.UP, _mount_yaw) * Basis(Vector3.RIGHT, _mount_pitch)
	var basis := mount.global_basis * turn
	return Transform3D(basis, mount.global_position - basis * mount_pivot)


## The grab driver's hook (XRToolsGrabDriver, a RetroXR patch): where a hold puts the gun. Whatever the hand wants,
## it is the gun turned about its pivot toward where the hand aims it, within its travel. `holder` is the hand (the
## driver's own, `get_picked_up_by()`, when null).
func constrain_grab(destination: Transform3D, holder: Node3D = null) -> Transform3D:
	if not is_mounted():
		return destination
	var by := holder if holder != null else get_picked_up_by()
	# The way the hand aims it: the barrel of the pose the hold WANTS (the grab point's tilt is in it).
	var aim := -destination.basis.z
	if mount_lever and by != null and not by.is_in_group("desktop_hand"):
		var lever := mount.global_position - by.global_position
		if lever.length() >= MOUNT_LEVER_MIN:
			aim = lever.normalized()
	var local := mount.global_basis.inverse() * aim
	_mount_yaw = clampf(atan2(-local.x, -local.z), -MOUNT_YAW_LIMIT, MOUNT_YAW_LIMIT)
	_mount_pitch = clampf(asin(clampf(local.y, -1.0, 1.0)), MOUNT_PITCH_LIMIT.x, MOUNT_PITCH_LIMIT.y)
	return mount_transform()


## The plug on the end of the cord, or null until the cord has been made (a deferred call).
func get_plug() -> ControllerPlug:
	return _cable_plug

# Pending port restore (set before cable is ready)
var _pending_port_restore: Dictionary = {}

# The glass being aimed at. Rebuilt whenever the console's set or its tube
# changes, cleared on unplug (see _current_aim).
var _aim: ScreenAim = null

# Toggle-hold state (VR)
var _allow_drop := false
var _saved_by: Node3D = null
var _holding_ctrl: XRController3D = null

# Desktop-hold state
var _desktop_held: bool = false

var _locomotion_manager: LocomotionManager = null
var _spawn_menu_ctrl: Node = null
var _left_vr_ctrl: XRController3D = null
var _right_vr_ctrl: XRController3D = null

## Hides the ray pointer on whichever hand is holding this, so a grab
## gesture cannot also fire the pointer at whatever is behind it.
var _pointer_block := VrPointerBlock.new()

@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _barrel_tip: Node3D = $BarrelTip
@onready var _laser_dot: MeshInstance3D = $LaserDot

# ── Physical control animation ────────────────────────────────────────────────
# The shell's trigger and buttons are display-only: the gun is aimed and fired
# from the VR controller (or the keyboard on desktop), so these show what the
# hand is doing. Driven from _pressed_now(), the same read that goes to the core,
# so the shell can never disagree with what the game is being told.

## Buttons that press into the barrel's top face, by the lightgun id they show.
const ANIM_BUTTONS: Dictionary = {
	ControllerBindings.LIGHTGUN_AUX_A: "AuxAButton",
	ControllerBindings.LIGHTGUN_AUX_B: "AuxBButton",
	ControllerBindings.LIGHTGUN_START: "StartButton",
}
## Kept well under how far the caps stand proud of the barrel (3 mm) — press
## them further and they read as vanishing into it rather than being pushed.
const BUTTON_PRESS := 0.001
## Trigger swing. Negative about +X so the blade's tip sweeps BACK toward the
## grip — a positive angle would push it forward, out of the hand.
const TRIGGER_PULL_DEG := -14.0
const ANIM_WEIGHT := 0.4

var _anim_btns: Array[Dictionary] = []   # {node, rest, lid}
var _trigger_pivot: Node3D = null
var _trigger_rest := Transform3D()
## The press state each part was last animated toward (lid, or ANIM_TRIGGER_KEY
## for the blade), and whether every part has reached it.
const ANIM_TRIGGER_KEY := -1
var _anim_last: Dictionary = {}
var _anim_settled: bool = false
## The frame's read, reused: _pressed_now is consumed within the frame it ran.
var _pressed_out: Dictionary = {}


## The trigger fires the gun and the thumbstick is the lightgun d-pad, so the
## push-out gesture has nothing to bind to. Catching one back off the laser
## still works. Queried by function_pickup._handoff_eligible.
func wants_ray_handoff() -> bool:
	return false


func _ready() -> void:
	super._ready()
	# A console's gun is a toggle (take it, it stays until the drop combo); a cabinet's is held while the
	# button is held: let go and the hand lets go, so it falls (or goes in the holster it is over).
	press_to_hold = captive
	if not captive:
		add_to_group("spawned")
	add_to_group(ControllerBindings.CONSUMER_GROUP)
	grabbed.connect(_on_grabbed_signal)
	dropped.connect(_on_dropped_signal)
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)
	# Read here rather than pushed in by whoever spawned the gun: a gun also
	# arrives by save restore and object sync, and those never set it.
	show_laser_dot = AppPrefs.aim_crosshair
	_laser_dot.visible = false
	_cache_controls()
	_spawn_cable()
	call_deferred("_find_vr_nodes")


func _find_vr_nodes() -> void:
	var rig := PadInputShared.find_rig(get_tree())
	_locomotion_manager = rig["locomotion"]
	_spawn_menu_ctrl = rig["spawn_menu"]
	_left_vr_ctrl = rig["left"]
	_right_vr_ctrl = rig["right"]
	# A spawn-menu spawn is handed to the grabbing hand before this deferred lookup
	# runs, so that grab found no manager and never blocked locomotion. Re-apply.
	_update_locomotion_block()


# ── Toggle-hold ───────────────────────────────────────────────────────────────

func _on_grabbed_signal(_pickable: Node3D, by: Node3D) -> void:
	var pickup := by as XRToolsFunctionPickup
	var ctrl := pickup.get_controller() if pickup else null as XRController3D
	# Only a HAND holding the gun shows how to put it down: a snap zone taking it (a holster)
	# is not a hold, and the hint hung over a gun in its holster.
	if _hint and (pickup != null or by.is_in_group("desktop_hand")):
		_hint.on_grabbed(by)
	if ctrl == null:
		# Desktop pickup: just flag desktop-held mode, don't set up VR toggle-hold.
		# Picked up with Shift to look at, it is held as anything else is, and does not play.
		if by.is_in_group("desktop_hand") and not DesktopPickup.inspecting(self):
			_desktop_held = true
			_laser_dot.visible = _connected_system != null and show_laser_dot
		return
	_saved_by = by
	_holding_ctrl = ctrl
	VrHold.set_model_visible(ctrl, false)
	_pointer_block.set_block(ctrl, true)
	_update_locomotion_block()


func _on_dropped_signal(_pickable: Node3D) -> void:
	# A cabinet's gun is held like any object: let go of it and it FALLS, unless it is let go at the
	# holster, whose snap zone takes it itself. The toggle-hold below (the grip lets go and the gun
	# is picked straight up again, until the drop combo) is the console gun's, and made a cabinet's
	# feel stuck to the hand; the old "goes back in its holster from anywhere" made it magnetic.
	if captive:
		_allow_drop = true
	if not _allow_drop and is_instance_valid(_saved_by):
		PokeTip.begin_rehold(_holding_ctrl)
		call_deferred("_rehold")
	else:
		if _hint:
			_hint.on_dropped()
		VrHold.set_model_visible(_holding_ctrl, true)
		_pointer_block.set_block(_holding_ctrl, false)
		_allow_drop = false
		_saved_by = null
		_holding_ctrl = null
		_desktop_held = false
		_laser_dot.visible = false
		_update_locomotion_block()


func _rehold() -> void:
	if _allow_drop:
		_allow_drop = false
		return
	if not is_instance_valid(_saved_by):
		VrHold.set_model_visible(_holding_ctrl, true)
		_pointer_block.set_block(_holding_ctrl, false)
		_saved_by = null
		_holding_ctrl = null
		_update_locomotion_block()
		return
	_saved_by.call("_pick_up_object", self)


## The combo test itself lives on HeldHint so the check and the row advertising
## it cannot disagree. Counting the use here rather than at the drop branch is
## deliberate: a predicate every drop passes through cannot be missed when
## another is added. HeldHint counts once per hold, so testing every frame does
## not inflate it.
func _is_combo_pressed(ctrl: XRController3D) -> bool:
	if not HeldHint.is_combo_pressed(ctrl):
		return false
	if _hint:
		_hint.note_used(&"drop_vr")
	return true


func _drop_all() -> void:
	VrHold.set_model_visible(_holding_ctrl, true)
	_pointer_block.set_block(_holding_ctrl, false)
	_allow_drop = true
	_holding_ctrl = null
	_laser_dot.visible = false
	_update_locomotion_block()
	drop()


func _exit_tree() -> void:
	# The cable is parented to current_scene, not to the gun, so any despawn
	# that is not the storage box (a network despawn, a menu delete) would
	# otherwise leave the plug and rope behind — the same rule as RetroController.
	if is_instance_valid(_cable_instance):
		_cable_instance.queue_free()
	_pointer_block.release(_left_vr_ctrl, _right_vr_ctrl)
	if _locomotion_manager != null:
		_locomotion_manager.clear_owner(VrHold.vr_block_owner(self))
		_locomotion_manager.set_block(VrHold.desktop_block_owner(self),
			LocomotionManager.CHANNEL_DESKTOP_MOVE, false)
	_allow_drop = true
	super._exit_tree()


func _update_locomotion_block() -> void:
	var left_held  := is_instance_valid(_holding_ctrl) and _holding_ctrl.tracker == &"left_hand"
	var right_held := is_instance_valid(_holding_ctrl) and _holding_ctrl.tracker == &"right_hand"
	var desktop_claim := _desktop_held and _connected_system != null and _port_index >= 0
	if _locomotion_manager != null:
		_locomotion_manager.set_block(VrHold.vr_block_owner(self), LocomotionManager.CHANNEL_LEFT,  left_held)
		_locomotion_manager.set_block(VrHold.vr_block_owner(self), LocomotionManager.CHANNEL_RIGHT, right_held)
	# Desktop has no hands, so the tracker tests above never fire there. The
	# desktop providers poll the InputMap, so blocking them is the only way to
	# stop WASD reaching the player while this device is claiming it.
		_locomotion_manager.set_block(VrHold.desktop_block_owner(self),
			LocomotionManager.CHANNEL_DESKTOP_MOVE, desktop_claim)
	if is_instance_valid(_spawn_menu_ctrl) and "disabled" in _spawn_menu_ctrl:
		_spawn_menu_ctrl.set("disabled", left_held)


# ── Cable ─────────────────────────────────────────────────────────────────────

func _spawn_cable() -> void:
	_cable_instance = CONTROLLER_CABLE_SCENE.instantiate()
	call_deferred("_add_cable_to_scene")


func _add_cable_to_scene() -> void:
	get_tree().current_scene.add_child(_cable_instance)
	if not captive:
		_cable_instance.add_to_group("spawned")
	_cable_plug = _cable_instance.get_node("ControllerPlug") as ControllerPlug
	_cable_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_cable_plug.set_controller(self)
	if not plug_mesh_path.is_empty():
		_cable_plug.set_plug_mesh(plug_mesh_path)
	# A hardwired cord disappears into the cabinet: no plug to see, none to pull, and the
	# rope ends where the cord entry is instead of 40 mm behind it.
	if captive:
		_cable_plug.hide()
	_cable_plug.add_collision_exception_with(self)
	_cable_plug.global_position = _cable_attach_point.global_position + Vector3(0, 0, -0.12)
	_cable_rope.start_node = _cable_attach_point
	_cable_rope.end_node = _cable_plug
	if captive:
		_cable_rope.end_anchor_offset = Vector3.ZERO
	CaptiveCord.resize(_cable_rope, cable_length)
	_cable_rope._init_points()
	_max_rope_length = _cable_rope.segment_count * _cable_rope.segment_length

	if not _pending_port_restore.is_empty():
		var sys: RetroSystem = _pending_port_restore.get("system")
		var idx: int = _pending_port_restore.get("port_index", -1)
		_pending_port_restore = {}
		if is_instance_valid(sys) and idx >= 0:
			sys.restore_controller_plug(idx, _cable_plug)
	# After the seat, not before: the lay ends at the socket.
	if captive and captive_cord_route.size() >= 2:
		if not CaptiveCord.lay(_cable_rope, captive_cord_route):
			push_warning("LightGun: captive cord route refused by the rope")


## Cache the control meshes. Absent on an older scene, in which case the gun just
## has nothing to animate.
func _cache_controls() -> void:
	for lid: int in ANIM_BUTTONS:
		var m := get_node_or_null(String(ANIM_BUTTONS[lid])) as MeshInstance3D
		if m != null:
			_anim_btns.append({"node": m, "rest": m.transform, "lid": lid})
	_trigger_pivot = get_node_or_null("TriggerPivot") as Node3D
	if _trigger_pivot != null:
		_trigger_rest = _trigger_pivot.transform


## Hysteresis for the analog VR sources — see InputLatch. Without it a single
## squeeze reaches the core as two presses.
var _latch := InputLatch.new()


## Which lightgun buttons are down this frame, keyed by LIGHTGUN_* id. One read
## of the input, shared by the core and the shell animation. Every mapped id is
## present, so an unheld gun reports them all false rather than reporting nothing.
func _pressed_now() -> Dictionary:
	var out := _pressed_out
	out.clear()
	if _desktop_held:
		for action_name: String in DESKTOP_LIGHTGUN_BUTTONS:
			var lid: int = DESKTOP_LIGHTGUN_BUTTONS[action_name]
			if lid >= 0:
				out[lid] = Input.is_action_pressed(action_name)
		_merge_poke(out)
		return out
	var vr: bool = is_instance_valid(_holding_ctrl)
	for vr_source: String in _lightgun_map:
		if vr_source == "stick":
			continue
		var lid: int = _lightgun_map[vr_source]
		if lid < 0:
			continue
		# A cabinet's gun is held only while the grip is (press_to_hold): there the grip is the hold and
		# nothing else. Bound to SELECT, as it is by default, it held the coin down for as long as the gun
		# was in the hand, and every grab was a credit.
		if captive and vr_source == "grip":
			out[lid] = bool(out.get(lid, false))
			continue
		var key := "%d:%s" % [_holding_ctrl.get_instance_id() if vr else 0, vr_source]
		var value: float = _holding_ctrl.get_float(vr_source) if vr else 0.0
		out[lid] = _latch.pressed(key, value, float(INPUT_THRESHOLDS.get(vr_source, 0.5)))
	_merge_poke(out)
	return out


## The shell's caps (not the trigger, which the holding hand pulls) also give
## under a fingertip — see ControlPoke. A target's bits are LIGHTGUN_* ids here,
## not RetroPad bits. Bound on first use rather than in _ready, so a gun that adds
## caps of its own to _anim_btns gets them too.
var _poke: ControlPoke = null


func _merge_poke(out: Dictionary) -> void:
	if _poke == null:
		_poke = ControlPoke.new(self)
		for e: Dictionary in _anim_btns:
			_poke.targets.append({"node": e["node"], "rest": e["rest"],
				"dir": e.get("dir", Vector3.DOWN), "bit": int(e["lid"])})
		_poke.targets.append_array(_extra_poke_targets())
	var poked := int(_poke.poll()["btn"])
	var lid := 0
	while poked != 0:
		if poked & 1:
			out[lid] = true
		poked >>= 1
		lid += 1


## Controls a gun moves outside _anim_btns (a d-pad), as ControlPoke targets whose
## bits are LIGHTGUN_* ids. Its own hook, so a gun pack overrides it with no
## super() to call, which a pack still loading in an older build could not do.
func _extra_poke_targets() -> Array[Dictionary]:
	return []


func _animate_controls(pressed: Dictionary) -> void:
	# A press change restarts the blend; once every part has reached its target
	# the frames until the next change write nothing.
	var changed := false
	for e: Dictionary in _anim_btns:
		var lid: int = e["lid"]
		var down_now: bool = pressed.get(lid, false)
		var was: Variant = _anim_last.get(lid)
		if not (was is bool) or bool(was) != down_now:
			_anim_last[lid] = down_now
			changed = true
	var trigger_now: bool = pressed.get(ControllerBindings.LIGHTGUN_TRIGGER, false)
	var trigger_was: Variant = _anim_last.get(ANIM_TRIGGER_KEY)
	if not (trigger_was is bool) or bool(trigger_was) != trigger_now:
		_anim_last[ANIM_TRIGGER_KEY] = trigger_now
		changed = true
	if changed:
		_anim_settled = false
	elif _anim_settled:
		return

	var at_target := true
	for e: Dictionary in _anim_btns:
		var node: MeshInstance3D = e["node"]
		var rest: Transform3D = e["rest"]
		var down := 1.0 if pressed.get(int(e["lid"]), false) else 0.0
		var tgt := Transform3D(rest.basis, rest.origin + Vector3.DOWN * (BUTTON_PRESS * down))
		var next := node.transform.interpolate_with(tgt, ANIM_WEIGHT)
		if next.is_equal_approx(tgt):
			next = tgt
		else:
			at_target = false
		node.transform = next
	if _trigger_pivot == null:
		_anim_settled = at_target
		return
	var pull := 1.0 if trigger_now else 0.0
	var tgt_x := Transform3D(
		_trigger_rest.basis * Basis(Vector3.RIGHT, deg_to_rad(TRIGGER_PULL_DEG * pull)),
		_trigger_rest.origin)
	var next_x := _trigger_pivot.transform.interpolate_with(tgt_x, ANIM_WEIGHT)
	if next_x.is_equal_approx(tgt_x):
		next_x = tgt_x
	else:
		at_target = false
	_trigger_pivot.transform = next_x
	_anim_settled = at_target


func _physics_process(_delta: float) -> void:
	# A gun on a mount goes where its cabinet goes: carried off, knocked, it stays on its pivot. A hand turning it
	# is the grab driver's (constrain_grab), which lands on the same place.
	if is_mounted() and not is_picked_up():
		freeze = true
		var home := mount_transform()
		if not global_transform.is_equal_approx(home):
			global_transform = home
	if _cable_plug == null or _cable_attach_point == null or _max_rope_length <= 0.0:
		return
	if _cable_plug.is_picked_up() or _connected_system != null:
		return

	PlugTether.reel_in(_cable_plug, _cable_plug.global_position,
			_cable_attach_point.global_position, _max_rope_length)


# ── Port events ───────────────────────────────────────────────────────────────

func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	_connected_system = system
	_port_index = port_index
	_laser_dot.visible = show_laser_dot
	_load_bindings()
	print("[LightGun] plugged into system port %d" % port_index)


## Reload bindings from disk (called externally after the user saves new bindings).
func reload_bindings() -> void:
	_load_bindings()


func _load_bindings() -> void:
	var sysid := ""
	if is_instance_valid(_connected_system):
		sysid = _connected_system.systemid
	var bindings := ControllerBindings.get_for_system(sysid)
	_lightgun_map = bindings["lightgun"]


func on_unplugged() -> void:
	print("[LightGun] unplugged from port %d" % _port_index)
	_laser_dot.visible = false
	_connected_system = null
	_port_index = -1
	_aim = null


## The glass of the set the console is showing on, or null. Looked up every
## frame and rebuilt only when it changes: the console can be recabled to
## another set while the gun stays plugged in, and a cabinet mod swaps its own
## tube in once the set is ready.
func _current_aim() -> ScreenAim:
	if _connected_system == null:
		_aim = null
		return null
	var mesh: MeshInstance3D = null
	if _connected_system.connected_tv != null:
		mesh = _connected_system.connected_tv.get_screen_mesh()
	elif _connected_system.get_model() != null:
		# No set to aim at: a cabinet's own tube is the glass (a handheld's, likewise).
		mesh = _connected_system.get_model().get_builtin_screen()
	if mesh == null or mesh.mesh == null:
		_aim = null
		return null
	if _aim == null or not _aim.is_for(mesh):
		_aim = ScreenAim.new(mesh)
	return _aim


func restore_port_connection(system: RetroSystem, port_index: int) -> void:
	if _cable_plug != null:
		system.restore_controller_plug(port_index, _cable_plug)
	else:
		_pending_port_restore = {"system": system, "port_index": port_index}


# ── Input forwarding ──────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# VR drop combo (desktop drop is handled by desktop_pickup via left click)
	if _is_combo_pressed(_holding_ctrl):
		_drop_all()
		return

	# The shell moves whether or not it is plugged into anything — an unplugged
	# gun still has a trigger you can squeeze.
	var pressed := _pressed_now()
	_animate_controls(pressed)

	if _connected_system == null or _port_index < 0:
		return

	var libretro := _connected_system.get_libretro_node()

	# Desktop mode: aim from camera centre, read keyboard/mouse for buttons
	if _desktop_held:
		_process_desktop_lightgun(libretro, pressed)
		return

	# VR mode: no controller held → report offscreen. The only buttons down are
	# the caps a fingertip is pressing on the shell (_merge_poke).
	if not is_instance_valid(_holding_ctrl):
		_set_aim(libretro, 0, 0, true)
		for lid: int in pressed:
			_set_button(libretro, lid, pressed[lid])
		if _lightgun_map.get("stick", "none") == "dpad":
			for lid: int in DPAD_IDS:
				_set_button(libretro, lid, false)
		_laser_dot.visible = false
		return

	var ctrl := _holding_ctrl

	# Buttons come from the map via _pressed_now(); "stick" is handled separately.
	for lid: int in pressed:
		_set_button(libretro, lid, pressed[lid])

	# Thumbstick → lightgun d-pad (thresholded).
	if _lightgun_map.get("stick", "none") == "dpad":
		var dirs := _stick_dpad(ctrl.get_vector2("primary"))
		for i in DPAD_IDS.size():
			_set_button(libretro, DPAD_IDS[i], dirs[i])

	_update_aim(libretro)


## Which way the thumbstick pushes the d-pad: up, down, left, right, as DPAD_IDS.
static func _stick_dpad(stick: Vector2) -> Array[bool]:
	return [stick.y > DPAD_THRESHOLD, stick.y < -DPAD_THRESHOLD,
		stick.x < -DPAD_THRESHOLD, stick.x > DPAD_THRESHOLD]


## Desktop: read keyboard+mouse, aim from camera centre ray.
func _process_desktop_lightgun(libretro: Libretro, pressed: Dictionary) -> void:
	for lid: int in pressed:
		_set_button(libretro, lid, pressed[lid])

	# D-pad from WASD/retro joypad actions
	_set_button(libretro, ControllerBindings.LIGHTGUN_DPAD_UP,
		Input.is_action_pressed("RETRO_JOYPAD_UP"))
	_set_button(libretro, ControllerBindings.LIGHTGUN_DPAD_DOWN,
		Input.is_action_pressed("RETRO_JOYPAD_DOWN"))
	_set_button(libretro, ControllerBindings.LIGHTGUN_DPAD_LEFT,
		Input.is_action_pressed("RETRO_JOYPAD_LEFT"))
	_set_button(libretro, ControllerBindings.LIGHTGUN_DPAD_RIGHT,
		Input.is_action_pressed("RETRO_JOYPAD_RIGHT"))

	_update_aim_desktop(libretro)


## VR aim: ray from barrel tip along barrel -Z. A RIFLE on a pivot (the long stock, `mount_lever`) tells the game its TRAVEL instead (MountAim): a ray from a rifle that turns 28 degrees up meets a glass that is 59 degrees up
## only at its bottom edge, and the reticle sat low whatever the hand did.
func _update_aim(libretro: Libretro) -> void:
	if is_mounted() and mount_lever:
		var turn := mount_turn()
		var at := MountAim.picture(turn.x, turn.y, MOUNT_YAW_LIMIT, MOUNT_PITCH_LIMIT)
		_set_aim(libretro, at.x, at.y, false)
		if _feeds_pointer():
			libretro.SetPointerState(_port_index, at.x, at.y,
				hand_button(ControllerBindings.LIGHTGUN_TRIGGER) or external_button(ControllerBindings.LIGHTGUN_TRIGGER))
		_laser_dot.visible = false
		return
	_apply_aim_hit(libretro, _barrel_tip.global_position, -_barrel_tip.global_transform.basis.z)


## Desktop aim: ray from camera centre along camera -Z (matches the crosshair).
func _update_aim_desktop(libretro: Libretro) -> void:
	var cam := get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		_set_aim(libretro, 0, 0, true)
		_laser_dot.visible = false
		return
	_apply_aim_hit(libretro, cam.global_position, -cam.global_transform.basis.z)


## Shared hit-test and coordinate conversion for both VR and desktop aim: the
## ray meets the glass itself, so the core is told the picture point drawn
## where the gun points, from any angle (ScreenAim).
func _apply_aim_hit(libretro: Libretro, ray_origin: Vector3, ray_dir: Vector3) -> void:
	var aim := _current_aim()
	var hit := aim.hit(ray_origin, ray_dir) if aim != null else {}
	if hit.is_empty():
		_set_aim(libretro, 0, 0, true)
		if _feeds_pointer():
			libretro.SetPointerState(_port_index, 0, 0, false)
		_laser_dot.visible = false
		return

	var picture: Vector2 = hit["picture"]
	var lx := int((picture.x * 2.0 - 1.0) * 32767)
	var ly := int((picture.y * 2.0 - 1.0) * 32767)
	_set_aim(libretro, lx, ly, false)
	if _feeds_pointer():
		libretro.SetPointerState(_port_index, lx, ly,
			hand_button(ControllerBindings.LIGHTGUN_TRIGGER) or external_button(ControllerBindings.LIGHTGUN_TRIGGER))

	# On the glass where the ray met it, just proud of it toward the gun.
	_laser_dot.visible = show_laser_dot
	_laser_dot.global_position = (hit["point"] as Vector3) - ray_dir.normalized() * 0.002


## Buttons pressed from OUTSIDE the gun, by the machine it is wired to: a cabinet's START
## buttons and its coin (lightgun id -> down). ORed with what the hand does, because the gun
## writes every mapped button every frame and would otherwise take them back.
var _external: Dictionary = {}


## A button pressed by the machine, not by a hand. See _external.
func set_external_button(lid: int, down: bool) -> void:
	if bool(_external.get(lid, false)) == down:
		return
	_external[lid] = down
	if _connected_system != null and _port_index >= 0:
		_set_button(_connected_system.get_libretro_node(), lid, false)


## Whether the HAND is holding a button down (the machine's own presses, set_external_button, left
## out). ArcadeInput reads START and SELECT here to send them as the joypad's as well.
func hand_button(lid: int) -> bool:
	return bool(_pressed_out.get(lid, false))


## Buttons the machine has taken over (lightgun id -> true): the hand's press of one no longer reaches the
## core, only the machine's (set_external_button), and the machine reads the hand through hand_button. A
## cabinet's foot pedal takes Aux A this way, because the game must hear the PEDAL, which the hand's Aux A
## only lifts (ArcadeInput._step_pedal).
var _claimed: Dictionary = {}


## Take a button over from the hand, or give it back. See _claimed.
func claim_button(lid: int, claimed: bool) -> void:
	if _claimed.has(lid) == claimed:
		return
	if claimed:
		_claimed[lid] = true
	else:
		_claimed.erase(lid)
	if _connected_system != null and _port_index >= 0:
		_set_button(_connected_system.get_libretro_node(), lid, hand_button(lid))


## What the core is told of one button now: see _told.
func sent_button(lid: int) -> bool:
	return _told(lid, hand_button(lid))


## What the core is told of one button the hand has `pressed` or not: the hand's press unless the machine has
## taken the button over, ORed with the machine's own.
func _told(lid: int, pressed: bool) -> bool:
	return (pressed and not _claimed.has(lid)) or bool(_external.get(lid, false))


## The VR controller holding this gun, or null (in a holster, on the floor, or in the desktop's hand).
func holding_controller() -> XRController3D:
	return _holding_ctrl if is_instance_valid(_holding_ctrl) else null


## The rows a cabinet adds to this gun's held hint (ArcadeInput: how its pedal takes cover), [] for none. A
## row is [id, platform, glyphs, caption]; a repeat of what is there already changes nothing.
var _cabinet_rows: Array = []


func set_cabinet_hint(rows: Array) -> void:
	if rows == _cabinet_rows or _hint == null:
		return
	for row: Array in _cabinet_rows:
		_hint.remove_row(row[0])
	_cabinet_rows = rows
	for row: Array in rows:
		_hint.add_row(row[0], row[1], row[2], row[3], HeldHint.WHEN_HELD)


## Whether this gun's core can only read an aimed gun as a pointer (ForcedCoreOptions.GUN_AS_POINTER).
## Asked of the machine twice a second, not per frame.
var _pointer_checked_at := -1000
var _pointer_core := false


func _feeds_pointer() -> bool:
	if _connected_system == null:
		return false
	var now := Engine.get_process_frames()
	if now - _pointer_checked_at > 30:
		_pointer_checked_at = now
		_pointer_core = ForcedCoreOptions.gun_feeds_pointer(String(_connected_system.call("_resolve_core")))
	return _pointer_core


## The machine-pressed state of one button, for the tests.
func external_button(lid: int) -> bool:
	return bool(_external.get(lid, false))


func _set_button(libretro: Libretro, button: int, pressed: bool) -> void:
	pressed = _told(button, pressed)
	if not NetworkManager.netplay_set_lightgun_button(_connected_system, _port_index,
			button, pressed):
		libretro.SetLightgunButton(_port_index, button, pressed)


## The aim last sent, in libretro light-gun coordinates (-0x7fff..0x7fff, y down): a cabinet whose game reads a gun as an analog stick
## sends it as the pad's left stick as well (ArcadeInput._gun_axes).
var last_aim := Vector2i.ZERO


func _set_aim(libretro: Libretro, x: int, y: int, offscreen: bool) -> void:
	last_aim = Vector2i(x, y)
	if not NetworkManager.netplay_set_lightgun_aim(_connected_system, _port_index,
			x, y, offscreen):
		libretro.SetLightgunPosition(_port_index, x, y)
		libretro.SetLightgunIsOffscreen(_port_index, offscreen)


