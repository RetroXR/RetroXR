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
## STRAIGHT (vertical, flush with the front), a 0.72 x 0.54 tube (half as wide again as the upright's: a
## 29 inch tube was the usual, a 50 inch projection the big one). A gun held at arm's length in front of a
## small screen walks into it; this one leaves room. Side silhouettes are (z, y), front +z. `inches` is
## the class of the tube the body is drawn with (a CRT's picture is about 87% of its class): a game's
## own monitor is sized against it (ArcadeCabinetBuilder.tube_for).
static func shapes() -> Dictionary:
	return {
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
		# The sit-down driving cabinet's monitor housing: the same lower body (the bay, the coin doors), then a
		# short dash lip and a monitor leaning back 25 degrees, lower than an upright's so a SEATED driver looks
		# into it (its middle at about 1.1 m). The seat, the wheel and the pedals are the cockpit in front of
		# it (ArcadeCabinetBuilder._build_cockpit), clear of the bay door's swing.
		"racer": {
			"w": 0.66, "h": 1.56, "tube": Vector2(0.48, 0.36), "inches": 27,
			"profile": [
				Vector2(-0.40, 0.00), Vector2(0.34, 0.00), Vector2(0.34, 0.09), Vector2(0.40, 0.09),
				Vector2(0.40, 0.78), Vector2(0.50, 0.80), Vector2(0.50, 0.86), Vector2(0.38, 0.88),
				Vector2(0.16, 1.36), Vector2(0.24, 1.36), Vector2(0.24, 1.56), Vector2(-0.40, 1.56),
			],
			"glass_a": Vector2(0.38, 0.88), "glass_b": Vector2(0.16, 1.36),
			"deck_a": Vector2(0.50, 0.86), "deck_b": Vector2(0.38, 0.88),
			"top": [0.64, -0.08],
			"marquee": {"y": 1.46, "h": 0.20, "z": 0.234, "trim_y": 1.359, "under": [0.08, 1.354, 0.20]},
			"marquee_bottom": 1.36, "glass_back_z": 0.11, "marquee_front_z": 0.24, "screen_front_z": 0.40,
		},
	}


## The shipped cabinets, by the name gen_arcade_cabinet.gd bakes them under (`--variant=`): the look
## (body, trim, marquee), the bay kind, a panel per player (`stick` with N buttons, `dial`, or `start`
## alone), the coin doors' x, whether it has front pad sockets or guns in holsters, and whether a pedal
## is drawn.
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
			"players": two_stick, "coins": [-0.14, 0.14], "sockets": true, "guns": 0, "pedal": false,
		},
		# Twin-gun shooter: no stick, no buttons but START, a gun on each side in a holster with its
		# cord going into the cabinet, and a foot pedal on the floor (player 1's button 2).
		"lightgun": {
			"out": "arcade_cabinet_lightgun.tscn", "title": "SHOOTING", "bay": "jamma",
			"shape": "wide",
			"body": Color(0.10, 0.10, 0.12), "trim": Color(0.95, 0.60, 0.05),
			"marquee": Color(0.80, 0.10, 0.10), "glow": Color(1.0, 0.25, 0.20),
			"players": [{"kind": "start", "player": 0, "start_x": -0.20}, {"kind": "start", "player": 1, "start_x": 0.20}],
			"coins": [-0.20, 0.20], "sockets": false, "guns": 2, "pedal": true,
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
			"coins": [-0.14, 0.14], "sockets": true, "guns": 0, "pedal": false,
		},
		# Laserdisc (Dragon's Lair): one stick and the sword button.
		"daphne": {
			"out": "arcade_cabinet_daphne.tscn", "title": "LASER", "bay": "laserdisc",
			"body": Color(0.12, 0.07, 0.20), "trim": Color(0.95, 0.75, 0.15),
			"marquee": Color(0.20, 0.35, 0.85), "glow": Color(0.4, 0.55, 1.0),
			"players": [{"kind": "stick", "player": 0, "stick_x": -0.13, "start_x": -0.03,
				"buttons": [{"pos": Vector2(0.06, 0.020), "radius": 0.027, "color": 0}]}],
			"coins": [0.0], "sockets": true, "guns": 0, "pedal": false,
		},
		# The laserdisc shooters (Mad Dog McCree and its kin): guns instead of a stick.
		"daphne_gun": {
			"out": "arcade_cabinet_daphne_gun.tscn", "title": "LASER GUN", "bay": "laserdisc",
			"body": Color(0.12, 0.07, 0.20), "trim": Color(0.95, 0.75, 0.15),
			"shape": "wide",
			"marquee": Color(0.20, 0.35, 0.85), "glow": Color(0.4, 0.55, 1.0),
			"players": [{"kind": "start", "player": 0, "start_x": -0.20}, {"kind": "start", "player": 1, "start_x": 0.20}],
			"coins": [-0.20, 0.20], "sockets": false, "guns": 2, "pedal": false,
		},
		# Discrete-logic games (Pong, Breakout): a paddle dial each and START.
		"dice": {
			"out": "arcade_cabinet_dice.tscn", "title": "DICE", "bay": "discrete",
			"body": Color(0.22, 0.13, 0.07), "trim": Color(0.90, 0.85, 0.70),
			"marquee": Color(0.10, 0.10, 0.10), "glow": Color(0.9, 0.9, 0.9),
			"players": [{"kind": "dial", "player": 0, "dial_x": -0.17, "start_x": -0.07},
				{"kind": "dial", "player": 1, "dial_x": 0.17, "start_x": 0.07}],
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


# ── the game's cabinet ───────────────────────────────────────────────────────
#
# A cabinet that follows the game in its bay builds the parts its game had (RetroSystemModelArcadeCabinet.
# morph_to): the panels, the coin doors, the guns, the monitor, the cockpit or the stage. `for_game` turns a
# cabinet's own row and the game's profile into that spec; the look (body colour, trim, marquee, title) and
# the bay are the cabinet's and never change.

## The most panels a deck takes (X-Men's six players), and the most coin doors on a coin face.
const MAX_PANELS := 6
const MAX_COIN_DOORS := 4
## The most guns a gun cabinet carries (Beast Busters had three).
const MAX_GUNS := 3
## The pitch between two players' panels on a two-player deck (the generic cabinet's), the gap left between
## two panels that crowd a wider deck, and how far a panel's stick stands in from its left edge.
const PANEL_PITCH := 0.31
const PANEL_GAP := 0.03
const STICK_IN := 0.04625
## A button column's pitch, and the first column's distance from the stick.
const COLUMN_PITCH := 0.06
const FIRST_COLUMN := 0.08
## The pitch of the coin doors by how many there are (1 to 4), on the upright's 0.62 m coin face.
const COIN_PITCH: Array[float] = [0.0, 0.28, 0.18, 0.14]


## The x a panel's parts reach on the deck, (left, right): what the deck must be wide enough for and what the
## panel's grip covers (ArcadeCabinetBuilder._build_player).
static func panel_extent(panel: Dictionary) -> Vector2:
	var start_x := float(panel["start_x"])
	var left := start_x - 0.02
	var right := start_x + 0.02
	match str(panel["kind"]):
		"stick", "twin":
			left = minf(left, float(panel["stick_x"]) - 0.045)
			right = maxf(right, float(panel["stick_x"]) + 0.045)
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


## The kind of panel a game's controls want: two sticks, a trackball, a paddle dial, buttons alone, or a stick.
## A dial or paddle with a pedal is a driving game's wheel (`wheel`, on a stand-up panel).
static func panel_kind(profile: ArcadeGameProfile) -> String:
	if profile == null or not profile.known:
		return "stick"
	if profile.has_kind(ArcadeGameProfile.KIND_TWIN):
		return "twin"
	if profile.has_kind(ArcadeGameProfile.KIND_BALL):
		return "ball"
	var steering := profile.has_kind(ArcadeGameProfile.KIND_DIAL) or profile.has_kind(ArcadeGameProfile.KIND_PADDLE)
	if steering and profile.has_kind(ArcadeGameProfile.KIND_PEDAL):
		return "wheel"
	if steering:
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
		_:
			var sx := left + STICK_IN
			out["kind"] = "stick"
			out["stick_x"] = sx
			out["buttons"] = button_grid(buttons, sx + FIRST_COLUMN)
			out["start_x"] = under.call(sx + FIRST_COLUMN) if columns > 0 else sx + 0.065
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
	var pitch := maxf(PANEL_PITCH, w + 0.0175) if n == 2 else w + PANEL_GAP
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
		ArcadeGameProfile.FORM_GUN, ArcadeGameProfile.FORM_RIFLE, ArcadeGameProfile.FORM_DANCE, \
				ArcadeGameProfile.FORM_PUMP, ArcadeGameProfile.FORM_RACE, ArcadeGameProfile.FORM_BIKE:
			return 0
	return profile.monitor_inches()


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
	spec["pedal"] = false
	spec["sockets"] = true
	spec.erase("gun_style")
	spec.erase("gun_pedals")
	spec.erase("cockpit")
	spec.erase("stage")
	spec.erase("bike")
	spec.erase("socket_count")
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
			if profile.gun_pedal():
				spec["gun_pedals"] = gun_xs(guns, ArcadeCabinetSpecs.shapes()["wide"]["w"], str(spec["gun_style"]))
		ArcadeGameProfile.FORM_RACE:
			shape = "racer"
			spec["players"] = []
			spec["cockpit"] = {"roof": profile.has_roof(), "shifter": buttons >= 1, "player": 0}
		ArcadeGameProfile.FORM_BIKE:
			shape = "racer"
			spec["players"] = []
			spec["bike"] = {"player": 0}
		ArcadeGameProfile.FORM_STAND:
			shape = "upright"
			spec["players"] = [{"kind": "wheel", "wheel_x": 0.0, "start_x": -0.20, "player": 0,
				"shifter": buttons >= 1, "buttons": []}]
		ArcadeGameProfile.FORM_DANCE, ArcadeGameProfile.FORM_PUMP:
			shape = "wide"
			var dancers := clampi(players, 1, 2)
			var arrows := 5 if form == ArcadeGameProfile.FORM_PUMP else 4
			var pads: Array = []
			for i in dancers:
				# The stage under each dancer: one in the middle, two side by side as the cabinets stood.
				var x := 0.0 if dancers == 1 else (-0.50 if i == 0 else 0.50)
				pads.append({"kind": "pad", "start_x": x * 0.44, "player": i, "stage_x": x, "arrows": arrows})
			spec["players"] = pads
			spec["stage"] = {"xs": [0.0] if dancers == 1 else [-0.50, 0.50], "arrows": arrows}
		_:
			if kind == "wheel":
				# A driving game the table gives no cabinet for: the stand-up wheel.
				spec["players"] = [{"kind": "wheel", "wheel_x": 0.0, "start_x": -0.20, "player": 0,
					"shifter": buttons >= 1, "buttons": []}]
			else:
				spec["players"] = layout_panels(kind, players, buttons, profile.alternating())
				# A socket on the front for each player's own pad, up to the four ports a machine has.
				var panels := (spec["players"] as Array).size()
				if panels > 2 and not profile.alternating():
					spec["socket_count"] = mini(panels, 4)
	spec["shape"] = shape
	var sh: Dictionary = shapes()[shape]
	spec["width"] = float(sh["w"])
	var doors := (spec["players"] as Array).size()
	if spec.has("cockpit") or spec.has("bike") or spec.has("stage"):
		doors = clampi(players, 1, 2)
	if profile.alternating():
		doors = 1
	doors = clampi(mini(profile.coins, maxi(doors, 1)), 1, MAX_COIN_DOORS)
	if int(spec["guns"]) >= 3:
		# A gun hangs in the middle of the front: two doors, either side of its holster.
		doors = mini(doors, 2)
		spec["coins"] = [-0.13, 0.13] if doors == 2 else [-0.13]
	elif doors == (base.get("coins", []) as Array).size() and shape == base_shape:
		spec["coins"] = (base["coins"] as Array).duplicate()
	else:
		spec["coins"] = coin_xs(doors, float(sh["w"]) - 0.04)
	var inches := screen_inches(profile)
	var screen := {"vertical": profile.is_vertical(), "screens": profile.screens()}
	if inches > 0 and inches != int(sh.get("inches", 25)):
		screen["inches"] = inches
	# The spec says nothing of a plain screen, so a game that changes nothing builds nothing.
	if bool(screen["vertical"]) or int(screen["screens"]) > 1 or screen.has("inches"):
		spec["screen"] = screen
	else:
		spec.erase("screen")
	# A game that wants exactly what the cabinet already is: the cabinet's own row, untouched.
	if _same_form(spec, base):
		return base.duplicate(true)
	return spec


## The panels of a gun cabinet: START alone for each gun, on the deck (the shipped gun cabinet's two at
## 20 cm either side of the middle). A gun on a post stands on the deck's front edge itself: its START is
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


## The x each gun rests at on a body `width` wide: two at its sides (the shipped gun cabinet's), three with one
## in the middle (the coin doors then stand either side of it). One gun in a holster hangs on the right (Time
## Crisis's); one on a post stands in the middle of the deck (Operation Wolf's Uzi, Silent Scope's rifle).
static func gun_xs(guns: int, width: float, style: String = "holster") -> Array:
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
	for key in ["players", "coins", "guns", "pedal", "sockets", "socket_count", "gun_style", "gun_pedals", "cockpit",
			"stage", "bike", "screen"]:
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
