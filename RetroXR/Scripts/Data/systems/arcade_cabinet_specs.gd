## ArcadeCabinetSpecs — what each shipped cabinet is, as data, and the bodies it can have.
##
## A cabinet is a SPEC (a Dictionary) that ArcadeCabinetBuilder turns into nodes: the look (body,
## trim, marquee), the bay kind, a panel per player, the coin doors, front sockets or guns in
## holsters, a pedal. The shipped cabinets are rows here (`variant`), baked into scenes by
## Tools/gen/gen_arcade_cabinet.gd; a cabinet in the room builds its parts again from a spec when the
## game in its bay wants another shape (`RetroSystemModelArcadeCabinet.morph_to`).
##
## Button 1 is RetroPad B, then A, Y, X, L, R (ArcadeProfiles.BUTTON_BITS); Neo Geo's A B C D are the
## first four. THE VARIANT NAMES ARE NOT PERSISTED (the registry ids are, model_registry.gd), but each
## baked scene names its row (`ArcadeCabinetBuilder.VARIANT_META`), so a row is renamed together
## with its scene or not at all.
class_name ArcadeCabinetSpecs
extends RefCounted


## The bodies. `upright` is the generic cabinet and every old one: 0.66 wide, 1.80 tall, the glass
## leaning back 27 degrees, a 0.44 x 0.33 tube. `wide` is the shooter's: 0.90 wide, 1.90 tall, the glass
## STRAIGHT (vertical, flush with the front), a 0.72 x 0.54 tube (half as wide again as the upright's, 35
## inches: a 29 inch tube was the usual, a 50 inch projection the big one). A gun held at arm's length
## in front of a small screen walks into it; this one leaves room. Side silhouettes are (z, y), front +z.
static func shapes() -> Dictionary:
	return {
		"upright": {
			"w": 0.66, "h": 1.80, "tube": Vector2(0.44, 0.33),
			"profile": [
				Vector2(-0.40, 0.00), Vector2(0.34, 0.00), Vector2(0.34, 0.09), Vector2(0.40, 0.09),
				Vector2(0.40, 0.78), Vector2(0.47, 0.80), Vector2(0.47, 0.92), Vector2(0.30, 1.00),
				Vector2(0.07, 1.46), Vector2(0.18, 1.46), Vector2(0.18, 1.80), Vector2(-0.40, 1.80),
			],
			# The glass runs along the silhouette's slanted edge, the deck's back edge to the marquee's underside.
			"glass_a": Vector2(0.30, 1.00), "glass_b": Vector2(0.07, 1.46),
			"top": [0.56, -0.11],
			"marquee": {"y": 1.62, "h": 0.31, "z": 0.174, "trim_y": 1.459, "under": [0.11, 1.454, 0.125]},
			"marquee_bottom": 1.46, "glass_back_z": 0.12, "marquee_front_z": 0.18, "screen_front_z": 0.40,
		},
		"wide": {
			"w": 0.90, "h": 1.90, "tube": Vector2(0.72, 0.54),
			"profile": [
				Vector2(-0.40, 0.00), Vector2(0.34, 0.00), Vector2(0.34, 0.09), Vector2(0.40, 0.09),
				Vector2(0.40, 0.78), Vector2(0.47, 0.80), Vector2(0.47, 0.92), Vector2(0.30, 1.00),
				Vector2(0.30, 1.66), Vector2(0.34, 1.66), Vector2(0.34, 1.90), Vector2(-0.40, 1.90),
			],
			"glass_a": Vector2(0.30, 1.00), "glass_b": Vector2(0.30, 1.66),
			"top": [0.72, -0.03],
			"marquee": {"y": 1.78, "h": 0.24, "z": 0.334, "trim_y": 1.659, "under": []},
			"marquee_bottom": 1.66, "glass_back_z": 0.20, "marquee_front_z": 0.30, "screen_front_z": 0.30,
		},
	}


## The shipped cabinets, by the name gen_arcade_cabinet.gd bakes them under (`--variant=`): the look
## (body, trim, marquee), the bay kind, a panel per player (`stick` with N buttons, `dial`, or `start`
## alone), the coin doors' x, whether it has front pad sockets or guns in holsters, and whether a pedal
## is drawn.
static func variants() -> Dictionary:
	var two_stick := [
		{"kind": "stick", "stick_x": -0.255, "start_x": -0.115, "buttons": six([-0.175, -0.115, -0.055])},
		{"kind": "stick", "stick_x": 0.055, "start_x": 0.195, "buttons": six([0.135, 0.195, 0.255])},
	]
	var blue := Color(0.14, 0.17, 0.33)
	return {
		"generic": {
			"out": "arcade_cabinet.tscn", "title": "ARCADE", "bay": "jamma",
			"body": blue, "trim": Color(0.90, 0.16, 0.28),
			"marquee": Color(0.95, 0.35, 0.20), "glow": Color(1.0, 0.45, 0.25),
			"players": two_stick, "coins": [-0.14, 0.14], "sockets": true, "guns": 0, "pedal": false,
		},
		# Twin-gun shooter: no stick, no buttons but START, a gun on each side in a holster with its
		# cord going into the cabinet, and a foot pedal on the floor (drawn, not active).
		"lightgun": {
			"out": "arcade_cabinet_lightgun.tscn", "title": "SHOOTING", "bay": "jamma",
			"shape": "wide",
			"body": Color(0.10, 0.10, 0.12), "trim": Color(0.95, 0.60, 0.05),
			"marquee": Color(0.80, 0.10, 0.10), "glow": Color(1.0, 0.25, 0.20),
			"players": [{"kind": "start", "start_x": -0.20}, {"kind": "start", "start_x": 0.20}],
			"coins": [-0.20, 0.20], "sockets": false, "guns": 2, "pedal": true,
		},
		# The MVS: a stick and four buttons (A B C D), START.
		"neogeo": {
			"out": "arcade_cabinet_neogeo.tscn", "title": "NEO GEO", "bay": "mvs",
			"body": Color(0.05, 0.05, 0.07), "trim": Color(0.85, 0.07, 0.10),
			"marquee": Color(0.70, 0.08, 0.10), "glow": Color(1.0, 0.2, 0.2),
			"players": [
				{"kind": "stick", "stick_x": -0.255, "start_x": -0.12, "buttons": row([-0.195, -0.145, -0.095, -0.045])},
				{"kind": "stick", "stick_x": 0.055, "start_x": 0.19, "buttons": row([0.125, 0.175, 0.225, 0.275])},
			],
			"coins": [-0.14, 0.14], "sockets": true, "guns": 0, "pedal": false,
		},
		# Laserdisc (Dragon's Lair): one stick and the sword button.
		"daphne": {
			"out": "arcade_cabinet_daphne.tscn", "title": "LASER", "bay": "laserdisc",
			"body": Color(0.12, 0.07, 0.20), "trim": Color(0.95, 0.75, 0.15),
			"marquee": Color(0.20, 0.35, 0.85), "glow": Color(0.4, 0.55, 1.0),
			"players": [{"kind": "stick", "stick_x": -0.13, "start_x": -0.03,
				"buttons": [{"pos": Vector2(0.06, 0.020), "radius": 0.027, "color": 0}]}],
			"coins": [0.0], "sockets": true, "guns": 0, "pedal": false,
		},
		# The laserdisc shooters (Mad Dog McCree and its kin): guns instead of a stick.
		"daphne_gun": {
			"out": "arcade_cabinet_daphne_gun.tscn", "title": "LASER GUN", "bay": "laserdisc",
			"body": Color(0.12, 0.07, 0.20), "trim": Color(0.95, 0.75, 0.15),
			"shape": "wide",
			"marquee": Color(0.20, 0.35, 0.85), "glow": Color(0.4, 0.55, 1.0),
			"players": [{"kind": "start", "start_x": -0.20}, {"kind": "start", "start_x": 0.20}],
			"coins": [-0.20, 0.20], "sockets": false, "guns": 2, "pedal": false,
		},
		# Discrete-logic games (Pong, Breakout): a paddle dial each and START.
		"dice": {
			"out": "arcade_cabinet_dice.tscn", "title": "DICE", "bay": "discrete",
			"body": Color(0.22, 0.13, 0.07), "trim": Color(0.90, 0.85, 0.70),
			"marquee": Color(0.10, 0.10, 0.10), "glow": Color(0.9, 0.9, 0.9),
			"players": [{"kind": "dial", "dial_x": -0.17, "start_x": -0.07},
				{"kind": "dial", "dial_x": 0.17, "start_x": 0.07}],
			"coins": [-0.14, 0.14], "sockets": true, "guns": 0, "pedal": false,
		},
	}


## One shipped cabinet's spec, or {} for a name that is none.
static func variant(name: String) -> Dictionary:
	return (variants().get(name, {}) as Dictionary).duplicate(true)


## Six buttons in two rows of three (the generic panel), from the three columns' x.
static func six(xs: Array) -> Array:
	var out: Array = []
	for r in 2:
		for col in 3:
			out.append({"pos": Vector2(float(xs[col]) + (0.012 if r == 0 else 0.0), 0.040 if r == 0 else -0.012),
				"radius": 0.0155, "color": r * 3 + col})
	return out


## N buttons in one gently arched row (Neo Geo's A B C D), from their x.
static func row(xs: Array) -> Array:
	var out: Array = []
	for i in xs.size():
		var y := 0.020 + (0.008 if i == 1 or i == 2 else 0.0)
		out.append({"pos": Vector2(float(xs[i]), y), "radius": 0.0155, "color": i})
	return out
