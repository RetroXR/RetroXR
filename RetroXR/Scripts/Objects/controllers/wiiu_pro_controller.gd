## WiiUProController — the Wii U Pro Controller (WUP-005) as a primitive: 161 x
## 105 x 48 mm (RetroXR-models nintendo/wiiu/pro-controller), two sticks above the
## D-pad and A/B/X/Y, L/R and ZL/ZR, - HOME +, POWER, four player lamps.
##
## Pairs like a Wii Remote (WiiLink, ports 1-3 on a Wii U) and is announced as
## Cemu's Pro Controller (RETRO_DEVICE_SUBCLASS(JOYPAD, 1)).
class_name WiiUProController
extends WiiUWirelessPad

const BODY := Vector3(0.161, 0.03, 0.068)
const SHELL := Color(0.08, 0.08, 0.09)
const BUTTON := Color(0.2, 0.2, 0.22)
const LED_OFF := Color(0.12, 0.12, 0.1)
const LED_ON := Color(0.35, 0.65, 1.0)

var _leds: Array[MeshInstance3D] = []


func _init() -> void:
	device_type = WiiLink.CEMU_PRO
	systemid = "wiiu"
	super._init()


func _build_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var shell := _mk_mat(SHELL, 0.35)
	var btn := _mk_mat(BUTTON, 0.4)
	var top := BODY.y * 0.5
	_mk_box(model, "Body", BODY, Vector3.ZERO, shell)
	# The two grips, hanging back toward the hands.
	_mk_box(model, "GripL", Vector3(0.042, 0.026, 0.05), Vector3(-0.058, -0.006, 0.045), shell)
	_mk_box(model, "GripR", Vector3(0.042, 0.026, 0.05), Vector3(0.058, -0.006, 0.045), shell)
	_mk_stick(model, "StickL", Vector3(-0.045, top + 0.005, -0.012), btn)
	_mk_stick(model, "StickR", Vector3(0.045, top + 0.005, 0.012), btn)
	_mk_dpad(model, Vector3(-0.045, top + 0.002, 0.018), btn)
	_mk_face(model, "FaceX", "X", Vector3(0.05, top + 0.002, -0.024), btn)
	_mk_face(model, "FaceB", "B", Vector3(0.05, top + 0.002, 0.0), btn)
	_mk_face(model, "FaceY", "Y", Vector3(0.038, top + 0.002, -0.012), btn)
	_mk_face(model, "FaceA", "A", Vector3(0.062, top + 0.002, -0.012), btn)
	_mk_cyl(model, "Select", 0.0026, 0.003, Vector3(-0.013, top + 0.0015, -0.008), btn)
	_mk_cyl(model, "Home", 0.0035, 0.002, Vector3(0.0, top + 0.001, 0.004), btn)
	_mk_cyl(model, "Start", 0.0026, 0.003, Vector3(0.013, top + 0.0015, -0.008), btn)
	# POWER, under HOME (WiiUWirelessPad builds its button on this key).
	_mk_cyl(model, "Power", 0.0028, 0.002, Vector3(0.0, top + 0.001, 0.016), btn)
	_mk_box(model, "ShoulderL", Vector3(0.03, 0.008, 0.006), Vector3(-0.05, 0.006, -BODY.z * 0.5 - 0.002), shell)
	_mk_box(model, "ShoulderR", Vector3(0.03, 0.008, 0.006), Vector3(0.05, 0.006, -BODY.z * 0.5 - 0.002), shell)
	_mk_box(model, "TriggerL", Vector3(0.028, 0.01, 0.01), Vector3(-0.05, -0.008, -BODY.z * 0.5 - 0.003), shell)
	_mk_box(model, "TriggerR", Vector3(0.028, 0.01, 0.01), Vector3(0.05, -0.008, -BODY.z * 0.5 - 0.003), shell)
	for i in 4:
		var led := _mk_box(model, "Led%d" % (i + 1), Vector3(0.003, 0.001, 0.0015),
			Vector3(-0.0075 + 0.005 * i, top + 0.0005, 0.028), _mk_mat(LED_OFF, 0.3))
		_leds.append(led)


func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	_light_player(port_index)


func on_unplugged() -> void:
	super.on_unplugged()
	_light_player(-1)


## The lamp for player N: port 1 is player 1 on a Wii U (port 0 is the GamePad's).
func _light_player(port_index: int) -> void:
	for i in _leds.size():
		var on := port_index >= 1 and i == port_index - 1
		var m := _leds[i].get_surface_override_material(0) as StandardMaterial3D
		if m == null:
			continue
		m.albedo_color = LED_ON if on else LED_OFF
		m.emission_enabled = on
		m.emission = LED_ON
