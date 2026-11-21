## TvSignal — what the cable a picture arrives on does to it.
##
## A set draws every input through one CRT stage, but the signal reaching that stage
## is not the same on every input, and the differences are the reason S-Video and
## component existed at all:
##
##   * COMPOSITE puts luma and chroma down ONE wire. The set separates them with a
##     notch filter at the color subcarrier, which also takes the finest luma detail
##     with it (Sonic's waterfall dither blends into a see-through sheet), and the
##     chroma comes out with about a third of luma's bandwidth: colors bleed sideways.
##   * S-VIDEO (Y/C) carries luma and chroma on two wires. No notch: luma keeps all
##     its detail. The chroma is still the same modulated subcarrier, so it still
##     bleeds, a little less (no comb or notch on it).
##   * COMPONENT (Y/Pb/Pr) carries luma and the two color-difference signals on three
##     wires, each baseband. No notch, and the color is nearly as sharp as the luma.
##   * RGB (VGA, HDMI, an RGB SCART lead) is the picture the core drew.
##
## The player's "Composite blend" (crt_notch) and "Smear" (crt_smear) sliders say how
## bad THIS SET'S composite is; an input's kind scales them, so a set tuned to look
## like a cheap composite TV still shows a clean picture on its component input.
## RF is composite with the modulator's losses on top, so it is drawn as composite.
##
## And the wiring decides the COLOR on a component input (Chroma): Y is a VIDEO jack,
## so a yellow composite cord in it is a black-and-white picture, and so is a
## component lead with its blue and red plugs left out; Pb and Pr crossed swap the
## two color-difference signals.
class_name TvSignal
extends RefCounted

enum Kind { COMPOSITE, SVIDEO, COMPONENT, RGB }

## The int is the shader's crt_chroma (crt_chroma.gdshaderinc): append only.
enum Chroma { FULL, MONO, SWAPPED }

## What each kind keeps of the player's composite artifacts, by uniform name.
## Composite is 1 (the sliders ARE its setting); S-Video loses the notch and keeps
## most of the chroma bleed (same subcarrier, no separation filter smearing it more);
## component keeps a trace of bleed (Pb/Pr are half luma's bandwidth on a 480i set);
## RGB keeps neither.
const SCALE := {
	Kind.COMPOSITE: {"crt_notch": 1.0, "crt_smear": 1.0},
	Kind.SVIDEO: {"crt_notch": 0.0, "crt_smear": 0.6},
	Kind.COMPONENT: {"crt_notch": 0.0, "crt_smear": 0.15},
	Kind.RGB: {"crt_notch": 0.0, "crt_smear": 0.0},
}

const KIND_NAMES := ["composite", "S-Video", "component", "RGB"]


## The kind of signal an input (RetroTV.Source) delivers. TV (the retired tuner
## slot) and anything unknown are composite: that is what every input was drawn as
## before there was a choice.
static func kind_of(source: int) -> Kind:
	match source:
		RetroTV.Source.SVIDEO:
			return Kind.SVIDEO
		RetroTV.Source.COMPONENT:
			return Kind.COMPONENT
		# SCART too: the leads the game offers are RGB SCART leads.
		RetroTV.Source.VGA, RetroTV.Source.HDMI, RetroTV.Source.SCART:
			return Kind.RGB
	return Kind.COMPOSITE


## A uniform's value on an input of `kind`, from the set's own (composite) value.
## A uniform the table does not scale passes through unchanged.
static func scaled(kind: Kind, uniform: String, value: float) -> float:
	var row: Dictionary = SCALE.get(kind, {})
	return value * float(row.get(uniform, 1.0))


## The color a component input delivers, from what reaches its Pb and Pr jacks.
##
## `links` are AvGraph links ({out, in, cord}) into the set; `y`, `pb`, `pr` the
## input's three video jacks. Each jack carries what the far end of its cord SENDS
## (RcaPort.channel_for), and only from the device whose picture is on Y: a second
## console's Pb on the same input is not this picture's color.
##
##   nothing on Y          FULL (no picture to color: the set's own no-signal blue
##                         goes through the same shader and must stay blue)
##   both right            FULL
##   both crossed          SWAPPED
##   anything else         MONO (one missing, both the same, a cord carrying audio)
static func component_chroma(links: Array, y: RcaPort, pb: RcaPort, pr: RcaPort) -> Chroma:
	var host: Node3D = null
	for link: Dictionary in links:
		if link.get("in") == y and link.get("out") is RcaPort:
			host = (link.get("out") as RcaPort).get_device()
			break
	if host == null:
		return Chroma.FULL
	var into_pb := _sent_into(links, pb, host)
	var into_pr := _sent_into(links, pr, host)
	if into_pb == RcaPort.Channel.VIDEO_PB and into_pr == RcaPort.Channel.VIDEO_PR:
		return Chroma.FULL
	if into_pb == RcaPort.Channel.VIDEO_PR and into_pr == RcaPort.Channel.VIDEO_PB:
		return Chroma.SWAPPED
	return Chroma.MONO


## The channel a jack receives from `host`, or -1 for none.
static func _sent_into(links: Array, jack: RcaPort, host: Node3D) -> int:
	if jack == null:
		return -1
	for link: Dictionary in links:
		if link.get("in") != jack:
			continue
		var out := link.get("out") as RcaPort
		if out == null:
			continue
		if host != null and out.get_device() != host:
			continue
		return out.channel_for(int(link.get("cord", 0)))
	return -1
