## ExpansionPower — an expansion unit that needs a supply of its own (docs/dev/power.md).
##
## The 32X takes its own AC adapter (an MK-2103 in its ADAPTOR jack), on top of the
## Genesis's: a console with an unpowered 32X on it shows no picture. PowerProfiles
## says which units take one, keyed by expansion id, with the console fields (`inlet`,
## `plug` / `takes`, `brick`). A unit with no row draws its power from the console,
## as a Satellaview or a 64DD does, and gets nothing here.
##
## The jack goes where the shell draws it: the shell's own marker (an empty named as
## SystemPower.MODEL_INLETS names one, which RetroXR-models' 32X exports as
## `DCInPort`), else the row's `power_jack` (a point in the shell's GLB frame, for a
## shipped shell exported before its marker), else low on the back of the unit's box.
## On a shell the stand-in jack's drawing is hidden, as on a console model.
##
## The console asks (SystemPower.allows_power_on) and is switched off when a unit
## on it loses its supply (SystemPower.on_expansion_power).
class_name ExpansionPower
extends RefCounted

const DC_PORT := preload("res://Scenes/Objects/cables/barrel_dc_port.tscn")
## The jack's name. A save names the socket a plug is in by it: never renamed.
const INLET_NAME := "PowerInlet"


## Give `unit` its supply if its row says it takes one. Returns its PowerInput, or null.
static func build(unit: RetroExpansion) -> PowerInput:
	var profile := PowerProfiles.for_machine(unit.expansion_id, "")
	if str(profile.get("inlet", "")) != "dc":
		return null
	_build_bay(unit, profile)
	var input := PowerInput.on(unit)
	input.label = "%s (%s)" % [ExpansionCatalog.label_of(unit.expansion_id), unit.name]
	var jack := DC_PORT.instantiate() as DcPort
	jack.name = INLET_NAME
	jack.connector = PowerProfiles.plug_of(profile)
	unit.add_child(jack)
	var where := place(unit, jack)
	input.add_inlet(jack)
	input.power_changed.connect(func(live: bool) -> void: _on_power_changed(unit, live))
	print("[Power] %s: its own DC IN (%s), %s" % [input.label, jack.connector, where])
	return input


## The profile's battery bay (the Disk System drive's six C cells), cut into the
## underside of the unit's box as a handheld stand-in's is (BatteryBay). A unit
## whose box is hidden under a shell still gets its seats and cover.
static func _build_bay(unit: RetroExpansion, profile: Dictionary) -> void:
	var bay: Dictionary = profile.get("bay", {})
	if bay.is_empty():
		return
	var body := unit.get_node_or_null("Body") as MeshInstance3D
	var s := unit.size()
	var seats := BatteryBay.build(unit, AABB(-s * 0.5, s), bay, "%s_battery_cover" % unit.expansion_id,
		Color(0.38, 0.38, 0.40), body)
	print("[Power] %s: battery bay built, %d %s seats" % [unit.expansion_id, seats, str(bay.get("size", "AA"))])


## Stand the jack in the unit's mouth for it. Returns where it went, for the log.
static func place(unit: RetroExpansion, jack: DcPort) -> String:
	var s := unit.size()
	var box := AABB(-s * 0.5, s)
	var shell := unit.get_node_or_null("Shell") as Node3D
	var mouth := Vector3.ZERO
	var on_model := false
	var from := ""
	if shell != null:
		for mouth_name: String in SystemPower.MODEL_INLETS:
			var marker := shell.find_child(mouth_name, true, false) as Node3D
			if marker != null and not marker is Port:
				mouth = (unit.global_transform.affine_inverse() * marker.global_transform).origin \
					if marker.is_inside_tree() else shell.transform * marker.position
				on_model = true
				from = "the shell's %s" % mouth_name
				break
		var point: Variant = ExpansionCatalog.row(unit.expansion_id).get("power_jack")
		if not on_model and point is Vector3:
			mouth = shell.transform * (point as Vector3)
			on_model = true
			from = "the shell's jack (row power_jack)"
	if not on_model:
		# The box: low and toward the right as seen from the front, on its back.
		mouth = Vector3(box.end.x - minf(0.035, s.x * 0.25), box.position.y + minf(0.022, s.y * 0.35),
			box.position.z)
		from = "the back of its box"
	var out := SystemPower._outward(mouth, box)
	var up := Vector3.UP if absf(out.y) < 0.9 else Vector3.BACK
	var x := up.cross(out).normalized()
	var basis := Basis(x, out.cross(x), out)
	var inlet := jack.get_node_or_null("Inlet") as MeshInstance3D
	var depth := (inlet.transform * inlet.get_aabb()).end.z if inlet != null and inlet.mesh != null else 0.0
	jack.transform = Transform3D(basis, mouth - out * depth)
	if on_model:
		for drawn: String in ["Inlet", "DcMouth", "DcPin"]:
			var part := jack.get_node_or_null(drawn) as Node3D
			if part != null:
				part.visible = false
	return "at %s, facing %s" % [from, str(out)]


## The unit's supply came or went: tell the console it is on, which decides.
static func _on_power_changed(unit: RetroExpansion, live: bool) -> void:
	if not is_instance_valid(unit):
		return
	var host := unit.get_host()
	if host != null and host._power_ctl != null:
		host._power_ctl.on_expansion_power(unit, live)


## The first unit on `host` whose own supply is dead, or null.
static func dead_unit(host: RetroSystem) -> RetroExpansion:
	if host == null or host._expansions == null:
		return null
	for unit: RetroExpansion in host._expansions.units():
		var input := PowerInput.of(unit)
		if is_instance_valid(unit) and input != null and not input.is_live():
			return unit
	return null
