## ArcadeInstruments — the rhythm games' own controllers, as data: where each part of a beatmania deck, a pop'n music panel, a guitar, a drum kit, a Taiko drum or
## a Mambo a Go-Go conga stands on the control deck, and which of MAME's buttons it is.
##
## A rhythm game's cabinet (the table's `tmusic` and `i<name>`, ArcadeGameProfile.instrument()) is the upright with a panel of its own kind a player
## (ArcadeCabinetBuilder._build_instrument draws it from this table); the parts are named for the control module, `Btn1`..`Btn10` for MAME's buttons (the pad's B A Y X L R L2 R2 L3
## R3, ArcadeProfiles.BUTTON_BITS) and `DialPivot` for a turntable or a knob, so the input and a headset's fingertips need nothing of their own: a fingertip presses a key, a pad, a dome
## or a sector of a drum (ArcadePanelHands, `sector` in the hands' zones), the dial turns with LEFT and RIGHT, as every dial does.
##
## A part may sit on another: its `z` is the height of what it stands on (a fret on the neck, a sector on a drum's shell), default the deck's own.
##
## WHICH BUTTON IS WHICH is read out of MAME's driver sources (konami/djmain.cpp, ksys573.cpp, namco/namcos10.cpp, the `INPUT_PORTS_START` blocks, mame0289). WHERE a part stands, how big it is
## and what colour is the research's and an estimate: every number below is a metre on a panel (x right, y toward the monitor, up the slope) and none was measured on a real cabinet.
## docs/dev/arcade-cabinets.md "Rhythm games" says which is which.
class_name ArcadeInstruments
extends RefCounted

const DECK := "deck"      ## beatmania: a turntable and five keys a player, two players
const POPN := "popn"      ## pop'n music: nine domes in two rows, one player
const GUITAR := "guitar"  ## GuitarFreaks: a guitar a player, held (three fret buttons, a pick, a wail button, an effect knob: ArcadeGuitar), START and a pedal on the panel, two players
const DRUMS := "drums"    ## DrumMania and Percussion Freaks: five pads and a bass pedal, one player
const TAIKO := "taiko"    ## Taiko no Tatsujin: a drum a player, each side of its face and each side of its rim a zone, two players
const CONGA := "conga"    ## Mambo a Go-Go: three drums of three pads, one player

const IDS: Array[String] = [DECK, POPN, GUITAR, DRUMS, TAIKO, CONGA]

## How many players an instrument's cabinet has panels for.
const MAX_PLAYERS := {DECK: 2, POPN: 1, GUITAR: 2, DRUMS: 1, TAIKO: 2, CONGA: 1}

## How much deeper than the upright's the control deck is for an instrument (ArcadeCabinetSpecs.deepened): a drum kit and a Taiko drum want a hand's reach of deck in front of the screen.
const DECK_EXTRA := {DECK: 0.0, POPN: 0.0, GUITAR: 0.0, DRUMS: 0.20, TAIKO: 0.25, CONGA: 0.12}

## The gap between two players' panels.
const PANEL_GAP := 0.03

## What a player holds that is wired to the cabinet, by kind: the scene (Tools/gen/gen_arcade_drumstick.gd) and how long its cord is. A panel's `gear` lists where each one rests (ArcadeCabinetBuilder builds
## the cradle and the `GearRest` marker the cabinet finds them by; ArcadeGearRack spawns, cords and holsters them).
const GEAR := {
	"drumstick": {"scene": "res://Scenes/Objects/peripherals/arcade_drumstick.tscn", "cord": 0.95},
	"guitar": {"scene": "res://Scenes/Objects/peripherals/arcade_guitar.tscn", "cord": 1.6},
}

const WHITE := Color(0.93, 0.93, 0.90)
const BLACK := Color(0.13, 0.13, 0.16)
const CREAM := Color(0.92, 0.88, 0.78)
const WOOD := Color(0.45, 0.15, 0.10)


static func is_known(instrument: String) -> bool:
	return IDS.has(instrument)


static func max_players(instrument: String) -> int:
	return int(MAX_PLAYERS.get(instrument, 1))


static func deck_extra(instrument: String) -> float:
	return float(DECK_EXTRA.get(instrument, 0.0))


## The panels of a game of `players` players on `instrument`: one each, side by side, the first on the left. `{kind: "music", instrument, player, mirror, start_x, start_y, x0, x1, y0, y1,
## parts, dial, pedal}`: the extents are the panel's own x and y reach about its middle `cx` (what the body is made as wide as, ArcadeCabinetSpecs.panel_extent).
static func panels(instrument: String, players: int) -> Array:
	var n := clampi(players, 1, max_players(instrument))
	var out: Array = []
	var width := _width(instrument)
	var pitch := width + PANEL_GAP
	for i in n:
		var cx := (float(i) - float(n - 1) * 0.5) * pitch
		# The second player's deck is the first's seen in a mirror (beatmania: the turntable on the outside), their buttons keeping the order a player reads them in.
		out.append(panel(instrument, i, cx, i == 1 and mirrors(instrument)))
	return out


## Does the second player's panel stand mirrored? beatmania's does (its turntable on the outside); a Taiko drum is its own mirror, and so is a GuitarFreaks panel (START and a pedal).
static func mirrors(instrument: String) -> bool:
	return instrument == DECK


## One panel about the deck's x `cx`.
static func panel(instrument: String, player: int, cx: float, mirror: bool) -> Dictionary:
	var layout := _layout(instrument)
	var sign_x := -1.0 if mirror else 1.0
	var parts: Array = []
	for src: Dictionary in layout["parts"]:
		parts.append(_placed(src, cx, sign_x, mirror))
	var out := {
		"kind": "music", "instrument": instrument, "player": player, "mirror": mirror,
		"start_x": cx + sign_x * float(layout["start"].x), "start_y": float(layout["start"].y),
		"x0": cx + minf(sign_x * float(layout["x"].x), sign_x * float(layout["x"].y)),
		"x1": cx + maxf(sign_x * float(layout["x"].x), sign_x * float(layout["x"].y)),
		"y0": float(layout["y"].x), "y1": float(layout["y"].y),
		"parts": parts, "buttons": [],
	}
	if layout.has("dial"):
		var d: Dictionary = (layout["dial"] as Dictionary).duplicate()
		d["pos"] = Vector2(cx + sign_x * float((layout["dial"]["pos"] as Vector2).x), float((layout["dial"]["pos"] as Vector2).y))
		out["dial"] = d
	if layout.has("pedal"):
		var p: Dictionary = (layout["pedal"] as Dictionary).duplicate()
		p["x"] = cx + sign_x * float(p["x"])
		out["pedal"] = p
	if layout.has("grip_x"):
		# The part of the panel a laser or a crosshair takes as the PANEL (ArcadePanelGrip): not what lies beside it (a cradle's stick is a pickable of its own, and a box over it would hide it).
		var gx: Vector2 = layout["grip_x"]
		out["gx0"] = cx + minf(sign_x * gx.x, sign_x * gx.y)
		out["gx1"] = cx + maxf(sign_x * gx.x, sign_x * gx.y)
	if layout.has("desktop_grip"):
		# What the panel is to a MOUSE: a drum is for sticks and fingers, so in desktop mode the part of it a crosshair takes as the panel shrinks to this (ArcadePanelGrip.desktop_rect); a headset keeps the whole.
		out["desktop_grip"] = str(layout["desktop_grip"])
	if layout.has("gear"):
		var gear: Array = []
		for src: Dictionary in layout["gear"]:
			var g := src.duplicate()
			var gp: Vector2 = src["pos"]
			g["pos"] = Vector2(cx + sign_x * gp.x, gp.y)
			if mirror:
				g["side"] = 1 - int(src["side"])
			gear.append(g)
		out["gear"] = gear
	return out


## A part of the layout carried to the panel at `cx`, mirrored if the panel is: its x flips, a sector's angles with it, and the buttons of a mirrored deck keep their numbering from
## the left (the layout numbers a mirrored panel's buttons from the other end).
static func _placed(src: Dictionary, cx: float, sign_x: float, mirror: bool) -> Dictionary:
	var out := src.duplicate()
	var pos: Vector2 = src["pos"]
	out["pos"] = Vector2(cx + sign_x * pos.x, pos.y)
	if mirror and src.has("a0"):
		# A sector seen in a mirror: angle a becomes 180 - a, and its ends swap.
		var a0 := 180.0 - float(src["a1"])
		var a1 := 180.0 - float(src["a0"])
		out["a0"] = a0
		out["a1"] = a1
	if mirror and src.has("flip_button") and src.has("btn"):
		out["btn"] = int(src["flip_button"])
	return out


static func _width(instrument: String) -> float:
	var layout := _layout(instrument)
	return float((layout["x"] as Vector2).y - (layout["x"] as Vector2).x)


## The layout of one (first) player's panel, about its own middle: `x` and `y` the reach of its parts AND of its START (what the body is made as wide as and the panel's grip covers), `start` where START stands, `parts` (each {name, shape, pos, btn?, color, ...}), and
## `dial` / `pedal` where there is a turntable, a knob or a bass pedal.
static func _layout(instrument: String) -> Dictionary:
	match instrument:
		DECK:
			return _deck()
		POPN:
			return _popn()
		GUITAR:
			return _guitar()
		DRUMS:
			return _drums()
		TAIKO:
			return _taiko()
		CONGA:
			return _conga()
	return {"x": Vector2(-0.1, 0.1), "y": Vector2(-0.05, 0.05), "start": Vector2.ZERO, "parts": []}


## beatmania (konami/djmain.cpp `beatmania_btn`: BUTTON1 to BUTTON5 and a turntable for each player, START1, START2 and an EFFECT button in the middle): the first player's turntable on the
## left of its five keys, three white keys in the front row and two black ones behind them, as a piano's (the research: "5 keys, 3 white and 2 black", a zigzag). The keys are numbered
## from the left on both decks.
static func _deck() -> Dictionary:
	var parts: Array = []
	for k in 5:
		var white := k % 2 == 0
		parts.append({
			"name": "Key%d" % (k + 1), "btn": k + 1, "shape": "box", "pos": Vector2(0.053 * float(k), -0.036 if white else 0.032),
			"size": Vector2(0.042, 0.072 if white else 0.058), "h": 0.014, "color": WHITE if white else BLACK,
			# On the mirrored deck the keys are laid from the other end: its leftmost is still key 1.
			"flip_button": 6 - (k + 1),
		})
	return {
		"x": Vector2(-0.245, 0.277), "y": Vector2(-0.095, 0.095), "start": Vector2(0.262, 0.0),
		"parts": parts,
		"dial": {"pos": Vector2(-0.15, 0.0), "kind": "turntable", "radius": 0.082, "plinth": 0.092},
	}


## pop'n music (konami/djmain.cpp `popnmusic_btn`: BUTTON1 to BUTTON9): nine domes across the panel, the five of the front row (white, green, red, green, white) and the four between them behind (yellow,
## blue, blue, yellow): button 1 is the leftmost, 9 the rightmost. START, which the game does not use, stands at the left end.
static func _popn() -> Dictionary:
	var colors: Array[Color] = [
		Color(0.95, 0.95, 0.95), Color(0.98, 0.85, 0.10), Color(0.15, 0.75, 0.25), Color(0.15, 0.40, 0.95), Color(0.92, 0.12, 0.12),
		Color(0.15, 0.40, 0.95), Color(0.15, 0.75, 0.25), Color(0.98, 0.85, 0.10), Color(0.95, 0.95, 0.95)]
	var parts: Array = []
	for i in 9:
		parts.append({
			"name": "Dome%d" % (i + 1), "btn": i + 1, "shape": "dome", "pos": Vector2((float(i) - 4.0) * 0.036, -0.030 if i % 2 == 0 else 0.030),
			"radius": 0.026, "h": 0.016, "color": colors[i],
		})
	return {"x": Vector2(-0.220, 0.176), "y": Vector2(-0.058, 0.058), "start": Vector2(-0.205, 0.0), "parts": parts}


## GuitarFreaks (konami/ksys573.cpp `gtrfrks`: Button R, G and B = BUTTON1 to 3, Pick = BUTTON6, Wailing = BUTTON7, an Effect Knob a dial, a START each): the guitar is HELD gear (ArcadeGuitar, hung in
## a holster on the cabinet's front each side of the screen, ArcadeCabinetSpecs.guitar_bays), so the player's panel is START and a pedal on the floor. The pedal is the wail's (BUTTON7): MAME has no pedal
## for GuitarFreaks, the cabinet had two (one a player) by the player's say-so, and the one button a foot could work while the hands are busy is the wailing.
static func _guitar() -> Dictionary:
	return {
		"x": Vector2(-0.15, 0.15), "y": Vector2(-0.07, 0.07), "start": Vector2(0.0, 0.0), "parts": [],
		# The grip of the panel is only the START: the rest of the deck is the cabinet's, and a box over it would hide the cups and the coin doors under it from a laser.
		"grip_x": Vector2(-0.04, 0.04),
		"pedal": {"btn": 7, "x": 0.0, "z": 0.78, "color": Color(0.20, 0.20, 0.22)},
	}


## DrumMania and Percussion Freaks (konami/ksys573.cpp `drmn`: High Tom = BUTTON1, Low Tom = BUTTON2, Hi-Hat = BUTTON3, Snare = BUTTON4, Cymbal = BUTTON5, Bass Drum = BUTTON6): five pads in an arc
## and the bass drum's pedal on the floor.
static func _drums() -> Dictionary:
	var parts: Array = [
		{"name": "HiHat", "btn": 3, "shape": "dome", "pos": Vector2(-0.30, 0.02), "radius": 0.075, "h": 0.014, "color": Color(0.98, 0.85, 0.10)},
		{"name": "Snare", "btn": 4, "shape": "dome", "pos": Vector2(-0.15, -0.08), "radius": 0.085, "h": 0.014, "color": Color(0.92, 0.15, 0.15)},
		{"name": "HighTom", "btn": 1, "shape": "dome", "pos": Vector2(-0.05, 0.10), "radius": 0.070, "h": 0.014, "color": Color(0.15, 0.75, 0.25)},
		{"name": "LowTom", "btn": 2, "shape": "dome", "pos": Vector2(0.10, 0.10), "radius": 0.075, "h": 0.014, "color": Color(0.15, 0.40, 0.95)},
		{"name": "Cymbal", "btn": 5, "shape": "dome", "pos": Vector2(0.27, 0.0), "radius": 0.090, "h": 0.010, "color": Color(0.95, 0.60, 0.12)},
	]
	return {
		"x": Vector2(-0.39, 0.36), "y": Vector2(-0.18, 0.18), "start": Vector2(0.0, -0.165), "parts": parts,
		"pedal": {"btn": 6, "x": 0.10, "color": Color(0.20, 0.20, 0.22)},
	}


## Taiko no Tatsujin (namco/namcos10.cpp `taiko`: a drum a player, BUTTON1 the right rim, BUTTON2 the right face, BUTTON3 the left face, BUTTON4 the left rim; "P1R Fuchi, Men, P1L Men, Fuchi"): a drum whose
## face is two halves and whose rim is two halves, each a zone a drumstick or a finger lands in.
static func _taiko() -> Dictionary:
	var parts: Array = [
		{"name": "DrumShell", "shape": "disc", "pos": Vector2.ZERO, "radius": 0.185, "h": 0.050, "color": WOOD, "decor": true, "tilt": TAIKO_TILT, "tilt_lift": TAIKO_LIFT},
		{"name": "FaceLeft", "btn": 3, "shape": "sector", "pos": Vector2.ZERO, "r0": 0.0, "r1": 0.122, "a0": 92.0, "a1": 268.0, "h": 0.014, "z": 0.050, "color": CREAM, "tilt": TAIKO_TILT, "tilt_lift": TAIKO_LIFT, "hit_a0": 90.0, "hit_a1": 270.0, "press": TAIKO_PRESS},
		{"name": "FaceRight", "btn": 2, "shape": "sector", "pos": Vector2.ZERO, "r0": 0.0, "r1": 0.122, "a0": -88.0, "a1": 88.0, "h": 0.014, "z": 0.050, "color": CREAM, "tilt": TAIKO_TILT, "tilt_lift": TAIKO_LIFT, "hit_a0": -90.0, "hit_a1": 90.0, "press": TAIKO_PRESS},
		{"name": "RimLeft", "btn": 4, "shape": "sector", "pos": Vector2.ZERO, "r0": 0.128, "r1": 0.172, "a0": 92.0, "a1": 268.0, "h": 0.014, "z": 0.050, "color": Color(0.75, 0.10, 0.10), "tilt": TAIKO_TILT, "tilt_lift": TAIKO_LIFT, "hit_a0": 90.0, "hit_a1": 270.0, "hit_r1": TAIKO_RIM_HIT, "press": TAIKO_PRESS},
		{"name": "RimRight", "btn": 1, "shape": "sector", "pos": Vector2.ZERO, "r0": 0.128, "r1": 0.172, "a0": -88.0, "a1": 88.0, "h": 0.014, "z": 0.050, "color": Color(0.75, 0.10, 0.10), "tilt": TAIKO_TILT, "tilt_lift": TAIKO_LIFT, "hit_a0": -90.0, "hit_a1": 90.0, "hit_r1": TAIKO_RIM_HIT, "press": TAIKO_PRESS},
	]
	# A pair of drumsticks (bachi) in a cradle each side of the drum, lying along the deck with the butt toward the player and the cord leaving the butt over the deck's front edge: left stick on the left.
	var sticks: Array = []
	for side in 2:
		sticks.append({"kind": "drumstick", "side": side, "pos": Vector2(STICK_X * (-1.0 if side == 0 else 1.0), STICK_Y)})
	return {"x": Vector2(-0.31, 0.31), "y": Vector2(-0.22, 0.19), "start": Vector2(0.0, -0.205), "parts": parts, "gear": sticks, "grip_x": Vector2(-0.205, 0.205), "desktop_grip": "start"}


## A real Taiko drum is not flat: its head leans toward the player. The deck itself already slopes about 11 degrees that way, so the drum turns TAIKO_TILT degrees more about its middle (X axis) for a head about
## 26 degrees off the horizontal, a real one's. `TAIKO_LIFT` is how far the turned drum is raised off the deck: 0, so its front edge, which the turn brings down by the shell's radius times the angle's sine, is SUNK
## into the deck plate (hidden by it) and the drum stands LOWER (2026-10-29, lowered about 6 cm: it stood too high). The front zone still clears the deck (its lowest point 4 mm over it: `arcade_form_tests`). The
## zones' own frames carry the turn, so a finger, a stick's crossing and the cap sinking (`TAIKO_PRESS` along the drum's own normal) all follow it.
## Heights over the floor (the deck at its middle 0.96 m): the face's middle about 1.02 m, its far edge 1.07 m, its near edge 0.97 m. NO official figure was found for the real cabinet (a rental listing gives the whole drum
## unit 1210 mm high, a fan guide puts the head's top at about 1200 mm); the lowering is the player's judgement, so change TAIKO_LIFT / TAIKO_TILT, not the deck.
const TAIKO_TILT := 15.0
const TAIKO_LIFT := 0.0
const TAIKO_PRESS := 0.010
## What a zone answers to is a little more than what is drawn (`hit_*` in the part, read by the builder into the zone's `sector` meta; the mesh keeps its own radii and angles): the halves meet at 90 degrees, with no
## 4 degree slit between them, and the rim answers out to here, past the shell's own edge (0.185) by a stick's thickness. Drawn, the rim stops 1.3 cm short of the wood's edge: a head that came down on that
## edge hit neither a don nor a ka, a "dead zone" at the side of the drum (2026-10-29).
const TAIKO_RIM_HIT := 0.19


## Where a drumstick's grip rests in its cradle, in the panel's frame: out from the drum's middle (the shell is 0.185 from it) and forward, so the butt is a hand's width from the deck's front edge.
const STICK_X := 0.245
const STICK_Y := -0.105


## Mambo a Go-Go (konami/ksys573.cpp `mamboagg`: Left, Centre and Right Pad 1 to 3 = BUTTON1 to BUTTON9: BUTTON1 Left Pad 1, BUTTON2 Centre Pad 1, BUTTON3 Right Pad 1, BUTTON4 Left Pad 2 ... BUTTON9 Right
## Pad 3): three drums side by side, each with its top half (pad 1), its bottom-left quarter (pad 2) and its bottom-right quarter (pad 3).
static func _conga() -> Dictionary:
	var parts: Array = []
	var tints: Array[Color] = [Color(0.85, 0.30, 0.10), Color(0.95, 0.70, 0.10), Color(0.15, 0.55, 0.85)]
	for d in 3:
		var x := (float(d) - 1.0) * 0.20
		parts.append({"name": "Drum%d" % (d + 1), "shape": "disc", "pos": Vector2(x, 0.02), "radius": 0.097, "h": 0.040, "color": Color(0.30, 0.18, 0.10), "decor": true})
		parts.append({"name": "Pad%d_1" % (d + 1), "btn": d + 1, "shape": "sector", "pos": Vector2(x, 0.02), "r0": 0.0, "r1": 0.085, "a0": 2.0, "a1": 178.0, "h": 0.012, "z": 0.040, "color": tints[d]})
		parts.append({"name": "Pad%d_2" % (d + 1), "btn": d + 4, "shape": "sector", "pos": Vector2(x, 0.02), "r0": 0.0, "r1": 0.085, "a0": 182.0, "a1": 268.0, "h": 0.012, "z": 0.040, "color": tints[d].lerp(Color.WHITE, 0.25)})
		parts.append({"name": "Pad%d_3" % (d + 1), "btn": d + 7, "shape": "sector", "pos": Vector2(x, 0.02), "r0": 0.0, "r1": 0.085, "a0": 272.0, "a1": 358.0, "h": 0.012, "z": 0.040, "color": tints[d].lerp(Color.BLACK, 0.2)})
	return {"x": Vector2(-0.30, 0.30), "y": Vector2(-0.13, 0.12), "start": Vector2(0.0, -0.115), "parts": parts}


## A flat annular sector of `a0` to `a1` degrees (counter-clockwise from +x, y up the slope) between radii `r0` and `r1`, `height` thick, in the frame a cap is built in: its local Y is the panel's normal
## (up out of the deck), so a point (x, y) of the panel is (x, ., -y) there. A `r0` of 0 is a pie slice from the centre.
static func sector_mesh(r0: float, r1: float, a0: float, a1: float, height: float, steps: int = 0) -> ArrayMesh:
	var n := steps if steps > 0 else maxi(int(ceilf(absf(a1 - a0) / 8.0)), 3)
	var outline := PackedVector2Array()
	for i in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		outline.append(Vector2(cos(a), sin(a)) * r1)
	if r0 > 0.0001:
		for i in n + 1:
			var a := deg_to_rad(lerpf(a1, a0, float(i) / float(n)))
			outline.append(Vector2(cos(a), sin(a)) * r0)
	else:
		outline.append(Vector2.ZERO)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := height * 0.5
	var tris := Geometry2D.triangulate_polygon(outline)
	var area := 0.0
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		area += p.x * q.y - q.x * p.y
	for t in range(0, tris.size(), 3):
		var vs: Array[Vector3] = []
		for k in 3:
			var p := outline[tris[t + k]]
			vs.append(Vector3(p.x, half, -p.y))
		_tri(st, vs[0], vs[1], vs[2], Vector3.UP)
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var edge := q - p
		var out2 := Vector2(edge.y, -edge.x).normalized()
		if area < 0.0:
			out2 = -out2
		var normal := Vector3(out2.x, 0.0, -out2.y)
		var a := Vector3(p.x, -half, -p.y)
		var b := Vector3(q.x, -half, -q.y)
		var c := Vector3(q.x, half, -q.y)
		var d := Vector3(p.x, half, -p.y)
		_tri(st, a, b, c, normal)
		_tri(st, a, c, d, normal)
	return st.commit()


## One triangle facing `normal`: Godot's front face is the CLOCKWISE one, so the vertices are ordered with their right-handed cross product against it.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
	for v: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)
