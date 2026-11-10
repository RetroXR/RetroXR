## Subwoofer — the RETRO XR powered subwoofer (RetroXR-models generic/subwoofer): a Loudspeaker with an amplifier
## plate on its back — LINE IN, a VOLUME knob, a rocker power switch and its own mains cord.
##
## ── Power (docs/dev/power.md) ────────────────────────────────────────────────
## Its own mains cord, as the decks and the AV switch have (ApplianceMains.hook_up, from the model's PowerCordExit
## strain relief), and a LATCHING rocker (RockerSwitch, the model's own cap on a pivot): it sounds while the rocker is ON
## and its supply is live — and with power simulation off every supply is. A rocker left ON comes back with the supply,
## as every latching switch does. Off, or unpowered, the LFE channel that reaches it plays at level 0 and nothing else
## folds onto it (SpeakerRig, via is_sounding()); the source keeps its voices where they were, so switching it back on is
## instant. The rocker is a VRLever, so it is saved and synced by the generic control walk; it starts ON, so a room saved
## before it existed keeps its bass.
##
## ── The VOLUME knob ──────────────────────────────────────────────────────────
## MOULDED. RetroXR has no subwoofer level (a set's and an amplifier's speaker outputs carry no per-channel gain), so the
## knob is the model's, drawn and boxed, and turns nothing. Making it live needs a gain on the sink contract first.
class_name Subwoofer
extends Loudspeaker

const TAG := "Subwoofer"
## The model's rocker cap and its knob: their own nodes on every level.
const ROCKER := "PowerRocker"
const KNOB := "VolumeKnob"

var _switch: RockerSwitch = null
var _mains: PowerInput = null
var _sounding: Variant = null


func _ready() -> void:
	super()
	_build_switch()
	_build_power()
	_refresh("ready")


## Whether a channel reaching this cabinet is heard: the rocker ON and a live supply.
func is_sounding() -> bool:
	return is_switched_on() and powered()


func is_switched_on() -> bool:
	return _switch == null or _switch.is_on()


## Whether its supply is live (always, with power simulation off).
func powered() -> bool:
	return _mains == null or _mains.is_live()


func power_switch() -> RockerSwitch:
	return _switch


func power_input() -> PowerInput:
	return _mains


# ── the rocker ───────────────────────────────────────────────────────────────

## The model's cap on a pivot of its own at the cap's origin (its pivot line, about whose X it tilts), every level's cap
## hung under it, and a RockerSwitch whose box is the cap as drawn, in the pivot's frame, so it tilts with the cap.
func _build_switch() -> void:
	var cap := _model.part(ROCKER) if _model != null else null
	if cap == null:
		push_warning("[%s] %s: the model has no %s; no power switch" % [TAG, name, ROCKER])
		return
	var pivot := Node3D.new()
	pivot.name = "RockerPivot"
	add_child(pivot)
	var local := global_transform.affine_inverse() * cap.global_transform
	pivot.transform = Transform3D(local.basis.orthonormalized(), local.origin)
	_model.attach_part(ROCKER, pivot)
	var drawn := ApplianceModel.node_bounds(pivot, pivot)
	var sw := RockerSwitch.new()
	sw.name = "PowerSwitch"
	sw.log_tag = TAG
	sw.target = pivot
	sw.box_engages = true
	sw.poke_torque_faces = VRHinge.FACE_Z_NEG          # the cap's face looks out of the back, the pivot's -Z
	sw.engage_radius = 0.012
	sw.icon_size = 0.012
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = drawn.size
	shape.shape = box
	shape.position = drawn.get_center()
	sw.add_child(shape)
	pivot.add_child(sw)
	sw.place_hint(Vector3(0, 0, drawn.position.z - 0.012))
	_switch = sw
	_switch.set_on(true, false)
	_switch.toggled.connect(func(on: bool) -> void: _refresh("switched %s" % ("ON" if on else "OFF")))
	print("[%s] %s: power rocker on its pivot, %s mm, ON" % [TAG, name, (drawn.size * 1000.0).snapped(Vector3.ONE * 0.1)])


# ── power ────────────────────────────────────────────────────────────────────

func _build_power() -> void:
	_mains = ApplianceMains.hook_up(self, _model)
	_mains.label = "Subwoofer (%s)" % name
	_mains.power_changed.connect(func(live: bool) -> void: _refresh("its supply %s" % ("came on" if live else "went")))
	print("[%s] %s: its own mains cord%s" % [TAG, name,
		" from the model's PowerCordExit" if _model != null and _model.part("PowerCordExit") != null
		else " (no PowerCordExit on the model: an exit made on its back)"])


## Put the sub's own cord away (plugged in out of sight) or bring it back: the System tab's Show Power Cord, and a peer's
## EV_MAINS_CORD_HIDDEN, as the AV switch does.
func set_mains_cord_hidden(on: bool) -> void:
	var cord: CaptiveMainsCord = _mains.captive as CaptiveMainsCord if _mains != null else null
	if cord == null or cord.hidden == on:
		return
	cord.set_hidden(on)
	print("[%s] %s: its mains cord %s" % [TAG, name, "put away (plugged in out of sight)" if on else "shown"])
	NetworkManager.report_event(NetEvents.Event.EV_MAINS_CORD_HIDDEN, {"obj": self, "hidden": on})


func _refresh(why: String) -> void:
	var now := is_sounding()
	if now == _sounding:
		return
	_sounding = now
	print("[%s] %s: %s: %s (rocker %s, supply %s)" % [TAG, name, why, "SOUNDING" if now else "SILENT",
		"ON" if is_switched_on() else "OFF", "live" if powered() else "dead"])


# ── collision ────────────────────────────────────────────────────────────────

## The body's and the laser's boxes are the cabinet as the model draws it, less the knob and the rocker (their own
## nodes): the knob gets a box of its own, and the rocker its own Area3D. What stands off the plate and is merged into
## the model's Body (LINE IN's jack, the cord relief, the screw heads) is in the cabinet's box, as an appliance's
## sockets are; the rocker stands 3.4 mm proud of the plate inside that box, deeper than the laser lets a control win
## from inside a shell, so a pocket over it is carved out of the laser's box (and the body's, which a fingertip meets).
func _fit_collision() -> void:
	var knob := _model.part(KNOB)
	var rocker := _model.part(ROCKER)
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var shape := get_node_or_null(path) as CollisionShape3D
		if shape == null:
			push_warning("[%s] %s: no %s to fit" % [TAG, name, path])
			continue
		var space := shape.get_parent() as Node3D
		var body := _model.bounds(space, [KNOB, ROCKER])
		var boxes: Array[AABB] = [body]
		if rocker != null:
			var r := ApplianceModel.node_bounds(rocker, space)
			var pocket := AABB(Vector3(r.position.x, r.position.y, body.position.z - 0.01),
				Vector3(r.size.x, r.size.y, r.end.z - body.position.z + 0.01))
			boxes = ApplianceModel.carve(body, pocket)
		if knob != null:
			boxes.append(ApplianceModel.node_bounds(knob, space))
		ApplianceModel.fit_collision(shape, boxes)
		print("[%s] %s: %s is the cabinet, %s mm, in %d boxes (the knob's its own)" % [TAG, name, path,
			(body.size * 1000.0).snapped(Vector3.ONE * 0.1), boxes.size()])
