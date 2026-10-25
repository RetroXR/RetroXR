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
## (`k8`: eight seconds to boot). A key without them is a key of the first table and reads as it did.
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
			_index[parts[i]] = parts[0]


## How many romsets the table holds, for the tests.
static func table_size() -> int:
	_load()
	return _index.size()


func _parse(key: String) -> void:
	# p<players>c<coins>b<buttons>w<ways>:<kind>+<kind>[;<attr>...]
	var halves := key.split(":", false)
	if halves.size() != 2:
		return
	var re := RegEx.create_from_string("^p(\\d+)c(\\d+)b(\\d+)w(\\d+)$")
	var m := re.search(halves[0])
	if m == null:
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


## How long this game takes to come up from power-on before it counts a coin, in seconds of the game's
## own time: the table's estimate for its driver (`k`), else ArcadeProfiles.BOOT_SECONDS.
func boot_seconds() -> float:
	var k := str(attrs.get("k", ""))
	return float(k) if k.is_valid_float() and float(k) > 0.0 else ArcadeProfiles.BOOT_SECONDS


# ── what the cabinet looked like (the table's attributes; docs/dev/arcade.md "The cabinet follows the game") ──

## The kinds of cabinet a game came in (`t`), besides the plain upright.
const FORM_UPRIGHT := "upright"
const FORM_GUN := "gun"            ## guns on cords, hung in holsters
const FORM_GUN_MOUNTED := "gunm"   ## guns on swivel mounts (Operation Wolf's Uzi)
const FORM_RIFLE := "rifle"        ## one rifle on a mount, with a scope (Silent Scope)
const FORM_RACE := "race"          ## a sit-down driving cockpit
const FORM_STAND := "stand"        ## a stand-up driving cabinet (the wheel on the panel, pedals at its foot)
const FORM_BIKE := "bike"          ## a ride-on motorbike
const FORM_DANCE := "dance"        ## a dance stage, four arrows a player
const FORM_PUMP := "pump"          ## a dance stage, five panels a player
const FORM_MUSIC := "music"        ## a rhythm game's own controller (turntable, drums, guitar): not built yet
const FORM_ODD := "odd"            ## a unique cabinet (docs/dev/arcade.md "Unusual cabinets"): not built yet


## The kind of cabinet: one of FORM_*. A game the table does not know, or one with nothing special, is an upright.
func form() -> String:
	var t := str(attrs.get("t", ""))
	return t if known and not t.is_empty() else FORM_UPRIGHT


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


## How many light guns (players with one); touch screens are not guns (kind `touch`).
func gun_count() -> int:
	return int(str(attrs.get("g", "0"))) if known else 0


## A gun game with a foot pedal (Time Crisis: step on it to come out of cover).
func gun_pedal() -> bool:
	return known and attrs.has("f")


## A driving cockpit with a roof over the seat.
func has_roof() -> bool:
	return known and attrs.has("o")


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
	if f == FORM_GUN or f == FORM_GUN_MOUNTED or f == FORM_RIFLE:
		return true
	return has_kind(KIND_GUN) and not _wants_stick()


## A driving game: a wheel and pedals (MAME calls them a paddle and a pedal; Pole Position's wheel is a dial).
func is_driving() -> bool:
	if not known:
		return false
	var f := form()
	return f == FORM_RACE or f == FORM_STAND or (has_kind(KIND_PADDLE) and has_kind(KIND_PEDAL))


func _wants_stick() -> bool:
	for k in _STICK_KINDS:
		if kinds.has(k):
			return true
	return false


## Does player `player` (0-based) have a panel in this game? Only the first two exist.
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
	return not known or (_wants_stick() and not is_gun())


## Is cap `index` (0-based, ArcadeProfiles.BUTTON_BITS order) on player `player`'s panel?
func button_visible(player: int, index: int) -> bool:
	if is_described():
		var ids: Dictionary = _described.get(player, {})
		return ids.has(ArcadeProfiles.BUTTON_BITS[index])
	return not known or index < buttons


## The label for a cap, in the core's own words shortened to fit one, or "" when the core did not name it.
func button_label(player: int, index: int) -> String:
	var ids: Dictionary = _described.get(player, {})
	return shorten(str(ids.get(ArcadeProfiles.BUTTON_BITS[index], "")))


## How many coin doors the game has a use for: one for a one-coin game, two at most (the cabinet has two).
func coin_doors() -> int:
	return clampi(coins, 1, 2) if known else 2


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
