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
	"link_plug": "a Game Boy Color link plug",
	"agb_link_plug": "a Game Boy Advance link plug",
	"dmg_link_plug": "an original Game Boy link plug",
	"gg_link_plug": "a Gear-to-Gear cable plug",
	"ws_link_plug": "a WonderSwan communication cable plug",
	"comlynx_plug": "a ComLynx cable plug",
	"ngp_link_plug": "a Neo Geo Pocket link cable plug",
	"vb_link_plug": "a Virtual Boy link cable plug",
	"psx_link_plug": "a PlayStation link cable plug",
	"saturn_link_plug": "a Saturn link cable plug",
	"jag_link_plug": "a JagLink cable plug",
	"ilink_plug": "an i.LINK cable plug",
	"gamecube_controller": "a GameCube controller plug",
	"playstation_controller": "a PlayStation controller plug",
	"de9_controller": "a DE-9 joystick plug",
	"wii_extension": "a Wii Remote extension plug",
	"usb_a": "a USB-A plug",
	"wii_sensorbar_plug": "a sensor bar plug",
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
##
## The Game Boy link connector is the same rule again. The Advance kept the
## Pocket and Color socket and added a key to its own lead's plug, so a Color's
## small plug goes into a Game Boy Advance (and plays in Game Boy mode) while the
## Advance's lead, its tab with nowhere to go, does not enter a Color, a Pocket
## or the Printer.
const ALSO_FITS := {
	"nema_1_15_plug": ["nema_5_15_plug"],
	"nema_1_15_polarized_plug": ["nema_5_15_plug"],
	"link_plug": ["agb_link_plug"],
}

## The controller port each console has, by systemid: what a pad's plug has to be
## to go in. A console not listed has a port of its own, "<systemid>_controller",
## and so does a pad that names its systemid and nothing else, so a NES pad fits a
## NES and nothing else. Physical fit, as on the hardware: a plug that cannot
## enter the socket does not belong however well its buttons would map, and one
## that can is not refused for having come in another box.
const CONTROLLER_PORTS := {
	# Sony kept the port from the PlayStation to the PlayStation 2: a DualShock 2
	# works in a PlayStation, and a PlayStation pad in a PlayStation 2.
	"psx": "playstation_controller",
	"ps2": "playstation_controller",
	# The Wii carries four GameCube ports under its flap.
	"gc": "gamecube_controller",
	"wii": "gamecube_controller",
	# Atari's DE-9 joystick port. Sega kept it on the Master System and the
	# Genesis, and a pad or stick from any of the three works in the others for
	# the buttons they share. Not the 7800: its two-button joysticks wire the same
	# shell differently, so it keeps a port of its own.
	"atari2600": "de9_controller",
	"mastersystem": "de9_controller",
	"genesis": "de9_controller",
}

## The connectors every room has a socket for, on the television, the wall and
## the monitor. A lead's end that is one of these says nothing about which
## console it is for, so the spawn card never offers a lead for one: the
## Composite Cable is the game's own answer to a phono jack.
const ROOM := ["composite_plug", "coax_plug", "trs_plug", "vga_plug", "nema_5_15_plug",
	"nema_1_15_plug", "nema_1_15_polarized_plug", "iec_c13_plug", "iec_c7_plug",
	"iec_c7_polarized_plug"]

## The leads the game ships for a console's own socket, offered on the card of a
## console that has one when no installed mod brings a lead for it. Game content,
## not a list of the sockets allowed. `spawn` is the lead's spawn token, `label`
## its row.
const GAME_LEADS := {
	# A plain lead for a socket of a console the game itself has no model of, so
	# a PlayStation 2 mod installed without its lead mod can still reach a set.
	"ps2_av_multi": {"spawn": "ps2_av_cable", "label": "Primitive AV Cable"},
	"n64_av_plug": {"spawn": "n64_av_cable", "label": "Stereo Composite Cable"},
	# A Saturn mod names the Genesis Model 2's socket too: the Saturn's 10-pin A/V
	# OUT is a round mini-DIN of the same look, and the game has no lead of its own
	# for that socket.
	"genesis_av_plug": {"spawn": "genesis_av_cable", "label": "A/V Cable"},
	"wii_av_plug": {"spawn": "wii_av_cable", "label": "AV Cable"},
	"dc_av_plug": {"spawn": "dc_av_cable", "label": "Stereo AV Cable"},
}

## A USB-A socket and plug, the standard's own: the PlayStation 2's two on its
## front take a GunCon 2.
const USB_A := "usb_a"

## The USB-A sockets each console has, by systemid. A plug in USB socket k is the
## device on the core's port k, which the core plugs into its own USB port k and
## keeps the pad on that port besides (RetroSystem._announce_port).
const USB_PORTS := {"ps2": 2}

## A Wii Remote's expansion port: the Nunchuk, the MotionPlus, and any extension
## a mod brings.
const WII_EXTENSION := "wii_extension"

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


## What a console's controller ports take, from its systemid; "" for none.
static func controller_port_of(systemid: String) -> String:
	if systemid.is_empty():
		return ""
	return str(CONTROLLER_PORTS.get(systemid, systemid + "_controller"))


## The connector `obj` presents to a socket: the `connector` it says it is, else
## what its `systemid` makes it (a pad's: see CONTROLLER_PORTS), else "". A
## controller port takes "" whatever it is, for the game's own generic props --
## the stand-in pad, the keyboard, the mouse, the multitap, the light gun -- which
## stand in for hardware nobody modelled and must work on every console.
static func of(obj: Object) -> String:
	if obj == null:
		return ""
	if "connector" in obj and not str(obj.get("connector")).is_empty():
		return str(obj.get("connector"))
	if "systemid" in obj:
		return controller_port_of(str(obj.get("systemid")))
	return ""


static func is_room(connector: String) -> bool:
	return ROOM.has(connector)


## The game's own lead for `connector` as {spawn, label}, or {} when it ships none.
static func game_lead(connector: String) -> Dictionary:
	return (GAME_LEADS.get(connector, {}) as Dictionary).duplicate()
