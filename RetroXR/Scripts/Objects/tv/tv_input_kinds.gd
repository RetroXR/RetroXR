## TvInputKinds — what each kind of television input IS, as data: its jacks, their
## node names, how its legend prints, what its signal does to the picture, and the
## stable number it is known by on disk and on the wire.
##
## A set does not carry a fixed bank of sockets any more (2026-11-21). It DECLARES its
## inputs (TvInputs.STOCK for the stock body, RetroTVShell.input_layout() for a
## cabinet), and TvPanel builds exactly those, from this table. Adding a kind is a row
## here; giving a set two HDMI inputs is two entries in its layout.
##
## Ids. Every input is an int, because that is what saves ("source", "tv_inputs") and
## netplay (EV_TV_PLUG "in", the set's source) have always carried. The FIRST instances
## keep the RetroTV.Source values they had (Composite 1-4 = 0-3, RF 5, VGA 6, HDMI 7,
## S-Video 8, component 9, SCART 10; 4 is the retired tuner), and any further instance
## is 32 + 16 * code + n, so HDMI 2 is 81 on every peer and in every save.
##
## Node names. Instance 1 keeps the name the jack has always had ("CompositePort",
## "AudioLIn", "HdmiPort"); instance n > 1 appends n ("CompositePort2", "HdmiPort2").
## Saved leads, a console's captive plug and mods (xenu.panasonic re-seats its sockets
## by these names) all find a socket by its name.
class_name TvInputKinds
extends RefCounted

const RCA := "res://Scenes/Objects/cables/rca_port.tscn"

## How far a phono jack's zone stands off the panel (tv.tscn's 10 mm convention). A jack
## whose zone stands elsewhere says so with its `proud`, and a jack turned half round
## about its own Z (a socket keyed up, as HDMI and the mini-DINs are, where a phono
## jack is authored upside down) with `turn`: TvPanel lays the rest of a group out in
## the phono frame and converts.
const RCA_PROUD := 0.01002

## A layout's group of jacks steps along this by default, in the first jack's frame.
const STEP := Vector3(-0.018, 0.0, 0.0)

## The kinds. `jacks` are in the order the set's arrays keep them: the picture first
## (video_port reads [0]), then L and R where the kind has its own audio ([1], [2]),
## then anything else (component's Pb, Pr). `panel` is the order they stand in along
## the panel, by index into `jacks`.
##
## How its legend prints: `legend` is the node name after "AvLegend" (composite's are
## numbered "AvLegend1".. instead), `heading` replaces AV IN, `words` is false for a
## wordless plate (one connector: printing VIDEO under it would name the wrong thing) or
## a {channel: word} map, and `extent` is the socket's half width / height when it is
## not a phono jack's round (AvLegend.jack_extent). `legend: ""` prints none.
const KINDS := {
	"composite": {"code": 0, "legacy": [0, 1, 2, 3], "osd": "COMPOSITE", "title": "Composite",
		"signal": TvSignal.Kind.COMPOSITE, "numbered": true,
		"jacks": [
			{"name": "CompositePort", "scene": RCA, "channel": RcaPort.Channel.VIDEO},
			{"name": "AudioLIn", "scene": RCA, "channel": RcaPort.Channel.AUDIO_L},
			{"name": "AudioRIn", "scene": RCA, "channel": RcaPort.Channel.AUDIO_R}],
		"panel": [0, 1, 2], "legend": "%d"},
	"rf": {"code": 1, "legacy": [5], "osd": "RF", "title": "Antenna",
		"signal": TvSignal.Kind.COMPOSITE, "numbered": false,
		# The F-type, and two more ways into the same input a layout may ask for
		# ("with"): a Belling-Lee socket (a PAL set's) and the 300-ohm VHF screw
		# terminals (a US set's, beside its F-type).
		"jacks": [{"name": "RfPort", "scene": "res://Scenes/Objects/cables/coax_port.tscn",
				"channel": RcaPort.Channel.VIDEO},
			{"name": "RfIecIn", "scene": "res://Scenes/Objects/cables/iec_aerial_port.tscn",
				"channel": RcaPort.Channel.VIDEO, "option": "iec", "proud": IEC_PROUD},
			{"name": "RfTwinLeadIn", "scene": "res://Scenes/Objects/cables/twin_lead_port.tscn",
				"channel": RcaPort.Channel.VIDEO, "option": "twinlead", "proud": TWINLEAD_PROUD,
				"turn": true}],
		"panel": [0, 1, 2], "legend": "Rf", "heading": "RF IN", "words": false},
	"vga": {"code": 2, "legacy": [6], "osd": "VGA", "title": "VGA",
		"signal": TvSignal.Kind.RGB, "numbered": false,
		"jacks": [{"name": "VgaPort", "scene": "res://Scenes/Objects/cables/vga_port.tscn",
			"channel": RcaPort.Channel.VIDEO}],
		# The monitor's DE-15 has never printed one.
		"panel": [0], "legend": ""},
	"hdmi": {"code": 3, "legacy": [7], "osd": "HDMI", "title": "HDMI", "numbered": false,
		"signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "HdmiPort", "scene": "res://Scenes/Objects/cables/hdmi_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": 0.0008, "turn": true}],
		"panel": [0], "legend": "Hdmi", "heading": "HDMI IN", "words": false},
	"svideo": {"code": 4, "legacy": [8], "osd": "S-VIDEO", "title": "S-Video", "numbered": false,
		"signal": TvSignal.Kind.SVIDEO,
		"jacks": [
			{"name": "SvideoIn", "scene": "res://Scenes/Objects/cables/svideo_port.tscn",
				"channel": RcaPort.Channel.VIDEO, "proud": 0.0024, "turn": true},
			{"name": "AudioLInS", "scene": RCA, "channel": RcaPort.Channel.AUDIO_L},
			{"name": "AudioRInS", "scene": RCA, "channel": RcaPort.Channel.AUDIO_R}],
		"panel": [0, 1, 2], "legend": "Svideo",
		"words": {RcaPort.Channel.VIDEO: "S-VIDEO", RcaPort.Channel.AUDIO_L: "L",
			RcaPort.Channel.AUDIO_R: "R"}},
	"component": {"code": 5, "legacy": [9], "osd": "COMPONENT", "title": "Component", "numbered": false,
		"signal": TvSignal.Kind.COMPONENT,
		"jacks": [
			{"name": "ComponentY", "scene": RCA, "channel": RcaPort.Channel.VIDEO,
				"tint": Color(0.16, 0.55, 0.24, 1.0)},
			{"name": "AudioLInC", "scene": RCA, "channel": RcaPort.Channel.AUDIO_L},
			{"name": "AudioRInC", "scene": RCA, "channel": RcaPort.Channel.AUDIO_R},
			{"name": "ComponentPb", "scene": RCA, "channel": RcaPort.Channel.VIDEO_PB},
			{"name": "ComponentPr", "scene": RCA, "channel": RcaPort.Channel.VIDEO_PR}],
		# Y Pb Pr L R along the panel, as a real one runs them.
		"panel": [0, 3, 4, 1, 2], "legend": "Component",
		"words": {RcaPort.Channel.VIDEO: "Y", RcaPort.Channel.VIDEO_PB: "Pb",
			RcaPort.Channel.VIDEO_PR: "Pr", RcaPort.Channel.AUDIO_L: "L", RcaPort.Channel.AUDIO_R: "R"}},
	"scart": {"code": 6, "legacy": [10], "osd": "SCART", "title": "SCART", "numbered": false,
		"signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "ScartIn", "scene": "res://Scenes/Objects/cables/scart_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": 0.0032, "turn": true}],
		# The bezel, 58 x 24 mm (generic/scart-socket), not a phono jack's round.
		"panel": [0], "legend": "Scart", "heading": "AV IN (RGB)", "words": false,
		"extent": Vector2(0.029, 0.012)},
	# DVI-D (2026-11-21): picture only, a computer's sound leaves on its own jacks.
	"dvi": {"code": 7, "legacy": [11], "osd": "DVI", "title": "DVI", "numbered": false,
		"signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "DviIn", "scene": "res://Scenes/Objects/cables/dvi_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": DVI_PROUD, "turn": true}],
		"panel": [0], "legend": "Dvi", "heading": "DVI IN", "words": false, "extent": DVI_EXTENT},
	# DisplayPort (2026-11-21): picture and sound on one plug, as HDMI.
	"displayport": {"code": 8, "legacy": [12], "osd": "DISPLAYPORT", "title": "DisplayPort",
		"numbered": false, "signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "DisplayPortIn", "scene": "res://Scenes/Objects/cables/displayport_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": DP_PROUD, "turn": true}],
		"panel": [0], "legend": "DisplayPort", "heading": "DP IN", "words": false, "extent": DP_EXTENT},
	# D-Terminal (2026-11-21): Japan's one-plug component, its sound on phonos beside it.
	"dterminal": {"code": 9, "legacy": [13], "osd": "D-TERMINAL", "title": "D-Terminal", "numbered": false,
		"signal": TvSignal.Kind.COMPONENT,
		"jacks": [
			{"name": "DTerminalIn", "scene": "res://Scenes/Objects/cables/dterminal_port.tscn",
				"channel": RcaPort.Channel.VIDEO, "proud": DTERM_PROUD, "turn": true},
			{"name": "AudioLInD", "scene": RCA, "channel": RcaPort.Channel.AUDIO_L},
			{"name": "AudioRInD", "scene": RCA, "channel": RcaPort.Channel.AUDIO_R}],
		"panel": [0, 1, 2], "legend": "DTerminal",
		"words": {RcaPort.Channel.VIDEO: "D", RcaPort.Channel.AUDIO_L: "L", RcaPort.Channel.AUDIO_R: "R"}},
	# JP-21 (2026-11-21): Japan's RGB, SCART's shell with its own pins, so its own connector.
	"jp21": {"code": 10, "legacy": [14], "osd": "RGB21", "title": "RGB21", "numbered": false,
		"signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "Jp21In", "scene": "res://Scenes/Objects/cables/jp21_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": 0.0032, "turn": true}],
		"panel": [0], "legend": "Jp21", "heading": "RGB IN", "words": false,
		"extent": Vector2(0.029, 0.012)},
}

## How far the D-Terminal, Belling-Lee and twin-lead sockets' mouths stand off the panel,
## from RetroXR-models generic/dterminal-socket, belling-lee-socket, twinlead-terminals.
## The Belling-Lee barrel stands 13.2 mm off its flange; the twin-lead zone is the point
## between the two screw seats, 1 mm in front of the 2 mm plate (twin_lead_port.tscn).
const DTERM_PROUD := 0.0025
const IEC_PROUD := 0.0132
const TWINLEAD_PROUD := 0.003

## How far the DVI and DisplayPort sockets' mouths stand off the panel, and their
## outer half width / height, from RetroXR-models generic/dvi-socket and
## generic/displayport-socket.
const DVI_PROUD := 0.0065
const DVI_EXTENT := Vector2(0.0197, 0.0063)
const DP_PROUD := 0.0025
const DP_EXTENT := Vector2(0.010, 0.0045)

## First id given to a kind's instance past its legacy ones.
const EXTRA_BASE := 32


static func has_kind(kind: String) -> bool:
	return KINDS.has(kind)


## The id of instance `n` (from 1) of `kind`, or -1 for an unknown kind.
static func id_for(kind: String, n: int) -> int:
	if not KINDS.has(kind) or n < 1:
		return -1
	var row: Dictionary = KINDS[kind]
	var legacy: Array = row["legacy"]
	if n <= legacy.size():
		return int(legacy[n - 1])
	return EXTRA_BASE + 16 * int(row["code"]) + n


## The kind and instance an id names, as {kind, n}, or {} for none (the retired tuner,
## anything out of range).
static func parse(id: int) -> Dictionary:
	for kind: String in KINDS:
		var row: Dictionary = KINDS[kind]
		var legacy: Array = row["legacy"]
		var at := legacy.find(id)
		if at >= 0:
			return {"kind": kind, "n": at + 1}
		var n := id - EXTRA_BASE - 16 * int(row["code"])
		if n > legacy.size() and n < 16:
			return {"kind": kind, "n": n}
	return {}


## The kind an id names, or "".
static func kind_of(id: int) -> String:
	return str(parse(id).get("kind", ""))


## A jack's node name for instance n.
static func node_name(jack: Dictionary, n: int) -> String:
	return str(jack["name"]) if n <= 1 else "%s%d" % [jack["name"], n]


## What the OSD shouts for an id: "COMPOSITE 2", "HDMI", "HDMI 2". A kind numbered from
## its first instance (composite) always carries its number; the rest only past 1.
static func osd_name(id: int) -> String:
	var p := parse(id)
	if p.is_empty():
		return "TV" if id == RetroTV.Source.TV else "INPUT %d" % id
	var row: Dictionary = KINDS[p["kind"]]
	var n: int = p["n"]
	return "%s %d" % [row["osd"], n] if bool(row["numbered"]) or n > 1 else str(row["osd"])


## What the back panel prints over an input's group: "Composite 2", "HDMI 1".
static func title(id: int) -> String:
	var p := parse(id)
	if p.is_empty():
		return ""
	var row: Dictionary = KINDS[p["kind"]]
	return "%s %d" % [row["title"], p["n"]] if str(p["kind"]) in ["composite", "hdmi"] \
		else str(row["title"]) if int(p["n"]) <= 1 else "%s %d" % [row["title"], p["n"]]


## What an input's signal does to the picture (TvSignal).
static func signal_of(id: int) -> TvSignal.Kind:
	var p := parse(id)
	if p.is_empty():
		return TvSignal.Kind.COMPOSITE
	return KINDS[p["kind"]]["signal"]


## Where jack `j` (an index into the kind's `jacks`) stands, given `at`, the pose of the
## group's FIRST jack along the panel as that jack itself is seated (what a shell's
## marker means), and `step`, the pitch between neighbours in a phono jack's frame.
static func jack_pose(kind: String, j: int, at: Transform3D, step: Vector3) -> Transform3D:
	var row: Dictionary = KINDS[kind]
	var jacks: Array = row["jacks"]
	var order: Array = row["panel"]
	var first: Dictionary = jacks[order[0]]
	var slot := order.find(j)
	var phono := at * _fix(first).affine_inverse()
	return phono * Transform3D(Basis(), step * float(slot)) * _fix(jacks[j])


## A jack's own pose against a phono jack's at the same spot.
static func _fix(jack: Dictionary) -> Transform3D:
	var basis := Basis(Vector3(0, 0, 1), PI) if bool(jack.get("turn", false)) else Basis()
	var proud: float = float(jack.get("proud", RCA_PROUD))
	# A phono jack's local +Z points out of the panel: standing less proud is -Z.
	return Transform3D(basis, Vector3(0.0, 0.0, proud - RCA_PROUD))


# ── Layouts ──────────────────────────────────────────────────────────────────
#
# A layout is an Array of {kind, at, step?, poses?, with?, extent?}: one entry per input,
# `with` the optional jacks of its kind to build too (the aerial's "iec", "twinlead"),
# `extent` its legend's socket half size where one jack is larger. `at` the pose
# of the group's first jack along the panel in the set's frame, `step` the pitch to the
# next (STEP if absent), and `poses`, optionally, every jack's own pose in panel order
# (a modeled cabinet with a marker per socket), which wins over at + step. SOURCE
# meets the inputs in id order.
# A kind's instances are numbered in the order the layout lists them.

const _RX := Basis(Vector3(1, 0, 0), PI)     # a phono jack's frame: authored upside down
const _RY := Basis(Vector3(0, 1, 0), PI)     # a keyed socket's: right way up, facing back


## The stock body's back panel (the Classic TV), laid out by what each input is. The
## body's back is 500 x 400 mm, x 0.25..-0.25 read left to right from behind it. Rows,
## bottom up, every legend plate at least 2 mm from the next (av_tests measures them):
##
##   y -0.150  Composite 1-4, then the aerial: F-type, Belling-Lee, VHF terminals
##   y -0.088  the better analog inputs: S-Video, component, D-Terminal
##   y -0.015  the 21-pin RGB inputs, SCART and RGB21 (tall plates), then the digital
##             ones: HDMI, DVI, DisplayPort
##   y  0.060  the speaker outputs (tv.tscn authors those; they are outputs)
##
## Composite 1-4 stay first and the aerial fifth: derived_layout reads them by index.
static func stock_layout() -> Array:
	var out: Array = []
	for i in 4:
		out.append({"kind": "composite", "at": _stock_at("composite", 0.15 - 0.068 * i, -0.15)})
	out.append({"kind": "rf", "with": _built_options("rf", ["iec", "twinlead"]), "extent": Vector2(0.0125, 0.0075),
		"at": _stock_at("rf", -0.14, -0.15),
		"poses": [_stock_at("rf", -0.14, -0.15),
			Transform3D(_RX, Vector3(-0.164, -0.15, -0.15 - IEC_PROUD)),
			Transform3D(_RY, Vector3(-0.193, -0.15, -0.15 - TWINLEAD_PROUD))]})
	out.append({"kind": "svideo", "at": _stock_at("svideo", 0.15, -0.088)})
	out.append({"kind": "component", "at": _stock_at("component", 0.07, -0.088)})
	if _built("dterminal"):
		out.append({"kind": "dterminal", "at": _stock_at("dterminal", -0.045, -0.088)})
	out.append({"kind": "scart", "at": _stock_at("scart", 0.12, -0.015)})
	out.append({"kind": "jp21", "at": _stock_at("jp21", 0.035, -0.015)})
	out.append({"kind": "hdmi", "at": _stock_at("hdmi", -0.04, -0.015)})
	out.append({"kind": "dvi", "at": _stock_at("dvi", -0.1, -0.015)})
	out.append({"kind": "displayport", "at": _stock_at("displayport", -0.165, -0.015)})
	return out


## Whether every jack scene of a kind is in this build. A socket whose model has not
## landed is left off the stock body rather than half built (and warned about by
## every set).
static func _built(kind: String) -> bool:
	for jack: Dictionary in KINDS[kind]["jacks"]:
		if not jack.has("option") and not ResourceLoader.exists(str(jack["scene"])):
			return false
	return true


## The options of a kind whose jack scenes are in this build.
static func _built_options(kind: String, options: Array) -> Array:
	var out: Array = []
	for jack: Dictionary in KINDS[kind]["jacks"]:
		if options.has(jack.get("option", "")) and ResourceLoader.exists(str(jack["scene"])):
			out.append(jack["option"])
	return out


## The pose of a kind's first jack at (x, y) on the stock body's back (its face at
## z -0.15): stood off it by the jack's own `proud`, and keyed right way up where the
## jack is `turn`ed (a phono jack is authored upside down, about X).
static func _stock_at(kind: String, x: float, y: float) -> Transform3D:
	var jack: Dictionary = KINDS[kind]["jacks"][KINDS[kind]["panel"][0]]
	var proud: float = float(jack.get("proud", RCA_PROUD))
	return Transform3D(_RY if bool(jack.get("turn", false)) else _RX, Vector3(x, y, -0.15 - proud))


## A cabinet's layout from the fields and markers every shell has always had, for one
## that declares none (RetroTVShell.input_layout): `av_inputs` composite groups off
## PortSeat (av_socket_step inside a group, av_group_step between), the aerial where
## `has_aerial` says (RfPortSeat, else the slot past the last composite group), and
## VGA / HDMI / S-Video / component / SCART only where the shell carries their seat.
## A shell with no PortSeat keeps the stock poses, as its sockets always did.
static func derived_layout(shell: RetroTVShell) -> Array:
	var out: Array = []
	var stock := stock_layout()
	var port: Variant = shell.port_seat()
	var sstep: Vector3 = shell.av_socket_step
	var gstep: Vector3 = shell.av_group_step
	for i in clampi(shell.av_inputs, 0, 4):
		var at: Transform3D = (stock[i] as Dictionary)["at"]
		if port is Transform3D:
			var base := port as Transform3D
			at = Transform3D(base.basis, base * (gstep * float(i)))
		out.append({"kind": "composite", "at": at, "step": sstep})
	if shell.has_aerial:
		var rf: Variant = shell.rf_port_seat()
		var at: Transform3D = (stock[4] as Dictionary)["at"]
		if rf is Transform3D:
			at = rf
		elif port is Transform3D:
			# The next group slot along, on its CENTRE (one socket step in), where a
			# group centres its printing; see the git history of TvPanel.seat_av_row.
			var base := port as Transform3D
			at = Transform3D(base.basis, base * (gstep * 4.0 + sstep))
		out.append({"kind": "rf", "at": at})
	for row: Array in [["vga", shell.vga_port_seat()], ["hdmi", shell.hdmi_port_seat()],
			["component", shell.component_seat()], ["svideo", shell.svideo_seat()],
			["scart", shell.scart_seat()], ["dvi", shell.dvi_seat()],
			["displayport", shell.displayport_seat()], ["dterminal", shell.dterminal_seat()],
			["jp21", shell.jp21_seat()]]:
		if row[1] is Transform3D:
			out.append({"kind": row[0], "at": row[1], "step": sstep})
	return out
