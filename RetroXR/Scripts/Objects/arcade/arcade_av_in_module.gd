## ArcadeAvInModule — the cabinet's composite input, in the compartment beside the power supply.
##
## A block with three phono sockets (VIDEO yellow, L white, R red) on its top, facing up, so a hand
## leaning into the open compartment puts a plug straight in. It belongs to the CABINET, not to a bay
## unit: any unit can be in the mount, and the sockets stay where they are.
##
## The rule is the bay's: while the compartment holds a unit (clipped in or cabled, whatever is in it)
## the unit has the screen, and this block is there but takes no input -- cords may be plugged in and
## carry nothing. Only with the compartment EMPTY does a machine cabled here play on the cabinet.
## `is_enabled()` says which, and a LED on the block shows it.
##
## The sockets answer to the cabinet as their device (the A/V graph walks up to the RetroSystem), which is
## what lets a lead's plugs be saved and restored by "<cabinet>/<socket name>" like any console's; this
## module only reads which machine is feeding VIDEO IN (`source`) when told a cord moved.
class_name ArcadeAvInModule
extends ArcadeModule

var _source: Node3D = null
var _led: MeshInstance3D = null
var _led_on: StandardMaterial3D = null
var _led_off: StandardMaterial3D = null
var _shown_on := false


func _init() -> void:
	kind = ArcadeProfiles.KIND_AV_IN


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_led = find_child("InLed", true, false) as MeshInstance3D
	_led_on = StandardMaterial3D.new()
	_led_on.albedo_color = Color(0.1, 0.9, 0.2)
	_led_on.emission_enabled = true
	_led_on.emission = Color(0.1, 0.9, 0.2)
	_led_off = StandardMaterial3D.new()
	_led_off.albedo_color = Color(0.25, 0.04, 0.04)
	_shown_on = false
	_paint_led(is_enabled())


## Does the block take input? Only while the compartment holds nothing.
func is_enabled() -> bool:
	var sys := host()
	if sys == null or not sys.has_method("get_bay"):
		return true
	return sys.call("get_bay") == null


## The machine cabled to VIDEO IN, whether or not the block is enabled (a cord can be in and idle).
func source() -> Node3D:
	return _source if is_instance_valid(_source) else null


## The picture to show on the cabinet: the cabled machine's, only while enabled.
func external_picture() -> Texture2D:
	if not is_enabled():
		return null
	var src := source()
	if src == null:
		return null
	return src.call("get_video_texture") as Texture2D


## A cord was seated or pulled on one of the cabinet's sockets: find who feeds VIDEO IN.
func refresh() -> void:
	_source = null
	var sys := host() as Node3D
	if sys == null:
		return
	for link: Dictionary in AvGraph.links_for(sys):
		var inp := link.get("in") as RcaPort
		if inp == null or inp.channel != RcaPort.Channel.VIDEO or not is_ancestor_of(inp):
			continue
		var out := link.get("out") as RcaPort
		var dev: Node3D = out.get_device() if out != null else null
		if dev != null and dev != sys and dev.has_method("get_video_texture"):
			_source = dev
			break


func tick(_delta: float) -> void:
	var on := is_enabled()
	if on != _shown_on:
		_paint_led(on)


func _paint_led(on: bool) -> void:
	_shown_on = on
	if _led != null:
		_led.material_override = _led_on if on else _led_off
