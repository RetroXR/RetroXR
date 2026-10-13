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

var _led: MeshInstance3D = null
var _led_off_material: Material = null
var _led_material: StandardMaterial3D = null


func _on_shell_ready() -> void:
	_led = find_child("PowerLED", true, false) as MeshInstance3D
	if _led != null:
		_led_off_material = _led.get_surface_override_material(0)


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


## The video-out lead plugs in at the headphone jack, out of the bottom edge. The
## handheld default finds no room beside the cartridge on a body this narrow and
## moves to the right flank, which on this shell is where the power switch slides.
func configure_cable_attach(attach_point: Node3D) -> void:
	super(attach_point)
	attach_point.position = Vector3(body_size.x * _AV_JACK_X_FRACTION, 0.0,
		body_size.z * 0.5 + 0.002)
	aim_cable_exit(attach_point, Vector3(0, 0, 1))
