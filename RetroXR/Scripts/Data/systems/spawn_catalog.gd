## SpawnCatalog — the per-system list of things the spawn menu can spawn.
##
## The Systems tab shows a title card per system; opening a card lists that
## system's spawnable ITEMS — its hardware model(s) plus the peripherals that go
## with it (e.g. PlayStation → Primitive System + Memory Card + Primitive
## Controller + Composite Cable).
##
## Hardware rows are NOT authored here. Every model is a row in
## SystemModelRegistry that already knows its own label and which platform it sits
## under, so this file asks for them and only hand-authors the peripherals. That is
## what makes adding or deleting a model a one-row edit: the menu follows.
##
## Each item is a Dictionary:
##   kind     : "system"     → a RetroSystem console (system.tscn)
##              "peripheral" → an existing pickable scene spawned by name
##   label    : row text — the HARDWARE's name, not a category ("DS Lite",
##              "PSP-1000"), so the row says what it actually spawns
##   model_id : (kind=="system")     the SystemModelRegistry row to spawn
##   variants : (kind=="system")     the colors that row comes in, when it lists
##                                   any: [{id, label, color}], the first its own
##   spawn    : (kind=="peripheral") an EXISTING spawn string that
##                                   SpawnMenuController._on_spawn_requested already
##                                   handles ("retro_controller", "memory_card", …)
class_name SpawnCatalog
extends RefCounted

## The stand-in pad — also the "Primitive Controller" row's spawn token.
const PRIMITIVE_CONTROLLER := "retro_controller"


## systemid → the peripherals that belong to that hardware. Systems with no entry
## just have none; their hardware rows still come from the registry.
##
## What is listed is the hardware RetroXR models itself: the memory card, and the
## Virtual Boy pad — that one is here rather than dropped to the generic row
## because it carries the console's POWER switch, so the platform is unplayable
## without it.
##
## Every non-handheld gets the "Primitive Controller" row appended by items_for
## below, so a platform losing its entry here loses a name, not a way to play.
const _PERIPHERALS: Dictionary = {
	# Both pads are named here rather than left to the generic Controllers row
	# because the console moulds its own sockets and each pad wears the matching
	# connector (plug_mesh_path), so they only look right together. The digital
	# pad shipped with the console; the DualShock is the later one you bought.
	"psx": [
		{"kind": "peripheral", "label": "Controller", "spawn": "ps1_controller"},
		{"kind": "peripheral", "label": "DualShock", "spawn": "ps1_dualshock"},
		{"kind": "peripheral", "label": "Memory Card", "spawn": "memory_card"},
	],
	"ps2": [
		{"kind": "peripheral", "label": "Memory Card", "spawn": "memory_card"},
	],
	"gc": [
		{"kind": "peripheral", "label": "Memory Card", "spawn": "memory_card"},
		{"kind": "peripheral", "label": "Microphone", "spawn": "gc_microphone"},
	],
	# Listed here rather than left to the console's own card row, for the same
	# reason the N64's paks are: a VMU goes into a CONTROLLER, and none of the
	# console-slot machinery that offers a memory card reaches it. A Dreamcast pad
	# takes two, and only the one in the front slot has its screen showing.
	"dreamcast": [
		{"kind": "peripheral", "label": "Visual Memory Unit", "spawn": "vmu"},
		# The other thing those two sockets take. A pad with a card in slot 1
		# and a pack in slot 2 is the arrangement most players ran, and is
		# flycast's own default for slot 2.
		{"kind": "peripheral", "label": "Jump Pack", "spawn": "jump_pack"},
		# Seaman wants the card in slot 1 and this in slot 2, which is why the
		# core offers it in either.
		{"kind": "peripheral", "label": "Microphone", "spawn": "dc_microphone"},
		# Sega's own AV OUT at the machine and three phonos at the set, the way the
		# console shipped. Nothing else's AV lead fits that socket.
		{"kind": "peripheral", "label": "Stereo AV Cable", "spawn": "dc_av_cable"},
	],
	# The Xbox's, which goes into a CONTROLLER too, two to a pad. Not where its
	# games save — that is the hard disk in the console — but where a save is
	# copied to be carried, and where one backed up to RomM comes home through.
	"xbox": [
		{"kind": "peripheral", "label": "Memory Unit", "spawn": "xbox_mu"},
	],
	# The printer is the far end of a Game Boy link lead, so it is offered where
	# the lead is. It runs a core of its own (gbprinter), fetched from the Game
	# Boy's BIOS / Extras page.
	"gb": [
		{"kind": "peripheral", "label": "Game Boy Printer", "spawn": "gb_printer"},
	],
	"gbc": [
		{"kind": "peripheral", "label": "Game Boy Printer", "spawn": "gb_printer"},
	],
	# The pad is named here because it is the only one with an expansion port, and
	# all three paks are useless without it. The paks themselves are listed rather
	# than left to the console's own card row: they go into a CONTROLLER, so none
	# of the console-slot machinery that offers a memory card reaches them.
	"n64": [
		{"kind": "peripheral", "label": "Controller", "spawn": "n64_controller"},
		{"kind": "peripheral", "label": "Rumble Pak", "spawn": "rumble_pak"},
		{"kind": "peripheral", "label": "Controller Pak", "spawn": "controller_pak"},
		{"kind": "peripheral", "label": "Transfer Pak", "spawn": "transfer_pak"},
		{"kind": "peripheral", "label": "Voice Recognition Unit", "spawn": "n64_vru"},
		# An AV MULTI OUT at the machine and three phonos at the set, so a plain
		# composite lead fits the television and nothing at this end. Nintendo's
		# SNS-008, shared by the Super Nintendo, the N64 and the GameCube.
		{"kind": "peripheral", "label": "Stereo Composite Cable",
			"spawn": "n64_av_cable"},
	],
	# The remote is named here even though it fits no socket: it is the Wii's
	# controller, and a player who spawns a Wii should be offered one without
	# having to know it lives under Controllers. The Nunchuk comes with it because
	# half the library needs one.
	"wii": [
		{"kind": "peripheral", "label": "Wiimote", "spawn": "wiimote"},
		{"kind": "peripheral", "label": "Nunchuk", "spawn": "nunchuk"},
		# A Wii playing a GameCube disc writes to a GameCube card, and its two
		# slots are real — under the memory flap beside the controller ports.
		{"kind": "peripheral", "label": "Memory Card", "spawn": "memory_card"},
		# Offered here too, because the games that need it need it absolutely:
		# without the dongle a remote reports no rotation and Wii Sports Resort
		# will not start.
		{"kind": "peripheral", "label": "Wii MotionPlus", "spawn": "motion_plus"},
		# Listed first among equals in spirit: without it the remote has nothing to
		# look at, and no amount of pressing SYNC produces a pointer.
		{"kind": "peripheral", "label": "Sensor Bar", "spawn": "sensor_bar"},
		# An AV Multi Out at the machine and three phonos at the set, so a plain
		# composite lead fits the television and nothing at this end.
		#
		# Still the one lead that fits NOTHING else, even now the N64 wears the same
		# shell: Nintendo kept the connector from the Super Nintendo to the Wii and
		# moved the signals on the last of them, so the SNS-008 serves three consoles
		# and the RVL-009 serves one. The two ports declare different plug groups for
		# exactly that reason.
		{"kind": "peripheral", "label": "Wii Composite Cable",
			"spawn": "wii_av_cable"},
	],
	"virtualboy": [
		{"kind": "peripheral", "label": "Controller", "spawn": "vb_controller"},
	],
	# The NES pad is named here rather than left to the generic row because the
	# console moulds its own connector and the pad wears it (plug_mesh_path), so
	# the two only look right together. No cartridge row: a cart comes from the
	# Games tab, which already spawns one per ROM keyed on systemid.
	"nes": [
		{"kind": "peripheral", "label": "Controller", "spawn": "nes_controller"},
		# The console wears sockets rather than a captive lead, so the lead it
		# shipped with is listed on its own card: video and ONE audio channel,
		# which is all an NES puts out.
		{"kind": "peripheral", "label": "Mono Composite Cable",
			"spawn": "mono_composite_cable"},
		# How this console actually reached a set in 1985, and the reason its rear
		# panel wears an RF SWITCH socket and a CH3/CH4 slide beside it.
		{"kind": "peripheral", "label": "RF Switch (RXR-003)", "spawn": "rf_switch"},
	],
	# No pads: both are moulded onto cords that come out of the back of the
	# machine and arrive with it, so there is no such thing as a spare. What IS
	# offered is the way a Famicom reached a television, since its only output is
	# the RF socket beside the channel switch.
	"famicom": [
		{"kind": "peripheral", "label": "RF Switch (RXR-003)", "spawn": "rf_switch"},
	],
	# Same reasoning as the NES: the console moulds its own DE-9 sockets and the
	# stick wears the matching plug, so the two only look right together. Named
	# CX40 because the 2600 shipped two quite different controllers and the
	# paddle is still to come.
	"atari2600": [
		{"kind": "peripheral", "label": "CX40 Joystick", "spawn": "atari_2600_cx40"},
	],
	# The SNES Mouse is here rather than left to the generic Controllers-tab mouse
	# because it wears its own connector and only fits a Super NES; the generic one
	# stays universal. The primitives are NOT dropped from this card — there is no
	# SNES console model or pad yet, so they are still the way to play it.
	"snes": [
		{"kind": "peripheral", "label": "SNES Mouse", "spawn": "snes_mouse"},
	],
	# The Model 2's A/V OUT is a 9-pin mini-DIN, so the generic composite lead fits
	# the television and nothing at this end. Sega's own lead: the round plug at the
	# console, three phonos at the set.
	"genesis": [
		{"kind": "peripheral", "label": "A/V Cable", "spawn": "genesis_av_cable"},
	],
	# The riser Sega packed with the 32X for the Model 2, whose slot leaves the
	# unit standing on its plug. On the 32X's card, beside the unit it clips under
	# (items_for appends a unit card's own rows after its units).
	"sega32x": [
		{"kind": "peripheral", "label": "Model 2 Spacer", "spawn": "sega32x_spacer"},
	],
}


## Platforms that model their own console AND their own pad, so the generic
## stand-ins are only clutter on their card. Everything else keeps them: for a
## platform with no hardware of its own they are the whole way to play it.
##
## The N64 is here for its pad more than its box: the generic pad has no expansion
## port, so on that card it was a controller that takes none of the three paks.
const _NO_STANDINS: Array[String] = ["nes", "famicom", "atari2600", "psx", "n64"]


## Platforms that model their own CONSOLE but not their own pad. The Primitive System
## box is a second, worse console on their card, so it goes; the Primitive Controller
## stays, because it is the only pad they have.
##
## Only while that model is available. rows_for lists a GLB-backed row only when its
## asset is present, so a build without the Dreamcast's or the Genesis's shell gets
## the box back rather than a card with no console on it at all.
const _NO_STANDIN_CONSOLE: Array[String] = ["dreamcast", "genesis"]


## Platforms that name their own A/V lead above, so the generic one would be a
## second cable doing the same job. The NES puts out one audio channel and lists the
## mono lead its console shipped with; the Wii and the N64 have no phono sockets at
## all, so the generic lead would fit their television and nothing on the console.
## The Famicom is here for a stronger reason than the other three: it has no
## composite socket at all, so the generic lead would fit its television and
## nothing on the console. Its card lists the RF switch instead. The Genesis, for
## the Wii's and N64's reason: its one socket is a 9-pin mini-DIN.
const _OWN_AV_LEAD: Array[String] = ["nes", "famicom", "wii", "n64", "genesis"]

## Hardware whose picture leaves on a captive pigtail rather than through sockets
## (av_port_channels() is empty), so a spawned lead has nothing to enter at that
## end. Every handheld is one — items_for reads the registry's flag for those —
## and so is the Virtual Boy, which stands on a table and is not flagged handheld
## but wears no A/V sockets either.
##
## A platform with no model of its own is NOT one of these: it spawns the
## primitive box, which does wear the three sockets, and the lead is how its
## picture reaches the set.
const _NO_AV_SOCKETS: Array[String] = ["virtualboy"]

## The lead every other platform reaches the TV with. Consoles spawn wearing a
## captive one, so this row is a spare — for a lead thrown in the trash, or a
## second TV.
const _AV_CABLE: Dictionary = {"kind": "peripheral", "label": "Composite Cable",
	"spawn": "composite_cable"}

## How a home computer is actually played. SystemInfo.computer marks the systems
## whose core reads the mouse on port 0 and takes keys globally — for those the
## pad is the odd peripheral and these two are the hardware, so they are listed
## on the card rather than left to the Controllers tab.
const _COMPUTER_INPUT: Array = [
	{"kind": "peripheral", "label": "Keyboard", "spawn": "retro_keyboard"},
	{"kind": "peripheral", "label": "Mouse", "spawn": "retro_mouse"},
]

## How a computer's picture reaches its monitor. Listed for computers only: the
## sockets it fits are the PC tower's and the CRT monitor's, and a console has
## neither. It does not replace the composite lead on those cards — VGA carries no
## sound, so a tower wired this way still needs the phono pair for audio, which is
## what the real machine needed too.
const _VGA_CABLE: Dictionary = {"kind": "peripheral", "label": "VGA Cable",
	"spawn": "vga_cable"}

## How a computer's sound reaches its speakers, and the speakers themselves. Listed
## for computers only, for the same reason the VGA lead is: the sockets a 3.5 mm plug
## fits are the tower's line out and the right speaker's line in, and a console has
## neither.
## The link lead, offered on the platforms that have a socket to put it in. Two
## handhelds and one cable is the whole of GBA multiplayer, and that lead carries
## a junction so a third and fourth can chain on.
##
## The Game Boy's are different leads: with nothing in the middle, because a Game
## Boy link is two machines and no more. And two of them, because the Pocket and
## the Color shrank the original's connector: the DMG-04 is large at both ends and
## fits an original Game Boy and the Printer, the CGB-003 small at both and fits a
## Color (or an Advance). The DMG-14 adapter takes a small plug in its back and
## goes into a large socket, so it is offered on both cards: it is how a Color
## reaches an original or the Printer. The PlayStation's is different again --
## different connector, different protocol -- so none is ever offered as another.
const _LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable", "spawn": "link_cable"}
const _DMG_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable",
	"spawn": "dmg_link_cable"}
const _GB_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable",
	"spawn": "gb_link_cable"}
const _GB_LINK_ADAPTER: Dictionary = {"kind": "peripheral", "label": "Link Cable Adapter",
	"spawn": "gb_link_adapter"}
const _PSX_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable",
	"spawn": "psx_link_cable"}
## The WonderSwan's Communication Cable is two units and no more, like the Game
## Boy's, so it is the same two-ended lead under Bandai's name -- keyed to the
## WonderSwan's socket alone (ws_link_cable.tscn).
const _WS_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Communication Cable",
	"spawn": "ws_link_cable"}
## Sega's Gear-to-Gear Cable joins two Game Gears and no more: the same
## two-ended lead again, under Sega's name, keyed to Game Gears alone.
const _GG_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Gear-to-Gear Cable",
	"spawn": "gg_link_cable"}
const _SATURN_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable",
	"spawn": "saturn_link_cable"}
const _JAG_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "JagLink Cable",
	"spawn": "jag_link_cable"}
## The PlayStation 2's i.LINK is a bus rather than a pair, so its lead comes with
## the hub that puts up to six consoles on one wire (ILinkBus). The hub is not a
## lead and is not in _LINK_LEADS; it is offered beside the lead in items_for.
const _ILINK_CABLE: Dictionary = {"kind": "peripheral", "label": "i.LINK Cable",
	"spawn": "ilink_cable"}
const _ILINK_HUB: Dictionary = {"kind": "peripheral", "label": "i.LINK Hub",
	"spawn": "ilink_hub"}

## LAN play (EthernetBus): a patch lead and the hub that puts up to eight
## consoles on one LAN. Offered on both platforms that had a network adapter
## games used for LAN play -- the GameCube's Broadband Adapter (Mario Kart:
## Double Dash!!) and the PlayStation 2's (Gran Turismo 4) -- and they share the
## one hub and the one lead, as they would on a real LAN.
const _ETHERNET_CABLE: Dictionary = {"kind": "peripheral", "label": "Ethernet Cable",
	"spawn": "ethernet_cable"}
const _ETHERNET_HUB: Dictionary = {"kind": "peripheral", "label": "Ethernet Hub",
	"spawn": "ethernet_hub"}
const _ETHERNET_PLATFORMS: Array = ["gc", "ps2"]

## ComLynx chains: every cable has a pass-through socket on its plug, so a third
## Lynx (up to eight) joins where the last one plugs in. That is the GBA lead's
## shape -- two ends and a junction -- under Atari's name, keyed to Lynxes alone.
const _COMLYNX_CABLE: Dictionary = {"kind": "peripheral", "label": "ComLynx Cable",
	"spawn": "comlynx_cable"}
## The SNK link cable joins two Neo Geo Pockets (either model, one core, one
## wire) and no more, so it is the same two-ended lead, keyed to NGPs alone.
const _NGP_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable",
	"spawn": "ngp_link_cable"}
## The Virtual Boy's link cable joins two units by their EXT. sockets. Nintendo
## never sold one and no retail game used it; what does is homebrew, and Mario's
## Tennis with its two-player code patched back in (docs/dev/vb-link.md).
const _VB_LINK_CABLE: Dictionary = {"kind": "peripheral", "label": "Link Cable",
	"spawn": "vb_link_cable"}

## The console-to-handheld lead, offered on BOTH platforms it joins. A player
## spawning a GameCube for Four Swords Adventures should be offered one without
## having to know it is filed under the handheld, and a player spawning a Game
## Boy Advance should be offered it without having to know it is filed under the
## console: it is one cable and it belongs to neither of them.
const _GC_GBA_CABLE: Dictionary = {"kind": "peripheral", "label": "GC-GBA Cable",
	"spawn": "gc_gba_cable"}
const _GC_GBA_PLATFORMS: Array = ["gc", "gba"]

## Which lead each platform is offered, keyed on the PLATFORM rather than the
## model: the GBA and the SP are two models of one platform and both have the
## socket.
const _LINK_LEADS: Dictionary = {
	"gba": _LINK_CABLE,
	"gb": _DMG_LINK_CABLE,
	"gbc": _GB_LINK_CABLE,
	"psx": _PSX_LINK_CABLE,
	"wonderswan": _WS_LINK_CABLE,
	"wonderswancolor": _WS_LINK_CABLE,
	"gamegear": _GG_LINK_CABLE,
	"saturn": _SATURN_LINK_CABLE,
	"atarijaguar": _JAG_LINK_CABLE,
	"ps2": _ILINK_CABLE,
	"atarilynx": _COMLYNX_CABLE,
	"ngp": _NGP_LINK_CABLE,
	"ngpc": _NGP_LINK_CABLE,
	"virtualboy": _VB_LINK_CABLE,
}


## The gun, offered on the platforms that sold one. One prop rather than a row per
## card because RetroXR models no Super Scope and no Light Phaser -- it is the
## generic stand-in, the same one the Controllers tab offers, so it is labelled
## for what it spawns rather than for the gun a given console shipped.
##
## Listed is hardware that really existed for the platform: the Zapper, the Super
## Scope, the Light Phaser, the Menacer and the Justifier, the Saturn's Stunner,
## the GunCon, Atari's XG-1, the Magnum Light Phaser on the three home computers
## it was sold for, the 3DO's Gamegun and the CD-i's Peacekeeper. A console that
## never had one does not get the row, so the card stays a hardware fact.
const _LIGHT_GUN: Dictionary = {"kind": "peripheral", "label": "Light Gun",
	"spawn": "light_gun"}
const _LIGHT_GUN_PLATFORMS: Array = [
	# No sega_cd: its card is the Mega-CD UNIT now, not a console, and the
	# Menacer and the Justifier plug into the Mega Drive underneath it -- whose
	# card is listed here and still offers the row. A gun on a card that spawns a
	# drive would describe a socket the drive does not have.
	"nes", "snes", "mastersystem", "genesis", "saturn",
	"dreamcast", "psx", "ps2", "atari2600", "atari7800",
	"atari800", "c64", "zxspectrum", "amstradcpc", "3do", "cdi",
]


const _TRS_KIT: Array = [
	{"kind": "peripheral", "label": "Speakers", "spawn": "speaker_pair"},
	{"kind": "peripheral", "label": "3.5 mm Cable", "spawn": "trs_cable"},
]


## The spawnable items for a system: its stand-in hardware, then the models that
## need imported assets, then its peripherals.
##
## The stand-ins lead the list — the platform's authored primitive models where it
## has any, then the Primitive System box, which is the only stand-in a platform
## without one has.
##
## `system_name` is unused now — a hardware row is labelled by its registry row
## rather than by the system's name, so a platform with two models says which is
## which. Kept in the signature because the menu passes it.
static func items_for(systemid: String) -> Array:
	return _with_offered_variants(_items_for(systemid), systemid)


# ── Colors of a row a mod does not own ────────────────────────────────────────
#
# A console's row is a model row and lists its own `variants`. A controller a
# mod BRINGS lists them on the item it adds (register_mod_peripherals). A
# controller that is the game's own, which a mod only dresses, has a row the
# mod cannot reach: it offers that row its variants here, by the row's token.

## spawn token, or "<systemid>|<spawn token>" for one card's row alone ->
## {"variants": Array, "owner": String}
static var _offered_variants: Dictionary = {}


## Offer `variants` for the row that spawns `spawn`. "" on success, else why not.
##
## With `systemid`, that card's row alone. A token can be shared by rows that
## spawn different things: every console's "Memory Card" row is "memory_card",
## and each spawns the card of its own console's family, so a PlayStation 2
## card's colors offered by the token alone would be offered on the PlayStation,
## GameCube and Wii pages too. A card's own offer wins over the token's.
static func register_mod_row_variants(spawn: String, variants: Array, owner_id: String,
		systemid: String = "") -> String:
	if spawn.is_empty():
		return "no spawn token"
	if variants.is_empty():
		return "no variants given for '%s'" % spawn
	var err := SystemModelRegistry.variants_error(variants)
	if not err.is_empty():
		return err
	var key := spawn if systemid.is_empty() else "%s|%s" % [systemid, spawn]
	if _offered_variants.has(key):
		return "'%s' already has variants from mod '%s'" % [key, _offered_variants[key]["owner"]]
	_offered_variants[key] = {"variants": variants.duplicate(true), "owner": owner_id}
	return ""


static func _with_offered_variants(items: Array, systemid: String = "") -> Array:
	if _offered_variants.is_empty():
		return items
	for item: Variant in items:
		var row := item as Dictionary
		var spawn := str(row.get("spawn", ""))
		var key := "%s|%s" % [systemid, spawn]
		if not _offered_variants.has(key):
			key = spawn
		if row.get("kind", "system") == "peripheral" and not row.has("variants") and _offered_variants.has(key):
			row["variants"] = (_offered_variants[key]["variants"] as Array).duplicate(true)
	return items


static func _items_for(systemid: String) -> Array:
	# An expansion with a card of its own IS this card, and is the whole of it.
	#
	# Almost every unit is also a systemid -- a 64DD's disks are "n64dd",
	# a Mega-CD's discs are "segacd" -- so each already had a tile in the systems
	# list, sitting beside the console it bolts to. That tile opened on "Primitive
	# System", because no model registry row serves those ids and the generic box
	# is the fallback. Pressing it spawned a whole imaginary console: a "Nintendo
	# 64DD system" that never existed, which is the exact fiction ExpansionCatalog
	# was written to replace. The tile was always the right home for the unit; it
	# was spawning the wrong thing.
	#
	# Nothing else belongs on this card. An expansion has no controller ports and
	# no sockets for a television -- it borrows both from the console standing on
	# it, and that console's own card still offers them. Offering a pad "for your
	# 64DD" would describe hardware that has nowhere to plug it in. The Mega-CD
	# loses its light-gun row the same way and for the same reason: the Menacer
	# goes into the Mega Drive, whose card already lists it.
	#
	# Not quite the whole of it: a unit with no card of its own that runs THIS
	# card's media belongs here too. The BS-X cartridge is one -- the Satellaview
	# card is the base station, the cartridge and the pack that goes in it, which
	# is the machine as a player has to build it.
	if ExpansionCatalog.has(systemid) and ExpansionCatalog.has_own_card(systemid):
		var own: Array = []
		# Gated exactly as a unit filed on somebody else's card is. This branch
		# used to add the unit unconditionally, so the firmware rule -- "a unit
		# that has not got them is not offered at all" -- held only for units
		# WITHOUT a tile of their own. It went unnoticed because the BS-X
		# cartridge was the only row naming firmware and it is filed under
		# satellaview; the Sufami Turbo is the first to name firmware AND own its
		# card, and it was offered without its shell.
		if ExpansionCatalog.firmware_present(systemid):
			own.append({"kind": "peripheral",
				"label": ExpansionCatalog.label_of(systemid),
				"spawn": "expansion:%s" % systemid})
		own.append_array(_units_carded_here(systemid))
		return own

	# The same card under another name: the MEDIA of a unit whose id differs from
	# it. The Jaguar CD is the one -- its id is jaguar_cd (persisted, so it
	# stays) and its discs are atarijaguarcd -- and without this its card fell
	# through to the console path below and grew a "Primitive System": a Jaguar
	# CD console, which never existed. It is an add-on for the Jaguar, the
	# Jaguar's card offers the console, and this card offers only the unit --
	# and whatever that unit carries into the room with it (_PERIPHERALS: the
	# 32X's Model 2 spacer), never a console or a pad.
	if _is_expansion_media(systemid):
		return _units_carded_here(systemid) + (_PERIPHERALS.get(systemid, []) as Array).duplicate(true)

	var primitive: Array = []
	var imported: Array = []
	# The cable sockets the consoles on this card list on their rows, for the
	# leads that fit them. A row that lists none is taken to wear phono jacks, as
	# the box below does.
	var sockets: Array[String] = []
	var phono := false
	var mod_console := false
	var rows := SystemModelRegistry.rows_for(systemid)
	for row: Dictionary in rows:
		# A row kept for the rooms that name it and not for the card: what was
		# once a color's own row and is now one of another row's variants.
		if bool(row.get("unlisted", false)):
			continue
		if not row.has("sockets"):
			phono = true
		for socket: Variant in row.get("sockets", []):
			if str(socket) == Connectors.PHONO:
				phono = true
			elif not sockets.has(str(socket)):
				sockets.append(str(socket))
		if SystemModelRegistry.is_mod_row(str(row.get("id", ""))):
			mod_console = true
		var item := {"kind": "system", "model_id": row.get("id", ""),
			"label": row.get("label", "Console")}
		# The colors the shell comes in, for a row that lists them: the menu
		# offers them when the row is held.
		var variants: Array = row.get("variants", [])
		if not variants.is_empty():
			item["variants"] = variants.duplicate(true)
		if (row.get("requires", []) as Array).is_empty():
			primitive.append(item)
		else:
			imported.append(item)

	# Anything not played in the hand can also take the primitive box and the
	# primitive pad. A handheld gets neither: a console box is shaped nothing like
	# the device, and its controls are its own buttons. Nor does a platform in
	# _NO_STANDINS, which brings both of its own.
	var handheld := SystemModelRegistry.platform_is_handheld(systemid)
	var standins := not handheld and not _NO_STANDINS.has(systemid)

	var items: Array = []
	items.append_array(primitive)
	# The generic box stands in for a platform with NO plain model of its own.
	# Where the platform authored one — the PC tower, the Virtual Boy — it is a
	# second and worse console on the same card.
	# A mod's console on the card is that for a platform the game ships no model
	# of. Only while one is really on it: a model that failed to load cannot leave
	# a card with no console.
	var own_console := (_NO_STANDIN_CONSOLE.has(systemid) or mod_console) \
		and not imported.is_empty()
	var boxed := standins and primitive.is_empty() and not own_console
	if boxed:
		items.append({"kind": "system", "label": "Primitive System",
			"model_id": SystemModelRegistry.PLACEHOLDER_ID})
	items.append_array(imported)
	# With more than one console on the card, say which the game reaches for
	# when nothing names a model: the first available row. Two mods modelling
	# the same console is the case this is for -- which of them that is follows
	# from their priority, and the card is the only place it can be seen.
	if items.size() > 1 and not rows.is_empty():
		var chosen := str((rows[0] as Dictionary).get("id", ""))
		for item: Dictionary in items:
			if str(item.get("model_id", "")) == chosen:
				item["default"] = true
	items.append_array((_PERIPHERALS.get(systemid, []) as Array).duplicate(true))
	# The machines that bolt onto this one -- but ONLY those actually filed under
	# this card, or a unit would be offered from two places at once and this card
	# would grow a row that duplicates a whole tile.
	#
	# ExpansionCatalog.card_systemid is what decides. It files a unit with no card
	# of its own under its MEDIA unless the row names a `card`, and what reaches
	# THIS call is whatever that lands on an ordinary console: currently the two
	# Super Game Boys, on the Super Famicom's card.
	#
	# They are the reason `card` exists. The media rule put them on the GAME BOY
	# card, which is defensible -- that is where you are standing when you want to
	# play a Game Boy game -- and it was tried. Then the person who asked for the
	# feature went looking for one, on the Super Famicom card, and did not find it.
	# A Super Game Boy is a Super Famicom cartridge that goes into a Super Famicom
	# slot, and that is where a hand reaches for it.
	#
	# The other two units with no tile do NOT arrive here, and both are worth
	# knowing about because each used to. The BS-X cartridge is filed under
	# satellaview, which is itself a row with a card, so the branch above catches
	# it -- before that it landed here and put Satellaview hardware on the Super
	# Famicom card among the pads and the leads. The Jaguar CD was the plain case
	# this call was written for until its discs became a systemid of their own; it
	# has a tile now and is spawned from that.
	items.append_array(_units_carded_here(systemid))
	# What mods bring for this card, whichever card they listed it on or none: the
	# pads and guns made for this console (one made for another console that
	# shares its port still plugs in -- a Genesis pad into a Master System -- it is
	# just not offered here), and the leads that fit its consoles' sockets. Each
	# stand-in below stays only while nothing installed does its job: the generic
	# gun while no gun is made for this console, the pad while no pad is, the
	# game's lead for a socket while no mod's lead fits it.
	var made_for := mod_objects_made_for(systemid)
	var own := func(role: String) -> bool:
		return made_for.any(func(f: Dictionary) -> bool: return f["role"] == role)
	var fitting := mod_objects_fitting(sockets)
	var fits := func(socket: String) -> bool:
		return fitting.any(func(f: Dictionary) -> bool:
			return f["role"] == ConnectorScan.ROLE_LEAD and f["plug"] == socket)
	# With the peripherals rather than the leads below: it is something you hold.
	if _LIGHT_GUN_PLATFORMS.has(systemid) and not own.call(ConnectorScan.ROLE_LIGHT_GUN):
		items.append(_LIGHT_GUN.duplicate())
	if _LINK_LEADS.has(systemid):
		items.append((_LINK_LEADS[systemid] as Dictionary).duplicate())
	if systemid == "gb" or systemid == "gbc":
		items.append(_GB_LINK_ADAPTER.duplicate())
	if systemid == "ps2":
		items.append(_ILINK_HUB.duplicate())
	if _ETHERNET_PLATFORMS.has(systemid):
		items.append(_ETHERNET_CABLE.duplicate())
		items.append(_ETHERNET_HUB.duplicate())
	if _GC_GBA_PLATFORMS.has(systemid):
		items.append(_GC_GBA_CABLE.duplicate())
	var info := SystemInfo.for_system(systemid)
	if info != null and info.computer:
		items.append_array(_COMPUTER_INPUT.duplicate(true))
		items.append(_VGA_CABLE.duplicate())
		items.append_array(_TRS_KIT.duplicate(true))
	if standins and not own.call(ConnectorScan.ROLE_CONTROLLER):
		items.append({"kind": "peripheral", "label": "Primitive Controller",
			"spawn": PRIMITIVE_CONTROLLER})
	# The generic lead fits phono jacks. Once no console on the card has any --
	# the box is gone and every row lists sockets without them -- it would fit the
	# television and nothing on the console, which is _OWN_AV_LEAD's reason.
	var no_phono := not boxed and not rows.is_empty() and not phono
	if not handheld and not _NO_AV_SOCKETS.has(systemid) \
			and not _OWN_AV_LEAD.has(systemid) and not no_phono:
		items.append(_AV_CABLE.duplicate())
	# A socket a console names needs a lead that fits it, and the mod that
	# brings the console need not bring one: the game's own lead for it stands in
	# while no installed mod's lead fits it.
	var mod_rows: Array = _mod_peripherals.get(systemid, [])
	for socket: String in sockets:
		var lead := Connectors.game_lead(socket)
		if lead.is_empty() or fits.call(socket):
			continue
		var spawn := str(lead["spawn"])
		if not _listed(items, spawn) and not _listed(mod_rows, spawn):
			items.append({"kind": "peripheral", "label": str(lead["label"]), "spawn": spawn})
	# Mod peripherals go LAST, after the stand-ins and the shipped accessories,
	# so a mod adds to a console's card rather than reordering it.
	items.append_array(mod_rows.duplicate(true))
	# Then whatever else is for this card, from mods that listed it elsewhere or
	# nowhere: another author's pad for this console, a lead for its socket.
	for f: Dictionary in made_for + fitting:
		if not _listed(items, str(f["spawn"])):
			items.append(_row_for_mod_object(str(f["type"])))
	return items


static func _listed(items: Array, spawn: String) -> bool:
	return items.any(func(i: Dictionary) -> bool: return str(i.get("spawn", "")) == spawn)


## Every pad and gun a mod registered that was made for `systemid` (its scene's
## systemid, ConnectorScan), as [{type, spawn, role}].
static func mod_objects_made_for(systemid: String) -> Array:
	var out: Array = []
	for type: String in ScenePersistence.mod_object_types():
		var info := ConnectorScan.of_scene(ScenePersistence.mod_object_scene(type))
		if not str(info["systemid"]).is_empty() and info["systemid"] == systemid:
			out.append({"type": type, "spawn": "mod:" + type, "role": info["role"]})
	return out


## Every object a mod registered that plugs into one of `sockets`, as
## [{type, spawn, role, plug}]: read from its scene (ConnectorScan), never from
## anything the mod said about it. A room connector (a phono end) fits nothing in
## particular, so it never matches.
static func mod_objects_fitting(sockets: Array) -> Array:
	var out: Array = []
	for type: String in ScenePersistence.mod_object_types():
		var info := ConnectorScan.of_scene(ScenePersistence.mod_object_scene(type))
		for plug: String in (info["plugs"] as PackedStringArray):
			if sockets.has(plug) and not Connectors.is_room(plug):
				out.append({"type": type, "spawn": "mod:" + type, "role": info["role"], "plug": plug})
				break
	return out


## The card row for a mod's object listed on a card it did not name: the row its
## mod gave it on another card, colors and all, else its menu label, else its name.
static func _row_for_mod_object(type: String) -> Dictionary:
	var spawn := "mod:" + type
	for systemid: String in _mod_peripherals:
		for row: Dictionary in _mod_peripherals[systemid]:
			if str(row.get("spawn", "")) == spawn:
				return row.duplicate(true)
	var label := str((_mod_spawnables.get(type, {}) as Dictionary).get("label", ""))
	if label.is_empty():
		label = type.get_slice(":", 1).replace("_", " ").capitalize()
	return {"kind": "peripheral", "label": label, "spawn": spawn}


## What `owner_id`'s page should say about its consoles' sockets: one that
## nothing installed fits, and one its row and its built console disagree on.
## Asked when the page is drawn, never stored at registration, because the lead
## may come from a mod that registers later or is switched on later.
static func socket_problems_for(owner_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Array[String] = []
	for row: Dictionary in SystemModelRegistry.rows_of_mod(owner_id):
		for socket: Variant in row.get("sockets", []):
			var name := str(socket)
			if seen.has(name) or Connectors.is_room(name) or game_lead_connectors().has(name):
				continue
			seen.append(name)
			if mod_objects_fitting([name]).is_empty():
				out.append("nothing installed fits its socket '%s': enable a lead mod for it" % name)
	out.append_array(_built_socket_notes.get(owner_id, PackedStringArray()))
	return out


## Every connector a lead the game ships has a plug for -- its A/V leads, its
## link cables, the i.LINK cable -- read off the leads' own scenes, which the
## game holds loaded already.
static func game_lead_connectors() -> PackedStringArray:
	if _game_lead_connectors.is_empty():
		for type: String in ScenePersistence.LEAD_SCENES:
			var packed := ScenePersistence.LEAD_SCENES[type] as PackedScene
			if packed == null:
				continue
			for plug: String in (ConnectorScan.of_scene(packed.resource_path)["plugs"] as PackedStringArray):
				if not _game_lead_connectors.has(plug):
					_game_lead_connectors.append(plug)
	return _game_lead_connectors


## Said once a mod's console is built: the sockets its row lists and the ones
## the console really wears, which the card cannot build it to look at.
static func note_built_sockets(owner_id: String, model_id: String, listed: Array, built: Array) -> void:
	var notes := PackedStringArray()
	for c: String in built:
		if not listed.has(c):
			notes.append("%s has a '%s' socket its row's sockets do not list" % [model_id, c])
	for c: String in listed:
		if not built.has(c):
			notes.append("%s's row lists a '%s' socket the console does not have" % [model_id, c])
	if notes.is_empty():
		_built_socket_notes.erase(owner_id)
	else:
		_built_socket_notes[owner_id] = notes


## The expansion units this card offers as rows of its own: the ones with no
## tile, filed here, and whose firmware is actually installed.
##
## The firmware gate is the reason this is a function rather than a loop written
## twice. A unit that names firmware and has not got it is not offered at all --
## it is not a machine yet, it is a box that goes into a slot and does nothing,
## and a spawn row for one is a promise the room cannot keep. The BS-X cartridge
## is the only unit that names any: without BS-X.bin in snes9x's system
## directory there is no shell for it to run.
## Whether `systemid` is only the media of an expansion unit -- a card that
## files a unit and is no console of its own (its host is somebody else).
static func _is_expansion_media(systemid: String) -> bool:
	for id: String in ExpansionCatalog.ids_carded_on(systemid):
		if ExpansionCatalog.media_of(id) == systemid 				and ExpansionCatalog.host_of(id) != systemid:
			return true
	return false


static func _units_carded_here(systemid: String) -> Array:
	var out: Array = []
	for id: String in ExpansionCatalog.ids_carded_on(systemid):
		if not ExpansionCatalog.firmware_present(id):
			continue
		out.append({"kind": "peripheral", "label": ExpansionCatalog.label_of(id),
			"spawn": "expansion:%s" % id})
	return out


# ── mod contributions ─────────────────────────────────────────────────────────

## systemid -> extra peripheral rows contributed by mods.
static var _mod_peripherals: Dictionary = {}
## An owner per systemid entry, so a failed mod's rows can be withdrawn.
static var _peripheral_owners: Dictionary = {}

## owner -> what its built consoles said about their sockets (note_built_sockets).
static var _built_socket_notes: Dictionary = {}
## See game_lead_connectors. The game's leads do not change while it runs.
static var _game_lead_connectors := PackedStringArray()

## Standalone spawnable props, shown on their own rather than under a console.
## type -> {label, owner}
static var _mod_spawnables: Dictionary = {}


## "" on success, else why the rows were refused. An empty list is an error and
## not a no-op: a mod that meant to add pads and added none would otherwise be
## told it succeeded, and its console's spawn card would simply have no pads.
static func register_mod_peripherals(systemid: String, items: Array,
		owner_id: String) -> String:
	if systemid.is_empty():
		return "systemid is empty"
	if items.is_empty():
		return "no peripherals given for '%s'" % systemid
	if not _mod_peripherals.has(systemid):
		_mod_peripherals[systemid] = []
	for item: Variant in items:
		var colors_error := SystemModelRegistry.variants_error((item as Dictionary).get("variants", []))
		if not colors_error.is_empty():
			return "%s: %s" % [str((item as Dictionary).get("label", "?")), colors_error]
	for item: Variant in items:
		var row := (item as Dictionary).duplicate(true)
		row["kind"] = "peripheral"
		# Tagged per ROW, like _mod_spawnables. A systemid's list is shared by
		# every mod that adds pads to that console, so the owner cannot live on
		# the list -- see drop_mod.
		row["owner"] = owner_id
		(_mod_peripherals[systemid] as Array).append(row)
	if not _peripheral_owners.has(owner_id):
		_peripheral_owners[owner_id] = []
	(_peripheral_owners[owner_id] as Array).append(systemid)
	return ""


## A prop the spawn menu can offer directly. `menu` carries at least a label.
## "" on success, else why the entry was refused, like every other registrar a
## mod reaches. A spawnable filed under an empty type could never be spawned and
## could never be found again to be withdrawn.
static func register_mod_spawnable(type: String, menu: Dictionary,
		owner_id: String) -> String:
	if type.is_empty():
		return "spawnable type is empty"
	var row := menu.duplicate(true)
	row["owner"] = owner_id
	row["label"] = str(menu.get("label", type))
	_mod_spawnables[type] = row
	return ""


## Every mod prop offered on the menu, as {type, label}.
static func mod_spawnables() -> Array:
	var out: Array = []
	for type: String in _mod_spawnables:
		out.append({"type": type, "label": str(_mod_spawnables[type].get("label", type))})
	return out


static func drop_mod(owner_id: String) -> void:
	# Row by row, not systemid by systemid. Two mods may both add pads to the
	# same console -- a console mod and a controller pack, say -- and they land
	# in one list, so erasing the systemid took the other mod's rows with it and
	# left that console short of pads with nothing to say why.
	for systemid: String in (_peripheral_owners.get(owner_id, []) as Array):
		var rows: Array = _mod_peripherals.get(systemid, [])
		var kept: Array = []
		for row: Variant in rows:
			if (row as Dictionary).get("owner", "") != owner_id:
				kept.append(row)
		if kept.is_empty():
			_mod_peripherals.erase(systemid)
		else:
			_mod_peripherals[systemid] = kept
	_peripheral_owners.erase(owner_id)
	for spawn: String in _offered_variants.keys():
		if _offered_variants[spawn].get("owner", "") == owner_id:
			_offered_variants.erase(spawn)
	_built_socket_notes.erase(owner_id)
	for type: String in _mod_spawnables.keys():
		if _mod_spawnables[type].get("owner", "") == owner_id:
			_mod_spawnables.erase(type)


## The single place that turns a catalog item into the string emitted on
## SpawnMenu2D.spawn_requested. Keeping this here means SpawnMenuController stays
## the one and only spawn authority.
##   system     → "model:<systemid>:<model_id>"
##                or, asked for in one of its row's colors,
##                "model_as:<variant>:<systemid>:<model_id>"
##   peripheral → the item's existing spawn string, verbatim
##                or, asked for in one of its colors,
##                "as:<variant>:<that string>"
##
## The systemid rides along because the placeholder row belongs to no platform, so
## its id alone cannot say which core to load. The variant goes in FRONT of it,
## under a prefix of its own: a mod's model id has a colon in it and is everything
## after the last field, so nothing can follow it.
static func spawn_token(systemid: String, item: Dictionary, variant: String = "") -> String:
	if item.get("kind", "system") == "peripheral":
		var spawn: String = item.get("spawn", "")
		return spawn if variant.is_empty() else "%s%s:%s" % [AS, variant, spawn]
	if not variant.is_empty():
		return "%s%s:%s:%s" % [MODEL_AS, variant, systemid, item.get("model_id", "")]
	return "%s%s:%s" % [MODEL, systemid, item.get("model_id", "")]


const MODEL := "model:"
const MODEL_AS := "model_as:"
## Any other row asked for in a color: the color, then the row's own token whole.
const AS := "as:"


## Whether a token asks for a console, in a color or as it comes.
static func is_model_token(token: String) -> bool:
	return token.begins_with(MODEL) or token.begins_with(MODEL_AS)


## The color a console's token asks for, or "" for the model as it comes.
static func variant_of_token(token: String) -> String:
	for prefix: String in [MODEL_AS, AS]:
		if token.begins_with(prefix):
			return token.substr(prefix.length()).get_slice(":", 0)
	return ""


## A row's own token, with the color it was asked for in taken off the front:
## what to spawn. A console's token is read by model_of_token instead.
static func plain_token(token: String) -> String:
	if not token.begins_with(AS):
		return token
	var rest := token.substr(AS.length())
	var colon := rest.find(":")
	return rest.substr(colon + 1) if colon >= 0 else ""


## The other way: what a "model:<systemid>:<model_id>" token asks for, as
## [systemid, model_id].
##
## The id is everything after the SECOND colon, because a mod's model id has a
## colon of its own ("xenu.sfc:shvc001"). Split at every colon and that row
## reaches the console as "xenu.sfc", which is no row at all: the platform's
## first row was spawned whichever one the player picked, so a mod's console
## only came out right while it was the only console on its card.
static func model_of_token(token: String) -> PackedStringArray:
	# Asked for in a color, the color is one more field in front.
	if token.begins_with(MODEL_AS):
		var rest := token.substr(MODEL_AS.length())
		var colon := rest.find(":")
		token = MODEL + (rest.substr(colon + 1) if colon >= 0 else "")
	var parts := token.split(":", true, 2)
	return PackedStringArray([
		parts[1] if parts.size() > 1 else "",
		parts[2] if parts.size() > 2 else "",
	])
