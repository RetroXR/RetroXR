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
const KINDS := {
	"composite": {"code": 0, "legacy": [0, 1, 2, 3], "osd": "COMPOSITE", "title": "Composite",
		"signal": TvSignal.Kind.COMPOSITE, "numbered": true,
		"jacks": [
			{"name": "CompositePort", "scene": RCA, "channel": RcaPort.Channel.VIDEO},
			{"name": "AudioLIn", "scene": RCA, "channel": RcaPort.Channel.AUDIO_L},
			{"name": "AudioRIn", "scene": RCA, "channel": RcaPort.Channel.AUDIO_R}],
		"panel": [0, 1, 2]},
	"rf": {"code": 1, "legacy": [5], "osd": "RF", "title": "Antenna",
		"signal": TvSignal.Kind.COMPOSITE, "numbered": false,
		"jacks": [{"name": "RfPort", "scene": "res://Scenes/Objects/cables/coax_port.tscn",
			"channel": RcaPort.Channel.VIDEO}],
		"panel": [0]},
	"vga": {"code": 2, "legacy": [6], "osd": "VGA", "title": "VGA",
		"signal": TvSignal.Kind.RGB, "numbered": false,
		"jacks": [{"name": "VgaPort", "scene": "res://Scenes/Objects/cables/vga_port.tscn",
			"channel": RcaPort.Channel.VIDEO}],
		"panel": [0]},
	"hdmi": {"code": 3, "legacy": [7], "osd": "HDMI", "title": "HDMI", "numbered": false,
		"signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "HdmiPort", "scene": "res://Scenes/Objects/cables/hdmi_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": 0.0008, "turn": true}],
		"panel": [0]},
	"svideo": {"code": 4, "legacy": [8], "osd": "S-VIDEO", "title": "S-Video", "numbered": false,
		"signal": TvSignal.Kind.SVIDEO,
		"jacks": [
			{"name": "SvideoIn", "scene": "res://Scenes/Objects/cables/svideo_port.tscn",
				"channel": RcaPort.Channel.VIDEO, "proud": 0.0024, "turn": true},
			{"name": "AudioLInS", "scene": RCA, "channel": RcaPort.Channel.AUDIO_L},
			{"name": "AudioRInS", "scene": RCA, "channel": RcaPort.Channel.AUDIO_R}],
		"panel": [0, 1, 2]},
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
		"panel": [0, 3, 4, 1, 2]},
	"scart": {"code": 6, "legacy": [10], "osd": "SCART", "title": "SCART", "numbered": false,
		"signal": TvSignal.Kind.RGB,
		"jacks": [{"name": "ScartIn", "scene": "res://Scenes/Objects/cables/scart_port.tscn",
			"channel": RcaPort.Channel.VIDEO, "proud": 0.0032, "turn": true}],
		"panel": [0]},
}

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
# A layout is an Array of {kind, at, step?, poses?}: one entry per input, `at` the pose
# of the group's first jack along the panel in the set's frame, `step` the pitch to the
# next (STEP if absent), and `poses`, optionally, every jack's own pose in panel order
# (a modeled cabinet with a marker per socket), which wins over at + step. SOURCE
# meets the inputs in id order.
# A kind's instances are numbered in the order the layout lists them.

const _RX := Basis(Vector3(1, 0, 0), PI)     # a phono jack's frame: authored upside down
const _RY := Basis(Vector3(0, 1, 0), PI)     # a keyed socket's: right way up, facing back


## The stock body's back panel: four composite inputs and the aerial along the bottom
## row, HDMI by the speaker outputs, component / S-Video / SCART along the top row.
static func stock_layout() -> Array:
	var out: Array = []
	for i in 4:
		out.append({"kind": "composite", "at": Transform3D(_RX, Vector3(0.15 - 0.068 * i, -0.15, -0.16002099))})
	out.append({"kind": "rf", "at": Transform3D(_RX, Vector3(-0.14, -0.15, -0.16002099))})
	out.append({"kind": "hdmi", "at": Transform3D(_RY, Vector3(-0.12, -0.09, -0.1508))})
	out.append({"kind": "component", "at": Transform3D(_RX, Vector3(0.15, -0.03, -0.16002099))})
	# 2.4 mm off the panel, not its collar's 1.2: the legend plate (0.5 mm proud) covered
	# its insert at 1.2 and it read as a black hole.
	out.append({"kind": "svideo", "at": Transform3D(_RY, Vector3(0.046, -0.03, -0.1524))})
	# On the top row, not the speaker row: its tall legend plate stood within 2 mm of
	# Composite 3 / 4 and S-Video there (av_tests keeps every two plates 2 mm apart).
	out.append({"kind": "scart", "at": Transform3D(_RY, Vector3(-0.06, -0.03, -0.1532))})
	return out


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
			["scart", shell.scart_seat()]]:
		if row[1] is Transform3D:
			out.append({"kind": row[0], "at": row[1], "step": sstep})
	return out
