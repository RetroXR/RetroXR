## ArcadeGameProfile — what the game in the bay needs from the cabinet.
##
## How many players and coins, how many buttons, and what kind of control: a stick, a light
## gun, a dial, a wheel with pedals. The cabinet's modules show that and no more (a one-player
## game has one panel, a two-button game two caps), so the cabinet follows the game instead of
## being one fixed panel (docs/dev/arcade.md, "The cabinet follows the game").
##
## Two sources, and the second wins where it speaks:
##  1. MAME's machine list, boiled down by Tools/arcade/gen_game_index.py into ArcadeGameTable
##     (by romset name). It covers every core, but it is MAME's idea of the game.
##  2. The core's own SET_INPUT_DESCRIPTORS (Libretro.GetInputDescriptors), which arrive once the
##     game has loaded. FBNeo describes THIS game ("Weak Punch", "Coin", exactly the ports and
##     buttons it reads); the MAME core describes the whole RetroPad for every game, which says
##     nothing, so a port that publishes all sixteen pad ids is ignored (measured with
##     Tools/cores/arcade_descriptors_probe: sf2 on fbneo 14 ids per port with names, on mame
##     all 16 and "A"/"B"/"Joy Left").
##
## A romset the table does not know (a homebrew, a prototype, a name this MAME build lacks) is
## `known == false` and leaves the cabinet exactly as it was: every panel and cap, no labels.
##
## Pure data and arithmetic: no nodes, so arcade_tests pins it without a cabinet.
class_name ArcadeGameProfile
extends RefCounted

## libretro's RETRO_DEVICE_JOYPAD.
const DEVICE_JOYPAD := 1
## A pad has this many ids (B Y SELECT START UP DOWN LEFT RIGHT A X L R L2 R2 L3 R3).
const PAD_IDS := 16
## The longest a cap label line may be, and the most lines: a cap is 31 mm across.
const LABEL_LINE := 6
const LABEL_LINES := 2

## The control kinds the table uses (gen_game_index.py).
const KIND_JOY := "joy"
const KIND_STICK := "stick"
const KIND_PADDLE := "paddle"
const KIND_PEDAL := "pedal"
const KIND_GUN := "gun"
const KIND_DIAL := "dial"
const KIND_BALL := "ball"
## Two sticks a player (Robotron, Smash TV, Battlezone's treads).
const KIND_TWIN := "twin"
## A touch screen, which MAME files as a light gun (Megatouch, the JPM quiz machines): not a gun.
const KIND_TOUCH := "touch"
const KIND_BUTTONS := "btn"

## Kinds a stick on the panel stands in for: a digital stick, an analog one, and the
## left/right a dial, a paddle or a trackball is steered with on a keyboard.
const _STICK_KINDS: Array[String] = [KIND_JOY, KIND_STICK, KIND_DIAL, KIND_PADDLE, KIND_BALL, KIND_TWIN]

static var _index: Dictionary = {}
## clone -> its parent romset (Tools/arcade/gen_game_index.py `tokens_of`).
static var _parents: Dictionary = {}
static var _loaded := false

var romset := ""
## Whether the table has this romset. An unknown one changes nothing on the cabinet.
var known := false
var players := 2
var coins := 2
var buttons := ArcadeProfiles.BUTTON_COUNT
var ways := 8
var kinds: PackedStringArray = PackedStringArray()
## The key's optional attributes after the kinds, `;`-separated, each a letter and a value
## (`r270`: the monitor's rotation). A key without them is a key of the first table and reads as it did.
var attrs: Dictionary = {}
## player -> {pad id: the core's word for it}, only for ports that describe THIS game.
var _described: Dictionary = {}


## The profile of a romset by its name ("sf2"), or an unknown one.
static func for_romset(p_romset: String) -> ArcadeGameProfile:
	_load()
	var name := p_romset.get_file().get_basename().to_lower()
	var p := ArcadeGameProfile.new()
	p.romset = name
	var key: String = _index.get(name, "")
	if not key.is_empty():
		p._parse(key)
	return p


## The profile of the game a board holds, from its file ("…/sf2.zip").
static func for_rom_path(path: String) -> ArcadeGameProfile:
	return for_romset(path.get_file().get_basename())


## The profile for a known key ("p2c2b6w8:joy"), for the tests.
static func from_key(p_romset: String, key: String) -> ArcadeGameProfile:
	var p := ArcadeGameProfile.new()
	p.romset = p_romset
	p._parse(key)
	return p


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for line in ArcadeGameTable.TABLE.split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() < 2:
			continue
		for i in range(1, parts.size()):
			# `parent=clone=clone`, `clone<parent` (a parent on another line), or a romset alone.
			var token := parts[i]
			var lt := token.find("<")
			if lt >= 0:
				var clone := token.substr(0, lt)
				_index[clone] = parts[0]
				_parents[clone] = token.substr(lt + 1)
				continue
			var names := token.split("=", false)
			for k in names.size():
				_index[names[k]] = parts[0]
				if k > 0:
					_parents[names[k]] = names[0]


## How many romsets the table holds, for the tests.
static func table_size() -> int:
	_load()
	return _index.size()


## The romset a clone is a version of ("sf2ce" is its own; "sf2ua" is "sf2"'s), or "" for a parent or a name
## the table does not know. MAME looks for a clone's artwork under its parent's name; so does ArcadeBezel.
static func parent_of(p_romset: String) -> String:
	_load()
	return str(_parents.get(p_romset.get_file().get_basename().to_lower(), ""))


func _parse(key: String) -> void:
	# p<players>c<coins>b<buttons>w<ways>:<kind>+<kind>[;<attr>...]
	var halves := key.split(":", false)
	if halves.size() != 2:
		push_warning("[Arcade] %s: malformed profile key '%s' (no single ':'): the whole panel shows" % [romset, key])
		return
	var re := RegEx.create_from_string("^p(\\d+)c(\\d+)b(\\d+)w(\\d+)$")
	var m := re.search(halves[0])
	if m == null:
		push_warning("[Arcade] %s: malformed profile key '%s' (head '%s'): the whole panel shows" % [romset, key, halves[0]])
		return
	known = true
	players = int(m.get_string(1))
	coins = int(m.get_string(2))
	buttons = int(m.get_string(3))
	ways = int(m.get_string(4))
	var tail := halves[1].split(";", false)
	kinds = PackedStringArray(tail[0].split("+", false)) if tail.size() > 0 else PackedStringArray()
	attrs.clear()
	for i in range(1, tail.size()):
		var token := tail[i]
		if not token.is_empty():
			attrs[token.substr(0, 1)] = token.substr(1)


# ── what the cabinet looked like (the table's attributes; docs/dev/arcade.md "The cabinet follows the game") ──

## The kinds of cabinet a game came in (`t`), besides the plain upright.
const FORM_UPRIGHT := "upright"
const FORM_GUN := "gun"            ## guns on cords, hung in holsters
const FORM_GUN_MOUNTED := "gunm"   ## guns on swivel mounts (Operation Wolf's Uzi)
const FORM_RIFLE := "rifle"        ## one rifle on a mount, with a scope (Silent Scope)
const FORM_RACE := "race"          ## a sit-down driving cockpit
const FORM_FLY := "fly"            ## a sit-down flight cockpit: a stick between the knees, a throttle by the left hand (After Burner II)
const FORM_RACEGUN := "racegun"    ## a sit-down cockpit of two seats: the driver's wheel and pedal and a gun for each player (Lucky & Wild)
const FORM_STAND := "stand"        ## a stand-up driving cabinet (the wheel on the panel, pedals at its foot)
const FORM_BIKE := "bike"          ## a ride-on motorbike
const FORM_CYCLE := "cycle"        ## a ride-on bicycle: a crank to pedal, bars to steer and tip (Prop Cycle)
const FORM_HOLO := "holo"          ## a hologram window: the picture floats in a dark stage (Time Traveler)
const FORM_SLOT := "slot"          ## two levers sliding in one slot (Panic Park)
const FORM_DANCE := "dance"        ## a dance stage, four arrows a player
const FORM_PUMP := "pump"          ## a dance stage, five panels a player
const FORM_MUSIC := "music"        ## a rhythm game's own controller (turntable, drums, guitar): the table's `i` says which (instrument())
const FORM_SKATE := "skate"        ## a rider standing on a skateboard deck that rocks, a rail round the front (Top Skater)
const FORM_SNOW := "snow"          ## the same on a snowboard (Alpine Surfer)
const FORM_SKI := "ski"            ## the same on a pair of skis (Alpine Racer)
const FORM_ODD := "odd"            ## a unique cabinet (docs/dev/arcade-cabinets.md, section 5): not built yet


## The kind of cabinet: one of FORM_*. A game the table does not know, or one with nothing special, is an upright.
func form() -> String:
	var t := str(attrs.get("t", ""))
	return t if known and not t.is_empty() else FORM_UPRIGHT


## Does the rider stand on a rocking board or pair of skis (the three forms ArcadeCabinetBuilder._build_board makes)?
func is_board() -> bool:
	var f := form()
	return f == FORM_SKATE or f == FORM_SNOW or f == FORM_SKI


## The main screen's rotation in degrees (0, 90, 180, 270): MAME's, for the monitor as it stood in the cabinet.
func rotation() -> int:
	return int(str(attrs.get("r", "0"))) if known else 0


## Did the monitor stand on its side (a "tate" game: Pac-Man, Galaga, most shooters of the 80s)?
func is_vertical() -> bool:
	var r := rotation()
	return r == 90 or r == 270


## How many screens the game drives (Darius three, Silent Scope two: the main one and the scope's).
func screens() -> int:
	return maxi(int(str(attrs.get("s", "1"))), 1) if known else 1


## Where the screens stand in the frame MAME draws (the table's `c`, Tools/arcade/layouts.py): each screen's rectangle in the
## layout's own units (y runs DOWN, as the picture's rows do), in screen order. Empty for a game of one screen, or one the table has no
## layout for.
func screen_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var text := str(attrs.get("c", ""))
	if not known or text.is_empty():
		return out
	for part in text.split("/", false):
		var n := part.split(",", false)
		if n.size() != 4:
			out.clear()
			return out
		out.append(Rect2(float(n[0]), float(n[1]), float(n[2]), float(n[3])))
	return out


## The whole frame in those units: every screen's rectangle together, or an empty Rect2 where the table has none.
func screen_frame() -> Rect2:
	var rects := screen_rects()
	if rects.is_empty():
		return Rect2()
	var frame := rects[0]
	for r in rects:
		frame = frame.merge(r)
	return frame


## The frame's width over its height (8.03 / 3 for two screens side by side, 4 / 6.03 for two stacked), or 0 where the table has none.
func frame_aspect() -> float:
	var frame := screen_frame()
	return frame.size.x / frame.size.y if frame.size.x > 0.0 and frame.size.y > 0.0 else 0.0


## Where screen `index` is in the frame as fractions of it (0..1 both ways, y down): the part of the picture that is that screen.
## An empty Rect2 for a screen the table does not place.
func screen_part(index: int) -> Rect2:
	var rects := screen_rects()
	var frame := screen_frame()
	if index < 0 or index >= rects.size():
		return Rect2()
	var r := rects[index]
	return Rect2((r.position.x - frame.position.x) / frame.size.x, (r.position.y - frame.position.y) / frame.size.y,
		r.size.x / frame.size.x, r.size.y / frame.size.y)


## How the game's three screens stand (the table's `d`): "fan" is three monitors side by side whose outer two are turned in toward the player (TX-1's, Buggy Boy's, Race Drivin' Panorama's), "" is the
## one wide glass every other game of several screens is drawn with.
func bank_style() -> String:
	return str(attrs.get("d", "")) if known else ""


## The parts of the frame a bank's three monitors show, LEFT, CENTRE, RIGHT (fractions of the frame, y down): the three screens' own parts put in the order they stand in the frame, which
## is not the order MAME numbers them in (Race Drivin' Panorama's first is the middle one). Empty unless the game is a bank of three the table places.
func bank_parts() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if bank_style().is_empty() or screens() != 3 or screen_rects().size() != 3:
		return out
	for i in 3:
		out.append(screen_part(i))
	out.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.get_center().x < b.get_center().x)
	return out


## The screen that is a scope's own (Silent Scope's, `l`, the lens): the cabinet shows it in the rifle's scope and the monitor shows the other.
## -1 for a game with none.
func scope_screen() -> int:
	return int(str(attrs.get("l", "-1"))) if known and attrs.has("l") else -1


## Whether the stacked screens of this game stand over one another rather than side by side (a PlayChoice-10, a Mega-Tech): a frame taller
## than it is wide.
func screens_stacked() -> bool:
	var aspect := frame_aspect()
	return aspect > 0.0 and aspect < 1.0


## How many light guns (players with one); touch screens are not guns (kind `touch`).
func gun_count() -> int:
	return int(str(attrs.get("g", "0"))) if known else 0


## What the gun game's extra switch is (the table's `f`): "cover" (Time Crisis' foot pedal: DOWN while the player is out of cover), "action" (Virtua Cop 3's: UP until the
## player steps on it for the ES mode) or "sensor" (a rifle's scope switch: DOWN while the player has an eye to the scope, Golgo 13's); "" for a game with none.
func pedal_kind() -> String:
	if not known or not attrs.has("f"):
		return ""
	var v := str(attrs["f"])
	if v.begins_with("s"):
		return "sensor"
	return "action" if v == "a" else "cover"


## A gun game with a foot pedal on the floor (Time Crisis: step on it to come out of cover; Virtua Cop 3: step on it for the ES mode).
func gun_pedal() -> bool:
	var kind := pedal_kind()
	return kind == "cover" or kind == "action"


## A rifle's scope sensor, as the MAME button number it is (Golgo 13's "Sensor" is button 2, Juusei no Requiem's "Scope Sensor" button 3); 0 for a game with none.
func scope_sensor_button() -> int:
	return int(str(attrs["f"]).substr(1)) if pedal_kind() == "sensor" else 0


## The game's steering is a YOKE that only turns (the table's `yhelm`: Road Blasters'), not a wheel: two grips on a bar, a hand on each.
func has_helm() -> bool:
	return known and str(attrs.get("y", "")) == "helm"


## The MAME buttons the game uses where they are not 1..N (the table's `u`: Road Blasters' 2 and 3, "Lasers" and "Special Weapon"), or [] for the usual run from 1.
func used_buttons() -> Array[int]:
	var out: Array[int] = []
	if known and attrs.has("u"):
		for c in str(attrs["u"]):
			out.append(int(c))
	return out


## A gun game whose player also works a joystick (the table's `j`; Gunbuster's: the stick walks and strafes while the gun aims): each gun's panel has a stick and two buttons,
## which reach the core on the gun's port as the joypad's.
func gun_stick() -> bool:
	return known and attrs.has("j")


## The game reads a service / test switch (MAME's `<input service="yes">`, the table's `v`): the cabinet shows the
## TEST and SERVICE switches in its compartment (ArcadeServiceModule), and takes them away for a game that reads none.
func has_service() -> bool:
	return known and attrs.has("v")


## The game has a Timekeeper chip (a battery RAM and a clock) whose memory it checks and may reject (Silent Scope: BACKUP DATA ERROR): the table's `b`.
## "h" when the image the chip is seeded from is hand built or missing, "g" when it is a good dump, "n" when there is none, "" for a game with no such
## chip (docs/dev/arcade-backup-memory.md, ArcadeBackupMemory).
func backup_class() -> String:
	return str(attrs.get("b", "")) if known else ""


func has_backup_memory() -> bool:
	return not backup_class().is_empty()


## The game's dial is a steering WHEEL with no pedals (the table's `h`): Bad Lands', where MAME calls the wheel a dial and the gas is a button. Its panel is a
## wheel for each player.
func steering_dial() -> bool:
	return known and attrs.has("h")


## How many arrows a dancer's stage has: the table's `n` where it is not four (DDR Solo's six), else four, and five for Pump It Up.
func stage_arrows() -> int:
	var n := str(attrs.get("n", ""))
	if known and n.is_valid_int():
		return clampi(int(n), 4, 6)
	return 5 if form() == FORM_PUMP else 4


## Which rhythm game's own controller a `music` cabinet has (the table's `i`): "deck" (beatmania: five keys and a turntable a player), "popn" (pop'n music's nine
## buttons), "guitar" (GuitarFreaks' two guitars), "drums" (DrumMania's pads and bass pedal), "taiko" (a Taiko drum a player), "conga" (Mambo a Go-Go's three drums), or
## "" for a rhythm game with none of them built.
func instrument() -> String:
	return str(attrs.get("i", "")) if known and form() == FORM_MUSIC else ""


## A driving cockpit with a roof over the seat.
func has_roof() -> bool:
	return known and attrs.has("o")


## What the game's sit-down version was built with (the table's `q`, Tools/arcade/cockpits.py SEATING): a seat you sit in, a cabin round it
## (a canopy, side panels), a base that moves with the play. MAME's Cabinet DIP names these versions ("Moving Deluxe", "Cockpit"); the cabinet
## is the sit-down one, whatever the DIP is set to.
func has_seat() -> bool:
	return known and str(attrs.get("q", "")).contains("s")


func has_cabin() -> bool:
	return known and str(attrs.get("q", "")).contains("c")


func has_motion() -> bool:
	return known and str(attrs.get("q", "")).contains("m")


## The cockpit is Sega's R-360 pod (the table's `r`, G-LOC R360 and Wing War R360): a sphere hung in rings that turn, where another cockpit has a cabin.
func has_ring() -> bool:
	return known and str(attrs.get("q", "")).contains("r")


## What the game's controller looks like when it is not a ball on a stick (the table's `y`, Tools/arcade/gen_game_index.py STYLE): "yoke" (Star Wars, Red Baron) or "rod" (Bass Fishing), else "".
func control_style() -> String:
	return str(attrs.get("y", "")) if known else ""


## The game reads a throttle lever (the table's `z`: an `IPT_AD_STICK_Z` of its own in MAME's driver, Tools/arcade/cockpits.py).
func has_throttle() -> bool:
	return known and attrs.has("z")


## Two players taking turns on ONE panel (the upright of an alternating game: Pac-Man, Donkey Kong).
func alternating() -> bool:
	return known and attrs.has("a")


## The monitor's class in inches: 19 for the early games, else 25 (a gun or driving cabinet's own is bigger,
## which is the cabinet's to say: ArcadeCabinetSpecs.screen_inches).
func monitor_inches() -> int:
	var m := str(attrs.get("m", ""))
	return int(m) if known and m.is_valid_int() else 25


## Take the core's own description of its inputs (Libretro.GetInputDescriptors: an Array of
## {port, device, index, id, description}). A port that publishes the whole pad is ignored.
func apply_descriptors(descriptors: Array) -> void:
	_described.clear()
	var by_port: Dictionary = {}
	for d: Variant in descriptors:
		var row := d as Dictionary
		if row == null or int(row.get("device", -1)) != DEVICE_JOYPAD:
			continue
		var id := int(row.get("id", -1))
		if id < 0 or id >= PAD_IDS:
			continue
		var port := int(row.get("port", 0))
		if not by_port.has(port):
			by_port[port] = {}
		(by_port[port] as Dictionary)[id] = str(row.get("description", ""))
	for port: int in by_port:
		if (by_port[port] as Dictionary).size() < PAD_IDS:
			_described[port] = by_port[port]


## Forget what the core said (it stopped): back to the table alone.
func clear_descriptors() -> void:
	_described.clear()


func is_described() -> bool:
	return not _described.is_empty()


func has_kind(kind: String) -> bool:
	return kinds.has(kind)


## A gun game: the panel has no stick, the gun is the control. A positional gun on a mount reads like an
## analog stick to MAME (Terminator 2), which the table's form says is a gun all the same.
func is_gun() -> bool:
	if not known:
		return false
	var f := form()
	if f == FORM_GUN or f == FORM_GUN_MOUNTED or f == FORM_RIFLE or f == FORM_RACEGUN:
		return true
	return has_kind(KIND_GUN) and not _wants_stick()


## A gun game whose control MAME files as an analog stick, not a light gun (Silent Scope's yaw and pitch, Terminator 2's and
## Operation Thunderbolt's aim, Alien3, Jurassic Park, Gunblade NY). libretro-mame binds an AD stick to the pad's LEFT stick and a
## light gun to the light-gun device alone, so the gun's aim also goes out as the left stick (ArcadeInput._gun_axes).
func aims_as_stick() -> bool:
	return is_gun() and has_kind(KIND_STICK)


## The gear lever the game has (the table's `x`, read from the driver sources by Tools/arcade/shifters.py): {} for none (an automatic, an H
## pattern a lever of two positions cannot say, a game the sources say nothing of: the cabinet draws no lever),
## `{"button": n, "toggle": bool}` for a two-position shifter on MAME's button n (1-6, ArcadeProfiles.button_bit): one MAME makes a toggle flips the gear
## at every press (the lever taps the button at every change), one it does not is held for as long as the lever is high; and `{"up": n, "down": m}` for a
## sequential box on two buttons (the lever taps `up` going high and `down` going low).
func shifter() -> Dictionary:
	var x := str(attrs.get("x", ""))
	if not known or x.length() < 2:
		return {}
	if x[0] == "s" and x.length() == 3 and x[1].is_valid_int() and x[2].is_valid_int():
		return {"up": int(x[1]), "down": int(x[2])}
	if x.length() == 2 and x[0].is_valid_int() and (x[1] == "t" or x[1] == "h"):
		return {"button": int(x[0]), "toggle": x[1] == "t"}
	return {}


func has_shifter() -> bool:
	return not shifter().is_empty()


## A driving game: a wheel and pedals (MAME calls them a paddle and a pedal; Pole Position's wheel is a dial).
func is_driving() -> bool:
	if not known:
		return false
	var f := form()
	return f == FORM_RACE or f == FORM_RACEGUN or f == FORM_STAND or (has_kind(KIND_PADDLE) and has_kind(KIND_PEDAL))


func _wants_stick() -> bool:
	for k in _STICK_KINDS:
		if kinds.has(k):
			return true
	return false


## Does player `player` (0-based) have a panel in this game?
func panel_visible(player: int) -> bool:
	if is_described():
		return _described.has(player)
	return not known or player < players


## Is there a stick on the panels? A dial, paddle or trackball game keeps it (left and right
## steer those); a gun, button-only or pedal-only game does not.
func stick_visible() -> bool:
	if is_described():
		var any := false
		for ids: Dictionary in _described.values():
			for bit in [ControllerBindings.JOYPAD_UP, ControllerBindings.JOYPAD_DOWN,
					ControllerBindings.JOYPAD_LEFT, ControllerBindings.JOYPAD_RIGHT]:
				any = any or ids.has(bit)
		return any
	return not known or (_wants_stick() and (not is_gun() or gun_stick()))


## Is cap `index` (0-based, ArcadeProfiles.BUTTON_BITS order) on player `player`'s panel?
func button_visible(player: int, index: int) -> bool:
	if is_described():
		var ids: Dictionary = _described.get(player, {})
		return ids.has(ArcadeProfiles.BUTTON_BITS[index])
	# A rhythm game's controller is built with the buttons it has: none of its caps is left out for the table's count of them (GuitarFreaks' pick is button 6 and its wail 7 of 5).
	if known and form() == FORM_MUSIC and not instrument().is_empty():
		return true
	if known and attrs.has("u"):
		return (index + 1) in used_buttons()
	return not known or index < buttons


## The label for a cap, in the core's own words shortened to fit one, or "" when the core did not name it.
func button_label(player: int, index: int) -> String:
	var ids: Dictionary = _described.get(player, {})
	return shorten(str(ids.get(ArcadeProfiles.BUTTON_BITS[index], "")))


## How many coin doors the game has a use for: one for a one-coin game, up to four (a four-player game's).
## A cabinet that keeps its own form shows those of its doors (ArcadeCabinetSpecs.for_game builds them).
func coin_doors() -> int:
	return clampi(coins, 1, ArcadeCabinetSpecs.MAX_COIN_DOORS) if known else 2


## The core's word for the coin input, or "" (FBNeo says "Coin" for pad id 2: what the cabinet
## has always sent). Only used to confirm it in the probe and the tests.
func coin_word(player: int = 0) -> String:
	var ids: Dictionary = _described.get(player, {})
	return str(ids.get(ArcadeProfiles.COIN_BIT, ""))


## A core's name for a button cut to a cap: at most LABEL_LINES lines of LABEL_LINE letters,
## the words on their own lines ("Medium Punch" -> "Medium\nPunch"). Nothing gives "".
static func shorten(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for w in words:
		if lines.size() >= LABEL_LINES:
			break
		lines.append(w.substr(0, LABEL_LINE))
	return "\n".join(lines)


func summary() -> String:
	return "%s known=%s players=%d coins=%d buttons=%d ways=%d kinds=%s described=%s" % [
		romset, known, players, coins, buttons, ways, ",".join(kinds), is_described()]
