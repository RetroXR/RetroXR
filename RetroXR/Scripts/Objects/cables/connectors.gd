## Connectors — what a socket takes and what a plug is, by name.
##
## Every socket and every plug in the room carries a `connector`, and a plug goes
## into a socket when the two name the same one. That string is the whole of the
## agreement: a socket's snap zone requires it as a group, and a plug joins it.
## It is set on the NODE, in its scene, so a socket or a lead -- the game's or a
## mod's -- needs no script of its own just to say what it is.
##
## A connector names an INTERCHANGEABLE family, not a machine: plugs that both fit
## and work. Nintendo put one 12-pin shell on the Super NES, the N64, the GameCube
## and the Wii, and a lead off the first three works on all three, so they share
## "n64_av_plug"; the Wii moved the pins, so its lead is "wii_av_plug" and is
## refused where it would have given no picture. Mods follow the same rule and
## name a socket of their own "<systemid>_<socket>" in lower case (see
## docs/modding.md); one only their own mod should ever fit is namespaced
## "<mod id>:<name>".
##
## This file holds only what the game knows ABOUT connectors -- what to call
## them, and the few that also fit another's socket. It is not a list of the
## names allowed: any name is a connector.
class_name Connectors
extends RefCounted

## The phono plug, and what a socket or plug is when its scene names nothing.
const PHONO := "composite_plug"

## What to call the thing a player is holding, when telling them where it goes.
## A connector with no row here is "a plug", which is honest if unhelpful.
const LABELS := {
	"composite_plug": "a phono plug",
	"coax_plug": "an F-type coax plug",
	"trs_plug": "a 3.5 mm stereo plug",
	"vga_plug": "a VGA plug",
	"n64_av_plug": "a Nintendo Multi Out plug",
	"wii_av_plug": "a Wii AV Multi Out plug",
	"dc_av_plug": "a Dreamcast AV OUT plug",
	"genesis_av_plug": "a Sega A/V OUT plug",
	"ps2_av_multi": "a PlayStation 2 AV MULTI plug",
	"link_plug": "a Game Boy Advance link plug",
	"gg_link_plug": "a Gear-to-Gear cable plug",
	"ws_link_plug": "a WonderSwan communication cable plug",
	"comlynx_plug": "a ComLynx cable plug",
	"ngp_link_plug": "a Neo Geo Pocket link cable plug",
	"vb_link_plug": "a Virtual Boy link cable plug",
	"psx_link_plug": "a PlayStation link cable plug",
	"saturn_link_plug": "a Saturn link cable plug",
	"jag_link_plug": "a JagLink cable plug",
	"ilink_plug": "an i.LINK cable plug",
	"gc_link_plug": "a GameCube controller plug",
	"nema_5_15_plug": "a grounded US wall plug",
	"nema_1_15_plug": "a two-prong US wall plug",
	"nema_1_15_polarized_plug": "a polarized two-prong US wall plug",
	"iec_c13_plug": "an IEC C13 appliance connector",
	"iec_c7_plug": "an IEC C7 figure-eight connector",
	"iec_c7_polarized_plug": "a polarized IEC C7 connector",
}

## A plug that also goes into another connector's socket, as on the hardware. Said
## once, here, by the plug joining that socket's group too -- a snap zone filters
## on ONE group, and the seating gate, the held preview, the aim highlight and the
## missed-socket report all ask the same is_in_group.
##
## A NEMA 5-15R is a 1-15R with a ground hole added under it: the two blade slots
## sit in the same places, at the same widths, so both two-prong plugs drop
## straight into a modern outlet and simply leave the ground hole empty. That is
## how the lamp, the clock radio and every wall wart in the room are really
## powered. Stated one way round on purpose: a 5-15P's ground pin has nowhere to
## go in a two-slot outlet, so a grounded plug still has to find a grounded
## socket, and a C7 is not a mains blade at all.
const ALSO_FITS := {
	"nema_1_15_plug": ["nema_5_15_plug"],
	"nema_1_15_polarized_plug": ["nema_5_15_plug"],
}

## The characters a connector name is made of. Lower case, because a group is
## compared byte for byte and "PS2_av_multi" would fit nothing; the rest are what
## a mod id ("xenu.ps2") and its namespace separator need.
const NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_.:-"


static func label_of(connector: String) -> String:
	return str(LABELS.get(connector, "a plug"))


## Every group a plug of `connector` joins: its own, and any it also fits.
static func groups_of(connector: String) -> PackedStringArray:
	var out := PackedStringArray([connector])
	for other: Variant in ALSO_FITS.get(connector, []):
		out.append(str(other))
	return out


## "" when `connector` is spelled as a connector can be, else why not.
static func problem(connector: String) -> String:
	if connector.is_empty():
		return "the connector name is empty"
	for c: String in connector:
		if not NAME_CHARS.contains(c):
			return "'%s' is not a connector name: use lower-case letters, digits and _ . : -" % connector
	return ""
