## ArcadeProfiles — the data the arcade cabinet and its boards run on.
##
## Tables and constants only, so a mod can overlay them and a test can read them
## without building a cabinet. The cabinet itself (arcade_cabinet_model.gd) and the
## modules under Scripts/Objects/arcade/ look everything up here: which systems a
## bay takes, which joypad bit a panel button is, what a coin is.
##
## The shipped tables are the base; a mod adds a bay kind through register_bay_kind
## rather than editing them, as everywhere else in the repo (docs/dev/mods.md).
class_name ArcadeProfiles
extends RefCounted

## The module contract the cabinet scenes honour (docs/dev/arcade.md). ADDITIVE
## ONLY: a module kind or a field may be added, never renamed or renumbered, and a
## cabinet that lacks an optional module is still valid.
const CONTRACT_VERSION := 1

## The registry id of the generic cabinet. PERSISTED in saved rooms and on the
## netplay wire (SystemModelRegistry ids are), so it is final.
const CABINET_MODEL_ID := "arcade_cabinet_generic"

## The JAMMA board: a bare PCB with a 56-contact comb on one edge, baked by
## Tools/gen/gen_arcade_board.gd. Every arcade ROM spawns wearing it.
const BOARD_SCENE := "res://Scenes/Objects/media/arcade_board.tscn"

## The Neo Geo MVS cartridge: a plastic cassette with the board's edge standing out of it
## (Tools/gen/gen_neogeo_cart.gd), not a bare board. Its shell's size is an estimate.
const NEOGEO_CART_SCENE := "res://Scenes/Objects/media/neogeo_cart.tscn"

# Module kinds. A module says which it is; the cabinet finds modules by TYPE and
# reads this, never a node name.
const KIND_SCREEN := &"screen"
const KIND_STICK_BUTTONS := &"stick_buttons"
const KIND_COIN := &"coin"
const KIND_BAY := &"bay"
const KIND_SOCKETS := &"sockets"
## The composite input block in the compartment (ArcadeAvInModule): a console cabled to it plays on the cabinet while the bay holds no unit.
const KIND_AV_IN := &"av_in"
## A foot pedal, wired to its player's button 2 (ArcadePedalModule): Time Crisis's.
const KIND_PEDAL := &"pedal"
## The TEST and SERVICE switches in the compartment (ArcadeServiceModule), beside the power switch's opposite.
const KIND_SERVICE := &"service"

## Bay kinds: what a bay takes. `systems` are the systemids whose boards fit. `romsets` is
## whether those systems run MAME-style romsets, i.e. are one family with `arcade` (the
## cores of one run the others' games, `core_serves_machine`): a Neo Geo MVS cabinet is its
## own system with its own cores, so it is a cabinet (`cabinet_systems`) but not part of the
## romset family (`systems`), or the generic cabinet would list the Neo Geo cores.
const BAY_JAMMA := "jamma"
const BAY_MVS := "mvs"
const BAY_LASERDISC := "laserdisc"
const BAY_DISCRETE := "discrete"
## Sega's NAOMI boards (flycast), and Sega's JVS-era cabinets that take a JAMMA board or a NAOMI: the machine is
## the system of the board seated in it (RetroSystem._follow_media_system; docs/dev/naomi-jvs.md). Not romset
## families: `arcade` is in that family through `jamma` already, and NAOMI is a system of its own.
const BAY_NAOMI := "naomi"
## The NAOMI 2 board: its own games and the NAOMI's cartridges.
const BAY_NAOMI2 := "naomi2"
const BAY_SEGA_JVS := "sega_jvs"
## The Sammy Atomiswave (flycast): a board of its own with a JAMMA edge, its game on a cartridge.
const BAY_ATOMISWAVE := "atomiswave"
const _BAYS: Dictionary = {
	"jamma": {"label": "JAMMA", "systems": ["arcade"]},
	"mvs": {"label": "Neo Geo MVS", "systems": ["neogeo"], "romsets": false},
	"laserdisc": {"label": "Laserdisc", "systems": ["daphne"], "romsets": false},
	"discrete": {"label": "Discrete logic", "systems": ["dice"], "romsets": false},
	"naomi": {"label": "NAOMI", "systems": ["naomi", "naomi2"], "romsets": false},
	"naomi2": {"label": "NAOMI 2", "systems": ["naomi2", "naomi"], "romsets": false},
	"sega_jvs": {"label": "JAMMA and NAOMI", "systems": ["arcade", "naomi", "naomi2"], "romsets": false},
	"atomiswave": {"label": "Atomiswave", "systems": ["atomiswave"], "romsets": false},
}

## Bay kinds a mod added: id -> {label, systems, romsets, owner}.
static var _mod_bays: Dictionary = {}

## Joypad bits. A player's panel: up to ten buttons, START, and the coin the gettoniera
## drops. The coin is SELECT because that is where MAME and FBNeo read it on a
## RetroPad; it is a property of the core, so it is stated once, here.
## The panels of the usual games have six (B A Y X L R, the order libretro-mame binds MAME's buttons 1 to 6 in); a rhythm game's controller has more (pop'n music's nine,
## Mambo a Go-Go's nine, GuitarFreaks' wailing is button 7), and MAME's buttons 7 to 10 are taken to be the pad's L2, R2, L3 and R3, the rest of the RetroPad (an estimate:
## nothing here has run a ten-button game on a core).
const BUTTON_COUNT := 10
const BUTTON_BITS: Array[int] = [
	ControllerBindings.JOYPAD_B, ControllerBindings.JOYPAD_A, ControllerBindings.JOYPAD_Y,
	ControllerBindings.JOYPAD_X, ControllerBindings.JOYPAD_L, ControllerBindings.JOYPAD_R,
	ControllerBindings.JOYPAD_L2, ControllerBindings.JOYPAD_R2, ControllerBindings.JOYPAD_L3, ControllerBindings.JOYPAD_R3,
]
const START_BIT := ControllerBindings.JOYPAD_START
const COIN_BIT := ControllerBindings.JOYPAD_SELECT


## The pad bit of MAME's button `n` (BUTTON1 is 1): B A Y X L R, the order libretro-mame binds them in, then L2 R2 L3 R3; -1 for one a pad has not got.
static func button_bit(n: int) -> int:
	return BUTTON_BITS[n - 1] if n >= 1 and n <= BUTTON_BITS.size() else -1


## The keyboard a cabinet plays from until the player binds one of its own: MAME's
## layout, the six buttons on the bottom row to the left (Ctrl, Alt, Space, Z, X, C; V, B, N, M for the four more of a rhythm game), START
## on 1 and the coin on 5. Applied on top of the global map only while a cabinet is
## attached (`DesktopBindings.apply_for_system`), so it never reaches a console.
## The stock map had the buttons on the numpad and the coin on Shift: a keyboard
## without a keypad could not hit the buttons at all. Keys are physical, as the rest.
const DESKTOP_KEYS: Dictionary = {
	"RETRO_JOYPAD_B": {"type": "key", "physical_keycode": KEY_CTRL, "keycode": 0},
	"RETRO_JOYPAD_A": {"type": "key", "physical_keycode": KEY_ALT, "keycode": 0},
	"RETRO_JOYPAD_Y": {"type": "key", "physical_keycode": KEY_SPACE, "keycode": 0},
	"RETRO_JOYPAD_X": {"type": "key", "physical_keycode": KEY_Z, "keycode": 0},
	"RETRO_JOYPAD_L": {"type": "key", "physical_keycode": KEY_X, "keycode": 0},
	"RETRO_JOYPAD_R": {"type": "key", "physical_keycode": KEY_C, "keycode": 0},
	# Buttons 7 to 10 (a rhythm game's): the bottom row goes on, V B N M.
	"RETRO_JOYPAD_L2": {"type": "key", "physical_keycode": KEY_V, "keycode": 0},
	"RETRO_JOYPAD_R2": {"type": "key", "physical_keycode": KEY_B, "keycode": 0},
	"RETRO_JOYPAD_L3": {"type": "key", "physical_keycode": KEY_N, "keycode": 0},
	"RETRO_JOYPAD_R3": {"type": "key", "physical_keycode": KEY_M, "keycode": 0},
	"RETRO_JOYPAD_START": {"type": "key", "physical_keycode": KEY_1, "keycode": 0},
	"RETRO_JOYPAD_SELECT": {"type": "key", "physical_keycode": KEY_5, "keycode": 0},
}

## How long a coin holds its bit. Long enough for any core to poll it across a
## frame at 60 fps, short enough never to read as a held button.
const COIN_PULSE_SECONDS := 0.10
## The quiet between two coins that go in one after the other (the escrow letting several in at once):
## a game counts a coin on the bit's EDGE, and two pulses with no gap are one long coin.
const COIN_GAP_SECONDS := 0.25

## How long a coin the cabinet is holding waits, once the core is running, before it goes in. MAME says
## nothing about when a game counts a coin and a board still running its RAM and ROM tests reads none, so
## this is ONE wait for every game, in the game's own time: there is no boot time per game, because none was
## ever measured and the table does not invent one. It errs long: a coin held a little too long is a credit
## a moment late (and START lets it in at once), one let in too early is lost. 0 lets it in on the first frame.
const COIN_WAIT_SECONDS := 4.0
## The least the core must have run before START may let a held coin in early: a frame count, so a
## START held through the switch-on does not push the coin into a board that has not started.
const COIN_MIN_FRAMES := 30
## After the held coins have gone in, START is held back this long, so the game sees the credit
## before the start (a START pressed while they were going in is sent afterwards, once).
const START_AFTER_COIN_SECONDS := 0.35


## Ids a .info file may file an arcade core under besides the tiles' own (the older MAME and
## FBAlpha cores say plain "arcade"; the CPS boards have ids of their own).
const ARCADE_ALIASES: Array[String] = ["arcade", "cps1", "cps2", "cps3", "mame", "fbneo", "hbmame"]


## `romsets` false makes the bay a CABINET's, not the romset family's (is_cabinet_system), as the
## laserdisc and discrete bays are: its systems are not offered the MAME/FinalBurn cores.
static func register_bay_kind(id: String, label: String, systems: Array, romsets: bool = true,
		owner_id: String = "") -> void:
	var canon: Array = []
	for s: Variant in systems:
		canon.append(SystemIds.canonical(str(s)))
	_mod_bays[id] = {"label": label, "systems": canon, "romsets": romsets, "owner": owner_id}
	print("[ArcadeProfiles] bay kind %s (%s) takes %s%s" % [id, label, canon,
		"" if owner_id.is_empty() else ", from " + owner_id])


## The prefix of a core's own option keys that are this romset's DIP switches, or "" for a core that keeps its DIPs
## elsewhere (MAME's are in its own menu and its cfg file). FinalBurn Neo names each `fbneo-dipswitch-<driver>-<dip>`,
## the driver being the set's name (measured: the DIP tab lists them, `RetroSystem.DIP_OPTION_MARK`).
static func dip_option_prefix(core: String, romset: String) -> String:
	if romset.is_empty():
		return ""
	if core == "fbneo":
		return "fbneo-dipswitch-%s-" % romset
	return ""


## Take back the bay kinds a mod added (ModApi.withdraw).
static func drop_mod(owner_id: String) -> void:
	for id: String in _mod_bays.keys():
		if str(_mod_bays[id].get("owner", "")) == owner_id:
			_mod_bays.erase(id)
			print("[ArcadeProfiles] bay kind %s withdrawn with %s" % [id, owner_id])


static func bay_kinds() -> Dictionary:
	var out := _BAYS.duplicate()
	out.merge(_mod_bays)
	return out


## Does a bay of this kind take this system's boards? A legacy id (`mame`, `fbneo`) is read
## through SystemIds.canonical, as everywhere: they are the one `arcade` system now.
## A NAOMI or NAOMI 2 board (each has the NAOMI's sockets, its hookup and its cartridge seat).
static func is_naomi_bay(bay_kind: String) -> bool:
	return bay_kind == BAY_NAOMI or bay_kind == BAY_NAOMI2


static func bay_accepts(bay_kind: String, systemid: String) -> bool:
	var row: Dictionary = bay_kinds().get(bay_kind, {})
	return (row.get("systems", []) as Array).has(SystemIds.canonical(systemid))


## Every systemid some bay takes that runs MAME-style romsets: the systems of the arcade
## family, whose cores serve one another's cabinets.
static func systems() -> Array:
	return _systems_of(true)


## Every systemid some bay takes, the romset family or not: the systems that play in a
## cabinet of this kind (a board, a cartridge or a disc in a bay behind a door).
static func cabinet_systems() -> Array:
	return _systems_of(false)


static func _systems_of(romsets_only: bool) -> Array:
	var out: Array = []
	for row: Dictionary in bay_kinds().values():
		if romsets_only and not bool(row.get("romsets", true)):
			continue
		for s: String in row.get("systems", []):
			if not out.has(s):
				out.append(s)
	return out


static func is_arcade_system(systemid: String) -> bool:
	return systems().has(SystemIds.canonical(systemid))


## Does this system play in a cabinet at all (arcade, Neo Geo MVS, Daphne, DICE)? Board art,
## the cabinet key layout and the missing-BIOS notice follow this; the cores a cabinet lists
## follow is_arcade_system.
static func is_cabinet_system(systemid: String) -> bool:
	return cabinet_systems().has(SystemIds.canonical(systemid))


## ── The art on a board's sticker ─────────────────────────────────────────────────────

## ScreenScraper's `box-texture` is the whole box laid flat (back, spine, front), and for an
## arcade game the scraper's "label" slot used to hold its `support-texture`, which is a render
## of the CABINET. A board's sticker wants the cover (or a real label), not the cabinet.
## The front panel of a laid-flat box is its right-hand end, about this wide against the height.
const COVER_ASPECT := 0.73
## A box texture wider than this against its height is a laid-flat wrap, not a single cover.
const WRAP_ASPECT := 1.2


## The front cover out of a box image: the right-hand part of a laid-flat wrap, or the whole
## image when it is already a single cover.
static func front_cover(img: Image) -> Image:
	if img == null or img.is_empty():
		return img
	var w := img.get_width()
	var h := img.get_height()
	if float(w) / float(maxi(h, 1)) <= WRAP_ASPECT:
		return img
	var cover_w := clampi(roundi(float(h) * COVER_ASPECT), 1, w)
	return img.get_region(Rect2i(w - cover_w, 0, cover_w, h))


## What a board's sticker shows: the front cover when there is a box image, else whatever label
## was scraped, else nothing. (The label slot only ever held the cabinet for arcade games until
## the scraper stopped filling it from `support-texture`, so the cover goes first.)
static func board_art(box: Image, label: Image) -> Image:
	if box != null and not box.is_empty():
		return front_cover(box)
	if label != null and not label.is_empty():
		return label
	return null
