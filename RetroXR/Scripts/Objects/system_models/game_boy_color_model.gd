## RetroSystemModelGameBoyColor — Game Boy Color (CGB-001; portrait, 160×144 LCD).
## The stand-in shell lives in game_boy_color_primitive.tscn.
##
## It sets no LCD shader: the base's pixel-AA default shows the core's picture in
## full colour, which is the whole of what this machine added. The Game Boy's
## shell stood in for it before it had one of its own, and that shell's panel is
## the DMG's — every Game Boy Color game was drawn in four greens.
class_name RetroSystemModelGameBoyColor
extends RetroSystemModelHandheld

## The power lamp beside the screen: red while the machine runs, the scene's own
## dark lens while it is off.
const _LED_COLOR := Color(1.0, 0.12, 0.08)

## The headphone jack on the bottom edge, left of centre, as a fraction of the
## body's width from its middle.
const _AV_JACK_X_FRACTION := -0.16

## The infrared window, while this machine and the one it faces are linked.
## Infrared cannot be seen, which is the trouble with it here: a link that is
## up and one that is not look exactly alike until a game says so. So the
## window glows, deep red and dim -- a remote control's lamp as a camera shows
## it, not a second power light. The strength was settled from a photograph
## (gbc_ir_room_probe, windowed): at 0.55 it was a bright red panel.
const _IR_COLOR := Color(1.0, 0.07, 0.1)
const _IR_GLOW := 0.12

var _led: MeshInstance3D = null
var _led_off_material: Material = null
var _led_material: StandardMaterial3D = null

var _ir_window: MeshInstance3D = null
var _ir_off_material: Material = null
var _ir_material: StandardMaterial3D = null


func _on_shell_ready() -> void:
	_led = find_child("PowerLED", true, false) as MeshInstance3D
	if _led != null:
		_led_off_material = _led.get_surface_override_material(0)
	_ir_window = find_child("IrWindow", true, false) as MeshInstance3D
	if _ir_window != null:
		_ir_off_material = _ir_window.get_surface_override_material(0)
		var port := _ir_window.get_node_or_null("IrPort") as IrPort
		if port != null:
			port.link_changed.connect(_light_ir)


func on_power_on() -> void:
	super()
	_light_led(true)


func on_power_off() -> void:
	super()
	_light_led(false)


func _light_led(on: bool) -> void:
	if _led == null:
		return
	if not on:
		_led.set_surface_override_material(0, _led_off_material)
		return
	if _led_material == null:
		_led_material = StandardMaterial3D.new()
		_led_material.albedo_color = _LED_COLOR.darkened(0.6)
		_led_material.emission_enabled = true
		_led_material.emission = _LED_COLOR
		_led_material.emission_energy_multiplier = 2.0
	_led.set_surface_override_material(0, _led_material)


## Lit by the window's IrPort when its pair comes up on the bus, and put out
## when it goes: switching either machine off does that, as does looking away.
func _light_ir(on: bool) -> void:
	if not is_instance_valid(_ir_window):
		return
	if not on:
		_ir_window.set_surface_override_material(0, _ir_off_material)
		return
	if _ir_material == null:
		_ir_material = StandardMaterial3D.new()
		_ir_material.albedo_color = _IR_COLOR.darkened(0.92)
		_ir_material.roughness = 0.25
		_ir_material.emission_enabled = true
		_ir_material.emission = _IR_COLOR
		_ir_material.emission_energy_multiplier = _IR_GLOW
	_ir_window.set_surface_override_material(0, _ir_material)


## The video-out lead plugs in at the headphone jack, out of the bottom edge. The
## handheld default finds no room beside the cartridge on a body this narrow and
## moves to the right flank, which on this shell is where the power switch slides.
func configure_cable_attach(attach_point: Node3D) -> void:
	super(attach_point)
	attach_point.position = Vector3(body_size.x * _AV_JACK_X_FRACTION, 0.0,
		body_size.z * 0.5 + 0.002)
	aim_cable_exit(attach_point, Vector3(0, 0, 1))
