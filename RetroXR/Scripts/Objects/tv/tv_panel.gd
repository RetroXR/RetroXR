## TvPanel — the set's back panel: its sockets, their legends, and which device is
## arriving on which input.
##
## A child of the RetroTV it serves, created unconditionally in _init, in the same
## shape as TvResize, TvFit, TvOsd and TvAudio.
##
## The INPUTS are built here, from the set's declared layout (build_inputs, 2026-11-21):
## the stock body's TvInputKinds.stock_layout() or its cabinet's input_layout(). Only
## what is declared exists; there is no fixed bank of sockets hidden per cabinet.
##
## Three arrays, all indexed by input id (TvInputKinds: the old RetroTV.Source values
## for each kind's first instance), because _input_for_device returns one and
## everything downstream indexes with it. Sized to the largest declared id, never
## smaller than the legacy range, and empty / null where a set has no such input:
##
##   _av_ports          the sockets themselves, [input][VIDEO, L, R, ...]
##   _snapped_plugs     the captive lead seated in each input's video socket
##   _connected_systems the host feeding each input
##
## The seven names a cabled device calls — accept_plug_restore, release_input,
## audio_ports, socket_holding, input_holding, on_av_source_found/lost and
## on_av_topology_changed — stay on RetroTV and forward here. rca_port.gd dispatches
## the last of those with has_method(), so the set has to answer it itself.
class_name TvPanel
extends Node

## The set this is the back of.
var _tv: RetroTV = null

## Centre-to-centre along the A/V row. The pitch the primitive console, the NES, the
## PC tower and both decks already use, so a lead reaches a set's sockets exactly as
## it reaches a deck's.
const AV_ROW_PITCH := 0.018

## The inputs built, id -> {kind, n, ports}; see build_inputs.
var _inputs: Dictionary = {}

## Centre-to-centre between one input group and the next. Wider than the printed
## legend plate, so the four plates stand clear of each other: they are coplanar by
## design, one standoff for all of them, so any overlap z-fights. A composite plate
## measures 63.1 mm, which at the old 60 mm pitch overlapped each neighbour by 3.1 mm;
## 68 leaves 4.9 mm of cabinet between them. av_tests `wiring/` measures the built
## plates rather than trusting a width — this comment said 57.6 mm while they were
## 63.1. tv.tscn authors the stock body's sockets at this pitch.
const AV_GROUP_PITCH := 0.068

## The A/V sockets, [input][VIDEO, L, R].
var _av_ports: Array = []

## The captive lead seated in each input's video socket, so a disconnect knows
## which host to tell.
var _snapped_plugs: Array = []

## The host feeding each input, or null. av_tests and the Tools/av probes read this
## directly to assert what the set thinks is cabled to it.
var _connected_systems: Array = []


## The host feeding each input (indexed by RetroTV.Source), null where none is.
## TvAudio fans its routing over it. The live array: read it, never write it —
## binding goes through the panel's own seat/unseat paths.
func connected_systems() -> Array:
	return _connected_systems

## Decks built into the cabinet, input -> deck (see TvDecks). Kept apart from
## _snapped_plugs because there is no plug: a built-in deck reaches its input with
## no lead at all, so neither the captive-lead lookup nor the cable graph finds it.
var _builtin: Dictionary = {}

## The six speaker outputs, in RcaPort.SPEAKER_OUT_CHANNELS order.
##
## An array of its own rather than another entry in _av_ports, which is indexed by
## RetroTV.Source over its whole range and walked by _input_for_device: a
## loudspeaker filed there would be read as a device arriving on an input.
var _speaker_outs: Array[RcaPort] = []

## Node names, in the same order. The scene authors them; a shell re-seats them.
const SPEAKER_OUT_NAMES := ["SpeakerOutL", "SpeakerOutR", "SpeakerOutC",
	"SpeakerOutLfe", "SpeakerOutSl", "SpeakerOutSr"]

## Where each speaker channel currently goes, keyed by RcaPort.Channel:
## `{"sink": Node3D, "speaker": int}`. A missing key is a channel with no cabinet on
## it, which folds rather than falling silent — see TvFit.surround_positions.
##
## Resolved when a plug moves and cached, never walked per frame.
var _speaker_dest: Dictionary = {}

## The headphone jack, built by seat_phones on a cabinet whose shell has one, or
## null. A 3.5 mm TRS socket, OUT.
var _phones: TrsPort = null
## What the jack's lead reaches — a pair of powered speakers — or null. While it is
## set the set's own speakers are cut off and its sound plays there instead, as
## plugging into a set's headphone jack does. Resolved when a plug moves.
var _phones_sink: Node3D = null

## Centre-to-centre up the back panel, from the input row to the speaker row.
##
## Up rather than down, and by more than a legend plate is tall: the stock body's floor
## is at -0.2 against an input row at -0.15, so there are 50 mm below and 350 mm above.
const SPEAKER_ROW_RISE := 0.06

## What the panel silk-screens under each speaker output, keyed by channel.
##
## Not RcaPort.CHANNEL_NAMES: those name a channel for the cord log and a suite pins
## them, while these have to fit an 18 mm socket pitch. A real 5.1 panel prints the
## same abbreviations for the same reason.
const SPEAKER_WORDS := {
	RcaPort.Channel.AUDIO_L: "FL",
	RcaPort.Channel.AUDIO_R: "FR",
	RcaPort.Channel.AUDIO_C: "C",
	RcaPort.Channel.AUDIO_LFE: "SUB",
	RcaPort.Channel.AUDIO_SL: "SL",
	RcaPort.Channel.AUDIO_SR: "SR",
}


func setup(tv: RetroTV) -> void:
	_tv = tv


## The speaker outputs, gathered from the scene's fixed names. Before the shell, which
## re-seats them (seat_speaker_row); they are the set's OUTPUTS and not declared.
func collect_outputs() -> void:
	_speaker_outs = []
	for out_name in SPEAKER_OUT_NAMES:
		var out := _tv.get_node_or_null(out_name) as RcaPort
		if out == null:
			push_warning("[RetroTV] missing speaker output %s" % out_name)
			continue
		_speaker_outs.append(out)


## Build the set's inputs from its layout (TvInputKinds' "Layouts"): one group of
## jacks per entry, named as they always were (TvInputKinds.node_name), posed off the
## entry's `at`, and filed under the input's id. Called once, after the shell is worn.
func build_inputs(layout: Array) -> void:
	_inputs = {}
	var counts := {}
	var top: int = RetroTV.Source.SCART
	for entry: Dictionary in layout:
		var kind := str(entry.get("kind", ""))
		if not TvInputKinds.has_kind(kind) or not entry.get("at") is Transform3D:
			push_warning("[RetroTV] %s: layout entry %s is not an input; skipped" % [_tv.name, entry])
			continue
		var n: int = int(counts.get(kind, 0)) + 1
		counts[kind] = n
		var id := TvInputKinds.id_for(kind, n)
		var step: Vector3 = entry.get("step", TvInputKinds.STEP)
		var poses: Array = entry.get("poses", [])
		_inputs[id] = {"kind": kind, "n": n, "ports": _build_group(kind, n, entry["at"], step, poses)}
		top = maxi(top, id)
	_av_ports = []
	_connected_systems = []
	_snapped_plugs = []
	for id in top + 1:
		_av_ports.append(_inputs[id]["ports"] if _inputs.has(id) else ([] as Array[RcaPort]))
		_connected_systems.append(null)
		_snapped_plugs.append(null)
	var names: PackedStringArray = []
	for id: int in input_ids():
		names.append(TvInputKinds.osd_name(id))
	print("[TV] %s: inputs %s" % [_tv.name, ", ".join(names) if not names.is_empty() else "<none>"])


## One input's jacks, in its kind's order (the picture, then L and R, then the rest).
func _build_group(kind: String, n: int, at: Transform3D, step: Vector3, poses: Array) -> Array[RcaPort]:
	var jacks: Array = TvInputKinds.KINDS[kind]["jacks"]
	var order: Array = TvInputKinds.KINDS[kind]["panel"]
	var out: Array[RcaPort] = []
	for j in jacks.size():
		var jack: Dictionary = jacks[j]
		var node_name := TvInputKinds.node_name(jack, n)
		var port := _tv.get_node_or_null(node_name) as RcaPort
		if port == null:
			var scene := load(str(jack["scene"])) as PackedScene
			if scene == null:
				push_warning("[RetroTV] %s: %s did not load; no %s" % [_tv.name, jack["scene"], node_name])
				continue
			port = scene.instantiate() as RcaPort
			port.name = node_name
			port.direction = RcaPort.Direction.IN
			port.channel = jack["channel"]
			if jack.has("tint"):
				port.jack_tint = jack["tint"]
			_tv.add_child(port)
		# A jack the entry poses itself (a model's own marker) stands exactly there.
		var slot := order.find(j)
		if slot < poses.size() and poses[slot] is Transform3D:
			port.transform = poses[slot]
		else:
			port.transform = TvInputKinds.jack_pose(kind, j, at, step)
		out.append(port)
	return out


## The ids of every input this set has, in SOURCE's order.
func input_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _inputs:
		out.append(id)
	out.sort()
	return out


## Whether this set has an input of that id.
func has_input(id: int) -> bool:
	return _inputs.has(id)


## How many composite inputs this cabinet actually carries sockets for.
func panel_inputs() -> int:
	var n := 0
	for id: int in _inputs:
		if _inputs[id]["kind"] == "composite":
			n += 1
	return n


## File a deck built into the cabinet on its input. TvDecks calls it before the
## deck announces itself, which is what lets source_found place it.
func attach_builtin(deck: Node3D, input: int) -> void:
	_builtin[input] = deck


## The deck built into one input, or null.
func builtin_deck(input: int) -> Node3D:
	var deck: Node3D = _builtin.get(input)
	return deck if is_instance_valid(deck) else null


## Whether this cabinet carries the aerial socket: whether its layout declares one.
func has_aerial() -> bool:
	return _inputs.has(RetroTV.Source.RF)


## The aerial on the far end of the coax socket, or null.
##
## Two ways to reach one, and both are one hop: an Antenna's own connector seated in
## the socket, or an RF switch's pigtail seated in it with an Antenna in the switch's
## ANT socket — which is what that socket is for, and how a console and broadcast
## television share one hole. Asked of the socket every time rather than remembered:
## it runs on a plug move and a key press, never per frame, and a remembered aerial
## is one more thing a binned lead can leave dangling.
func aerial() -> Antenna:
	if not has_aerial():
		return null
	var rf := _tv.rf_port() as RcaPort
	var plug: RcaPlug = (rf.seated_plug() as RcaPlug) if rf != null else null
	if plug == null or not is_instance_valid(plug.cable):
		return null
	if plug.cable is Antenna:
		return plug.cable as Antenna
	if plug.cable is RfSwitch:
		return (plug.cable as RfSwitch).aerial()
	return null


## Whether this cabinet carries the six speaker outputs.
##
## The stock body does — it is a flat box with 350 mm of clear back above the input
## row. A shell claims them the way it claims the DE-15, by saying so: a row of 5.1
## phono outputs on a wood-cabinet 70s set or a VGA monitor is the same anachronism
## as a coax tuner input on the latter.
## The marker is the switch, as VgaPortSeat is for the DE-15 — one fact rather than a
## boolean beside a seat that could disagree with it.
func has_speaker_outs() -> bool:
	if _speaker_outs.size() != SPEAKER_OUT_NAMES.size():
		return false
	return _tv.shell() == null or _tv.shell().speaker_out_seat() is Transform3D


## The speaker outputs, in RcaPort.SPEAKER_OUT_CHANNELS order. Empty when this
## cabinet has none, so a caller can ask rather than test the shell itself.
func speaker_outs() -> Array[RcaPort]:
	return _speaker_outs if has_speaker_outs() else ([] as Array[RcaPort])


## Turn off the speaker outputs on a cabinet with no SpeakerOutSeat: no socket, and
## nothing printed. (Inputs are built only where declared, so none is ever turned off.)
##
## `enabled` as well as `visible`: hiding a snap zone stops it drawing and nothing
## else, so an invisible socket left enabled goes on catching plugs out of the air.
func disable_absent_inputs() -> void:
	if not has_speaker_outs():
		for out: RcaPort in _speaker_outs:
			out.visible = false
			out.enabled = false


## The VIDEO socket of one input — the one that decides what is on the glass, and
## the one a captive lead goes into.
func video_port(input: int) -> RcaPort:
	if input < 0 or input >= _av_ports.size() or (_av_ports[input] as Array).is_empty():
		return null
	return _av_ports[input][0]


## Print the back-panel legends: one per declared input, in its kind's style, plus the
## speaker row's.
##
## A set is a sink, so every A/V one reads AV IN; what tells them apart is the title
## above the jacks. The plate is the cabinet's call — a moulded CRT back is curved,
## and a flat rectangle across it either floats off the curve or cuts in.
func print_legends() -> void:
	if _tv.shell() != null and not _tv.shell().print_legends:
		print("[TV] %s: the cabinet prints its own legends; none printed" % _tv.name)
		return
	var plate: bool = _tv.shell() == null or _tv.shell().av_legend_plate
	for id: int in input_ids():
		_print_legend(id, plate)
	if has_speaker_outs():
		_print_speaker_legend(plate)


## One input's legend. Names are the ones each always had ("AvLegend2", "AvLegendRf",
## "AvLegendHdmi"; a second of a kind gets its number), which a mod's shell hides by.
##
## RF is wordless: CoaxPort reports Channel.VIDEO because the routing needs somewhere to
## send the picture, and printing VIDEO under an aerial hole would name the wrong
## connector. The row the words would take still takes its space, so its plate comes
## out the height of a composite group's. HDMI and SCART print the same way; S-Video
## and component name each jack as a real panel does. A socket not on the phono 10 mm
## gets its plate's standoff from its own (TvInputKinds `proud`), and a group mixing
## the two stands at their mean (AvLegend._panel_frame), 0.5 mm proud either way.
func _print_legend(id: int, plate: bool) -> void:
	var input: Dictionary = _inputs[id]
	var kind: String = input["kind"]
	var n: int = input["n"]
	if kind == "vga":
		return          # the monitor's DE-15 has never printed one
	var legend := AvLegend.attach(_tv, _av_ports[id])
	if legend == null:
		return
	var suffix := "" if n <= 1 else str(n)
	legend.title = TvInputKinds.title(id)
	legend.show_plate = plate
	var jacks: Array = TvInputKinds.KINDS[kind]["jacks"]
	var depth := 0.0
	for jack: Dictionary in jacks:
		depth += float(jack.get("proud", TvInputKinds.RCA_PROUD)) - 0.0005
	legend.standoff = depth / float(jacks.size())
	match kind:
		"composite":
			legend.name = "AvLegend%d" % n
			legend.standoff = AvLegend.PANEL_STANDOFF
		"rf":
			legend.name = "AvLegendRf" + suffix
			legend.heading_override = "RF IN"
			legend.show_words = false
			legend.standoff = AvLegend.PANEL_STANDOFF
		"hdmi":
			legend.name = "AvLegendHdmi" + suffix
			legend.heading_override = "HDMI IN"
			legend.show_words = false
		"scart":
			legend.name = "AvLegendScart" + suffix
			legend.heading_override = "AV IN (RGB)"
			legend.show_words = false
			# The bezel, 58 x 24 mm (generic/scart-socket), not a phono jack's round.
			legend.jack_extent = Vector2(0.029, 0.012)
		"component":
			legend.name = "AvLegendComponent" + suffix
			legend.word_override = {
				RcaPort.Channel.VIDEO: "Y", RcaPort.Channel.VIDEO_PB: "Pb",
				RcaPort.Channel.VIDEO_PR: "Pr", RcaPort.Channel.AUDIO_L: "L",
				RcaPort.Channel.AUDIO_R: "R",
			}
		"svideo":
			legend.name = "AvLegendSvideo" + suffix
			legend.word_override = {
				RcaPort.Channel.VIDEO: "S-VIDEO", RcaPort.Channel.AUDIO_L: "L",
				RcaPort.Channel.AUDIO_R: "R",
			}
	legend.rebuild()


## Re-resolve which cabinet is on each speaker output. Called when any plug in the
## room moves, so it must be cheap and must not assume the move was ours.
##
## Resolved from the set's OWN sockets rather than from the lead that reported, for
## the reason AvSource.resolve states: a cable reports only its own cords, so with
## six leads on one panel whichever moved last would cancel the other five.
##
## Asking the set resolves its OUTPUTS only. A link where the television's socket is
## the IN end belongs to the console driving it, and resolve() skips it.
func on_av_topology_changed() -> void:
	_phones_sink = _resolve_phones()
	if not has_speaker_outs():
		_speaker_dest = {}
		return
	var dest := AvSource.resolve(_tv, true).audio_dest
	# The jack's lead resolves as a stereo cord onto the AUDIO_L and AUDIO_R keys,
	# which are FL and FR's, and may have written over the speaker row's own. It is
	# not a speaker output, so it is taken back out; while it is cabled the set plays
	# through the jack and reads none of this (RetroTV.get_speaker_positions).
	for ch: Variant in dest.keys():
		var entry: Dictionary = dest[ch]
		if _phones_sink != null and entry.get("sink") == _phones_sink:
			dest.erase(ch)
	_speaker_dest = dest


## Whatever the headphone jack's lead reaches that can say where its speakers are.
func _resolve_phones() -> Node3D:
	if not is_instance_valid(_phones):
		return null
	for link in AvGraph.links_for(_tv):
		if link["out"] != _phones:
			continue
		var target: Node3D = (link["in"] as RcaPort).get_device()
		if target != null and target != _tv and target.has_method("get_speaker_positions"):
			return target
	return null


## The sink carrying this set's sound through its headphone jack, or null.
func phones_sink() -> Node3D:
	return _phones_sink if is_instance_valid(_phones_sink) else null


## The headphone jack, or null on a cabinet without one.
func phones() -> TrsPort:
	return _phones


## Build the headphone jack where the shell's PhonesSeat says, or nothing at all
## where the shell has none — the same switch the speaker row's marker is.
func seat_phones(at: Variant) -> void:
	if not at is Transform3D or is_instance_valid(_phones):
		return
	var scene: PackedScene = load("res://Scenes/Objects/cables/trs_port.tscn")
	if scene == null:
		push_warning("[RetroTV] trs_port.tscn did not load; no headphone jack built")
		return
	_phones = scene.instantiate() as TrsPort
	_phones.name = "PhonesOut"
	_phones.direction = RcaPort.Direction.OUT
	_tv.add_child(_phones)
	TvFit.seat(_phones, at)


## Where each speaker channel goes, keyed by RcaPort.Channel. See _speaker_dest.
func speaker_destinations() -> Dictionary:
	return _speaker_dest


## The speaker row's legend. One plate over all six, not six plates: the channel a
## socket carries is the only thing that distinguishes them, and that is what the
## words under the jacks say.
##
## No `title` — SPEAKERS above and the channels below is the whole of it, and a title
## row would only repeat the heading. No divider either: the row stands alone on the
## panel rather than beside a bank.
func _print_speaker_legend(plate: bool) -> void:
	var legend := AvLegend.attach(_tv, _speaker_outs)
	if legend == null:
		return
	legend.name = "AvLegendSpeakers"
	legend.heading_override = "SPEAKERS"
	legend.word_override = SPEAKER_WORDS
	legend.show_plate = plate
	legend.rebuild()


## Seat the six speaker outputs off the shell's SpeakerOutSeat.
##
## That marker names the FIRST socket, FRONT L, and the other five step off it by the
## shell's own av_socket_step — the same contract PortSeat has, so a cabinet that
## stands its printing on end carries this row the same way round as its inputs.
##
## Absent leaves them where tv.tscn authored them, which with the stock body hidden
## would be six live sockets floating beside the cabinet — so it is also the switch
## has_speaker_outs reads, and disable_absent_inputs turns them off straight after.
func seat_speaker_row(at: Variant) -> void:
	if not at is Transform3D or _speaker_outs.size() != SPEAKER_OUT_NAMES.size():
		return
	var base: Transform3D = at
	var step := Vector3(-AV_ROW_PITCH, 0.0, 0.0)
	if _tv.shell() != null:
		step = _tv.shell().av_socket_step
	for i in _speaker_outs.size():
		TvFit.seat(_speaker_outs[i], Transform3D(base.basis, base * (step * float(i))))


## Snaps a captive cable plug into one of this TV's video sockets (used by save/load
## and netplay to restore connections). Defaults to Composite 1, which is where a
## caller that has no opinion — and every save written before there were four — means.
func accept_plug_restore(plug: CablePlug, input: int) -> void:
	var port := video_port(input)
	if port == null:
		port = _tv.composite_port() as RcaPort
	print("[RetroTV] accept_plug_restore: plug=%s port=%s" % [plug, port])
	port.pick_up_object(plug)
	print("[RetroTV] accept_plug_restore: done, port.picked_up=%s" % port.picked_up_object)


## Drop whatever captive lead is in one input's video socket. Used by netplay when
## another player unplugs one; the input defaults to Composite 1 for an event from a
## peer that predates there being four.
func release_input(input: int) -> void:
	var port := video_port(input)
	if port != null:
		port.drop_object()


## The L and R sockets of one composite input, in that order — the pair a captive
## lead's audio cords go into beside its picture cord. Empty for an input this
## cabinet has no sockets for, and for the tuner, which has no audio of its own.
func audio_ports(input: int) -> Array:
	if input < 0 or input >= _av_ports.size():
		return []
	var trio: Array = _av_ports[input]
	# L and R only: a component input's Pb and Pr come after them (collect).
	return trio.slice(1, 3) if trio.size() > 1 else []


## Which socket ANYWHERE on this set is holding `plug` — audio as well as video.
## port_holding answers the narrower question of which INPUT a lead is feeding, and
## an audio cord is never the answer to that one.
func socket_holding(plug: Node3D) -> XRToolsSnapZone:
	for group: Array in _av_ports:
		for port: RcaPort in group:
			if port.picked_up_object == plug:
				return port
	for out: RcaPort in _speaker_outs:
		if out.picked_up_object == plug:
			return out
	return null


## Which video socket is holding `plug`, or null. Lets a host that seated a captive
## lead find its way back to the right socket without knowing the numbering.
func port_holding(plug: Node3D) -> XRToolsSnapZone:
	var input := _input_holding_or(plug, -1)
	return video_port(input) if input >= 0 else null


## Which INPUT is holding `plug`, for a host writing itself to a save file. Anything it
## cannot find falls back to Composite 1, which is where a restore with no opinion puts
## a lead anyway.
func input_holding(plug: Node3D) -> int:
	return _input_holding_or(plug, RetroTV.Source.COMPOSITE_1)


func _input_holding_or(plug: Node3D, fallback: int) -> int:
	for id: int in input_ids():
		var port := video_port(id)
		if port != null and port.picked_up_object == plug:
			return id
	return fallback


## Called when a cable plug snaps into one of the video sockets. `input` is bound
## per socket at connect time, so the handler knows which one without asking.
func on_plug_snapped(plug: Node3D, input: int) -> void:
	# Hand the incoming host a clean screen so the C++ video handler doesn't
	# capture our CRT wrapper as the "original" material to restore later.
	_tv.display().drop_sampled()
	if plug is CablePlug:
		var plugged := plug as CablePlug
		_snapped_plugs[input] = plugged
		# Prevent the frozen kinematic plug from physically pushing the TV
		_tv.add_collision_exception_with(plugged)
		var system := plugged.get_system()
		if system:
			_connected_systems[input] = system
			# Multi-output systems need to know WHICH cable landed; other
			# hosts (VCR/DVD) keep the plain single-arg contract.
			if system is RetroSystem:
				(system as RetroSystem).on_tv_connected(_tv, plugged)
			elif system.has_method("on_tv_connected"):
				# Guarded: only a host with a captive lead implements this. The decks
				# dropped it when they moved to sockets and a spawned cable, and an
				# unguarded call errors on any plug that names one as its system.
				system.on_tv_connected(_tv)
			# A console plugged in while the set is showing something else must stay
			# off the glass until SOURCE selects it, or it repaints the screen from
			# under whatever is playing. Stated through the same pass SOURCE uses,
			# so the answer is given in BOTH directions: a host told only when it is
			# unselected has to guess when that stops being true, and one that
			# remembers the "no" — every host must, since it can arrive while the
			# machine is off — would never hear it lifted.
			# …and it must be silent too until SOURCE picks it, for the same reason.
			_tv.audio().apply_volume()
			# And decoding if the set is on SURROUND or feeding an amplifier. It was
			# only ever told when the key was pressed, so a console plugged into a set
			# already switched played stereo until someone pressed it again.
			_tv.audio().apply_audio_out()
			NetworkManager.report_event(NetEvents.Event.EV_TV_PLUG,
				{"owner": system, "tv": _tv, "ch": plugged.channel, "in": input})


## Called by a deck that has worked out it is feeding this set through a composite
## lead. Takes the place of on_plug_snapped's host lookup, which only works for a
## captive lead whose plug carries a back-reference to its owner; a composite
## cable's plugs belong to no device, so the deck tells the set instead.
func source_found(source: Node3D) -> void:
	var input := _input_for_device(source)
	if input < 0:
		return                  # nothing of ours is actually joined to it
	# Hand the incoming host a clean screen, exactly as the plug path does, so the
	# video handler doesn't capture our CRT wrapper as the material to restore.
	_tv.display().drop_sampled()
	_connected_systems[input] = source
	# Only if its sound is ours: a console with its picture here and its sound in an
	# amplifier is the amplifier's to set (TvAudio.carries_sound).
	# Through the contract like every other push, so a source without the method (a
	# mod's video-only box) is logged once rather than erroring on every plug.
	if _tv.audio().carries_sound(source):
		AvSourceContract.push_volume(source, _tv.audio().volume_for(input))
	_tv.audio().apply_channel_mode()
	_tv.audio().apply_audio_out()
	# Same rule as the captive-lead path, and stated the same way: a deck cabled up
	# to an input nobody is watching waits its turn rather than painting over the one
	# they are, and hears so when its turn comes.


## Called by that deck when the last cord between the two is pulled.
func source_lost(source: Node3D) -> void:
	var found := false
	for i in _connected_systems.size():
		if _connected_systems[i] == source:
			_connected_systems[i] = null
			found = true
	if not found:
		return                  # already replaced by something else
	_tv.display().drop_sampled()


## Which input a device's signal is arriving on, or -1 if none of ours reaches it.
##
## Worked out from the cable rather than passed in, because the caller does not know
## it: a deck announces itself through on_av_source_found having resolved only that
## this television is its sink, and CompositeCable._resolve tells the SOURCE end
## first — so the set is told before its own on_av_topology_changed runs, and reading
## the answer off a stored link list would be both a frame late and one ordering
## assumption deep.
##
## VIDEO wins over audio when a device reaches more than one input, because the
## picture is what the input is named for. But audio alone still counts: a deck with
## its sound in Composite 2 and its video cord out is on Composite 2, and used to be
## heard there — which is the whole reason the L/R sockets are separate.
func _input_for_device(dev: Node3D) -> int:
	if not is_instance_valid(dev):
		return -1
	# A deck built into the cabinet has no lead to find it by.
	for input: int in _builtin:
		if _builtin[input] == dev:
			return input
	# A captive lead names its own host and carries no CompositeCable at all, so it
	# is not in the graph. Over every input the set has sockets for, which includes
	# the aerial one: a console reached through an RF switch is found here exactly
	# as one on a composite lead is.
	for i in _av_ports.size():
		var captive: CablePlug = _snapped_plugs[i]
		if is_instance_valid(captive) and captive.get_system() == dev:
			return i

	# Everything else comes off the graph, which walks every cable the device is
	# on rather than every socket this set owns — the same answer from one walker
	# instead of a second copy of it here.
	var audio_match := -1
	for link: Dictionary in AvGraph.links_for(dev):
		if (link["out"] as RcaPort).get_device() != dev:
			continue
		var in_port := link["in"] as RcaPort
		var i := input_of_port(in_port)
		if i < 0:
			continue
		if in_port.channel == RcaPort.Channel.VIDEO:
			return i
		if audio_match < 0:
			audio_match = i
	return audio_match


## The input a socket feeds on this set, or -1. One of an input's own jacks gives that
## input; a jack on an adapter seated in one of them (a SCART block's phonos, which
## answer host_socket) gives the input of the socket the adapter is in.
func input_of_port(port: RcaPort) -> int:
	for depth in 3:          # a block in a block is nothing real; bounded anyway
		if port == null:
			return -1
		for i in _av_ports.size():
			if (_av_ports[i] as Array).has(port):
				return i
		port = (port.call("host_socket") as RcaPort) if port.has_method("host_socket") else null
	return -1


## Called when a cable plug leaves one of the video sockets.
func on_plug_released(input: int) -> void:
	# Unwrap before the host tears down so it restores over its own material,
	# not our CRT wrapper.
	_tv.display().drop_sampled()
	var plugged: CablePlug = _snapped_plugs[input]
	if plugged:
		_tv.remove_collision_exception_with(plugged)
		var system := plugged.get_system()
		if system:
			if system is RetroSystem:
				(system as RetroSystem).on_tv_disconnected(plugged)
			elif system.has_method("on_tv_disconnected"):
				system.on_tv_disconnected()
		_connected_systems[input] = null
		_snapped_plugs[input] = null
		NetworkManager.report_event(NetEvents.Event.EV_TV_UNPLUG, {"tv": _tv, "in": input})


## Read off the host duck-typed, and a host that has no opinion counts as a match:
## the channel switch belongs to the CONSOLE (an NES wears one on its back panel),
## so a deck or a machine without one fed through an RF switch should simply appear
## rather than being invisibly wrong on both channels.
func rf_tuned() -> bool:
	# Read untyped: assigning a freed source to a typed Node3D is itself an error,
	# and a mod's device can be freed without telling the set.
	var entry: Variant = _connected_systems[RetroTV.Source.RF] \
		if _connected_systems.size() > RetroTV.Source.RF else null
	if not is_instance_valid(entry):
		return false
	var host := entry as Node3D
	if not host.has_method("get_rf_channel"):
		return true
	var ch := int(host.call("get_rf_channel"))
	# -1 is "this machine has no channel switch". A match, not a mismatch: otherwise
	# a deck fed through an RF switch would be invisible on BOTH channels.
	return ch < 0 or ch == _tv.rf_channel


## The host feeding one input, whether or not it is the selected one, or null. Read
## by the set's menu, which lists what is on every input.
func host_on(input: int) -> Node3D:
	if input < 0 or input >= _connected_systems.size():
		return null
	var system: Variant = _connected_systems[input]     # untyped: may be freed
	return system as Node3D if is_instance_valid(system) else null


## Every cord into one input that carries a different signal from the socket it is
## in, as "L in R" (the cord's signal, then the jack): a left lead in the right
## jack, a picture in an audio jack. Read by the set's menu, which is the only
## place that says so — the routing simply follows the wire, so a crossed pair is
## swapped speakers and a picture in an audio jack is no picture, with nothing to
## tell the player why.
##
## Off the graph rather than the plugs: a plug carries no channel (a cord is a
## wire), so what it carries is the OUTPUT at its far end. A console's captive lead
## seats one plug for the whole input and is never in here, which is right — it
## cannot be crossed.
func miswired(input: int) -> PackedStringArray:
	var out := PackedStringArray()
	if input < 0 or input >= _av_ports.size():
		return out
	for link: Dictionary in AvGraph.links_for(_tv):
		var in_port := link["in"] as RcaPort
		if input_of_port(in_port) != input:
			continue
		var from := link["out"] as RcaPort
		# Per CORD, as AvSource.resolve reads it: an AV Multi Out (a Super NES's,
		# an N64's, a Wii's) is one socket carrying all three, and its own
		# `channel` is VIDEO — read that and a lead wired right said "VIDEO in L,
		# VIDEO in R".
		var cord := int(link.get("cord", 0))
		var sent := from.channel_for(cord)
		var jack := in_port.channel_for(cord)
		if sent == jack:
			continue
		# A mono machine's one audio cord carries all its sound, which plays in
		# whichever audio jack it is in; that is not a crossed pair.
		if _is_audio(sent) and _is_audio(jack) and not _stereo_source(from.get_device()):
			continue
		out.append("%s in %s" % [channel_word(sent), channel_word(jack)])
	out.sort()
	return out


static func _is_audio(ch: int) -> bool:
	return ch == RcaPort.Channel.AUDIO_L or ch == RcaPort.Channel.AUDIO_R


## Whether a source sends left and right separately. A console says (its channel
## list); decks and everything else are stereo, as AvSource.resolve treats them.
static func _stereo_source(dev: Node3D) -> bool:
	if dev != null and dev.has_method("av_is_stereo"):
		return bool(dev.call("av_is_stereo"))
	return true


## A channel as the legend under a jack names it: VIDEO, L, R, C, SL …
static func channel_word(channel: int) -> String:
	var key: String = RcaPort.Channel.keys()[channel]
	return key.trim_prefix("AUDIO_")


## The host feeding the selected input, if there is one and it is still alive.
func selected_system() -> Node3D:
	var input := _tv.selected_input()
	if input < 0:
		return null
	# Untyped: a source freed without telling the set (a mod's device) is still in
	# the slot, and assigning it to a typed Node3D errors every frame.
	var system: Variant = _connected_systems[input]
	return system as Node3D if is_instance_valid(system) else null
