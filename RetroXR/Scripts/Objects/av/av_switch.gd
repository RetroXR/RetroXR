## AvSwitch — the RETRO XR composite AV selector (RetroXR-models generic/av-switch): four composite inputs and one
## output, every jack on the back, one four-position slide on the front under four backlit labels.
##
## ── Routing ─────────────────────────────────────────────────────────────────
## A pass-through, as the 32X is (AvGraph "Several sockets through"): `av_through_map()` gives the OUT trio's three
## sockets to the SELECTED input's three, video for video, left for left, right for right. Every other device sees the
## switch spliced out of the wiring — a console on the selected input resolves the set on TO TV as its own sink, the
## set files that console on its input, and an amplifier on TO TV hears it — so nothing downstream has any code for a
## switch. The slide is MECHANICAL: it routes with or without power, as a real passive selector does.
##
## What the switch must do is tell everyone when to look again: a cord moved on one of its sockets (a lead on TO TV is
## not the console's lead, so the console is never told by it), or the slide moved. `_notify` tells every device cabled
## to it now and every one cabled last time, and another switch on either side forwards it; `_busy` stops two switches
## cabled into each other telling each other for ever, and AvGraph's `seen` sets stop the walk itself looping.
##
## ── The labels ──────────────────────────────────────────────────────────────
## A label lights while a LIVE source reaches its input (`source_live`: a machine switched on, a deck with a supply),
## through any chain of switches; the selected one is brightest. Nothing live there, or no supply on the switch's own DC
## IN with power simulation on, is dark. Sources do not say when they are switched on, so the states are looked at
## twice a second and the windows redrawn only when one CHANGES.
##
## ── Power ───────────────────────────────────────────────────────────────────
## A 5.5 x 2.1 mm DC IN on the model's `DcIn` (PowerProfiles "av_switch", the RETRO XR 9 V adapter). It lights the
## labels only; with power simulation off everything has a supply.
class_name AvSwitch
extends XRToolsPickable

const GROUP := "av_switch"
const INPUTS := 4
## The sockets' names, which are the model's mouths too (renamed `<name>Mouth` there). A save and a netplay seat event
## name a plug's socket by them: never renamed.
const CHANNELS := ["Video", "AudioL", "AudioR"]
const OUT_NAMES := ["VideoOut", "AudioLOut", "AudioROut"]
const DC_PORT := preload("res://Scenes/Objects/cables/barrel_dc_port.tscn")
const INLET_NAME := "PowerInlet"
const PROFILE := "av_switch"
## The windows' backlight: warm, as the concept draws it.
const LIT := Color(1.0, 0.78, 0.45)
const WINDOW_DARK := Color(0.11, 0.10, 0.08)
const DIM_ENERGY := 0.55
const BRIGHT_ENERGY := 2.4
## How often the labels look at their sources (s). Only a change redraws them.
const LABEL_POLL_S := 0.5

enum LabelState { DARK, LIT, SELECTED }
const LABEL_WORDS := ["dark", "lit", "selected"]

## The input the slide is on, 0-3. Follows the slide; set it with select().
var selected := 0

@onready var _model: ApplianceModel = $Model
@onready var _slide: VRSlider = $Selector

## [[video, left, right]] per input.
var _inputs: Array = []
var _outputs: Array[RcaPort] = []
var _mains: PowerInput = null
var _jack: DcPort = null
## Per input: the window material every level's label shares, and its state.
var _windows: Array[StandardMaterial3D] = []
var _states := PackedInt32Array([-1, -1, -1, -1])
var _tabs: Array[Node3D] = []
var _poll := 0.0
## The devices told last time, so one just cabled away still hears.
var _told: Array = []
## What the log last said about the wiring and the labels.
var _said := ""
var _said_labels := ""
## Whether the slide's last move came off the wire (a peer's), for the Debug tab.
var _last_from_wire := false

## Switches forwarding a change right now: two cabled into each other's inputs would otherwise tell each other for ever.
static var _busy := {}

@onready var _options_panel: AvSwitchOptionsPanel = get_node_or_null("AvSwitchOptionsPanel") as AvSwitchOptionsPanel


func _ready() -> void:
	super()
	add_to_group("spawned")
	add_to_group(GROUP)
	for i in INPUTS:
		var trio: Array[RcaPort] = []
		for ch: String in CHANNELS:
			trio.append(get_node("Input%d%s" % [i + 1, ch]) as RcaPort)
		_inputs.append(trio)
	for n: String in OUT_NAMES:
		_outputs.append(get_node(n) as RcaPort)
	_dress()
	_build_power()
	selected = _index_of(_slide.value)
	_slide.value_changed.connect(_on_slide)
	_refresh_labels(true)
	print("[AvSwitch] %s: ready, slide on input %d" % [name, selected + 1])


# ── dressing ─────────────────────────────────────────────────────────────────

func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[AvSwitch] %s: no model to dress the box from" % name)
		return
	# The mouths are named like the sockets; a recursive find on the switch must meet the socket, not the empty.
	var names: Array[String] = []
	for i in INPUTS:
		for ch: String in CHANNELS:
			names.append("Input%d%s" % [i + 1, ch])
	names.append_array(OUT_NAMES)
	names.append("DcIn")
	for n: String in names:
		for mouth in _model.parts(n):
			mouth.name = n + "Mouth"
	for n: String in names:
		var port := get_node_or_null(n) as Node3D
		if port != null:
			DeckFace.seat_port(_model, port, n + "Mouth")
	_dress_labels()
	_dress_slide()
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	# Body and laser box are what the model draws: the tab stands proud of them, and the windows are recessed.
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D], ["SlideTab"])
	print("[AvSwitch] %s: dressed from the model (%d levels)" % [name, _model.levels.size()])


## One material per input, put on its label's window surface (found by NAME: the exporter keeps no order) on every level.
func _dress_labels() -> void:
	for i in INPUTS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = WINDOW_DARK
		mat.roughness = 0.25
		mat.emission = LIT
		_windows.append(mat)
		var found := 0
		for part in _model.parts("Label%d" % (i + 1)):
			var mi := part as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m != null and m.resource_name == "AVS_LabelWindow":
					mi.set_surface_override_material(s, mat)
					found += 1
		if found == 0:
			push_warning("[AvSwitch] %s: the model has no window for input %d" % [name, i + 1])


## The slide on the model's tab: the close level's tab is the slider's knob, and every other level's follows it.
## Its box is the tab exactly, no margin, and it rides with the tab.
func _dress_slide() -> void:
	var tabs := _model.parts("SlideTab")
	if tabs.is_empty():
		push_warning("[AvSwitch] %s: the model has no SlideTab; the slide has nothing to move" % name)
		return
	_tabs = tabs
	var tab := tabs[0] as MeshInstance3D
	var keep := _slide.value
	var box: AABB = (global_transform.affine_inverse() * tab.global_transform) * tab.get_aabb()
	# value 0 is -travel/2 from the slider's origin, and the model draws the tab at position 1 (value 0).
	_slide.position = box.get_center() + Vector3.RIGHT * _slide.travel * 0.5
	_slide.set_value_no_signal(0.0)
	var shape := _slide.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		ApplianceModel.fit_box(shape, ApplianceModel.node_bounds(tab, _slide))
		_slide.set_knob_collision(shape)
	_slide.set_knob_mesh(tab)
	_slide.set_value_no_signal(keep)
	_follow_tab()


func _follow_tab() -> void:
	if _tabs.size() < 2 or not is_instance_valid(_tabs[0]):
		return
	for i in range(1, _tabs.size()):
		if is_instance_valid(_tabs[i]):
			_tabs[i].position = _tabs[0].position


# ── power ────────────────────────────────────────────────────────────────────

func _build_power() -> void:
	var profile := PowerProfiles.for_machine(PROFILE, "")
	_mains = PowerInput.on(self)
	_mains.label = "AV Selector (%s)" % name
	_jack = DC_PORT.instantiate() as DcPort
	_jack.name = INLET_NAME
	_jack.connector = PowerProfiles.plug_of(profile)
	add_child(_jack)
	var mouth := _model.part("DcInMouth") if _model != null else null
	if mouth != null:
		var t := _model.part_transform("DcInMouth", self)
		var inlet := _jack.get_node_or_null("Inlet") as MeshInstance3D
		var depth := (inlet.transform * inlet.get_aabb()).end.z if inlet != null and inlet.mesh != null else 0.0
		_jack.transform = Transform3D(t.basis, t.origin - t.basis.z * depth)
		for drawn: String in ["Inlet", "DcMouth", "DcPin"]:
			var part := _jack.get_node_or_null(drawn) as Node3D
			if part != null:
				part.visible = false
	else:
		push_warning("[AvSwitch] %s: no DcIn on the model; the DC jack stands at the switch's origin" % name)
	_mains.add_inlet(_jack)
	_mains.power_changed.connect(_on_power_changed)
	print("[AvSwitch] %s: DC IN %s (%s)" % [name, _jack.connector, "on the model's DcIn" if mouth else "unplaced"])


func power_input() -> PowerInput:
	return _mains


## Whether the switch's own supply is live (always, with power simulation off).
func powered() -> bool:
	return _mains == null or _mains.is_live()


func _on_power_changed(live: bool) -> void:
	print("[AvSwitch] %s: %s" % [name, "its supply came on: the labels light" if live
		else "its supply went: the labels are dark, the slide still routes"])
	_refresh_labels(true)


# ── the slide ────────────────────────────────────────────────────────────────

static func _index_of(v: float) -> int:
	return clampi(roundi(v * float(INPUTS - 1)), 0, INPUTS - 1)


static func _value_of(index: int) -> float:
	return float(clampi(index, 0, INPUTS - 1)) / float(INPUTS - 1)


## Put the slide on input `index` (0-3), as a hand would: it routes, tells everyone and is sent like any slide.
func select(index: int) -> void:
	_slide.set_value(_value_of(index))


func _on_slide(v: float) -> void:
	_follow_tab()
	var now := _index_of(v)
	_last_from_wire = NetworkManager.is_event_applying()
	if now == selected:
		return
	var was := selected
	selected = now
	print("[AvSwitch] %s: slide %d -> %d%s" % [name, was + 1, selected + 1,
		" (from a peer)" if _last_from_wire else ""])
	_notify("the slide moved")


# ── the pass-through contract (AvGraph) ──────────────────────────────────────

## {output socket: input socket} for the selected input, video for video, left for left, right for right.
func av_through_map() -> Dictionary:
	var out := {}
	if _inputs.size() <= selected or _outputs.size() < OUT_NAMES.size():
		return out
	var trio: Array = _inputs[selected]
	for k in OUT_NAMES.size():
		out[_outputs[k]] = trio[k]
	return out


## A cord moved on one of the switch's sockets (CompositeCable tells every device at both ends).
func on_av_topology_changed(_links: Array) -> void:
	_notify("a cord moved")


## Tell every device cabled to the switch, now and last time, to look again; another switch passes it on.
func _notify(why: String) -> void:
	if not is_inside_tree() or _busy.has(self):
		return
	_busy[self] = true
	var now: Array = []
	for link: Dictionary in AvGraph.own_links(self):
		for end: String in ["out", "in"]:
			var dev := (link[end] as RcaPort).get_device()
			if dev != null and dev != self and not now.has(dev):
				now.append(dev)
	var told: Array = []
	for dev: Variant in _told + now:
		if not is_instance_valid(dev) or told.has(dev):
			continue
		if not (dev as Object).has_method("on_av_topology_changed"):
			continue
		told.append(dev)
		(dev as Object).call("on_av_topology_changed", [])
	_told = now
	_busy.erase(self)
	var said := describe_wiring()
	if said != _said:
		_said = said
		print("[AvSwitch] %s (%s): %s" % [name, why, said])
	_refresh_labels(true)
	_refresh_panel()


# ── what reaches each input ──────────────────────────────────────────────────

## The output really feeding input `index`'s video socket (through any chain of switches), or its audio's if no video
## is cabled, or null.
func source_port(index: int) -> RcaPort:
	if index < 0 or index >= _inputs.size():
		return null
	for port: RcaPort in _inputs[index]:
		var feed := AvGraph.feeding_at(self, port)
		if feed != null:
			return AvGraph.source_of(feed)
	return null


## The machine on input `index`, or null.
func source_device(index: int) -> Node3D:
	var port := source_port(index)
	if port == null:
		return null
	var dev := port.get_device()
	# Followed all the way round a loop, the walk stops at a switch's own output: no machine.
	return null if dev is AvSwitch else dev


## Whether `dev` is sending: a machine switched on (or showing its attract), a deck or a set with its supply.
static func source_live(dev: Node) -> bool:
	if not is_instance_valid(dev):
		return false
	if dev is RetroSystem:
		return bool(dev.get("is_powered_on")) or bool(dev.get("attracting"))
	if dev.has_method("mains_live"):
		return bool(dev.call("mains_live"))
	var input := PowerInput.of(dev)
	return input == null or input.is_live()


func input_live(index: int) -> bool:
	return source_live(source_device(index))


func label_state(index: int) -> int:
	if not powered() or not input_live(index):
		return LabelState.DARK
	return LabelState.SELECTED if index == selected else LabelState.LIT


func _process(delta: float) -> void:
	_poll += delta
	if _poll < LABEL_POLL_S:
		return
	_poll = 0.0
	_refresh_labels(false)


## Redraw the windows whose state changed (all of them with `force`), and log a change.
func _refresh_labels(force: bool) -> void:
	var changed := false
	for i in mini(INPUTS, _windows.size()):
		var s := label_state(i)
		if s == _states[i] and not force:
			continue
		if s != _states[i]:
			changed = true
		_states[i] = s
		var mat := _windows[i]
		mat.emission_enabled = s != LabelState.DARK
		mat.albedo_color = WINDOW_DARK if s == LabelState.DARK else LIT
		mat.emission_energy_multiplier = BRIGHT_ENERGY if s == LabelState.SELECTED else DIM_ENERGY
	if changed:
		var words := PackedStringArray()
		for i in INPUTS:
			words.append("%d %s" % [i + 1, LABEL_WORDS[_states[i]]])
		var line := ", ".join(words)
		if line != _said_labels:
			_said_labels = line
			print("[AvSwitch] %s: labels %s%s" % [name, line, "" if powered() else " (no supply)"])
		_refresh_panel()


# ── words, for the log and the Debug tab ─────────────────────────────────────

static func _dev_words(dev: Node) -> String:
	if not is_instance_valid(dev):
		return "nothing"
	return "%s (%s)" % [dev.name, str(dev.get_path()) if dev.is_inside_tree() else "not in the room"]


## What TO TV is cabled to, as {device, port} rows.
func output_readers() -> Array:
	var out: Array = []
	for link: Dictionary in AvGraph.own_links(self):
		if _outputs.has(link["out"]):
			var port := link["in"] as RcaPort
			out.append({"device": port.get_device(), "port": port, "out": link["out"]})
	return out


## Whether this switch's output comes back into its own selected input (two switches cabled into each other's
## selected inputs). Walked socket by socket through every pass-through on the way, so a switch upstream standing
## on an EMPTY input (whose output then leads nowhere) is not mistaken for a loop.
func loop_refused() -> bool:
	if _inputs.is_empty():
		return false
	var seen := {}
	var feed := AvGraph.feeding_at(self, (_inputs[selected] as Array)[0] as RcaPort)
	while feed != null:
		var dev := feed.get_device()
		if dev == self:
			return true
		if not AvGraph.is_through(dev) or seen.has(dev):
			return false
		seen[dev] = true
		var map := AvGraph.through_map(dev)
		if not map.has(feed):
			return false
		feed = AvGraph.feeding_at(dev, map[feed] as RcaPort)
	return false


func describe_wiring() -> String:
	var ins := PackedStringArray()
	for i in INPUTS:
		var dev := source_device(i)
		ins.append("IN%d %s" % [i + 1, "-" if dev == null else String(dev.name)])
	var reads := PackedStringArray()
	for r: Dictionary in output_readers():
		var d: Node = r["device"]
		var n := String(d.name) if is_instance_valid(d) else "?"
		if not reads.has(n):
			reads.append(n)
	return "%s; selected %d; TO TV -> %s%s" % [", ".join(ins), selected + 1,
		"<none>" if reads.is_empty() else ", ".join(reads), "; LOOP refused" if loop_refused() else ""]


## The Debug tab's sections ([title, [[label, value], ...]]), as VCRPlayer.debug_state.
func debug_state() -> Array:
	var out: Array = []
	for i in INPUTS:
		var rows: Array = []
		for k in CHANNELS.size():
			var port: RcaPort = (_inputs[i] as Array)[k]
			var feed := AvGraph.feeding_at(self, port)
			rows.append(["%s jack" % ["Yellow (video)", "White (L)", "Red (R)"][k],
				"lead seated, from %s" % _dev_words(feed.get_device()) if feed != null
				else ("lead seated, far end loose" if port.seated_plug() != null else "empty")])
		var dev := source_device(i)
		rows.append(["Source", _dev_words(dev)])
		rows.append(["Sending", ("yes" if input_live(i) else "no (switched off)") if dev != null else "—"])
		rows.append(["Label", LABEL_WORDS[label_state(i)]])
		out.append(["Input %d" % (i + 1), rows])
	out.append(["Slide", [["Position", str(selected + 1)], ["Selected input", "INPUT %d" % (selected + 1)],
		["Value", "%.3f" % _slide.value]]])
	var reads: Array = []
	for r: Dictionary in output_readers():
		var d: Node = r["device"]
		reads.append(["%s ->" % (r["out"] as RcaPort).name, "%s, %s" % [_dev_words(d), (r["port"] as RcaPort).name]])
	if reads.is_empty():
		reads.append(["TO TV", "nothing cabled"])
	var final := AvGraph.source_of(_outputs[0]) if not _outputs.is_empty() else null
	var final_dev := final.get_device() if final != null else null
	reads.append(["Resolves to", "nothing" if final_dev == null or final_dev == self or final_dev is AvSwitch
		else _dev_words(final_dev)])
	out.append(["Output", reads])
	var plug := _jack.picked_up_object if _jack != null else null
	out.append(["Power", [
		["DC IN", "plug seated" if plug != null else "empty"],
		["Supply", "live" if powered() else "dead"],
		["Power simulation", "on" if AppPrefs.power_simulation else "off"],
		["Supply line", _mains.describe() if _mains != null else "—"]]])
	var fed_by := PackedStringArray()
	for i in INPUTS:
		for port: RcaPort in _inputs[i]:
			var feed := AvGraph.feeding_at(self, port)
			if feed != null and feed.get_device() is AvSwitch and not fed_by.has(String(feed.get_device().name)):
				fed_by.append(String(feed.get_device().name))
	var feeds := PackedStringArray()
	for r: Dictionary in output_readers():
		var d: Node = r["device"]
		if d is AvSwitch and not feeds.has(String(d.name)):
			feeds.append(String(d.name))
	out.append(["Chain", [
		["Fed by a switch", "none" if fed_by.is_empty() else ", ".join(fed_by)],
		["Feeds a switch", "none" if feeds.is_empty() else ", ".join(feeds)],
		["Loop", "REFUSED: the output comes back into this switch" if loop_refused() else "none"]]])
	var role := "not in a session"
	if NetworkManager.is_active():
		role = "host" if NetworkManager.is_host() else "client"
	out.append(["Netplay", [["Role", role],
		["Last slide move", "from the wire (a peer)" if _last_from_wire else "local"]]])
	return out


# ── the options panel ────────────────────────────────────────────────────────

func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		push_warning("[AvSwitch] %s: no options panel" % name)
		return
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


func _refresh_panel() -> void:
	if _options_panel != null and _options_panel.visible:
		_options_panel.refresh()
