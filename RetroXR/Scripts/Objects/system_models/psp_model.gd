## RetroSystemModelPSP — Sony PlayStation Portable (PSP-1000, 480×272 widescreen).
##
## The animation code below drives a shell that models each control as its own
## mesh — the ✕○□△ face buttons, the d-pad, the analog nub, the L/R shoulders,
## Start/Select/Home, the volume ± and sound/display keys, the slide POWER switch,
## the EJECT latch and the UMD door. The stand-in authors none of those, so those
## passes find nothing and no-op.
##
## Media is the UMD (systemid "psp"), which loads through the
## back-edge UMD door rather than a top slot.
class_name RetroSystemModelPSP
extends RetroSystemModelHandheld


## The PSP-1000 shell suffixes its lens mesh "screen_mesh_0".
func _glb_screen_name() -> String:
	return "screen_mesh_0"




# --- button animation -------------------------------------------------------

## PSP face diamond → RetroPad. ✕ is the confirm/B button, ○ back/A, □ Y, △ X —
## the same glyph-position convention RetroPad already uses.
const _FACE_MESH: Dictionary = {
	ControllerBindings.JOYPAD_B: "FireButtonBottom",   # ✕
	ControllerBindings.JOYPAD_A: "FireButtonRight",    # ○
	ControllerBindings.JOYPAD_Y: "FireButtonLeft",     # □
	ControllerBindings.JOYPAD_X: "FireButtonTop",      # △
	ControllerBindings.JOYPAD_START:  "StartButton",
	ControllerBindings.JOYPAD_SELECT: "SelectButton",
}
const _SHOULDER_MESH: Dictionary = {
	ControllerBindings.JOYPAD_L: "LShoulderButton",
	ControllerBindings.JOYPAD_R: "RShoulderButton",
}

const _FACE_PRESS := 0.0016
const _SHOULDER_PRESS := 0.0030
const _NUB_SLIDE := 0.0022
const _DPAD_TILT_DEG := 9.0
const _ANIM_W := 0.4
## Press axis in the button meshes' PARENT frame ("Shell") — set from the
## face-button normal at cache time, since the GLB carries its own baked
## lay-back rotation (Shell is rotated ~-90° about X relative to this model
## node) and every animated mesh's `.transform` is local to that same Shell,
## not to this node.
var _press_dir := Vector3(0, 0, -1)
## This model's "up" (screen-normal) direction expressed in Shell's local
## frame — the frame-consistent counterpart to _press_dir for building a
## sideways axis (nub slide, power switch slide).
var _shell_up := Vector3.UP

var _anim_cached := false
var _anim_btns: Array[Dictionary] = []   # {node, rest, bit, depth}
var _anim_nub: Dictionary = {}           # analog nub: {node, rest, pivot}
var _anim_dpad: Dictionary = {}          # {node, rest, pivot}


func _on_shell_ready() -> void:
	_cache_anim_meshes()
	_configure_power_slide()
	_configure_open_slide()
	_configure_volume_buttons()
	_configure_umd_door()
	_configure_power_led()


## Both shells spell the pill switches this way, so this claims them on both paths
## and the shared stand-in pass skips them.
func _own_animated_meshes() -> PackedStringArray:
	return PackedStringArray(["StartButton", "SelectButton"])


func _cache_anim_meshes() -> void:
	if _anim_cached:
		return
	_anim_cached = true
	# Press direction: into the face, i.e. the negated screen normal, expressed
	# in the button meshes' own parent frame (Shell) — every animated mesh's
	# .transform lives there, NOT in this model node's frame, and Shell carries
	# its own baked lay-back rotation relative to this node. Averaged over the
	# button and snapped to an axis — a single triangle's normal catches a
	# bevelled side (the PSP's read as diagonal).
	var probe := find_child("FireButtonBottom", true, false) as MeshInstance3D
	if probe != null:
		var shell := probe.get_parent() as Node3D
		if shell != null:
			_press_dir = -_axis_normal(probe, shell)
			_shell_up = shell.global_transform.basis.inverse() * Vector3.UP
	elif _glb == null:
		# The stand-in has no Shell to measure off and no lay-back to correct for:
		# its controls are direct children of this model, lying flat with the
		# screen up. The GLB-frame default pushes them out of the back edge.
		_press_dir = Vector3.DOWN
		_shell_up = Vector3.UP
	for map: Dictionary in [_FACE_MESH, _SHOULDER_MESH]:
		var depth: float = _FACE_PRESS if map == _FACE_MESH else _SHOULDER_PRESS
		for bit: int in map:
			var m := find_child(map[bit], true, false) as MeshInstance3D
			if m != null:
				_anim_btns.append({"node": m, "rest": m.transform, "bit": bit, "depth": depth})
	# Analog nub: mesh "StickLeft2", pivot empty "StickLeft".
	var nub := find_child("StickLeft2", true, false) as MeshInstance3D
	if nub != null:
		_anim_nub = {"node": nub, "rest": nub.transform, "pivot": _pivot_of(nub, "StickLeft")}
	# D-pad: mesh "Dpad2", pivot empty "Dpad".
	var dpad := find_child("Dpad2", true, false) as MeshInstance3D
	if dpad != null:
		_anim_dpad = {"node": dpad, "rest": dpad.transform, "pivot": _pivot_of(dpad, "Dpad")}


## btn = RETRO_JOYPAD bitmask; lstick/rstick are the analog values (−1..1) as sent
## to the core (y already screen-negated). Lerps the meshes toward that state.
func animate_controls(btn: int, lstick: Vector2, rstick: Vector2) -> void:
	# The stand-in authors its face diamond and pad in the shared stand-in
	# vocabulary, which the base pass drives; this shell's own names are below.
	super.animate_controls(btn, lstick, rstick)
	if not _anim_cached:
		_cache_anim_meshes()

	for e: Dictionary in _anim_btns:
		var node: MeshInstance3D = e["node"]
		var rest: Transform3D = e["rest"]
		var down := 1.0 if (btn & (1 << int(e["bit"]))) != 0 else 0.0
		var tgt := Transform3D(rest.basis, rest.origin + _press_dir * (float(e["depth"]) * down))
		node.transform = node.transform.interpolate_with(tgt, _ANIM_W)

	if not _anim_nub.is_empty():
		# The nub slides in-plane. The plane is perpendicular to the press axis;
		# lstick.x runs across the face, lstick.y up it (already screen-negated).
		var ax := _shell_up.cross(_press_dir).normalized()
		if ax.length() < 0.5:
			ax = Vector3.RIGHT
		var ay := _press_dir.cross(ax).normalized()
		var off := (ax * lstick.x + ay * lstick.y) * _NUB_SLIDE
		var node: MeshInstance3D = _anim_nub["node"]
		var rest: Transform3D = _anim_nub["rest"]
		node.transform = node.transform.interpolate_with(Transform3D(rest.basis, rest.origin + off), _ANIM_W)

	if not _anim_dpad.is_empty():
		var pitch := float((btn >> ControllerBindings.JOYPAD_UP) & 1) - float((btn >> ControllerBindings.JOYPAD_DOWN) & 1)
		var roll := float((btn >> ControllerBindings.JOYPAD_LEFT) & 1) - float((btn >> ControllerBindings.JOYPAD_RIGHT) & 1)
		# Screen-up handheld: UP/DOWN tilt about the console's left-right axis (X),
		# LEFT/RIGHT about the front-back axis. Pitch is negated so UP pushes the
		# far edge into the shell, matching the 3DS. This rotation is built and
		# applied in Shell's LOCAL frame (Dpad2's .transform lives there), and
		# Shell carries a ~-90° lay-back about X relative to this model node —
		# so "front-back" in the model's own frame is Shell's local Y axis, not
		# Z (rotating about Shell's Z instead, as a naive port of the 3DS code
		# would, spins the whole pad around the screen-normal axis — exactly the
		# "rolling" bug this was fixed from).
		var r := Basis.from_euler(Vector3(deg_to_rad(-pitch * _DPAD_TILT_DEG), deg_to_rad(-roll * _DPAD_TILT_DEG), 0.0))
		var node: MeshInstance3D = _anim_dpad["node"]
		var rest: Transform3D = _anim_dpad["rest"]
		var pivot: Vector3 = _anim_dpad["pivot"]
		var about := Transform3D(r, pivot - r * pivot)
		node.transform = node.transform.interpolate_with(about * rest, _ANIM_W)


# --- power slide ------------------------------------------------------------

## The PSP powers on with a SLIDE, not a button — the switch on the right edge
## pushes up toward the top of the device.
##
## The VRSlider owns the real PowerButton cap (set_knob_mesh), so the switch you
## see IS the knob: it traces the pointer highlight and travels with the value.
## This used to be a second, parallel mechanism — the slider drove a hidden
## placeholder while a bespoke _set_power_mesh() slid the real mesh off the
## value_changed signal — which left the cap unlit under the pointer and the
## travel axis defined in two places. Direction and throw are authored on the
## slider in psp.tscn.
##
## That axis is NOT a cardinal direction. The right edge tapers — it is widest at
## the bottom and narrows toward the top — so the cap has to travel along the
## surface it sits in, about 19 degrees off -Z. Sliding it straight along -Z (the
## obvious reading of "pushes up") buries it 1.4 mm into the shell over a 4 mm
## throw. The authored (0.320634, 0, -0.947203) is the shell's own edge tangent,
## least-squares fitted across the travel span at the switch's height; the cap
## mesh's principal axis independently agrees to within 1.5 degrees.
var _power_mesh: MeshInstance3D = null


func _configure_power_slide() -> void:
	_power_mesh = find_child("PowerButton", true, false) as MeshInstance3D
	if _power_mesh == null or _power_switch == null:
		return
	# Sit the interaction zone on the real switch FIRST — set_knob_mesh derives
	# the travel axis from the slider's global transform, so it has to run after.
	_power_switch.global_position = _mesh_center(_power_mesh)
	_power_switch.set_knob_mesh(_power_mesh)


# --- volume ------------------------------------------------------------------

## The PSP has no volume SLIDER — it has two buttons, and the shell models them:
## "Button Minus" and "Button Plus", 4.7 x 3.4 mm each, side by side on the face
## just above the bottom lip. The inherited VolumeSlider was authored at
## x = +0.087 against a shell that ends at +0.0815, so it floated a few mm off
## the right edge, nowhere near either button, driving nothing you could see.
##
## With the buttons doing the job the slider is gone from psp.tscn entirely, so
## this owns the level itself. That is the whole of what the slider was still
## providing: handheld_model wires _volume_slider.value_changed to the host and
## re-applies its position on power-on, and both of those are null-guarded, so
## deleting the node just means doing the two calls here.
const _VOLUME_STEP := 0.1

## 0..1, full volume by default.
var _volume: float = 1.0


func _configure_volume_buttons() -> void:
	for spec: Array in [["VolumeDown", "Button Minus", -1.0], ["VolumeUp", "Button Plus", 1.0]]:
		var btn := get_node_or_null(String(spec[0])) as VRButton
		var mesh := find_child(String(spec[1]), true, false) as MeshInstance3D
		if btn == null or mesh == null:
			continue
		btn.global_position = _mesh_center(mesh)
		btn.set_button_mesh(mesh)   # the shell's own key IS the button
		# Face-mounted, so they press INTO the face: _press_dir already points that
		# way in the meshes' own parent frame (Shell), which is the frame
		# depress_axis is read in.
		btn.depress_axis = _press_dir
		var lbl := btn.get_node_or_null("ButtonLabel") as Label3D
		if lbl != null:
			lbl.visible = false
		var step := float(spec[2]) * _VOLUME_STEP
		btn.button_pressed.connect(func() -> void: _step_volume(step))


func _step_volume(delta: float) -> void:
	var was := _volume
	_volume = clampf(_volume + delta, 0.0, 1.0)
	if not is_equal_approx(_volume, was):
		_push_volume()


## Only reaches the host once it has an audio player, which is why on_power_on
## re-sends it — presses while the system is off still count, they just have
## nowhere to land until it comes up.
func _push_volume() -> void:
	var host := get_parent()
	if host != null and host.has_method("set_audio_volume"):
		host.set_audio_volume(_volume)


# --- UMD door latch ----------------------------------------------------------

## The UMD door is released by a SPRUNG LATCH on the back edge, not a button: you
## push it along the edge and the door pops, and it springs straight back. That is
## the same mechanism as the power switch, so it is the same class
## (VRSpringReturnSlider) — but with no dwell. The power switch has to be HELD to
## mean it; the latch fires the moment it reaches the end of its throw, which is
## what on_hold_sec = 0 with a 0.98 threshold buys.
##
## It travels along +X, toward the R shoulder. The shell prints "OPEN ———▷" beside
## it with the arrow pointing that way, and the strip's own principal axis is pure
## X (10.3 mm long, 0.7 mm thick) — a slide, not a press. It used to be mounted as
## the cabinet's generic eject VRButton with depress_axis = -_press_dir, i.e.
## driven along the FACE normal, so pressing it shoved the latch through the edge
## sideways-on.
##
## Reports intent, not position, so the door OPENS every time — it never toggles.
## Pushing it shut again is the door's own job (see _configure_umd_door, which
## calls request_tray_state(false) when the hinge is pushed to the closed stop).
var _open_slider: VRSpringReturnSlider = null


func _configure_open_slide() -> void:
	_open_slider = get_node_or_null("OpenSlider") as VRSpringReturnSlider
	var latch := find_child("EjectButton", true, false) as MeshInstance3D
	if _open_slider == null or latch == null:
		return
	# Position before set_knob_mesh: it derives the travel axis from the slider's
	# global transform, so it has to run after. Same order as the power slide.
	_open_slider.global_position = _mesh_center(latch)
	_open_slider.set_knob_mesh(latch)
	_open_slider.toggle_requested.connect(func() -> void:
		var host := get_parent()
		if host != null and host.has_method("request_tray_state"):
			host.request_tray_state(true))


# --- power LED ---------------------------------------------------------------

## The GLB ships FOUR overlapping "PowerLED"/"PowerLED_001".."_003" meshes,
## all stacked at the same position — looks like separate authored on/off/
## brightness states meant to be toggled by visibility, but nothing ever did,
## so all four render at once and the LED reads as permanently lit regardless
## of power state. Keep just one ("PowerLED") and drive it dynamically instead
## (same fix as the N64's always-lit LED meshes).
var _power_led: MeshInstance3D = null


func _configure_power_led() -> void:
	_power_led = find_child("PowerLED", true, false) as MeshInstance3D
	for nm in ["PowerLED_001", "PowerLED_002", "PowerLED_003"]:
		var extra := find_child(nm, true, false) as MeshInstance3D
		if extra != null:
			extra.visible = false
	_set_power_led(false)


func on_power_on() -> void:
	super.on_power_on()
	_set_power_led(true)
	# The base does this off _volume_slider, which this shell no longer has.
	_push_volume()


func on_power_off() -> void:
	super.on_power_off()
	_set_power_led(false)


func _set_power_led(on: bool) -> void:
	if _power_led == null:
		return
	var mat := _power_led.get_surface_override_material(0) as StandardMaterial3D
	if mat == null or not mat.resource_local_to_scene:
		mat = StandardMaterial3D.new()
		mat.resource_local_to_scene = true
		_power_led.set_surface_override_material(0, mat)
	mat.albedo_color = Color(0.05, 0.3, 0.08) if on else Color(0.05, 0.06, 0.05)
	mat.emission_enabled = on
	mat.emission = Color(0.5, 1.0, 0.3)
	mat.emission_energy_multiplier = 1.0 if on else 0.0


# --- UMD door + eject -------------------------------------------------------

## The UMD lives behind a hinged door on the back — a real mesh ("PSP UMD
## Deckel22"; "Deckel" is German for "lid/cover", same shell as the German-named
## AVKabel/PowerKabel cable meshes) on a real back-edge hinge, a
## VRSpringLatchedHinge rig (same idea as the disc consoles' lids —
## Dreamcast/PS2/Saturn) rather than trusting the GLB's own door
## animation/pivot empty ("PSP UMD Deckel"), which (like those consoles'
## broken Close clips) doesn't drive the mesh correctly. This gives the door a
## real spring: EJECT pops it open, and it can be grabbed and pushed shut by
## hand — it only latches when released near the closed limit.
##
## Baked into psp.tscn as UMDDoorPivot (with the door + UMD Schacht liner
## reparented onto it) / UMDDoorPivot/UMDDoorHinge / .../CollisionShape3D —
## same idiom as playstation_one.tscn's LidMount/LidPivot/LidHinge — rather
## than built at runtime. The pivot hinges at the door's real edge (its
## global-Z-MAXIMUM, the opposite end from the disc consoles' lids) with a
## 180°-about-Y yaw so the door swings DOWN and away from the shell instead
## of up through it; the hinge's grab box only covers the free (swinging)
## half of the door, away from the pivot. See Tools/bake_psp.gd in history
## for how it was built, if it ever needs rebuilding from a fresh GLB.
## The pivot must sit on the edge OPPOSITE the latch, and the latch is on the back
## edge (see _configure_open_slide) — a latch holds a door's free edge, it does not
## share a line with the hinge. Both psp.tscn and psp_primitive.tscn therefore
## hinge at the door's FRONT edge with a 180°-about-Y yaw, which is what makes the
## spring's positive max_deg swing the door DOWN and away from the shell instead of
## up through it. The stand-in used to hinge at the back edge, alongside the latch,
## and opened the wrong way.
const _UMD_OPEN_DEG := 40.0
var _umd_hinge: VRSpringLatchedHinge = null
var _umd_door_pivot: Node3D = null


func _configure_umd_door() -> void:
	var pivot := get_node_or_null("UMDDoorPivot") as Node3D
	if pivot == null:
		return
	_umd_door_pivot = pivot
	_umd_hinge = pivot.get_node_or_null("UMDDoorHinge") as VRSpringLatchedHinge
	if _umd_hinge != null:
		_umd_hinge.max_deg = _UMD_OPEN_DEG
		_umd_hinge.rotation_changed.connect(_on_umd_door_swung)


## The UMD's real slot is part of the door assembly itself (the "UMD Schacht"
## chute liner is modelled as a child of this same pivot) — unlike a spindle
## console, the seated disc should swing with the door, not stay fixed to
## the shell. See MediaTray.disc_lid_pivot.
func get_disc_lid_pivot() -> Node3D:
	return _umd_door_pivot


func has_spring_latched_lid() -> bool:
	return _umd_hinge != null


## OPEN/CLOSE come through here on a tray-loader system (RetroSystem calls
## play_open/play_close when the eject latch toggles).
func play_open() -> void:
	if _umd_hinge != null:
		_umd_hinge.open()


func play_close() -> void:
	if _umd_hinge != null:
		_umd_hinge.latch_closed()


## The hand pushed the door home (or the wheel/laser did, on desktop) — tell
## the host so it marks the UMD tray closed, same as the disc consoles.
func _on_umd_door_swung(_deg: float) -> void:
	if _umd_hinge != null and _umd_hinge.is_latched_closed():
		var host := get_parent()
		if host != null and host.has_method("request_tray_state"):
			host.request_tray_state(false)


## The PSP has no cabinet-style OPEN button: the shell's own sprung latch does the
## job (see _configure_open_slide), so the generic one stays hidden rather than
## floating beside it claiming the same mesh.
func has_eject_button() -> bool:
	return false


func configure_buttons(_power_btn: VRButton, _reset_btn: VRButton, _eject_btn: VRButton) -> void:
	pass


## UMD loads through the back-edge door. The MediaSlot ride travels the zone's
## -Z, so keep the flat placement (no cartridge-style -90° rotation).
func configure_cartridge_slot(slot: Node3D) -> void:
	var socket := _glb.find_child("System Socket", true, false) as Node3D if _glb != null else null
	if socket != null:
		slot.global_position = socket.global_position
	else:
		slot.position = Vector3(0, 0, -body_size.z / 2.0 - 0.01)
	var visual := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if visual:
		visual.visible = false
	# An authored "UMDSeat" marker (baked into the scene, riding the Shell) wins
	# over the socket-derived pose above, so the UMD rest can be dialled in
	# visually in the editor — same idiom as the disc systems' "DiscSeat"
	# (see playstation_one_model.gd). Absent → keep the socket-derived pose.
	var seat := _seat_marker("UMDSeat")
	if seat != null:
		slot.global_transform = seat.global_transform


# --- helpers ----------------------------------------------------------------

## True world position of a button/switch mesh. The PSP-1000 GLB's control
## meshes all ship with an IDENTITY node transform — their offset lives
## entirely in the baked vertex data, not the node's transform.origin — so
## mesh.global_position always reads as Shell's own origin, not the mesh's
## actual location. Every mesh-anchored interaction zone (eject latch, power
## slide) needs this instead.
func _mesh_center(mesh: MeshInstance3D) -> Vector3:
	return mesh.global_transform * mesh.get_aabb().get_center()


## Mean outward normal of a mesh, snapped to the nearest primary axis, in
## `ref`'s frame (pass the mesh's own parent so the result lines up with the
## `.transform` these meshes are actually animated in). Averaging cancels the
## button's bevel; snapping guards against a residual tilt sending presses in
## slightly off directions.
func _axis_normal(mi: MeshInstance3D, ref: Node3D) -> Vector3:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return Vector3.UP
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	if norms.is_empty():
		return Vector3.UP
	var rel := ref.global_transform.affine_inverse() * mi.global_transform
	var acc := Vector3.ZERO
	for nrm in norms:
		acc += (rel.basis * nrm).normalized()
	if acc.length() < 0.001:
		return Vector3.UP
	acc = acc.normalized()
	# Snap to whichever axis it lies closest to.
	var ax := Vector3.RIGHT
	if absf(acc.y) >= absf(acc.x) and absf(acc.y) >= absf(acc.z):
		ax = Vector3.UP
	elif absf(acc.z) >= absf(acc.x):
		ax = Vector3.BACK
	return ax * signf(acc.dot(ax))


## A pivot empty's position in the mesh's parent frame, or the mesh AABB centre.
func _pivot_of(mesh: MeshInstance3D, empty_name: String) -> Vector3:
	for n in find_children("*", "Node3D", true, false):
		if n is MeshInstance3D:
			continue
		if String(n.name) == empty_name:
			return mesh.get_parent().to_local((n as Node3D).global_position)
	var a: AABB = mesh.get_aabb()
	return mesh.transform * a.get_center()
