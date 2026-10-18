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

# Module kinds. A module says which it is; the cabinet finds modules by TYPE and
# reads this, never a node name.
const KIND_SCREEN := &"screen"
const KIND_STICK_BUTTONS := &"stick_buttons"
const KIND_COIN := &"coin"
const KIND_BAY := &"bay"
const KIND_SOCKETS := &"sockets"

## Bay kinds: what a bay takes. `systems` are the systemids whose boards fit. A
## Neo Geo MVS (a later bay) is another entry here and another host in the bay, not
## another cabinet.
const BAY_JAMMA := "jamma"
const _BAYS: Dictionary = {
	"jamma": {"label": "JAMMA", "systems": ["arcade"]},
}

## Bay kinds a mod added: id -> {label, systems}.
static var _mod_bays: Dictionary = {}

## Joypad bits. A player's panel: six buttons, START, and the coin the gettoniera
## drops. The coin is SELECT because that is where MAME and FBNeo read it on a
## RetroPad; it is a property of the core, so it is stated once, here.
const BUTTON_COUNT := 6
const BUTTON_BITS: Array[int] = [
	ControllerBindings.JOYPAD_B, ControllerBindings.JOYPAD_A, ControllerBindings.JOYPAD_Y,
	ControllerBindings.JOYPAD_X, ControllerBindings.JOYPAD_L, ControllerBindings.JOYPAD_R,
]
const START_BIT := ControllerBindings.JOYPAD_START
const COIN_BIT := ControllerBindings.JOYPAD_SELECT

## How long a coin holds its bit. Long enough for any core to poll it across a
## frame at 60 fps, short enough never to read as a held button.
const COIN_PULSE_SECONDS := 0.10


## Ids a .info file may file an arcade core under besides the tiles' own (the older MAME and
## FBAlpha cores say plain "arcade"; the CPS boards have ids of their own).
const ARCADE_ALIASES: Array[String] = ["arcade", "cps1", "cps2", "cps3", "mame", "fbneo", "hbmame"]


static func register_bay_kind(id: String, label: String, systems: Array) -> void:
	_mod_bays[id] = {"label": label, "systems": systems.duplicate()}


static func bay_kinds() -> Dictionary:
	var out := _BAYS.duplicate()
	out.merge(_mod_bays)
	return out


## Does a bay of this kind take this system's boards? A legacy id (`mame`, `fbneo`) is read
## through SystemIds.canonical, as everywhere: they are the one `arcade` system now.
static func bay_accepts(bay_kind: String, systemid: String) -> bool:
	var row: Dictionary = bay_kinds().get(bay_kind, {})
	return (row.get("systems", []) as Array).has(SystemIds.canonical(systemid))


## Every systemid some bay takes: the systems that play in a cabinet.
static func systems() -> Array:
	var out: Array = []
	for row: Dictionary in bay_kinds().values():
		for s: String in row.get("systems", []):
			if not out.has(s):
				out.append(s)
	return out


static func is_arcade_system(systemid: String) -> bool:
	return systems().has(SystemIds.canonical(systemid))


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
