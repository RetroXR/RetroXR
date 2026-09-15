## RetroSystemModelNDS — Nintendo DS, the original "Phat" (clamshell, two
## 256×192 screens). This is the DEFAULT nds model; the later DS Lite is the
## "nds:lite" variant (nds_lite_model.gd), which subclasses this and swaps only
## the shell GLB — every dual-screen behaviour below is shared.
##
## melonDS/desmume default layout: top/bottom stacked in one 256×384
## framebuffer — top half = top screen, bottom half = touch screen.
## Two video-out cables (TOP / BOTTOM, from the dual-screen base); tapping a
## TV connected to the BOTTOM cable feeds the touch screen.
## Shell geometry lives in nds.tscn; this sets the composite UV mapping + cart.
class_name RetroSystemModelNDS
extends RetroSystemModelDualScreen


## The UV windows assume the stacked composite, and taps (device pad or
## the BOTTOM TV) arrive as RETRO_DEVICE_POINTER — both DS cores default to a
## MOUSE-style pointer that ignores it (melonDS "Mouse" mode, DeSmuME
## pointer_type "mouse"). Force touch mode on both; each core ignores the
## other's keys.
##
## A DS has no microphone button, and melonDS DS gates its mic on L3, which is
## masked below; "always" leaves the listening to the game.
func get_forced_core_options() -> Dictionary:
	return {
		"melonds_touch_mode": "Touch",
		"melonds_screen_layout": "Top/Bottom",
		"melonds_screen_gap": "0",
		"melonds_mic_input": "microphone",
		"melonds_mic_input_active": "always",
		"desmume_pointer_type": "touch",
		"desmume_screens_layout": "top/bottom",
	}


## The DS has L and R and nothing else on its shoulders — no triggers, no stick
## clicks. Both cores bind hotkeys to the four buttons it lacks, and neither can
## be turned off by a core option: melonDS puts "swap screens" on R2 and "close
## lid" on L3, DeSmuME "lid close/open" on L2 (the screens go white) and "quick
## screen switch" on R3. Silence all four.
func get_unsupported_button_mask() -> int:
	return (1 << ControllerBindings.JOYPAD_L2) \
		| (1 << ControllerBindings.JOYPAD_R2) \
		| (1 << ControllerBindings.JOYPAD_L3) \
		| (1 << ControllerBindings.JOYPAD_R3)


## Insets from the base half's front-left corner, used only when the shell
## doesn't model the slider as its own mesh (the Phat bakes it into the body).
const _VOL_EDGE_INSET := 0.004
const _VOL_FRONT_INSET := 0.020


## Power LED. The DS Lite ships a lit/unlit mesh PAIR ("lights on" / "lights
## off", coincident at the front-right corner) to swap between; the Phat bakes
## its LED into the body and only marks the spot with a "Power Light" empty, so
## a small emissive dot is built there instead. Green, like the hardware.
const _LED_SIZE := Vector3(0.003, 0.002, 0.005)
const _LED_COLOR := Color(0.35, 1.0, 0.35)

var _led_on: MeshInstance3D = null
var _led_off: MeshInstance3D = null


func _ready() -> void:
	super()
	_place_volume_slider()
	_setup_power_light()
	_set_power_light(false)


func _setup_power_light() -> void:
	_led_on = find_child("lights on", true, false) as MeshInstance3D
	_led_off = find_child("lights off", true, false) as MeshInstance3D
	if _led_on != null:
		return
	var marker := find_child("Power Light", true, false) as Node3D
	if marker == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "PowerLed"
	var bm := BoxMesh.new()
	bm.size = _LED_SIZE
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _LED_COLOR
	mat.emission_enabled = true
	mat.emission = _LED_COLOR
	mat.emission_energy_multiplier = 2.5
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	mi.global_position = marker.global_position
	_led_on = mi


func _set_power_light(on: bool) -> void:
	if _led_on != null:
		_led_on.visible = on
	if _led_off != null:
		_led_off.visible = not on


func on_power_on() -> void:
	super()
	_set_power_light(true)


func on_power_off() -> void:
	super()
	_set_power_light(false)


## Put the power control's touch zone on the shell's REAL power switch.
##
## The dual-screen base places a generic power button proportionally on the front
## face (body_size.x * 0.36) and BUILDS a little cylinder mesh for it, because a
## primitive clamshell has no power switch to point at. Both DS shells do model
## one, so that stand-in ended up as a floating puck on the front lip while the
## actual switch sat unused: the Lite models it as a mesh ("Power Slider", right
## edge at x=+0.070); the Phat only PAINTS it, but still marks it with a "Power"
## empty on the face above the D-pad (x=-0.057) — which is where the hardware puts
## it, the right edge being the Lite's arrangement. Prefer the mesh, fall back to
## the marker, and drop the synthetic puck in either case — the shell already
## draws a switch. A painted-only switch then needs a touch box built for it; see
## _fit_painted_power_switch.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	super(power_btn, reset_btn, eject_btn)
	if power_btn == null:
		return
	var mesh := find_child("Power Slider", true, false) as MeshInstance3D
	var marker := find_child("Power", true, false) as Node3D
	var where := Vector3.ZERO
	if mesh != null and mesh.mesh != null:
		where = (mesh.global_transform * mesh.get_aabb() as AABB).get_center()
		power_btn.set_button_mesh(mesh)
	elif marker != null:
		where = marker.global_position
	else:
		return   # no real switch on this shell: keep the base's stand-in
	var puck := power_btn.get_node_or_null("HandheldPowerMesh") as MeshInstance3D
	if puck != null and puck != mesh:
		puck.hide()
	power_btn.global_position = where
	if mesh == null:
		_fit_painted_power_switch(power_btn, marker)
	# The label is authored to sit under a front-face puck; on a side-edge switch
	# it would float off the shell, and the hardware is self-explanatory.
	var lbl := power_btn.get_node_or_null("ButtonLabel") as Label3D
	if lbl != null:
		lbl.hide()


## The painted switch, measured off a top-down render of the shell: a flat 10.0 x
## 3.5 mm decal centred at model-local (-0.0571, -0.0268) — which the GLB's "Power"
## empty marks to within 0.2 mm. The face around it sits at y = 0.0028; the empty
## itself is buried 1.1 mm under that.
const _PAINTED_SWITCH := Vector3(0.0100, 0.0012, 0.0035)
const _PAINTED_FACE_Y := 0.0028
## Poke volume over the decal. Deeper and wider than the print so a fingertip can
## actually land on a 3.5 mm target.
const _PAINTED_TOUCH_BOX := Vector3(0.014, 0.010, 0.010)


## Stop-gap for a control the shell only PAINTS. The Phat merges its whole body
## into one mesh and prints the power switch into the texture, so there is nothing
## to hand set_button_mesh — the button ended up at the right spot with the base's
## front-face collision box (16 x 16 x 8 mm, pressing along -Z) and no visual at
## all, which is why it read as sitting off the switch.
##
## Give it a box over the print instead, plus a hidden box the size of the print
## for the hover outline to trace, so an unmodelled control still targets and
## highlights like a modelled one. Replace this the day the shell gets real switch
## geometry — then it takes the normal set_button_mesh path with the Lite.
func _fit_painted_power_switch(power_btn: VRButton, marker: Node3D) -> void:
	if marker == null:
		return
	var up := global_transform.basis.y.normalized()
	var lift := _PAINTED_FACE_Y - to_local(marker.global_position).y
	var col := power_btn.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		col.shape = col.shape.duplicate()
		(col.shape as BoxShape3D).size = _PAINTED_TOUCH_BOX
		col.global_position = marker.global_position + up * lift
	# The D-pad is 23 mm away on the same face — don't reach across to it.
	power_btn.trigger_radius = 0.010

	var box := MeshInstance3D.new()
	box.name = "PaintedPowerSwitch"
	var decal := BoxMesh.new()
	decal.size = _PAINTED_SWITCH
	box.mesh = decal
	power_btn.add_child(box)
	# Pose it BEFORE set_button_mesh, which caches the depress origin and parent.
	box.global_position = marker.global_position + up * lift
	box.global_basis = global_basis
	power_btn.set_button_mesh(box)
	power_btn.set_depress_axis_world(-up)   # top-face switch: presses straight down
	power_btn.depress_depth = 0.0008
	power_btn.set_outline_hidden_source(true)
	box.hide()


## Put the volume slider's touch zone on the shell's REAL volume control.
##
## Both DS scenes authored it at x=+0.0685 — which is the POWER switch side. The
## base moves the power switch onto the GLB's "Power" marker (Lite: x=+0.0701),
## so the two controls ended up 1.5 mm apart, each with a 2.8 cm engage radius:
## reaching for one was indistinguishable from the other, and the volume slider
## wasn't anywhere near the real hardware's slider.
##
## The DS Lite models the control ("Volume Slider" mesh, front-left at
## x=-0.0554, z=+0.0384), so use it directly. The Phat bakes its buttons and
## sliders into the body mesh, leaving nothing to snap to — fall back to the
## base half's front-left edge, which is where the slider sits on real hardware.
func _place_volume_slider() -> void:
	var vs := get_node_or_null("VolumeSlider") as Node3D
	if vs == null:
		return
	var mesh := find_child("Volume Slider", true, false) as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var ab: AABB = mesh.global_transform * mesh.get_aabb()
		vs.global_position = ab.get_center()
		return
	var base := _base_half_aabb()
	if base.size.x <= 0.0001:
		return
	vs.position = Vector3(base.position.x + _VOL_EDGE_INSET,
		base.get_center().y, base.end.z - _VOL_FRONT_INSET)


## Bounds of the lower half only, in model space. The lid meshes are reparented
## onto LidPivot by the base's upgrade pass, so whatever is still under Shell IS
## the base half.
func _base_half_aabb() -> AABB:
	var shell := get_node_or_null("Shell") as Node3D
	if shell == null:
		return AABB()
	var acc := AABB()
	var first := true
	for n in shell.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var ab: AABB = (global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		acc = ab if first else acc.merge(ab)
		first = false
	return acc


func _init() -> void:
	# Stacked 256×384 composite: top half / bottom half.
	top_uv_rect = Rect2(0.0, 0.0, 1.0, 0.5)
	bottom_uv_rect = Rect2(0.0, 0.5, 1.0, 0.5)
	cart_size = Vector3(0.033, 0.035, 0.004)   # DS Game Card




## The upper clamshell half (folds with the hinge); the top screen lens + its
## dark backing panel are handled by the base. Everything else = the base half.
func _lid_mesh_names() -> PackedStringArray:
	return PackedStringArray(["Top"])
