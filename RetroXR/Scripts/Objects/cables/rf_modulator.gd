## Nintendo's RF Modulator (NUS-003): how a Nintendo 64 reached a set with only an
## aerial socket.
##
## A rigid black block, no cord at all: its MULTI OUT plug goes straight into the
## console's AV MULTI OUT, an RCA "RF OUT" jack sits on its far end, and a CH3-CH4
## slide beside that jack picks the channel it modulates onto. The RF switch's
## console lead (RfSwitch's PlugA0, a phono plug) goes into RF OUT and its coax
## pigtail into the set, exactly as an NES is hooked up.
##
## So it is a CompositeCable of ONE plug and no rope, the way LinkAdapter is:
##   * PlugA0 IS the whole block (connector "n64_av_plug"). There is no PlugB0 and
##     no VerletRope; CompositeCable tolerates both (_plug_at, the null rope), so
##     the block is one rigid, grabbable body, saved, binned and synced as a lead.
##   * Its RF OUT is an AdapterRcaPort (PlugA0/RfOut: OUT, VIDEO, rf_feed), which
##     answers get_device() with whatever the block is seated in. A lead from it is
##     then, to AvGraph and AvSource, a lead from the console's own RF OUT -- the
##     same path an NES's RfOut takes, with no new code in the routing.
##   * The channel is the BLOCK's, not the console's: the N64's model has no slide
##     and answers -1. RetroSystem.get_rf_channel asks channel_on(self) when its
##     model has no opinion, so a set on its aerial input reads this block's slide
##     through the console it is plugged into, the way it reads an NES's own.
##
## The stand-in scene (n64_rf_modulator.tscn) is laid out in the plug frame of the
## N64 AV lead's console plug; the transform from RetroXR-models' glTF frame is at
## the top of that scene, for a mod that dresses it.
class_name RfModulator
extends CompositeCable

## Every modulator in the room, for channel_on: usually none, at most a few.
const GROUP := &"rf_modulator"
## The slide's two detents, value 0 then value 1.
const CHANNELS: Array[int] = [3, 4]

@onready var _socket: AdapterRcaPort = get_node_or_null("PlugA0/RfOut") as AdapterRcaPort
@onready var _slider: VRSlider = get_node_or_null("PlugA0/ChannelSwitch") as VRSlider
@onready var _knob: MeshInstance3D = get_node_or_null("PlugA0/ChannelKnob") as MeshInstance3D

var _channel: int = CHANNELS[0]
## The machine the block was seated in at the last resolve. A cache for
## channel_on, which a set asks every frame it is on the aerial input; host()
## itself is always asked of the sockets.
var _seated_in: Node3D = null
## The lead plug RF OUT holds, kept clear of the block it is pushed into.
var _lead_body: PhysicsBody3D = null


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	if _slider != null:
		# Authored at the CH3 detent (value 0): set_knob_mesh anchors the knob where
		# it finds it at the CURRENT value.
		if _knob != null:
			_slider.set_knob_mesh(_knob)
		_slider.value_changed.connect(_on_channel_slid)
		_channel = CHANNELS[1] if _slider.value >= 0.5 else CHANNELS[0]
	if _socket != null:
		_socket.has_picked_up.connect(_on_lead_seated)
		_socket.has_dropped.connect(_on_lead_pulled)


## What the plug is seated in -- the machine RF OUT speaks for -- or null while
## the block hangs loose.
func host() -> Node3D:
	var plug := _plug_at(0, 0)
	var port: Port = plug.seated_port() if plug != null else null
	return port.get_device() if port != null else null


## The RF OUT socket, for a probe or a test.
func socket() -> AdapterRcaPort:
	return _socket


## The CH3-CH4 slide, for a probe, a test or a mod.
func channel_switch() -> VRSlider:
	return _slider


## Which channel the slide is on: 3 or 4.
func channel() -> int:
	return _channel


## Move the slide (the machine's menu, a test), so the knob, the set's re-read and
## the save all follow the one path a hand takes.
func set_channel(ch: int) -> void:
	if _slider != null and CHANNELS.has(ch):
		_slider.set_value(float(CHANNELS.find(ch)))


## Let a mod's knob ride the slide in place of the stand-in cap.
##
## `mesh` must already stand where its model puts the knob, which is the CH3
## detent (RetroXR-models' ChannelPivot), under PlugA0 or anything that moves with
## it. VRSlider.set_knob_mesh anchors a knob at the CURRENT value, so the slide is
## put to CH3 for the adoption and back afterwards, silently: the channel does not
## change.
func adopt_channel_knob(mesh: MeshInstance3D) -> void:
	if _slider == null or mesh == null:
		return
	var was := _slider.value
	_slider.set_value_no_signal(0.0)
	_slider.set_knob_mesh(mesh)
	_slider.set_value_no_signal(was)
	if _knob != null and _knob != mesh:
		_knob.hide()


## The channel the modulator seated in `machine` is on, or -1 when none is. Read
## by RetroSystem.get_rf_channel for a machine whose own model has no slide.
static func channel_on(machine: Node) -> int:
	var mod := on(machine)
	return mod.channel() if mod != null else -1


## The modulator seated in `machine`, or null.
static func on(machine: Node) -> RfModulator:
	if machine == null or not machine.is_inside_tree():
		return null
	for node: Node in machine.get_tree().get_nodes_in_group(GROUP):
		var mod := node as RfModulator
		if mod != null and is_instance_valid(mod._seated_in) and mod._seated_in == machine:
			return mod
	return null


func _on_channel_slid(value: float) -> void:
	var next: int = CHANNELS[1] if value >= 0.5 else CHANNELS[0]
	if next == _channel:
		return
	_channel = next
	print("[RfModulator] channel switch -> CH%d" % _channel)
	# The set has to re-read it: on the aerial input the picture only appears when
	# its own tuning matches, and nothing else would tell it this moved.
	var machine := host()
	if machine != null and machine.has_method("on_rf_channel_changed"):
		machine.call("on_rf_channel_changed")


## The block's own plug moving changes which machine the lead in RF OUT belongs
## to. That lead holds the routing (and its record of who it last told is how a
## machine left behind hears of it), so it is made to resolve again once this one
## has, as AvAdapter does for its socket.
func _resolve() -> void:
	super._resolve()
	_seated_in = host()
	if not is_instance_valid(_socket):
		return
	var lead_plug := _socket.seated_plug() as RcaPlug
	if lead_plug != null and is_instance_valid(lead_plug.cable) and lead_plug.cable != self:
		lead_plug.cable.on_plug_seating_changed()


## A seated phono plug's collider runs on into the jack, and so into the block: a
## frozen plug overlapping a loose block would shove it across the table.
func _on_lead_seated(what: Variant) -> void:
	var plug := _plug_at(0, 0)
	var body := what as PhysicsBody3D
	if plug == null or body == null:
		return
	_on_lead_pulled()
	plug.add_collision_exception_with(body)
	_lead_body = body


func _on_lead_pulled() -> void:
	var plug := _plug_at(0, 0)
	if plug != null and is_instance_valid(_lead_body):
		plug.remove_collision_exception_with(_lead_body)
	_lead_body = null
