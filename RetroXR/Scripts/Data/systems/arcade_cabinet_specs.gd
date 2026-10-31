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
## leaning back 27 degrees, a 0.44 x 0.33 tube. `tate` is the upright of a monitor on its side: the glass
## 0.13 m longer up the same slant and a 0.48 x 0.36 tube, so turned upright it fills a tall window. `wide` is
## the shooter's: 0.90 wide, 1.90 tall, the glass STRAIGHT (vertical, flush with the front), a 0.72 x 0.54 tube
## (half as wide again as the upright's: a 29 inch tube was the usual, a 50 inch projection the big one). A gun
## held at arm's length in front of a small screen walks into it; this one leaves room. `tall` is the tate body
## for a picture the right way up: the upright of a WIDE cabinet (three or more players), whose 0.44 m tube was
## lost in a body twice as wide (wide_picture). Side silhouettes are
## (z, y), front +z. `inches` is the class of the tube the body is drawn with (a CRT's picture is about 87% of
## its class): a game's own monitor is sized against it (ArcadeCabinetBuilder.tube_for).
static func shapes() -> Dictionary:
	var out := {
		"upright": {
			"w": 0.66, "h": 1.80, "tube": Vector2(0.44, 0.33), "inches": 25,
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
		# The upright of a game whose monitor stood on its side (a "tate" game: 1943, Batsugun, Galaga): the
		# same body, deck and coin face, but the glass runs 0.65 m up the slant (0.51 on the upright) and the
		# marquee sits above it, so a 25 inch class tube turned upright (0.36 x 0.48 m) fills a window as tall
		# as it is, instead of floating in a landscape one.
		"tate": {
			"w": 0.66, "h": 1.92, "tube": Vector2(0.48, 0.36), "inches": 25,
			"profile": [
				Vector2(-0.40, 0.00), Vector2(0.34, 0.00), Vector2(0.34, 0.09), Vector2(0.40, 0.09),
				Vector2(0.40, 0.78), Vector2(0.47, 0.80), Vector2(0.47, 0.92), Vector2(0.30, 1.00),
				Vector2(0.01, 1.58), Vector2(0.12, 1.58), Vector2(0.12, 1.92), Vector2(-0.40, 1.92),
			],
			"glass_a": Vector2(0.30, 1.00), "glass_b": Vector2(0.01, 1.58),
			"top": [0.51, -0.135],
			"marquee": {"y": 1.74, "h": 0.31, "z": 0.114, "trim_y": 1.579, "under": [0.11, 1.574, 0.065]},
			"marquee_bottom": 1.58, "glass_back_z": 0.06, "marquee_front_z": 0.12, "screen_front_z": 0.40,
		},
		"wide": {
			"w": 0.90, "h": 1.90, "tube": Vector2(0.72, 0.54), "inches": 40,
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
		# The sit-down cabinet's monitor housing: the same lower body (the bay, the coin doors), then a HOOD over the
		# bay door's swing (a shelf 0.34 m deep, its underside above the door's top) and the monitor leaning back 25
		# degrees from the hood's front edge, lower than an upright's so a SEATED player looks into it (its middle at
		# about 1.1 m). The hood is why the glass is under a metre from the seated eyes, where a monitor flush with the
		# bay would be 1.6 m off and fill 16 degrees of the view (the real cabinets' filled about 30). The seat, the wheel
		# and the pedals are the cockpit in front of it (ArcadeCabinetBuilder._build_cockpit), clear of the door's swing.
		"racer": {
			"w": 0.66, "h": 1.56, "tube": Vector2(0.48, 0.36), "inches": 27,
			"profile": [
				Vector2(-0.40, 0.00), Vector2(0.34, 0.00), Vector2(0.34, 0.09), Vector2(0.40, 0.09),
				Vector2(0.40, 0.78), Vector2(0.50, 0.80), Vector2(0.84, 0.80), Vector2(0.84, 0.88),
				Vector2(0.62, 1.36), Vector2(0.70, 1.36), Vector2(0.70, 1.56), Vector2(-0.40, 1.56),
			],
			"glass_a": Vector2(0.84, 0.88), "glass_b": Vector2(0.62, 1.36),
			# No control deck (the controls are the cockpit's): a plate inside the hood's front lip, which takes the deck's place.
			"deck_a": Vector2(0.83, 0.84), "deck_b": Vector2(0.83, 0.88),
			"hood": {"z0": 0.50, "z1": 0.84, "y0": 0.80, "y1": 0.88},
			"top": [1.10, 0.15],
			"marquee": {"y": 1.46, "h": 0.20, "z": 0.694, "trim_y": 1.359, "under": [0.08, 1.354, 0.66]},
			"marquee_bottom": 1.36, "glass_back_z": 0.57, "marquee_front_z": 0.70, "screen_front_z": 0.40,
		},
	}
	# The upright of a WIDE cabinet (three or more players): the tate body with the glass TALL_EXTRA longer again, so a
	# picture the right way up (0.77 x 0.58 at most, a 40 inch class) stands in it with its 3 cm of black round it.
	out["tall"] = lengthened(out["tate"], TALL_EXTRA)
	return out


## `shape` with its glass `extra` metres longer up the same slant: the glass's top corner, the marquee over it and the
## top of the body move up and back with it, nothing below the glass moves (the tate body is the upright lengthened
## this way, by hand).
static func lengthened(shape: Dictionary, extra: float) -> Dictionary:
	var out := shape.duplicate(true)
	var a: Vector2 = shape["glass_a"]
	var b: Vector2 = shape["glass_b"]
	var d := (b - a).normalized() * extra
	var outline: Array[Vector2] = []
	for p: Vector2 in shape["profile"]:
		if p == b:
			outline.append(p + d)
		elif p.y >= b.y:
			# The marquee's front and the top of the body follow the glass; the rear wall (z at -0.40) only rises.
			outline.append(p + Vector2(0.0 if p.x < -0.39 else d.x, d.y))
		else:
			outline.append(p)
	out["profile"] = outline
	out["glass_b"] = b + d
	out["h"] = float(shape["h"]) + d.y
	var top: Array = shape["top"]
	out["top"] = [float(top[0]) + d.x, float(top[1]) + d.x * 0.5]
	var marquee: Dictionary = (shape["marquee"] as Dictionary).duplicate(true)
	marquee["y"] = float(marquee["y"]) + d.y
	marquee["trim_y"] = float(marquee["trim_y"]) + d.y
	marquee["z"] = float(marquee["z"]) + d.x
	var under: Array = marquee["under"]
	if not under.is_empty():
		marquee["under"] = [under[0], float(under[1]) + d.y, float(under[2]) + d.x]
	out["marquee"] = marquee
	out["marquee_bottom"] = float(shape["marquee_bottom"]) + d.y
	out["glass_back_z"] = float(shape["glass_back_z"]) + d.x
	out["marquee_front_z"] = float(shape["marquee_front_z"]) + d.x
	return out


## `shape` with its control deck `extra` metres DEEPER toward the player: the apron's front (the silhouette's points at the deck's front z) and the deck's front edge
## move out together, the glass, the marquee and the body behind them not at all (a slot's deck: Panic Park's two levers and the START above each).
## `apron_z` says where the apron's face now is (ArcadeCabinetBuilder._build_shell hangs its boxes on it).
static func deepened(shape: Dictionary, extra: float) -> Dictionary:
	var out := shape.duplicate(true)
	var a: Vector2 = shape.get("deck_a", Vector2(0.47, 0.92))
	var outline: Array[Vector2] = []
	for p: Vector2 in shape["profile"]:
		outline.append(p + Vector2(extra, 0.0) if is_equal_approx(p.x, a.x) and p.y >= 0.79 else p)
	out["profile"] = outline
	out["deck_a"] = a + Vector2(extra, 0.0)
	out["deck_b"] = shape.get("deck_b", Vector2(0.30, 1.00))
	out["apron_z"] = a.x + extra
	return out


## The shipped cabinets, by the name gen_arcade_cabinet.gd bakes them under (`--variant=`): the look
## (body, trim, marquee), the bay kind, a panel per player (`stick` with N buttons, `dial`, or `start`
## alone), the coin doors' x, and whether it has front pad sockets or guns in holsters.
static func variants() -> Dictionary:
	var two_stick := [
		{"kind": "stick", "player": 0, "stick_x": -0.255, "start_x": -0.115, "buttons": six([-0.175, -0.115, -0.055])},
		{"kind": "stick", "player": 1, "stick_x": 0.055, "start_x": 0.195, "buttons": six([0.135, 0.195, 0.255])},
	]
	var blue := Color(0.14, 0.17, 0.33)
	return {
		"generic": {
			"out": "arcade_cabinet.tscn", "title": "ARCADE", "bay": "jamma",
			"body": blue, "trim": Color(0.90, 0.16, 0.28),
			"marquee": Color(0.95, 0.35, 0.20), "glow": Color(1.0, 0.45, 0.25),
			"players": two_stick, "coins": [-0.14, 0.14], "sockets": true, "guns": 0,
		},
		# The MVS: a stick and four buttons (A B C D), START.
		"neogeo": {
			"out": "arcade_cabinet_neogeo.tscn", "title": "NEO GEO", "bay": "mvs",
			"body": Color(0.05, 0.05, 0.07), "trim": Color(0.85, 0.07, 0.10),
			"marquee": Color(0.70, 0.08, 0.10), "glow": Color(1.0, 0.2, 0.2),
			"players": [
				{"kind": "stick", "player": 0, "stick_x": -0.255, "start_x": -0.12, "buttons": row([-0.195, -0.145, -0.095, -0.045])},
				{"kind": "stick", "player": 1, "stick_x": 0.055, "start_x": 0.19, "buttons": row([0.125, 0.175, 0.225, 0.275])},
			],
			"coins": [-0.14, 0.14], "sockets": true, "guns": 0,
		},
		# Laserdisc (Dragon's Lair): one stick and the sword button.
		"daphne": {
			"out": "arcade_cabinet_daphne.tscn", "title": "LASER", "bay": "laserdisc",
			"body": Color(0.12, 0.07, 0.20), "trim": Color(0.95, 0.75, 0.15),
			"marquee": Color(0.20, 0.35, 0.85), "glow": Color(0.4, 0.55, 1.0),
			"players": [{"kind": "stick", "player": 0, "stick_x": -0.13, "start_x": -0.03,
				"buttons": [{"pos": Vector2(0.06, 0.020), "radius": 0.027, "color": 0}]}],
			"coins": [0.0], "sockets": true, "guns": 0,
		},
		# The laserdisc shooters (Mad Dog McCree and its kin): guns instead of a stick.
		"daphne_gun": {
			"out": "arcade_cabinet_daphne_gun.tscn", "title": "LASER GUN", "bay": "laserdisc",
			"body": Color(0.12, 0.07, 0.20), "trim": Color(0.95, 0.75, 0.15),
			"shape": "wide",
			"marquee": Color(0.20, 0.35, 0.85), "glow": Color(0.4, 0.55, 1.0),
			"players": [{"kind": "start", "player": 0, "start_x": -0.20}, {"kind": "start", "player": 1, "start_x": 0.20}],
			"coins": [-0.20, 0.20], "sockets": false, "guns": 2,
		},
		# Discrete-logic games (Pong, Breakout): a paddle dial each and START.
		"dice": {
			"out": "arcade_cabinet_dice.tscn", "title": "DICE", "bay": "discrete",
			"body": Color(0.22, 0.13, 0.07), "trim": Color(0.90, 0.85, 0.70),
			"marquee": Color(0.10, 0.10, 0.10), "glow": Color(0.9, 0.9, 0.9),
			"players": [{"kind": "dial", "player": 0, "dial_x": -0.17, "start_x": -0.07},
				{"kind": "dial", "player": 1, "dial_x": 0.17, "start_x": 0.07}],
			"coins": [-0.14, 0.14], "sockets": true, "guns": 0,
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


# ── the game's cabinet ───────────────────────────────────────────────────────
#
# A cabinet that follows the game in its bay builds the parts its game had (RetroSystemModelArcadeCabinet.
# morph_to): the panels, the coin doors, the guns, the monitor, the cockpit or the stage. `for_game` turns a
# cabinet's own row and the game's profile into that spec; the look (body colour, trim, marquee, title) and
# the bay are the cabinet's and never change.

## How deep behind the glass a hologram cabinet's picture stands (Time Traveler: the picture floats in a dark stage
## 30 cm back), and how far a slot's lever slides either side of where it rests (Panic Park: two levers, one slot,
## each the half of it that is its own).
const HOLO_DEPTH := 0.30
const SLOT_TRAVEL := 0.14
## How far a lever's handle (a dome 4.5 cm in radius) and its carriage reach past the end of the carriage's travel: the body is as wide as the levers need
## with it, or the handle at the end of the slot stood outside the case. A slot's deck is also deeper than the upright's (SLOT_DECK_EXTRA): START stands
## ABOVE each lever (toward the screen) as Panic Park's did, and the lever below it has the deck's front edge a hand's breadth away.
const SLOT_HANDLE_REACH := 0.05
const SLOT_DECK_EXTRA := 0.07

## How wide a two-seat cockpit's body is (Lucky & Wild): two seats of 0.40 m side by side and the dash they sit at, and where each seat's player sits and their gun
## hangs, on the cockpit's x (the driver on the left, the gunner on the right; the holsters in the middle of the dash, a hand's reach from either).
const RACEGUN_WIDTH := 0.90
const RACEGUN_SEAT_X := 0.21
const RACEGUN_GUN_XS: Array[float] = [-0.07, 0.07]

## The most panels a deck takes (X-Men's six players), and the most coin doors on a coin face.
const MAX_PANELS := 6
const MAX_COIN_DOORS := 4
## The most guns a gun cabinet carries (Beast Busters had three).
const MAX_GUNS := 3
## The pitch between two players' panels on a two-player deck (the generic cabinet's), the least pitch of three
## or more (a player's share of a four-player deck: 30 cm, a real one's twelve inches), the gap left between two
## panels that would crowd it, and how far a panel's stick stands in from its left edge.
const PANEL_PITCH := 0.31
const PANEL_PITCH_MULTI := 0.30
const PANEL_GAP := 0.03
const STICK_IN := 0.04625
## What a window's frame takes of the glass edge's length (the top and the bottom of the bezel): the most a tube can
## stand is the edge less this. The window is cut 3 cm round the picture and the bezel needs 5.5 cm either end of the
## edge, which is 0.11 + 2 x 0.03: a tube any taller would touch the window's edge (ArcadeCabinetBuilder._build_monitor).
const GLASS_FRAME := 0.17
## What the glass keeps of a body's width on each side besides the black round the picture: the most a tube can be
## wide is the space between the sides (the body less its 2 x 2 cm walls) less this.
const GLASS_SIDES := 0.08
## How much of a wide body's width the pictures of a game of SEVERAL screens take (X-Men's two across a 1.9 m body), and the widest
## body a game's screens may make (five screens in a row, Jaleco's, would be 3.3 m).
const MULTI_SHARE := 0.80
const MAX_SCREENS_BODY := 2.40
## How much longer the tall body's glass is than the tate body's (0.65 m): 0.75 m of glass, 2.0 m of cabinet.
const TALL_EXTRA := 0.10
## How much of a WIDE body's width the picture takes. A 2P upright's is 0.67 (0.44 m of 0.66); a real three- or
## four-player cabinet's tube was about half of its body (Gauntlet Legends: a 25 inch tube in 0.93 m, TMNT's panel
## 0.94 m), which on a 1.2 m body RetroXR draws as a lost postage stamp. 0.58 keeps a 3P or 4P cabinet looking
## like a bigger upright, not a small screen in a long box.
const PICTURE_SHARE := 0.58
## A button column's pitch, and the first column's distance from the stick.
const COLUMN_PITCH := 0.06
const FIRST_COLUMN := 0.08
## A flight yoke's panel: the stick stands this far from the panel's left edge, the first column of caps this far to its right, and its handgrips reach this far from its middle.
const YOKE_IN := 0.15
const YOKE_FIRST_COLUMN := 0.19
const YOKE_REACH := 0.15
## The pitch of the coin doors by how many there are (1 to 4), on the upright's 0.62 m coin face.
const COIN_PITCH: Array[float] = [0.0, 0.28, 0.18, 0.14]


## The x a panel's parts reach on the deck, (left, right): what the deck must be wide enough for and what the
## panel's grip covers (ArcadeCabinetBuilder._build_player).
static func panel_extent(panel: Dictionary) -> Vector2:
	var start_x := float(panel["start_x"])
	var left := start_x - 0.02
	var right := start_x + 0.02
	match str(panel["kind"]):
		"stick", "twin", "rotary", "yoke", "rod":
			var reach := YOKE_REACH if str(panel["kind"]) == "yoke" else 0.045
			left = minf(left, float(panel["stick_x"]) - reach)
			right = maxf(right, float(panel["stick_x"]) + reach)
			if str(panel["kind"]) == "twin":
				left = minf(left, float(panel["stick2_x"]) - 0.045)
				right = maxf(right, float(panel["stick2_x"]) + 0.045)
		"ball":
			left = minf(left, float(panel["ball_x"]) - 0.055)
			right = maxf(right, float(panel["ball_x"]) + 0.055)
		"dial":
			left = minf(left, float(panel["dial_x"]) - 0.045)
			right = maxf(right, float(panel["dial_x"]) + 0.045)
		"wheel":
			left = minf(left, float(panel["wheel_x"]) - 0.15)
			right = maxf(right, float(panel["wheel_x"]) + (0.25 if bool(panel.get("shifter", false)) else 0.15))
		"slot":
			left = minf(left, float(panel["slot_x"]) - SLOT_TRAVEL - SLOT_HANDLE_REACH)
			right = maxf(right, float(panel["slot_x"]) + SLOT_TRAVEL + SLOT_HANDLE_REACH)
		"music":
			# A rhythm game's controller is wider than a stick and caps: its own layout says by how much (ArcadeInstruments.panel).
			left = minf(left, float(panel["x0"]))
			right = maxf(right, float(panel["x1"]))
	for bt: Dictionary in panel.get("buttons", []):
		var pos: Vector2 = bt["pos"]
		var radius := float(bt["radius"])
		left = minf(left, pos.x - radius - 0.02)
		right = maxf(right, pos.x + radius + 0.02)
	return Vector2(left, right)


## How wide the deck must be for these panels: twice the farthest any of them reaches from the middle.
static func panels_span(players: Array) -> float:
	var reach := 0.0
	for panel: Dictionary in players:
		var e := panel_extent(panel)
		reach = maxf(reach, maxf(-e.x, e.y))
	return reach * 2.0


## The x of each panel's middle on the deck: where its player stands, and so where the coin door under it and the
## socket for its pad go.
static func panel_centres(players: Array) -> Array:
	var out: Array = []
	for panel: Dictionary in players:
		var e := panel_extent(panel)
		out.append((e.x + e.y) * 0.5)
	return out


## How wide the body is for these panels: the shape's own while they fit its deck (within a centimetre: the
## generic panel's last cap reaches 30.3 cm from the middle of a 62 cm deck), else as wide as the deck needs
## them, with 2 cm to spare either side. A three- or four-player cabinet was a real one WIDE all the way up
## (Konami's was 1.2 m, the monitor in the middle and the marquee as wide as the body), never a standard
## upright with a long plate stuck on the front.
static func body_width(shape_width: float, players: Array) -> float:
	var span := panels_span(players)
	return shape_width if span <= shape_width - 0.04 + 0.01 else span + 0.08


## The kind of panel a game's controls want: two sticks, a trackball, a paddle dial, buttons alone, or a stick.
## A dial or paddle with a pedal is a driving game's wheel (`wheel`, on a stand-up panel). A dial AND a stick is a rotary joystick (`rotary`: Ikari Warriors,
## Top Gunner's bootleg, Victory Road, Heavy Barrel, Tron...): the stick leans and its shaft turns.
static func panel_kind(profile: ArcadeGameProfile) -> String:
	if profile == null or not profile.known:
		return "stick"
	# A controller of its own shape (the table's `y`): a flight yoke, a fishing rod.
	if profile.control_style() == "yoke" or profile.control_style() == "rod":
		return profile.control_style()
	if profile.has_kind(ArcadeGameProfile.KIND_TWIN):
		return "twin"
	if profile.has_kind(ArcadeGameProfile.KIND_BALL):
		return "ball"
	var steering := profile.has_kind(ArcadeGameProfile.KIND_DIAL) or profile.has_kind(ArcadeGameProfile.KIND_PADDLE)
	if steering and (profile.has_kind(ArcadeGameProfile.KIND_PEDAL) or profile.steering_dial()):
		return "wheel"
	if steering:
		# A spinner beside a stick (a dial, never a paddle: a paddle with a joystick is a driving game's wheel and gear lever) is a stick that twists.
		if profile.has_kind(ArcadeGameProfile.KIND_DIAL) and not profile.has_kind(ArcadeGameProfile.KIND_PADDLE) \
				and (profile.has_kind(ArcadeGameProfile.KIND_JOY) or profile.has_kind(ArcadeGameProfile.KIND_STICK)):
			return "rotary"
		return "dial"
	if profile.has_kind(ArcadeGameProfile.KIND_JOY) or profile.has_kind(ArcadeGameProfile.KIND_STICK):
		return "stick"
	if profile.has_kind(ArcadeGameProfile.KIND_BUTTONS):
		return "buttons"
	return "stick"


## The caps of a panel with `count` buttons whose first column stands at `x0`: one row for up to three, Neo
## Geo's arched row for four, two rows of three for six (the generic panel's) and three over two for five.
static func button_grid(count: int, x0: float) -> Array:
	var xs := func(n: int) -> Array:
		var out: Array = []
		for k in n:
			out.append(x0 + COLUMN_PITCH * k)
		return out
	match clampi(count, 0, 6):
		0:
			return []
		1, 2, 3:
			var out: Array = []
			for k in count:
				out.append({"pos": Vector2(x0 + COLUMN_PITCH * k, 0.014), "radius": 0.0155, "color": k})
			return out
		4:
			return row(xs.call(4))
		5:
			var five := six(xs.call(3))
			five.remove_at(5)
			return five
		_:
			return six(xs.call(3))


## How many button columns a panel of `count` buttons has.
static func button_columns(count: int) -> int:
	match clampi(count, 0, 6):
		0:
			return 0
		1, 2, 3:
			return count
		4:
			return 4
		_:
			return 3


## How wide one panel of this kind and this many buttons is, edge to edge (what panels are spaced by).
static func panel_width(kind: String, buttons: int) -> float:
	var columns := button_columns(buttons)
	# From the first button column to the last cap's outer edge (the top row of two stands 12 mm right).
	var caps := 0.0 if columns == 0 else COLUMN_PITCH * (columns - 1) + 0.0355 + (0.012 if buttons >= 5 else 0.0)
	match kind:
		"twin":
			return 0.045 + 0.16 + (0.07 + caps if columns > 0 else 0.045)
		"ball":
			return 0.055 + (0.09 + caps if columns > 0 else 0.095)
		"buttons":
			return maxf(0.0355 + caps, 0.07)
		"wheel":
			return 0.30 + (0.07 + caps if columns > 0 else 0.0)
		"yoke":
			return YOKE_IN + (YOKE_FIRST_COLUMN + caps if columns > 0 else YOKE_REACH)
		_:
			return 0.045 + (FIRST_COLUMN + caps if columns > 0 else 0.085)


## One player's panel of `kind` with `buttons` caps, its parts laid out about the panel's middle `cx`.
static func panel(kind: String, buttons: int, cx: float, player: int) -> Dictionary:
	var left := cx - panel_width(kind, buttons) * 0.5
	var columns := button_columns(buttons)
	# START under the middle column (the generic panel's), between two, or beside a control with no buttons.
	var under := func(x0: float) -> float:
		return x0 + COLUMN_PITCH * (floorf((columns - 1) * 0.5) if columns >= 3 else (columns - 1) * 0.5)
	var out := {"kind": kind, "player": player}
	match kind:
		"twin":
			var s1 := left + STICK_IN
			out["stick_x"] = s1
			out["stick2_x"] = s1 + 0.16
			out["start_x"] = s1 + 0.08
			out["buttons"] = button_grid(buttons, s1 + 0.16 + 0.07)
		"ball":
			var bx := left + 0.055
			out["ball_x"] = bx
			out["buttons"] = button_grid(buttons, bx + 0.09)
			out["start_x"] = under.call(bx + 0.09) if columns > 0 else bx + 0.075
		"buttons":
			var x0 := left + 0.0355
			out["buttons"] = button_grid(buttons, x0)
			out["start_x"] = under.call(x0) if columns > 0 else left + 0.035
		"dial":
			var dx := left + STICK_IN
			out["dial_x"] = dx
			out["buttons"] = button_grid(buttons, dx + FIRST_COLUMN)
			out["start_x"] = under.call(dx + FIRST_COLUMN) if columns > 0 else dx + 0.065
		"wheel":
			# A player's own steering wheel on the deck (Bad Lands'): the wheel standing out of the panel toward the player, the buttons beside it, no pedals and no lever.
			var wx := left + 0.15
			out["wheel_x"] = wx
			out["pedals"] = false
			out["shifter"] = false
			out["buttons"] = button_grid(buttons, wx + 0.22)
			out["start_x"] = under.call(wx + 0.22) if columns > 0 else wx + 0.2
		_:
			# A yoke is 0.30 m across: its handgrips clear the first column of caps.
			var yoke := kind == "yoke"
			var sx := left + (YOKE_IN if yoke else STICK_IN)
			var first := YOKE_FIRST_COLUMN if yoke else FIRST_COLUMN
			out["kind"] = kind if kind in ["rotary", "yoke", "rod"] else "stick"
			out["stick_x"] = sx
			out["buttons"] = button_grid(buttons, sx + first)
			out["start_x"] = under.call(sx + first) if columns > 0 else sx + (0.13 if yoke else 0.065)
	return out


## The panels for a game: one per player across the deck, each the kind of control the game has and as many
## buttons as it reads. Two players stand where the generic cabinet's two always did; three or more crowd
## the deck (which grows wings for them). `alternating`: ONE panel both players take turns on, in the
## middle, and a START for the second player beside it.
static func layout_panels(kind: String, players: int, buttons: int, alternating: bool = false) -> Array:
	var n := clampi(players, 1, MAX_PANELS)
	var w := panel_width(kind, buttons)
	var out: Array = []
	if alternating or n == 1:
		var only := panel(kind, buttons, 0.0, 0)
		out.append(only)
		if alternating:
			only["label"] = "1P"
			out.append({"kind": "start", "start_x": panel_extent(only).y + 0.05, "player": 1, "label": "2P"})
		return out
	var pitch := maxf(PANEL_PITCH, w + 0.0175) if n == 2 else maxf(PANEL_PITCH_MULTI, w + PANEL_GAP)
	for i in n:
		out.append(panel(kind, buttons, (float(i) - float(n - 1) * 0.5) * pitch, i))
	return out


## The coin doors' x for `count` doors on a body `inner_width` wide between its sides.
static func coin_xs(count: int, inner_width: float) -> Array:
	var n := clampi(count, 1, MAX_COIN_DOORS)
	var pitch := COIN_PITCH[n - 1] * inner_width / 0.62
	var out: Array = []
	for i in n:
		out.append((float(i) - float(n - 1) * 0.5) * pitch)
	return out


## The class of the tube a game's cabinet had: the table's (19 inches before 1985, else 25), and for the kinds
## of cabinet built around a big screen, that body's own (0 = the shape's tube as it is drawn).
static func screen_inches(profile: ArcadeGameProfile) -> int:
	match profile.form():
		ArcadeGameProfile.FORM_GUN, ArcadeGameProfile.FORM_GUN_MOUNTED, ArcadeGameProfile.FORM_RIFLE, \
				ArcadeGameProfile.FORM_DANCE, ArcadeGameProfile.FORM_PUMP, ArcadeGameProfile.FORM_RACE, \
				ArcadeGameProfile.FORM_BIKE, ArcadeGameProfile.FORM_CYCLE, \
				ArcadeGameProfile.FORM_SKATE, ArcadeGameProfile.FORM_SNOW, ArcadeGameProfile.FORM_SKI:
			return 0
	return profile.monitor_inches()


## The upright-family body whose glass holds a tube of this class (25 inch = the upright's own): the upright while it fits with its black round it,
## else the tall one.
static func class_shape(inches: int) -> String:
	var up: Dictionary = shapes()["upright"]
	var native: Vector2 = up["tube"]
	var tube := native * (float(inches) / float(up.get("inches", 25)))
	return "upright" if tube.y <= glass_limits(up, 9.0).y + 0.001 else "tall"


## The body and the tube a WIDE upright gets: the upright's own 0.44 m tube is the right size for a 0.66 m body and
## a postage stamp in a 1.2 m one, so a picture takes PICTURE_SHARE of the body's width (never less than the
## upright's, never more than the tall glass holds). Up to what the upright's glass holds with its black round the
## picture (0.46 m wide) the body stays the upright; past it the `tall` body's longer glass is used.
## {"shape", "inches"}, the class being relative to that shape's own tube, or {} for a body the upright's tube
## already suits.
static func wide_picture(width: float) -> Dictionary:
	var shapes_ := shapes()
	var up: Dictionary = shapes_["upright"]
	var tall: Dictionary = shapes_["tall"]
	var up_tube: Vector2 = up["tube"]
	var tall_tube: Vector2 = tall["tube"]
	var up_glass := ((up["glass_b"] as Vector2) - (up["glass_a"] as Vector2)).length() - GLASS_FRAME
	var tall_glass := ((tall["glass_b"] as Vector2) - (tall["glass_a"] as Vector2)).length() - GLASS_FRAME
	var aspect := up_tube.y / up_tube.x
	var wanted := width * PICTURE_SHARE
	if wanted <= up_tube.x + 0.005:
		return {}
	if wanted * aspect <= up_glass:
		return {"shape": "upright", "inches": roundi(float(up["inches"]) * wanted / up_tube.x)}
	wanted = minf(wanted, tall_glass / (tall_tube.y / tall_tube.x))
	return {"shape": "tall", "inches": roundi(float(tall["inches"]) * wanted / tall_tube.x)}


## The most picture a shape's glass holds at a body width: the width between the body's sides less GLASS_SIDES, and the length of
## the slanted edge less GLASS_FRAME. `shape_row` is a row of shapes().
static func glass_limits(shape_row: Dictionary, inner_width: float) -> Vector2:
	var edge := (shape_row["glass_b"] as Vector2) - (shape_row["glass_a"] as Vector2)
	return Vector2(inner_width - GLASS_SIDES, edge.length() - GLASS_FRAME)


## The tube a screen spec asks for, metres: the shape's own tube (`native`, a tube of class `native_inches`) scaled to the game's
## class, stood on its side for a vertical game, several side by side for a game with several screens, and made to fit the glass the
## shape has (scaled down whole, never squashed). `screen` = {"inches": class (absent: the shape's own), "vertical": bool,
## "screens": n, "aspect": the frame's width over its height}. A game of several screens whose layout is known (`aspect`, the table's
## `c`) gets n screens' worth of glass in the shape of the frame MAME draws them in: side by side (2.68 for two), over one another
## (0.66), a triple (4.02), a square of four (1.32); without it they stand side by side, which is what most of them do.
static func tube_for(screen: Dictionary, limits: Vector2, native: Vector2, native_inches: float) -> Vector2:
	var tube := native
	if screen.has("inches") and native_inches > 0.0:
		tube = native * (float(screen["inches"]) / native_inches)
	var n := maxi(int(screen.get("screens", 1)), 1)
	var aspect := float(screen.get("aspect", 0.0))
	if n > 1 and aspect > 0.0:
		var area := tube.x * tube.y * float(n)
		tube = Vector2(sqrt(area * aspect), sqrt(area / aspect))
	else:
		if bool(screen.get("vertical", false)):
			tube = Vector2(tube.y, tube.x)
		tube.x *= n
	var k := minf(1.0, minf(limits.x / tube.x, limits.y / tube.y))
	return tube * k


## The tube a spec's cabinet is drawn with, metres: its shape's own, or the one its `screen` asks for fitted to the glass that shape has at
## that width. What the builder lays the monitor out with, and what the tests measure.
static func tube_of(spec: Dictionary) -> Vector2:
	var sh: Dictionary = shapes()[str(spec.get("shape", "upright"))]
	var tube: Vector2 = sh["tube"]
	var screen: Dictionary = spec.get("screen", {})
	var plain: bool = not bool(screen.get("vertical", false)) and int(screen.get("screens", 1)) <= 1 and not screen.has("inches") \
			and not screen.has("aspect")
	if not screen.is_empty() and not plain:
		var inner := float(spec.get("width", sh["w"])) - 0.04
		tube = tube_for(screen, glass_limits(sh, inner), tube, float(sh.get("inches", 25)))
	return tube


## The body a game of SEVERAL screens wants (`screen` has their frame's `aspect`): the first shape of the chain from `shape` up whose
## glass is tall enough for the pictures at their class AND lets them take MULTI_SHARE of a body `width` wide (X-Men's six panels: the
## tall glass, a 40 inch class a screen), else the last of them with the pictures scaled to its glass; and a body wide enough for the
## glass to hold them. A pair side by side is 0.88 m of picture and wants a 1.0 m body, three 1.3 m; a pair over one another is a
## portrait picture that wants the tall glass (a PlayChoice-10, a Mega-Tech) and fits the usual 0.66 m. A racing cabinet's monitor housing
## has no taller glass to go to: its body widens instead. {"shape", "width", "inches"} (the class, 0 = the shape's own).
static func screens_body(screen: Dictionary, shape: String, width: float) -> Dictionary:
	var chain: Array = {"upright": ["upright", "tall"], "tate": ["tate", "tall"], "tall": ["tall"]}.get(shape, [shape])
	var result := {"shape": shape, "width": width, "inches": 0}
	for i in chain.size():
		var row: Dictionary = shapes()[chain[i]]
		var mine := screen.duplicate()
		var room := glass_limits(row, 9.0).y
		var pair := tube_for(mine, Vector2(INF, INF), row["tube"], float(row.get("inches", 25)))
		var aspect := pair.x / pair.y
		# The pictures a wide body leaves room for grow to MULTI_SHARE of it, as far as this glass is tall.
		var target := minf(MULTI_SHARE * width, room * aspect)
		if target > pair.x + 0.01:
			mine["inches"] = roundi(float(mine.get("inches", row.get("inches", 25))) * target / pair.x)
			pair = tube_for(mine, Vector2(INF, INF), row["tube"], float(row.get("inches", 25)))
		var reaches := pair.x >= minf(MULTI_SHARE * width, 9.0) - 0.01 or MULTI_SHARE * width <= pair.x
		if (pair.y <= room + 0.001 and reaches) or i == chain.size() - 1:
			var k := minf(1.0, room / pair.y)
			var need := ceilf((pair.x * k + 0.04 + GLASS_SIDES) * 100.0) / 100.0
			result = {"shape": str(chain[i]), "width": minf(maxf(width, need), maxf(width, MAX_SCREENS_BODY)),
				"inches": int(mine.get("inches", 0))}
			break
	return result


## Where the seats of a bench in front of an UPRIGHT stand, front to back (a gun ride's, in ArcadeCabinetBuilder, stand at 1.16 m, 0.7 m from a panel on the deck: too far to work its sticks):
## the cushion's front a hand's reach from the panel's, the eyes 0.6 m from the glass.
const UPRIGHT_BENCH_Z := 0.98


## How far the outer two monitors of a bank are turned in toward the player: TX-1's side screens "tilted 30 degrees" (Wikipedia, a summary; the direction is the research's guess, a bank that
## wraps round the driver). The bank is laid out by `bank_layout`.
const BANK_YAW_DEG := 30.0


## Where the three monitors of a bank stand in the monitor's own frame (+Z out of the glass, X along it, Y up it), for a whole tube of `tube` metres with `parts` of the frame (left, centre, right as
## [x, y, w, h] fractions) and `yaw_deg`: each monitor is as tall as the tube and as wide as its part is, in the picture's own shape (`frame_aspect`: width over height of the whole frame). The centre
## one stands square to the glass; each wing is hinged on a centre edge and turned in by `yaw_deg`, its outer edge toward the player; the centre is set back so the wings' outer edges are on the plane
## the picture would stand on. `{"sizes": [Vector2 x3], "x": [x of each middle], "z": [z of each middle, 0 = the plane the outer edges stand on], "yaw": [radians each], "span": width across the outer edges}`.
static func bank_layout(tube: Vector2, parts: Array, frame_aspect: float, yaw_deg: float) -> Dictionary:
	var sizes: Array = []
	for part in parts:
		var w := tube.y * frame_aspect * float(part[2]) / maxf(float(part[3]), 0.0001)
		sizes.append(Vector2(w, tube.y))
	var yaw := deg_to_rad(yaw_deg)
	var wl: float = (sizes[0] as Vector2).x
	var wc: float = (sizes[1] as Vector2).x
	var wr: float = (sizes[2] as Vector2).x
	var set_back := maxf(wl, wr) * sin(yaw)
	var xs := [-(wc * 0.5 + wl * 0.5 * cos(yaw)), 0.0, wc * 0.5 + wr * 0.5 * cos(yaw)]
	var zs := [-set_back + wl * 0.5 * sin(yaw), -set_back, -set_back + wr * 0.5 * sin(yaw)]
	return {"sizes": sizes, "x": xs, "z": zs, "yaw": [yaw, 0.0, -yaw], "set_back": set_back,
		"span": wc + wl * cos(yaw) + wr * cos(yaw)}


## The shapes a fixed gun can have besides the pistol (a spec's `gun_scene`): the scene each is built from, Tools/gen/gen_arcade_gun.gd.
const GUN_SCENES := {
	"stick": "res://Scenes/Objects/peripherals/arcade_light_stick.tscn",
	"blaster": "res://Scenes/Objects/peripherals/arcade_light_blaster.tscn",
}


## How many times the scope of a rifle game of ONE screen (Golgo 13, Silent Scope EX) magnifies the part of the picture the rifle points at. It was 2.5 and a flat
## rectangle: nothing said it magnified (Golgo 13, 2026-10-27); the lens draws a round field and a reticle now (arcade_screen.gdshader).
const SCOPE_ZOOM := 3.0


## What a scope game shows in its rifle's scope (`l`, the table): {"index", "main": the part of the frame the monitor shows, "lens": the part the
## scope shows, both as fractions of the frame [x, y, w, h], y down, "aspect": the frame's}, or {} for a game with no scope or a table with no
## layout for it. The monitor shows the other screen alone; the frame is drawn by MAME so the scope's own screen is in it and the cabinet cuts it
## out (ArcadeScreenModule). A rifle game of ONE screen has no second one to show: its scope is DIGITAL, {"zoom": SCOPE_ZOOM}: the monitor shows the whole
## picture and the lens the part of it the rifle points at, magnified (a scope that shows nothing was a dead eyepiece: Golgo 13).
static func scope_of(profile: ArcadeGameProfile) -> Dictionary:
	var index := profile.scope_screen()
	var rects := profile.screen_rects()
	if index < 0 and profile.form() == ArcadeGameProfile.FORM_RIFLE:
		return {"zoom": SCOPE_ZOOM}
	if index < 0 or index >= rects.size() or rects.size() < 2:
		return {}
	var main_index := 0 if index != 0 else 1
	var part := func(i: int) -> Array:
		var r := profile.screen_part(i)
		return [snappedf(r.position.x, 0.0001), snappedf(r.position.y, 0.0001), snappedf(r.size.x, 0.0001), snappedf(r.size.y, 0.0001)]
	return {"index": index, "main": part.call(main_index), "lens": part.call(index), "aspect": snappedf(profile.frame_aspect(), 0.001)}


## The spec a cabinet takes for the game in its bay: `base` (the cabinet's own row) with the form, the
## panels, the coin doors, the guns, the monitor and what stands in front changed to the game's
## (ArcadeGameProfile). A game the table does not know, or none, is the cabinet as it was baked.
static func for_game(base: Dictionary, profile: ArcadeGameProfile) -> Dictionary:
	var spec := base.duplicate(true)
	if profile == null or not profile.known:
		return spec
	var form := profile.form()
	var base_shape := str(base.get("shape", "upright"))
	# What every form starts from: no guns, no pedal, the cabinet's front sockets, its own body.
	spec["form"] = form
	spec["guns"] = 0
	spec["sockets"] = true
	spec.erase("gun_style")
	spec.erase("gun_pedals")
	spec.erase("gun_scene")
	spec.erase("scope_sensor")
	spec.erase("cockpit")
	spec.erase("bench")
	spec.erase("stage")
	spec.erase("bike")
	spec.erase("cycle")
	spec.erase("board")
	spec.erase("holo")
	spec.erase("deck_extra")
	spec.erase("socket_count")
	spec.erase("bays")
	var shape := base_shape
	var players: int = clampi(profile.players, 1, MAX_PANELS)
	var buttons: int = clampi(profile.buttons, 0, 6)
	var kind := panel_kind(profile)
	match form:
		ArcadeGameProfile.FORM_GUN, ArcadeGameProfile.FORM_GUN_MOUNTED, ArcadeGameProfile.FORM_RIFLE:
			shape = "wide"
			var guns := clampi(profile.gun_count() if profile.gun_count() > 0 else players, 1, MAX_GUNS)
			if form == ArcadeGameProfile.FORM_RIFLE:
				guns = 1
			spec["guns"] = guns
			spec["sockets"] = false
			spec["gun_style"] = {ArcadeGameProfile.FORM_GUN: "holster", ArcadeGameProfile.FORM_GUN_MOUNTED: "mounted",
				ArcadeGameProfile.FORM_RIFLE: "rifle"}[form]
			spec["players"] = gun_panels(guns, str(spec["gun_style"]))
			# A fixed gun that is not a pistol: Rail Chase's joystick-like one, Laser Ghost's big blaster (the table's `y`, Tools/gen/gen_arcade_gun.gd --variant=).
			if form == ArcadeGameProfile.FORM_GUN_MOUNTED and profile.control_style() in GUN_SCENES:
				spec["gun_scene"] = profile.control_style()
			# A player who also works a joystick (Gunbuster's walk): a stick and two buttons on the panel of each gun, in place of START alone.
			if profile.gun_stick():
				spec["players"] = layout_panels("stick", guns, 2)
			if profile.gun_pedal():
				spec["gun_pedals"] = gun_xs(guns, ArcadeCabinetSpecs.shapes()["wide"]["w"], str(spec["gun_style"]))
			# A rifle's scope sensor (Golgo 13): a switch on the deck by the post, wired to the MAME button the game reads it as.
			if form == ArcadeGameProfile.FORM_RIFLE and profile.scope_sensor_button() > 0:
				spec["scope_sensor"] = {"button": profile.scope_sensor_button()}
			# A ride (Rail Chase, The Lost World, Jurassic Park): a bench in front of the guns, a seat a gun, two at most, on a base that moves
			# where the game's did.
			if profile.has_seat() and form != ArcadeGameProfile.FORM_RIFLE:
				spec["bench"] = {"seats": mini(guns, 2), "motion": profile.has_motion()}
		ArcadeGameProfile.FORM_RACE:
			shape = "racer"
			spec["players"] = []
			spec["cockpit"] = {"roof": profile.has_roof(), "shifter": profile.has_shifter(), "player": 0, "motion": profile.has_motion()}
			if profile.has_helm():
				# A yoke in place of the wheel, one gas pedal in place of two, the game's own buttons on the dash.
				(spec["cockpit"] as Dictionary).merge({"helm": true, "buttons": helm_panel(profile)["buttons"]})
		ArcadeGameProfile.FORM_FLY:
			# A flight cockpit: the driving cockpit's platform, dash and seat, with a stick between the knees and a throttle by the left hand in
			# place of the wheel and the shifter; a cabin round the seat where the game's was (After Burner's), a base that moves where its was.
			shape = "racer"
			spec["players"] = []
			spec["cockpit"] = {"flight": true, "roof": profile.has_cabin(), "cabin": profile.has_cabin(), "ring": profile.has_ring(), "motion": profile.has_motion(),
				"throttle": profile.has_throttle(), "pedals": profile.has_kind(ArcadeGameProfile.KIND_PEDAL), "shifter": false, "player": 0}
		ArcadeGameProfile.FORM_RACEGUN:
			# A car with a driver and a gunner (Lucky & Wild): the driving cockpit made two seats wide, the first seat's wheel and pedal, a gun for each player in a holster on
			# the dash between the seats, and a START for the gunner beside the driver's (the cockpit's own: no deck panel on a body with no deck).
			shape = "racer"
			spec["guns"] = 2
			spec["sockets"] = false
			spec["gun_style"] = "dash"
			spec["players"] = []
			spec["cockpit"] = {"roof": false, "shifter": false, "player": 0, "motion": false, "seats": 2}
		ArcadeGameProfile.FORM_BIKE:
			shape = "racer"
			spec["players"] = []
			spec["bike"] = {"player": 0}
		ArcadeGameProfile.FORM_CYCLE:
			# A rider on a bicycle looks at a big screen at head height: the wide body's, 0.90 m of straight glass.
			shape = "wide"
			spec["players"] = []
			spec["cycle"] = {"player": 0}
		ArcadeGameProfile.FORM_SKATE, ArcadeGameProfile.FORM_SNOW, ArcadeGameProfile.FORM_SKI:
			# A rider STANDING on a rocking board (Top Skater, Alpine Surfer, Alpine Racer): the wide body's big screen at standing height, the rig on a stand in front of it, one rail
			# round the front to hold. The vehicle is the form.
			shape = "wide"
			spec["players"] = []
			spec["board"] = {"player": 0, "vehicle": form}
		ArcadeGameProfile.FORM_SLOT:
			# Two levers in one slot, each its player's: red on the left half, blue on the right (Panic Park). One
			# player's game parks the other lever at its end.
			var levers: Array = []
			for i in clampi(players, 1, 2):
				levers.append({"kind": "slot", "player": i, "slot_x": -SLOT_TRAVEL if i == 0 else SLOT_TRAVEL,
					"start_x": -SLOT_TRAVEL if i == 0 else SLOT_TRAVEL, "buttons": []})
			spec["players"] = levers
			spec["deck_extra"] = SLOT_DECK_EXTRA
		ArcadeGameProfile.FORM_MUSIC:
			# A rhythm game's own controller where one is built (beatmania's decks, pop'n's domes, GuitarFreaks' guitars, DrumMania's pads, a Taiko drum a player, Mambo a Go-Go's three drums), a
			# deck as deep as it needs; any other (IIDX, Keyboardmania) keeps the generic panels.
			var instrument := profile.instrument()
			if ArcadeInstruments.is_known(instrument):
				spec["players"] = ArcadeInstruments.panels(instrument, players)
				if ArcadeInstruments.deck_extra(instrument) > 0.0:
					spec["deck_extra"] = ArcadeInstruments.deck_extra(instrument)
				if instrument == ArcadeInstruments.GUITAR:
					# GuitarFreaks' guitars hang on the FRONT, one each side of the screen at its height: a wide body, a vertical glass, a bay a side (ArcadeCabinetSpecs.guitar_bays).
					shape = "wide"
					spec["bays"] = guitar_bays(players)
			else:
				spec["players"] = layout_panels(kind, players, buttons, profile.alternating())
		ArcadeGameProfile.FORM_STAND:
			shape = "upright"
			spec["players"] = [{"kind": "wheel", "wheel_x": 0.0, "start_x": -0.20, "player": 0,
				"shifter": profile.has_shifter(), "buttons": []}]
			if profile.has_helm():
				spec["players"] = [helm_panel(profile)]
		ArcadeGameProfile.FORM_DANCE, ArcadeGameProfile.FORM_PUMP:
			shape = "wide"
			var dancers := clampi(players, 1, 2)
			var arrows := profile.stage_arrows()
			var pads: Array = []
			for i in dancers:
				# The stage under each dancer: one in the middle, two side by side as the cabinets stood.
				var x := 0.0 if dancers == 1 else (-0.50 if i == 0 else 0.50)
				pads.append({"kind": "pad", "start_x": x * 0.44, "player": i, "stage_x": x, "arrows": arrows})
			spec["players"] = pads
			spec["stage"] = {"xs": [0.0] if dancers == 1 else [-0.50, 0.50], "arrows": arrows}
		_:
			if kind == "wheel" and not profile.steering_dial():
				# A driving game the table gives no cabinet for: the stand-up wheel.
				spec["players"] = [{"kind": "wheel", "wheel_x": 0.0, "start_x": -0.20, "player": 0,
					"shifter": profile.has_shifter(), "buttons": []}]
			else:
				spec["players"] = layout_panels(kind, players, buttons, profile.alternating())
				# A socket on the front for each player's own pad, up to the four ports a machine has.
				var panels := (spec["players"] as Array).size()
				if panels > 2 and not profile.alternating():
					spec["socket_count"] = mini(panels, 4)
				# An upright you sat at (Darius's bench-style seat): a bench in front of its deck, a seat a player, close enough to reach the panel.
				if profile.has_seat():
					spec["bench"] = {"seats": clampi(players, 1, 2), "motion": false, "seat_z": UPRIGHT_BENCH_Z}
	# A hologram cabinet is the upright with its picture standing deep in a dark stage behind the glass.
	if form == ArcadeGameProfile.FORM_HOLO:
		spec["holo"] = {"depth": HOLO_DEPTH}
	# A monitor on its side wants a taller window than the upright has: the same body with a longer glass.
	if shape == "upright" and profile.is_vertical():
		shape = "tate"
	var width := body_width(float(shapes()[shape]["w"]), spec["players"])
	if form == ArcadeGameProfile.FORM_RACEGUN:
		width = maxf(width, RACEGUN_WIDTH)
	if spec.has("bays"):
		width = GUITAR_BODY_W
	var inches := screen_inches(profile)
	if spec.has("bays"):
		# The picture fills the deck between the guitars' bays.
		inches = GUITAR_INCHES
	var several := profile.screens() > 1 and profile.frame_aspect() > 0.0 and profile.scope_screen() < 0
	# A body widened by three or more panels wants a picture to match (every upright body is 0.66 wide to begin with).
	if shape == "upright" and not several:
		var wide := wide_picture(width)
		if not wide.is_empty():
			shape = str(wide["shape"])
			inches = int(wide["inches"])
		elif inches > int(shapes()["upright"].get("inches", 25)) and not profile.is_vertical():
			# A game whose own monitor was bigger than the upright's (Panic Park's 33 inch) wants the glass that holds it, and a body
			# wide enough for it between the sides.
			shape = class_shape(inches)
			var row: Dictionary = shapes()[shape]
			var tube := (row["tube"] as Vector2) * (float(inches) / float(row.get("inches", 25)))
			width = maxf(width, ceilf((tube.x + 0.04 + GLASS_SIDES) * 100.0) / 100.0)
	# The screen(s): a scope game's monitor shows its first screen alone and the scope the second; a game of several screens, the frame MAME
	# lays them out in; any other, one picture, stood on its side for a monitor that was.
	var screen := {"vertical": profile.is_vertical(), "screens": profile.screens()}
	var scope := scope_of(profile)
	if not scope.is_empty():
		screen = {"vertical": false, "screens": 1, "scope": scope}
	elif several:
		screen["aspect"] = snappedf(profile.frame_aspect(), 0.001)
		# Three monitors whose outer two are turned toward the player (TX-1, Buggy Boy, Race Drivin' Panorama): each shows its own third of the frame.
		var bank_parts := profile.bank_parts()
		if bank_parts.size() == 3:
			var parts: Array = []
			for part in bank_parts:
				parts.append([snappedf(part.position.x, 0.0001), snappedf(part.position.y, 0.0001), snappedf(part.size.x, 0.0001), snappedf(part.size.y, 0.0001)])
			screen["bank"] = {"style": profile.bank_style(), "yaw": BANK_YAW_DEG, "parts": parts}
	if inches > 0 and inches != int(shapes()[shape].get("inches", 25)):
		screen["inches"] = inches
	if several and shape in ["upright", "tate", "tall", "racer"]:
		var body := screens_body(screen, shape, width)
		shape = str(body["shape"])
		width = float(body["width"])
		if int(body["inches"]) > 0:
			screen["inches"] = int(body["inches"])
		if int(screen.get("inches", 0)) == int(shapes()[shape].get("inches", 25)):
			screen.erase("inches")
	spec["shape"] = shape
	var sh: Dictionary = shapes()[shape]
	spec["width"] = width
	# The bay is baked with the cabinet and a form never rebuilds it: its door keeps the width the base had.
	spec["door_width"] = float(base.get("width", shapes()[base_shape]["w"])) - 0.06
	var doors := (spec["players"] as Array).size()
	if spec.has("cockpit") or spec.has("bike") or spec.has("cycle") or spec.has("board") or spec.has("stage"):
		doors = clampi(players, 1, 2)
	if profile.alternating():
		doors = 1
	doors = clampi(mini(profile.coins, maxi(doors, 1)), 1, MAX_COIN_DOORS)
	if int(spec["guns"]) >= 3:
		# A gun hangs in the middle of the front: two doors, either side of its holster.
		doors = mini(doors, 2)
		spec["coins"] = [-0.13, 0.13] if doors == 2 else [-0.13]
	elif doors == (base.get("coins", []) as Array).size() and shape == base_shape \
			and is_equal_approx(width, float(base.get("width", sh["w"]))):
		spec["coins"] = (base["coins"] as Array).duplicate()
	elif spec.has("bays"):
		# The deck between a guitar cabinet's bays holds the doors, one under each player's panel.
		spec["coins"] = panel_centres(spec["players"]) if doors >= 2 else [0.0]
	elif doors >= 3 and doors == (spec["players"] as Array).size():
		# A door under each player's panel.
		spec["coins"] = panel_centres(spec["players"])
	else:
		spec["coins"] = coin_xs(doors, width - 0.04)
	# The spec says nothing of a plain screen, so a game that changes nothing builds nothing.
	if bool(screen["vertical"]) or int(screen["screens"]) > 1 or screen.has("inches") or screen.has("scope"):
		spec["screen"] = screen
	else:
		spec.erase("screen")
	# A game that wants exactly what the cabinet already is: the cabinet's own row, untouched.
	if _same_form(spec, base):
		return base.duplicate(true)
	return spec


## The panel of a game steered by a YOKE (the table's `yhelm`, Road Blasters): the wheel panel with the yoke in place of the wheel, one gas pedal and no brake, START in the middle
## and a cap for each of the game's own buttons (`used_buttons`: "Lasers" and "Special Weapon") either side of the yoke's base, each named for its MAME button.
static func helm_panel(profile: ArcadeGameProfile) -> Dictionary:
	var used := profile.used_buttons()
	var caps: Array = []
	for k in used.size():
		var left := k < (used.size() + 1) / 2
		var slot := float(k) if left else float(k - (used.size() + 1) / 2)
		var x := (-0.20 - slot * 0.07) if left else (0.20 + slot * 0.07)
		caps.append({"n": used[k], "pos": Vector2(x, 0.0), "radius": 0.020, "color": k % 2})
	return {"kind": "wheel", "style": "helm", "wheel_x": 0.0, "start_x": 0.0, "start_y": -0.085, "player": 0,
		"shifter": false, "pedals": true, "gas_only": true, "buttons": caps}


## The panels of a gun cabinet: START alone for each gun, on the deck (two at 20 cm either side of the middle). A gun on a post stands on the deck's front edge itself: its START is
## beside the post, on the side toward the middle.
static func gun_panels(guns: int, style: String = "holster") -> Array:
	var xs: Array = [[0.0], [-0.20, 0.20], [-0.24, 0.0, 0.24]][clampi(guns, 1, MAX_GUNS) - 1]
	if style != "holster":
		xs = []
		for x: float in gun_xs(guns, ArcadeCabinetSpecs.shapes()["wide"]["w"], style):
			xs.append(x + (0.12 if x < -0.01 else -0.12))
	var out: Array = []
	for i in xs.size():
		out.append({"kind": "start", "start_x": float(xs[i]), "player": i})
	return out


## A GuitarFreaks cabinet's guitars hang on its FRONT, one each side of the screen at its height, so the picture is clear of them and a player standing at the middle of the deck has one a
## side: the deck's panels (a START and a pedal each) take GUITAR_DECK_HALF either side of the middle, a bay GUITAR_BAY_W beyond that, and the body is as wide as the two (the side panels
## inside it). A guitar's waist hangs GUITAR_BAY_Y over the floor in the bay's middle, its body standing in a cup on a shelf that juts GUITAR_BAY_Z - 0.47 m out over the deck's lip and its neck
## held by a clip on an arm out of the front panel (ArcadeCabinetBuilder `_build_bays`): the lowest end of it 0.95 m, the head 1.63 m, under the marquee. It hangs over the lip so that its cord
## drops in front of the apron: a cord hangs between its two ends, and a one at the deck's own height would hang inside the cabinet. Estimates: nothing has measured a real cabinet.
const GUITAR_DECK_HALF := 0.36
const GUITAR_BAY_W := 0.34
const GUITAR_BAY_X := GUITAR_DECK_HALF + GUITAR_BAY_W * 0.5
const GUITAR_BODY_W := 2.0 * (GUITAR_DECK_HALF + GUITAR_BAY_W) + 0.04
const GUITAR_BAY_Y := 1.16
## How far in front of the cabinet's body the guitar hangs (its centre line).
const GUITAR_BAY_Z := 0.54
## The class of tube a guitar cabinet's picture is: the one that fills the deck's width between the bays (a 4:3 picture 0.68 m wide), more than the table's 25 inch.
const GUITAR_INCHES := 38


## The bays of a guitar cabinet, the first player's on the left: `{player, x (the bay's middle, about the cabinet's), y (the guitar's waist), z, guitar (a guitar hangs there: a game of one player
## leaves the second bay empty)}`.
static func guitar_bays(players: int) -> Array:
	var out: Array = []
	for i in 2:
		out.append({"player": i, "x": -GUITAR_BAY_X if i == 0 else GUITAR_BAY_X, "y": GUITAR_BAY_Y, "z": GUITAR_BAY_Z, "guitar": i < clampi(players, 1, 2)})
	return out


## The x each gun rests at on a body `width` wide: two at its sides, three with one
## in the middle (the coin doors then stand either side of it). One gun in a holster hangs on the right (Time
## Crisis's); one on a post stands in the middle of the deck (Operation Wolf's Uzi, Silent Scope's rifle).
static func gun_xs(guns: int, width: float, style: String = "holster") -> Array:
	if style == "dash":
		return RACEGUN_GUN_XS.slice(0, clampi(guns, 1, RACEGUN_GUN_XS.size()))
	var side := width * 0.5 - 0.09
	match clampi(guns, 1, MAX_GUNS):
		1:
			return [side] if style == "holster" else [0.0]
		2:
			return [-side, side]
		_:
			return [-side, 0.0, side]


## Whether two specs build the same cabinet (the keys a form is made of; the look is the cabinet's).
static func _same_form(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("shape", "upright")) != str(b.get("shape", "upright")):
		return false
	for key in ["players", "coins", "guns", "sockets", "socket_count", "gun_style", "gun_pedals", "gun_scene", "scope_sensor", "cockpit", "bench",
			"stage", "bike", "cycle", "board", "holo", "screen", "deck_extra", "bays"]:
		if not _same_value(a.get(key), b.get(key)):
			return false
	var wa := float(a.get("width", shapes()[str(a.get("shape", "upright"))]["w"]))
	var wb := float(b.get("width", shapes()[str(b.get("shape", "upright"))]["w"]))
	return is_equal_approx(wa, wb)


## Deep equality that reads 0.1 + 0.2 as 0.3 (positions are computed).
static func _same_value(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var da := a as Dictionary
		var db := b as Dictionary
		if da.size() != db.size():
			return false
		for k: Variant in da:
			if not db.has(k) or not _same_value(da[k], db[k]):
				return false
		return true
	if a is Array and b is Array:
		var aa := a as Array
		var ab := b as Array
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _same_value(aa[i], ab[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b as Vector2)
	return typeof(a) == typeof(b) and a == b
