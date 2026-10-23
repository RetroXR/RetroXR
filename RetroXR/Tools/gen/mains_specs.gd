## Mains plugs and sockets of every MainsRegions region, as numbers: the one
## place their geometry is written down.
##
## gen_wall_outlet.gd bakes the plates from SOCKETS, gen_power_connectors.gd the
## plugs from PLUGS, and Tests/mains_region_tests.gd seats every plug in every
## socket with fits() and checks that what goes in physically is exactly what
## Connectors.ALSO_FITS says goes in -- so a table that claims a fit the pins
## cannot make, or a mesh that drifted from its table, fails a test.
##
## Units are millimetres. Everything is in the SOCKET'S frame as seen facing the
## wall: +X right, +Y up, the socket's origin where the seated plug's origin lands.
## A plug's pins are written where they sit once seated, so its mesh mirrors X
## (a seated plug is turned half round about Y: plug.tscn's SnapGrabPoint).
##
## Sources, short keys:
##   NEMA   en.wikipedia.org/wiki/NEMA_connector
##   JIS    JIS C 8303:2007 clause text (kikakurui.com/c8/C8303-2007-01.html)
##   PANA   www2.panasonic.biz/jp/terasu/skill/dictionary/outlet.html
##   CEE7   en.wikipedia.org/wiki/CEE_7, /Schuko, /Europlug; worldstandards.eu E/F/C
##   BS1363 en.wikipedia.org/wiki/BS_1363; worldstandards.eu G
##   AS3112 EESS test report form for AS/NZS 3112:2017 A1:2021 (Fig. 2.1 values)
##   GB1002 GB 1002 draft filed with the WTO (TBT CHN 24_02217), Figures 1-4
##   SEV    de.wikipedia.org/wiki/SN_441011, en.wikipedia.org/wiki/SEV_1011
##   CEI    it.wikipedia.org/wiki/Spina_elettrica; plugsocketmuseum.nl/Italian1
##   DK     en.wikipedia.org/wiki/DS_107-2-D1; plugsocketmuseum.nl/Danish1
##   60906  en.wikipedia.org/wiki/IEC_60906-1; plugsocketmuseum.nl/IEC60906-1
##   BS546  en.wikipedia.org/wiki/BS_546; IS 1293:2005 Annex A (law.resource.org)
##   SI32   worldstandards.eu H; plugsocketmuseum.nl/Israeli1
## EST marks a number no source gave: a clearance over the pin it must take, or a
## body read off the standard's minimum pin-to-edge distance.
class_name MainsSpecs
extends RefCounted

## A pin: "at" its centre, "shape" rect (size = x, y extents; "angle" turns it
## about Z, degrees anticlockwise) or round ("d"), "len" from the face, and an
## optional insulating "sleeve" length. "tip" moves a round pin's tip centre
## (the Europlug's converge); the fit is read at its base, since they flex.
## "body" is the face outline, a polygon; "face_holes" are where a socket's
## stud goes into the face (CEE 7/7's earth socket).
const PLUGS := {
	# NEMA: 12.7 centres, 6.35 x 1.5 blades, 7.9 polarized neutral (on the left
	# with the plug upright); 5-15 earth Ø4.75, 11.9 below the blade centres.
	# The blade line sits 4.2 above the origin in all three, where the 5-15R puts
	# its slots, so a two-prong plug seats in a grounded outlet's slots.
	"nema_5_15_plug": {
		"pins": [
			{"shape": "rect", "at": Vector2(-6.35, 4.2), "size": Vector2(1.5, 6.3), "len": 17.0},
			{"shape": "rect", "at": Vector2(6.35, 4.2), "size": Vector2(1.5, 6.3), "len": 17.0},
			{"shape": "round", "at": Vector2(0, -7.7), "d": 4.75, "len": 21.0},
		],
		"body": "rrect", "body_size": Vector2(35.3, 38.9), "body_at": Vector2(0, 0),
	},
	"nema_1_15_plug": {
		"pins": [
			{"shape": "rect", "at": Vector2(-6.35, 4.2), "size": Vector2(1.5, 6.35), "len": 16.0},
			{"shape": "rect", "at": Vector2(6.35, 4.2), "size": Vector2(1.5, 6.35), "len": 16.0},
		],
		"body": "rrect", "body_size": Vector2(28.0, 18.0), "body_at": Vector2(0, 4.2),
	},
	"nema_1_15_polarized_plug": {
		"pins": [
			{"shape": "rect", "at": Vector2(-6.35, 4.2), "size": Vector2(1.5, 7.9), "len": 16.0},
			{"shape": "rect", "at": Vector2(6.35, 4.2), "size": Vector2(1.5, 6.35), "len": 16.0},
		],
		"body": "rrect", "body_size": Vector2(28.0, 18.0), "body_at": Vector2(0, 4.2),
	},
	# CEE7: Ø4.8 x 19 pins on 19 centres; round body Ø36.7 (a retailer's 7/4);
	# the earth socket for the 7/5 pin, 10 above the pin line (EST Ø5.5).
	"cee_7_7_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.8, "len": 19.0},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.8, "len": 19.0},
		],
		"body": "circle", "body_size": Vector2(36.7, 36.7), "body_at": Vector2.ZERO,
		"face_holes": [{"at": Vector2(0, 10), "d": 5.5}],
	},
	# CEE7 Europlug: 19 long, Ø4.0 tips 9 long, Ø3.8 sleeves 10 long; 19 apart at
	# the base, 17.5 at the tip; face 35.3 x 13.7 with 45-degree ends.
	"cee_7_16_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "tip": Vector2(-8.75, 0), "d": 4.0,
				"len": 19.0, "sleeve": 10.0},
			{"shape": "round", "at": Vector2(9.5, 0), "tip": Vector2(8.75, 0), "d": 4.0,
				"len": 19.0, "sleeve": 10.0},
		],
		"body": "europlug", "body_size": Vector2(35.3, 13.7), "body_at": Vector2.ZERO,
	},
	# BS1363: L/N 6.4 x 4.0 x 17.7 on 22.2 centres, sleeves 9; earth 4.0 x 8.0 x
	# 22.3, 22.2 above them. Body EST: at least 9.5 from the L/N pins to its edge.
	"bs_1363_plug": {
		"pins": [
			{"shape": "rect", "at": Vector2(-11.1, 0), "size": Vector2(6.4, 4.0), "len": 17.7, "sleeve": 9.0},
			{"shape": "rect", "at": Vector2(11.1, 0), "size": Vector2(6.4, 4.0), "len": 17.7, "sleeve": 9.0},
			{"shape": "rect", "at": Vector2(0, 22.2), "size": Vector2(4.0, 8.0), "len": 22.3},
		],
		"body": "rrect", "body_size": Vector2(48.0, 54.0), "body_at": Vector2(0, 11.0),
		"cord_exit": "bottom",
	},
	# AS3112: 6.35 x 1.63 blades; L/N 17.06 long, 7.92 from the centre, 30 degrees
	# off vertical leaning in ("/ \"), sleeves 8.7; earth 19.94 long, 10.31 below.
	# Face EST inside the 21.9 projection limit.
	"as_3112_plug": {
		"pins": [
			{"shape": "rect", "at": Vector2(-6.86, 3.96), "size": Vector2(1.63, 6.35), "angle": -30.0,
				"len": 17.06, "sleeve": 8.7},
			{"shape": "rect", "at": Vector2(6.86, 3.96), "size": Vector2(1.63, 6.35), "angle": 30.0,
				"len": 17.06, "sleeve": 8.7},
			{"shape": "rect", "at": Vector2(0, -10.31), "size": Vector2(1.63, 6.35), "len": 19.94},
		],
		"body": "rrect", "body_size": Vector2(36.0, 38.0), "body_at": Vector2(0, -2.0),
	},
	"as_3112_2pin_plug": {
		"pins": [
			{"shape": "rect", "at": Vector2(-6.86, 3.96), "size": Vector2(1.63, 6.35), "angle": -30.0,
				"len": 17.06, "sleeve": 8.7},
			{"shape": "rect", "at": Vector2(6.86, 3.96), "size": Vector2(1.63, 6.35), "angle": 30.0,
				"len": 17.06, "sleeve": 8.7},
		],
		"body": "rrect", "body_size": Vector2(34.0, 24.0), "body_at": Vector2(0, 3.0),
	},
	# SEV T12: Ø4.0 x 19 pins, sleeves 8; L/N 19 apart, earth 5 below. Body 35.5 x
	# 18.5, its lower corners cut at 45 degrees toward the earth (outline 35-36 x 17-20).
	"sev_1011_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.0, "len": 19.0, "sleeve": 8.0},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.0, "len": 19.0, "sleeve": 8.0},
			{"shape": "round", "at": Vector2(0, -5), "d": 4.0, "len": 19.0},
		],
		"body": "swiss", "body_size": Vector2(35.5, 18.5), "body_at": Vector2(0, -1.0),
	},
	# CEI S11: Ø4.0 x 19 pins in one line, 9.5 apart. Body EST (sleeves EST 7).
	"cei_23_50_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.0, "len": 19.0, "sleeve": 7.0},
			{"shape": "round", "at": Vector2(0, 0), "d": 4.0, "len": 19.0},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.0, "len": 19.0, "sleeve": 7.0},
		],
		"body": "rrect", "body_size": Vector2(34.0, 15.0), "body_at": Vector2.ZERO,
	},
	# DK 2-1a: Ø4.8 x 19 L/N on 19 centres; the half-round earth, 6.5 across and 4
	# thick, 14 long, 13 below. Body EST.
	"ds_k_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.8, "len": 19.0},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.8, "len": 19.0},
			{"shape": "rect", "at": Vector2(0, -13), "size": Vector2(6.5, 4.0), "len": 14.0,
				"half_round": true},
		],
		"body": "rrect", "body_size": Vector2(36.0, 38.0), "body_at": Vector2(0, -4.0),
	},
	# 60906 (SANS 164-2): Ø4.5 x 19 pins, L/N 19 apart, earth 3 below their
	# midpoint; outline 35.5 wide, 17 high.
	"sans_164_2_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.5, "len": 19.0, "sleeve": 8.0},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.5, "len": 19.0, "sleeve": 8.0},
			{"shape": "round", "at": Vector2(0, -3), "d": 4.5, "len": 19.0},
		],
		"body": "iec60906", "body_size": Vector2(35.5, 17.0), "body_at": Vector2.ZERO,
	},
	# NBR 14136 10 A: the same layout with Ø4.0 pins 19.5 long, no sleeves;
	# measured outline 35.4 x 17.6.
	"nbr_14136_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.0, "len": 19.5},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.0, "len": 19.5},
			{"shape": "round", "at": Vector2(0, -3), "d": 4.0, "len": 19.5},
		],
		"body": "iec60906", "body_size": Vector2(35.4, 17.6), "body_at": Vector2.ZERO,
	},
	# BS546 15 A / IS 1293 16 A / SANS 164-1: Ø7.1 L/N 25.4 apart, 18.6 long; Ø8.7
	# earth 28.6 above them, 28.6 long. Body EST: 9.52 from the L/N pins to its edge.
	"bs_546_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-12.7, 0), "d": 7.1, "len": 18.6},
			{"shape": "round", "at": Vector2(12.7, 0), "d": 7.1, "len": 18.6},
			{"shape": "round", "at": Vector2(0, 28.6), "d": 8.7, "len": 28.6},
		],
		"body": "circle", "body_size": Vector2(58.0, 58.0), "body_at": Vector2(0, 11.0),
	},
	# IS 1293 6 A (Type D): Ø5.08 L/N 19.1 apart, 15.9 long; Ø7.06 earth 22.2 above,
	# 20.6 long. Body EST: 7.94 from the L/N pins to its edge.
	"is_1293_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.55, 0), "d": 5.08, "len": 15.9},
			{"shape": "round", "at": Vector2(9.55, 0), "d": 5.08, "len": 15.9},
			{"shape": "round", "at": Vector2(0, 22.2), "d": 7.06, "len": 20.6},
		],
		"body": "circle", "body_size": Vector2(46.0, 46.0), "body_at": Vector2(0, 8.0),
	},
	# SI32 round-pin: Ø4.5 x 19, L/N 19 apart, earth 9.5 below their midpoint.
	# Body EST.
	"si_32_plug": {
		"pins": [
			{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.5, "len": 19.0},
			{"shape": "round", "at": Vector2(9.5, 0), "d": 4.5, "len": 19.0},
			{"shape": "round", "at": Vector2(0, -9.5), "d": 4.5, "len": 19.0},
		],
		"body": "rrect", "body_size": Vector2(34.0, 30.0), "body_at": Vector2(0, -4.5),
	},
}

## A socket: its "holes" (each a list of round/rect parts; a pin must lie inside
## one hole, and one hole takes one pin), any "studs" standing out of it (CEE 7/5's
## earth pin, which a plug's face has to have a socket for), an optional "recess"
## (outline, as a plug body, and depth) the plug's face has to fit, and a
## "shutter" -- the hole whose pin opens the others (BS 1363).
const SOCKETS := {
	# NEMA 5-15R / 1-15R slots: EST from the same family's JIS/Panasonic figures
	# (7 hot, 9 neutral, 2.0 wide); the earth hole EST Ø5.6.
	"nema_5_15_plug": {
		"holes": [
			[{"shape": "rect", "at": Vector2(-6.35, 4.2), "size": Vector2(2.0, 9.0)}],
			[{"shape": "rect", "at": Vector2(6.35, 4.2), "size": Vector2(2.0, 7.0)}],
			[{"shape": "round", "at": Vector2(0, -7.7), "d": 5.6}],
		],
	},
	# JIS polarized receptacle (now required): left ~9, right ~7 (PANA); slots
	# 2.3 wide, read off Panasonic's WN1512K drawing.
	"jis_c8303_socket": {
		"holes": [
			[{"shape": "rect", "at": Vector2(-6.35, 4.2), "size": Vector2(2.3, 9.0)}],
			[{"shape": "rect", "at": Vector2(6.35, 4.2), "size": Vector2(2.3, 7.0)}],
		],
	},
	# GB 1002 two-pin: slots 2.0 x 7.3 on 12.7 centres (Figure 2).
	"gb_1002_2pin_socket": {
		"holes": [
			[{"shape": "rect", "at": Vector2(-6.35, 4.2), "size": Vector2(2.0, 7.3)}],
			[{"shape": "rect", "at": Vector2(6.35, 4.2), "size": Vector2(2.0, 7.3)}],
		],
	},
	# CEE7 7/3: Ø5.5 holes on 19 centres, a round well 17.5 deep and about Ø40.5
	# (measured off a straight-on Busch-Jaeger photo). The earthing clips are contacts at the well's sides, not
	# in a plug's way.
	"cee_7_3_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 5.5}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 5.5}],
		],
		"recess": {"body": "circle", "body_size": Vector2(40.5, 40.5), "body_at": Vector2.ZERO,
			"depth": 17.5},
	},
	# CEE7 7/5: the same holes and well, 15 deep, and its Ø4.8 earth pin 10 off
	# the pin line, at the top (Legrand's own pictures).
	"cee_7_5_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 5.5}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 5.5}],
		],
		"studs": [{"at": Vector2(0, 10), "d": 4.8, "len": 14.0}],
		"recess": {"body": "circle", "body_size": Vector2(40.5, 40.5), "body_at": Vector2.ZERO,
			"depth": 15.0},
	},
	# BS1363: L/N apertures at most 7.2 x 4.8, earth 8.8 x 4.8; shutters behind
	# L/N, opened by the earth pin.
	"bs_1363_plug": {
		"holes": [
			[{"shape": "rect", "at": Vector2(-11.1, 0), "size": Vector2(7.2, 4.8)}],
			[{"shape": "rect", "at": Vector2(11.1, 0), "size": Vector2(7.2, 4.8)}],
			[{"shape": "rect", "at": Vector2(0, 22.2), "size": Vector2(4.8, 8.8)}],
		],
		"shutter": 2,
	},
	# AS3112: slots EST 2.3 x 7.3 (GB 1002's 10 A slots: the same plug fits both).
	"as_3112_socket": {
		"holes": [
			[{"shape": "rect", "at": Vector2(-6.86, 3.96), "size": Vector2(2.3, 7.3), "angle": -30.0}],
			[{"shape": "rect", "at": Vector2(6.86, 3.96), "size": Vector2(2.3, 7.3), "angle": 30.0}],
			[{"shape": "rect", "at": Vector2(0, -10.31), "size": Vector2(2.3, 7.3)}],
		],
	},
	# SEV T13: Ø4.5 (+0.2) holes; hexagonal well at least 21 x 36.5, 13 deep.
	"sev_1011_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.7}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 4.7}],
			[{"shape": "round", "at": Vector2(0, -5), "d": 4.7}],
		],
		"recess": {"body": "swiss", "body_size": Vector2(36.5, 22.0), "body_at": Vector2(0, -1.0),
			"depth": 13.0},
	},
	# CEI P17/11 bipasso: each side a figure-eight of Ø4.5 at 19 and Ø5.1 at 26
	# (museum measured), the earth in the middle (EST Ø5.3).
	"cei_23_50_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.5},
				{"shape": "round", "at": Vector2(-13, 0), "d": 5.1}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 4.5},
				{"shape": "round", "at": Vector2(13, 0), "d": 5.1}],
			[{"shape": "round", "at": Vector2(0, 0), "d": 5.3}],
		],
	},
	# DK: Ø5.5 holes on 19 centres (CEE7 Europlug article); the earth slot EST
	# over the 6.5 x 4 pin.
	"ds_k_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 5.5}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 5.5}],
			[{"shape": "rect", "at": Vector2(0, -13), "size": Vector2(7.5, 5.0)}],
		],
	},
	# 60906 SANS 164-2: Ø5 holes, a 10 deep well the plug's outline (EST +0.6).
	"sans_164_2_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 5.0}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 5.0}],
			[{"shape": "round", "at": Vector2(0, -3), "d": 5.0}],
		],
		"recess": {"body": "iec60906", "body_size": Vector2(36.6, 18.2), "body_at": Vector2.ZERO,
			"depth": 10.0},
	},
	# NBR 14136 10 A: Ø4.2 holes (museum measured), the same well.
	"nbr_14136_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 4.2}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 4.2}],
			[{"shape": "round", "at": Vector2(0, -3), "d": 4.2}],
		],
		"recess": {"body": "iec60906", "body_size": Vector2(36.6, 18.2), "body_at": Vector2.ZERO,
			"depth": 10.0},
	},
	# BS546 / IS 1293 16 A: Ø8.0 L/N holes (IS 1293 K); earth EST Ø10.
	"bs_546_plug": {
		"holes": [
			[{"shape": "round", "at": Vector2(-12.7, 0), "d": 8.0}],
			[{"shape": "round", "at": Vector2(12.7, 0), "d": 8.0}],
			[{"shape": "round", "at": Vector2(0, 28.6), "d": 10.0}],
		],
	},
	# IS 1293 6 A: Ø6.0 L/N holes (K); earth EST Ø8.
	"is_1293_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.55, 0), "d": 6.0}],
			[{"shape": "round", "at": Vector2(9.55, 0), "d": 6.0}],
			[{"shape": "round", "at": Vector2(0, 22.2), "d": 8.0}],
		],
	},
	# SI32: Ø5 round holes on 19 centres (CEE7 Europlug article), earth 9.5 below.
	"si_32_socket": {
		"holes": [
			[{"shape": "round", "at": Vector2(-9.5, 0), "d": 5.0}],
			[{"shape": "round", "at": Vector2(9.5, 0), "d": 5.0}],
			[{"shape": "round", "at": Vector2(0, -9.5), "d": 5.0}],
		],
	},
}


## Whether a plug of `plug_id` goes into a socket of `socket_id`, by the numbers.
static func fits(plug_id: String, socket_id: String) -> bool:
	return why_not(plug_id, socket_id).is_empty()


## "" when it goes in, else the first thing that stops it.
static func why_not(plug_id: String, socket_id: String) -> String:
	var plug: Dictionary = PLUGS.get(plug_id, {})
	var socket: Dictionary = SOCKETS.get(socket_id, {})
	if plug.is_empty() or socket.is_empty():
		return "unknown plug or socket"
	var holes: Array = socket.get("holes", [])
	var used := {}
	for pin: Dictionary in plug.get("pins", []):
		var found := -1
		for i in holes.size():
			if not used.has(i) and _inside_hole(_pin_outline(pin), holes[i]):
				found = i
				break
		if found < 0:
			return "a pin at %s has no hole" % pin.get("at")
		used[found] = true
	if socket.has("shutter") and not used.has(int(socket["shutter"])):
		return "nothing opens the shutters"
	var body := outline(plug)
	for stud: Dictionary in socket.get("studs", []):
		var blocked := false
		for p in _circle(stud.get("at"), float(stud.get("d", 0.0)) * 0.5):
			if Geometry2D.is_point_in_polygon(p, body):
				blocked = true
		if blocked:
			var taken := false
			for hole: Dictionary in plug.get("face_holes", []):
				if (hole.get("at") as Vector2).distance_to(stud.get("at")) \
						+ float(stud.get("d", 0.0)) * 0.5 <= float(hole.get("d", 0.0)) * 0.5:
					taken = true
			if not taken:
				return "the socket's stud at %s hits the face" % stud.get("at")
	if socket.has("recess"):
		var well := outline(socket["recess"])
		for p in body:
			if not Geometry2D.is_point_in_polygon(p, well):
				return "the face does not go into the well"
	return ""


## A plug's face, or a socket's well, as a polygon.
static func outline(spec: Dictionary) -> PackedVector2Array:
	var size: Vector2 = spec.get("body_size", Vector2.ZERO)
	var at: Vector2 = spec.get("body_at", Vector2.ZERO)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var pts := PackedVector2Array()
	match str(spec.get("body", "rrect")):
		"circle":
			return _circle(at, hx)
		"europlug":
			# The ends run in at 45 degrees from the flats to a point.
			pts = [Vector2(hx, 0), Vector2(hx - hy, hy), Vector2(-hx + hy, hy),
				Vector2(-hx, 0), Vector2(-hx + hy, -hy), Vector2(hx - hy, -hy)]
		"swiss":
			# Square top corners, the bottom ones cut at 45 degrees toward the earth.
			var c := hy * 0.6
			pts = [Vector2(hx, hy), Vector2(-hx, hy), Vector2(-hx, -hy + c),
				Vector2(-hx + c, -hy), Vector2(hx - c, -hy), Vector2(hx, -hy + c)]
		"iec60906":
			# A Europlug's face carried down over the earth pin: the 2-pin plug is
			# 14 high (the Europlug's 13.7) and the 3-pin 17, so the extra 3 is on
			# the earth side. The 45-degree ends are EST, read from the Europlug.
			var top := 7.0 * size.y / 17.0
			var bottom := size.y - top
			pts = [Vector2(hx, 0), Vector2(hx - top, top), Vector2(-hx + top, top),
				Vector2(-hx, 0), Vector2(-hx + bottom, -bottom), Vector2(hx - bottom, -bottom)]
		_:
			var r := minf(4.0, minf(hx, hy))
			for corner in 4:
				var c := Vector2(hx - r if corner == 0 or corner == 3 else -hx + r,
					hy - r if corner < 2 else -hy + r)
				for s in 4:
					var a := deg_to_rad(float(corner) * 90.0 + float(s) * 30.0)
					pts.append(c + Vector2(cos(a), sin(a)) * r)
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + at)
	return out


## A pin's section at its base, as points.
static func _pin_outline(pin: Dictionary) -> PackedVector2Array:
	var at: Vector2 = pin.get("at")
	if str(pin.get("shape")) == "round":
		return _circle(at, float(pin.get("d", 0.0)) * 0.5)
	return _rect(at, pin.get("size"), float(pin.get("angle", 0.0)))


## Every point of `pts` inside one of the hole's parts -- a figure-eight hole
## takes a pin in either lobe, not across the waist.
static func _inside_hole(pts: PackedVector2Array, hole: Array) -> bool:
	for part: Dictionary in hole:
		var poly: PackedVector2Array
		if str(part.get("shape")) == "round":
			poly = _circle(part.get("at"), float(part.get("d", 0.0)) * 0.5)
		else:
			poly = _rect(part.get("at"), part.get("size"), float(part.get("angle", 0.0)))
		var all_in := true
		for p in pts:
			if not Geometry2D.is_point_in_polygon(p, poly):
				all_in = false
				break
		if all_in:
			return true
	return false


static func _circle(at: Vector2, r: float, n := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(at + Vector2(cos(a), sin(a)) * r)
	return out


static func _rect(at: Vector2, size: Vector2, angle_deg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var h := size * 0.5
	for c: Vector2 in [Vector2(h.x, h.y), Vector2(-h.x, h.y), Vector2(-h.x, -h.y), Vector2(h.x, -h.y)]:
		out.append(at + c.rotated(deg_to_rad(angle_deg)))
	return out
