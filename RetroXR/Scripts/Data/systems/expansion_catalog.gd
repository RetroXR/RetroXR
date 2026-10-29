## ExpansionCatalog — the historical console expansions, as physical units.
##
## A 64DD is not a different Nintendo 64 and a Mega-CD is not a different Mega
## Drive. Each was a separate box you bought, carried home and BOLTED TO the
## console: the 64DD went under the N64 through the hatch in its floor, the
## Mega-CD went under the Mega Drive, the 32X went into the cartridge slot on
## top. Two machines, two pieces of media, one stack.
##
## RetroXR used to model each combination as its own systemid — "nintendo_64dd"
## and "sega_cd" sat in the systems list beside the consoles they plug into, and
## spawning one gave you a whole imaginary console that never existed. This file
## is the other way round: an expansion is a THING, it spawns on its own, and it
## only does anything once a console is actually standing on it.
##
## What a row says
## ---------------
##   label       row text in the spawn menu, and the name printed on the unit
##   host        the console systemid this unit belongs to
##   media       the systemid of the media its OWN bay takes ("nintendo_64dd" for
##               a 64DD disk). Empty when the unit takes no media of its own.
##   mount       MOUNT_BELOW — the console stands ON this unit (64DD, Mega-CD)
##               MOUNT_ABOVE — this unit stands on the CONSOLE (32X, Jaguar CD)
##   size        the primitive box, in metres
##   seat_y      MOUNT_BELOW only: where a console standing on this unit rests, in
##               the unit's own frame, metres above its middle. Unset, the top of
##               `size`, which is right for a flat roof. A shell whose highest
##               points are locating pins and a plug rather than its deck says
##               where the deck is (the 64DD), or the console rests on the pins.
##   loader      MediaDimensions.LOADER_* for its own bay
##   media_in_host
##               this unit has NO bay: its media goes into the CONSOLE's own
##               cartridge slot. See the Satellaview row.
##   bays        how many cartridges this unit takes at once. One unless it says
##               otherwise, which is every unit but the Sufami Turbo. A second
##               bay is addressed by INDEX everywhere it is read -- get_media(1),
##               the expansion_media_b: token -- so a row that does not name it
##               keeps exactly the behaviour it had.
##   firmware    files the CORE must already have for this unit to do anything,
##               named as its .info names them. A unit that has not got them is
##               still offered in the spawn menu; switching on a machine built
##               with it refuses with "BIOS required" naming the file
##               (missing_row). The Sega CD, BS-X cartridge, Sufami Turbo, both
##               Super Game Boys and the Saturn's ROM carts and Video CD Card
##               name some.
##   card        the systemid whose spawn card offers this unit, overriding the
##               media rule in card_systemid. Only the Super Game Boys name it,
##               and only because a player went looking for one on the Super
##               Famicom card and did not find it there.
##   rom_title   the title in the internal header of a ROM that IS this unit, so
##               a dump sitting in the library spawns the adapter instead of a
##               cartridge. See adapter_for_rom.
##   rom_code    the same thing for a Game Boy Advance dump, whose identity is the
##               four-character game code at 0xAC rather than a title string --
##               PEAJ, PSAJ and PSAE are the three e-Readers, and they are the
##               same four codes mGBA switches the reader hardware on from.
##   rom_from_firmware
##               this unit's OWN program IS the firmware file above, rather than
##               something a player spawns out of the library. The BS-X cartridge
##               is the other way round -- its shell is a .sfc in the Satellaview
##               folder, and spawning it from there is what fills rom_path. A
##               Super Game Boy has no library file to be spawned from at all, so
##               without this its rom_path stays empty and a pairing that needs
##               it degrades to a plain load without saying so. See
##               RetroSystem._expansion_roms.
##   cap_color   a coloured plate across the unit's top face, for a unit whose
##               real shell is not all one colour. The Expansion Pak's red top
##               is the one that needs it — it is how a player tells the
##               upgrade from the Jumper Pak it replaces at a glance, in a bay
##               where both are the same size and shape. Absent means plain.
##   shell       a GLB the unit wears instead of the primitive box, scaled to
##               `size`. Its markers, when it has them: SocketMarker (where a
##               seated disk's centre sits), EjectButton and AccessLed meshes,
##               CartFloor (where a cartridge in the unit's own slot rests its
##               bottom edge; the 32X) and Flap_Front / Flap_Back (slot flaps
##               origined on their hinges, swung open while a cartridge is in).
##   shell_albedo
##               a colour map swapped onto the shell's "shell" material, for a
##               second unit that is the same casting in a different finish.
##   shell_lods  lower levels of detail for the shell, nearest first, each
##               [GLB path, metres from the camera where it takes over]. They
##               must share the shell's bounds; see RetroExpansion._build_shell_lods.
##   connector   for a MOUNT_CARTRIDGE unit whose modelled tongue goes INTO the
##               slot (the e-Reader): the point, in the unit's frame, that the
##               console's cartridge seat takes -- where a cartridge's middle
##               would be. Absent, the unit stands on the console's roof.
##   seat_yaw    degrees a MOUNT_CARTRIDGE unit is turned about its own +Y when
##               seated, relative to a cartridge (whose +Z, its label, faces away
##               from the player). The e-Reader is 180: its front -- card slit,
##               sticker -- faces the player. Absent, 0.
##   accessory_group
##               a clip-on accessory this unit takes, by the group it joins: the
##               unit grows an AccessoryMount snap zone at its shell's origin,
##               the accessory rides it from then on and is saved on the unit as
##               "accessory". The 32X's Model 2 spacer ("sega32x_spacer"). Absent,
##               no mount. See RetroExpansion._build_accessory_mount.
##   swipe_slit  for a LOADER_SWIPE unit whose shell has a card channel: the
##               groove's frame in the unit's frame (axes as CardSwipeSlit
##               documents them). Absent, a groove is cut in the roof.
##   socket      for a MOUNT_ABOVE unit, which of the console's sockets it goes
##               into, when that is not the one ExpansionSocket every such unit
##               shares. A Saturn's Video CD Card ("mpeg_card") slides into a slot
##               in the back of its own, behind the battery door, and stays in while
##               a cartridge goes in and out of the slot behind the lid. The console
##               grows the socket (RetroSystem._build_unit_sockets) and the model
##               places it (RetroSystemModel.configure_unit_socket). Absent, "".
##   ethernet_port
##               a network adapter's RJ45 socket, on the face left outside the
##               console, and the link-bus port its core attaches the cable on:
##               4 for the GameCube's Broadband Adapter, 1 for the PS2's Network
##               Adapter. The unit grows an EthernetPort; EthernetBus walks from it
##               to the console it is seated on. Absent, no socket.
##   cover_socket
##               for a MOUNT_BELOW unit, the opening in the console's floor its plug
##               goes up into, when the console's model covers that opening
##               (RetroSystemModel.configure_cover_socket): "n64_ext" under the N64,
##               "snes_ext" under a Super NES. The cover is a PortCover in the
##               console's slot for that id; the unit takes no console whose cover
##               is on, and the slot is shut while the console stands on the unit.
##               Absent, the console stands on the unit as it always did.
##   jack        for a unit with an `ethernet_port` whose shell has its jack modelled:
##               the socket's frame in the unit's frame, its +Z out of the jack's
##               mouth (where a plug arrives from) and its +Y the side the plug's
##               latch is on. A mod's shell sets it (override_expansion_shell).
##               Absent, the socket is in the middle of the face left showing.
##   link_socket, link_plug
##               for a unit that plugs into its console's link port and passes it
##               through to a socket of its own -- the e-Reader's EXT on its top:
##               that socket's frame in the unit's frame (a LinkPort's, +Z out of
##               the mouth, +Y the key side) and the point where the unit's plug
##               leaves its housing. Seated where that plug lands in the console's
##               LinkPort, the console's port is moved up into the socket
##               (RetroExpansion._take_link_port); elsewhere -- an SP -- it stays.
##               A mod's shell may move either, on a unit whose row has them.
##               Absent, the unit has no link socket.
##   slot_basis  for a LOADER_SLOT unit, how its media lies as it goes in, in the
##               slot's frame (MediaSlot rides it along the slot's -Z). Absent, a
##               flat disk's quarter turn back: label up, shutter first (64DD,
##               FDS). The Game Boy Player's Game Pak goes in label down, contacts
##               first: a quarter turn the other way.
##   slot_marker_depth
##               for a LOADER_SLOT unit with a shell: the media rides in until its
##               MIDDLE is at the shell's SocketMarker (the Game Boy Player's Game
##               Pak, whose end stays out of the slot). Absent, to the disk's lip
##               just inside the mouth.
##   eject_axis  for a unit whose shell has its own EjectButton cap: the way it is
##               pushed, in the unit's frame, when that is not into the front face
##               -- the Game Boy Player's lever, in its right side, slides toward
##               the front (+Z). The hit box then sits on the face the cap is in.
##   eject_travel
##               how far that cap travels, in metres. Absent, 4 mm.
##   default_occupant
##               this unit comes pre-installed on a bare console — a Jumper
##               Pak, not something a player goes looking for. RetroSystem
##               seats one automatically the first time a fresh console of the
##               matching host is built, and never on a restore, where
##               whatever the save recorded (this unit, a real upgrade, or
##               nothing) always wins. See default_occupant_for and
##               RetroSystem._seed_default_occupant.
##
## Which way a unit mounts is the whole of the geometry: the LOWER object always
## wears the socket (a snap zone on its top face) and the UPPER object always
## wears the foot (a snap grab point on its underside). One relation, drawn from
## whichever side the row says. That is what lets the Tower of Power exist
## without a single line about towers: a Mega-CD accepts a Mega Drive on its top,
## and that same Mega Drive accepts a 32X on ITS top, so the three stack by two
## independent facts rather than by a special case.
class_name ExpansionCatalog
extends RefCounted

## Re-exported from ExpansionDefs, which owns them so a unit file can name one
## without referencing this class -- see expansion_defs.gd. Callers keep saying
## ExpansionCatalog.MOUNT_BELOW.
const MOUNT_BELOW := ExpansionDefs.MOUNT_BELOW
const MOUNT_ABOVE := ExpansionDefs.MOUNT_ABOVE
const MOUNT_CARTRIDGE := ExpansionDefs.MOUNT_CARTRIDGE
const SAVE_OWNER_MEDIA := ExpansionDefs.SAVE_OWNER_MEDIA
const SAVE_OWNER_UNIT := ExpansionDefs.SAVE_OWNER_UNIT


## Every expansion is a file of its own under expansions/, holding its ROW, the
## BOOT recipes only it takes part in, and the notes for both. A combination
## recipe belongs to the unit that decides its core -- the Tower of Power is
## picodrive because of the 32X, so it lives in sega_32x.gd.
const _UNITS: Array = [
	preload("res://Scripts/Data/systems/expansions/nintendo_64dd.gd"),
	preload("res://Scripts/Data/systems/expansions/nintendo_64dd_dev.gd"),
	preload("res://Scripts/Data/systems/expansions/expansion_pak.gd"),
	preload("res://Scripts/Data/systems/expansions/jumper_pak.gd"),
	preload("res://Scripts/Data/systems/expansions/fds.gd"),
	preload("res://Scripts/Data/systems/expansions/satellaview.gd"),
	preload("res://Scripts/Data/systems/expansions/bsx_cart.gd"),
	preload("res://Scripts/Data/systems/expansions/sufami_turbo.gd"),
	preload("res://Scripts/Data/systems/expansions/super_game_boy.gd"),
	preload("res://Scripts/Data/systems/expansions/super_game_boy_2.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_cd.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_cd_ram_cart.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_32x.gd"),
	preload("res://Scripts/Data/systems/expansions/power_base_converter.gd"),
	preload("res://Scripts/Data/systems/expansions/fm_sound_unit.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_saturn_ram_cart.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_saturn_extram_1m.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_saturn_extram_4m.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_saturn_kof95_rom.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_saturn_ultraman_rom.gd"),
	preload("res://Scripts/Data/systems/expansions/sega_saturn_vcd_card.gd"),
	preload("res://Scripts/Data/systems/expansions/pc_engine_cd.gd"),
	preload("res://Scripts/Data/systems/expansions/jaguar_cd.gd"),
	preload("res://Scripts/Data/systems/expansions/ereader.gd"),
	preload("res://Scripts/Data/systems/expansions/ereader_plus.gd"),
	preload("res://Scripts/Data/systems/expansions/ereader_usa.gd"),
	preload("res://Scripts/Data/systems/expansions/gamecube_broadband_adapter.gd"),
	preload("res://Scripts/Data/systems/expansions/ps2_network_adapter.gd"),
	preload("res://Scripts/Data/systems/expansions/game_boy_player.gd"),
]

## The canonical order of the units, and it is LOAD-BEARING: sorted_ids() hands
## back ids in this order and boot_for() builds its "host|id|id" key from that,
## so a pair reordered here stops matching its BOOT row -- silently, since the
## lookup just misses. Assembly walks this list rather than either source, so a
## unit file reordered in _UNITS cannot change it.
const _ORDER: Array = [
	"nintendo_64dd", "nintendo_64dd_dev", "expansion_pak", "jumper_pak", "fds", "satellaview",
	"bsx_cart", "sufami_turbo", "super_game_boy", "super_game_boy_2",
	"sega_cd", "sega_cd_ram_cart", "sega_32x", "power_base_converter", "fm_sound_unit",
	"sega_saturn_ram_cart", "sega_saturn_extram_1m", "sega_saturn_extram_4m",
	"sega_saturn_kof95_rom", "sega_saturn_ultraman_rom", "sega_saturn_vcd_card",
	"pc_engine_cd", "jaguar_cd", "ereader", "ereader_plus", "ereader_usa",
	"gamecube_broadband_adapter", "ps2_network_adapter", "game_boy_player",
]


## How a host+expansion combination is actually launched, keyed by the host
## systemid and the attached expansion ids joined with "|" in ROWS order.
##
##   core     the core the COMBINATION needs, which is often not the console's
##            own default: a Mega Drive with a 32X on it is a picodrive machine.
##   roms     which media the core would be handed, in order. "host" is the
##            console's own slot, "expansion:<id>" is that unit's bay. An entry
##            whose bay is EMPTY is skipped, and the first survivor is what the
##            core is actually given — see the note on subsystems below.
##   core_only_with_host
##            `core` above applies only while the CONSOLE's own slot is filled.
##            With it empty, expansion_boot() drops the core and the machine
##            resolves one the way a bare console does -- the player's own
##            pick, or the manager's default for the systemid. Set it only for
##            a stack whose empty-slot boot is an ordinary way to play AND
##            whose every candidate core handles it; without it a row pins its
##            core either way, which is what the other rows need.
##   options  core options the combination pins, the same way BiosBoot pins the
##            BIOS ones.
##   sidecar  a file extension the CORE looks for beside the host cartridge,
##            rather than being handed. See the 64DD row.
##
## Subsystems: REACHABLE, since the BS-X pairing was wired up. A row that names
## one is loaded through retro_load_game_special with the whole ordered set —
## Libretro::StartSubsystemContent carries the array, RetroSystem's
## _start_subsystem_content assembles it, and the C++ resolves the ident against
## whatever table the core published. A row WITHOUT a `subsystem` block still
## loads through a plain retro_load_game with one path, which for most of them is
## not a limitation at all; for the 64DD it remains the real gap. Checked at
## source with the two sessions working on those cores:
##
##   - snes9x advertises exactly ONE subsystem, "multicart_addon", and it is not
##     the Satellaview. BS-X content is auto-detected from the ROM header and the
##     core sources BS-X.bin itself. Nothing is missing here.
##   - mupen64plus-next declares an "ndd" subsystem AND a sidecar workaround, and
##     the workaround is not good enough. See `subsystem` below.
##
## `subsystem` on a row records a VERIFIED pairing: the ident the core advertises
## and the order it wants its media in. It is deliberately kept apart from `roms`,
## which means something else — `roms` is the preference order for the single path
## handed over on a plain load, and the two orders genuinely differ for the 64DD
## and again for the Super Game Boy. A row whose subsystem cannot be completed
## (an empty bay, a core bridge without the call, a core that never published the
## ident) falls back to that plain load rather than failing.
##
## An earlier version of this file asserted a "64dd" subsystem, a "bsx" one, and
## a "mupen64plus-64dd-hardware" core option. All three were invented, and the
## last one does not exist in that core at all. They are recorded here because a
## plausible guess in a data table is worse than a blank: it reads as research.
##
## A combination with no row here still stacks physically and still says what it
## is; it simply launches as the bare console would. That is deliberate: the
## point of this file is the hardware, and a missing launch recipe should cost a
## player a feature, not the ability to build the stack.
##
## UNVERIFIED marks a row nobody has checked against the core's source or run.
## The core names on those are informed guesses and nothing more.
## The assembled tables. Public because callers read ExpansionCatalog.ROWS
## directly, and a Dictionary built here reads exactly like the const it
## replaced.
##
## Assembled in _static_init rather than lazily: it runs once when the class is
## first loaded, so no accessor has to remember to prime the table first, and
## there is no state where ROWS is half built.
static var ROWS: Dictionary = {}
static var BOOT: Dictionary = {}


static func _static_init() -> void:
	var by_id: Dictionary = {}
	for unit: Script in _UNITS:
		by_id[unit.ID] = unit
	# Walked in _ORDER rather than in _UNITS order: insertion order IS
	# sorted_ids' order, so it must be stated once here and not be a property of
	# how the preloads happen to be listed.
	for id: String in _ORDER:
		ROWS[id] = (by_id[id] as Script).ROW
	for unit: Script in _UNITS:
		BOOT.merge(unit.BOOT)
	_check_row_keys()


## Every field a unit's row may hold (the row docs above say what each is), and
## what it reads as when the row leaves it out. The schema in one place: the
## accessors below read through _field(), and _static_init refuses no row but
## reports any key not listed here, so a misspelt key is an error in the log rather
## than a silent default.
const FIELDS := {
	"label": null,
	"host": "",
	"media": "",
	"passes": [],
	"mount": MOUNT_BELOW,
	"size": Vector3(0.3, 0.08, 0.25),
	"lid": false,
	"loader": MediaDimensions.LOADER_NONE,
	"media_in_host": false,
	"panel": "",
	"memory": "",
	"label_front": false,
	"label_top": false,
	"card": "",
	"bays": 1,
	"firmware": [],
	"firmware_first_present": false,
	"rom_code": "",
	"rom_title": "",
	"rom_from_firmware": false,
	"default_occupant": false,
	"save_owner": SAVE_OWNER_MEDIA,
	"shell": "",
	"shell_albedo": "",
	"shell_lods": [],
	"shell_offset": Vector3.ZERO,
	"connector": null,
	"seat_y": NAN,
	"seat_yaw": 0.0,
	"swipe_slit": null,
	"accessory_group": "",
	"cap_color": Color(0, 0, 0, 0),
	"socket": "",
	"cover_socket": "",
	"ethernet_port": -1,
	"jack": null,
	"link_socket": null,
	"link_plug": null,
	"slot_basis": null,
	"slot_marker_depth": false,
	"eject_axis": null,
	"eject_travel": NAN,
}


## A row field, or its FIELDS default when the row (with any mod's shell laid
## over it, row()) leaves it out. A list default comes back as a fresh copy.
static func _field(id: String, key: String) -> Variant:
	if not FIELDS.has(key):
		push_error("[ExpansionCatalog] '%s' is not a row field" % key)
		return null
	var r := row(id)
	if r.has(key):
		return r[key]
	var fallback: Variant = FIELDS[key]
	return (fallback as Array).duplicate() if fallback is Array else fallback


## Report any key a unit's row holds that FIELDS does not list.
static func _check_row_keys() -> void:
	for id: String in ROWS:
		for key: Variant in (ROWS[id] as Dictionary):
			if not FIELDS.has(key):
				push_error("[ExpansionCatalog] unit '%s': '%s' is not a row field (see FIELDS)" % [id, key])


## The core a recipe names on this platform: `android` when there is one and we
## are on it, else `core`.
##
## Split out and given `mobile` rather than asking the OS itself, because the
## branch that matters cannot be reached from a desktop test run -- and it is
## the branch that shipped broken. A Quest resolved to "mupen64plus_next", a
## name the buildbot publishes for Windows only, and reported the core missing.
static func core_of(spec: Dictionary, mobile: bool) -> String:
	if mobile:
		var over := str(spec.get("android", ""))
		if not over.is_empty():
			return over
	return str(spec.get("core", ""))

## The row for an id, or an empty Dictionary. With a mod's shell for the unit
## laid over it: every accessor below reads through here, so the shell, its size
## and where its tongue and card channel are all change together or not at all.
##
## The id may name one of that shell's variants, "<unit>@<variant>" (shell_key):
## the variant's fields are laid over the shell's.
static func row(id: String) -> Dictionary:
	var variant := ""
	var at := id.find(VARIANT_MARK)
	if at >= 0:
		variant = id.substr(at + 1)
		id = id.substr(0, at)
	if not _mod_shells.has(id):
		return ROWS.get(id, {})
	var merged: Dictionary = (ROWS.get(id, {}) as Dictionary).duplicate()
	merged.merge(_mod_shells[id]["fields"] as Dictionary, true)
	merged.merge((_mod_shells[id]["variants"] as Dictionary).get(variant, {}) as Dictionary, true)
	return merged


# ── a mod's shell for a unit ──────────────────────────────────────────────────

## What a mod may say about a unit's shell, and the type each must be. Nothing
## else of a row is a mod's to change: what the unit IS -- its host, its media,
## the dump it runs -- stays the game's.
const _SHELL_FIELDS := {
	"shell": TYPE_STRING, "size": TYPE_VECTOR3, "shell_lods": TYPE_ARRAY,
	"connector": TYPE_VECTOR3, "swipe_slit": TYPE_TRANSFORM3D, "seat_yaw": TYPE_FLOAT,
	"shell_offset": TYPE_VECTOR3, "jack": TYPE_TRANSFORM3D,
	# Where the shell's link socket and plug are -- on a unit whose row has them;
	# a shell does not give a unit a socket its hardware never had.
	"link_socket": TYPE_TRANSFORM3D, "link_plug": TYPE_VECTOR3,
	# Where a console standing on the unit rests, for a shell whose deck is not
	# its top: the Super Famicom sinks 19 mm into the Satellaview's tray.
	"seat_y": TYPE_FLOAT,
}

## unit id -> {owner, fields, variants: {variant id -> fields}}.
static var _mod_shells: Dictionary = {}

## Between a unit's id and one of its shell's variants in a shell_key.
const VARIANT_MARK := "@"


## The id to read a unit's shell by, for a unit that is `variant` (its row's
## color or market, SystemModelRegistry.variant_of): the unit's id, or
## "<unit>@<variant>" when the mod's shell it wears has a shell of that variant's
## own -- a market whose unit was another molding, at another size. Every
## accessor below takes either.
static func shell_key(id: String, variant: String) -> String:
	if variant.is_empty() or not _mod_shells.has(id) \
			or not (_mod_shells[id]["variants"] as Dictionary).has(variant):
		return id
	return id + VARIANT_MARK + variant


## How far a unit's shell sits from the middle of its own bounds, in the unit's
## frame. A unit is seated by the middle of its size, and a shell is centred on
## that; but the part of a real shell that locates it is not always the middle of
## the whole -- a pak whose body goes in a pocket carries a boss on one face and a
## cap that overhangs the other. Zero for every shell the game ships.
static func shell_offset_of(id: String) -> Vector3:
	return _field(id, "shell_offset")


## Where a network adapter's socket is in the unit's frame (the row docs'
## `jack`), or null for the middle of the face left outside the console.
static func ethernet_jack_of(id: String) -> Variant:
	return _field(id, "jack")


## The socket that carries the console's link port up through the unit (the row
## docs' `link_socket`), or null for a unit that passes none through.
static func link_socket_of(id: String) -> Variant:
	return _field(id, "link_socket")


## Where the unit's own plug into the console's link port is (the row docs'
## `link_plug`), or null.
static func link_plug_of(id: String) -> Variant:
	return _field(id, "link_plug")


## The mod whose shell this unit wears, or "".
static func shell_owner_of(id: String) -> String:
	return str((_mod_shells.get(id.get_slice(VARIANT_MARK, 0), {}) as Dictionary).get("owner", ""))


## "" on success, else why the shell was refused.
##
## `shell` and `size` are required; the rest default to the unit's own, which is
## right for a model in the same frame as the game's (the same shell with its
## branding on, say). `size` is the model's true bounds, fitted per axis.
##
## `variants` is {variant id: fields}, for a unit whose markets were different
## moldings: the shell a unit of that variant wears (shell_key), each field over
## the shell's. One with a shell of its own and no `shell_lods` has one level.
static func register_mod_shell(id: String, fields: Dictionary, owner_id: String) -> String:
	if not ROWS.has(id):
		return "'%s' is not an expansion unit" % id
	var own := fields.duplicate()
	var variants: Variant = own.get("variants", {})
	own.erase("variants")
	var checked := {}
	var err := _check_shell_fields(own, checked)
	if not err.is_empty():
		return err
	if not checked.has("shell"):
		return "shell does not exist: "
	if not checked.has("size"):
		return "size is required: the shell's true bounds, in metres"
	# The game's lower levels and its recolour belong to the game's shell.
	if not checked.has("shell_lods"):
		checked["shell_lods"] = []
	checked["shell_albedo"] = ""
	if not (variants is Dictionary):
		return "variants is {variant id: shell fields}"
	var by_variant := {}
	for vid: Variant in (variants as Dictionary):
		var vname := str(vid)
		var given: Variant = (variants as Dictionary)[vid]
		if not (vid is String) or vname.is_empty() or vname.contains(VARIANT_MARK) or not (given is Dictionary):
			return "variants is {variant id: shell fields}, and an id has no '%s'" % VARIANT_MARK
		var theirs := {}
		err = _check_shell_fields(given as Dictionary, theirs)
		if not err.is_empty():
			return "variant %s: %s" % [vname, err]
		if theirs.has("shell") and not theirs.has("shell_lods"):
			theirs["shell_lods"] = []
		by_variant[vname] = theirs
	_mod_shells[id] = {"owner": owner_id, "fields": checked, "variants": by_variant}
	return ""


## Copies `fields` into `checked`, checking each is one a shell can set, of its
## type, and a model that is there at a size that is one. Returns "" when ok, else the reason.
static func _check_shell_fields(fields: Dictionary, checked: Dictionary) -> String:
	for key: Variant in fields:
		if not _SHELL_FIELDS.has(key):
			return "'%s' is not something a shell can set (%s)" % [key, ", ".join(_SHELL_FIELDS.keys())]
		var value: Variant = fields[key]
		if (key == "seat_yaw" or key == "seat_y") and value is int:
			value = float(value)
		if typeof(value) != _SHELL_FIELDS[key]:
			return "%s is the wrong type" % key
		checked[key] = value
	if checked.has("shell"):
		var shell := str(checked["shell"])
		if shell.is_empty() or not ResourceLoader.exists(shell):
			return "shell does not exist: %s" % shell
	if checked.has("size"):
		var size: Vector3 = checked["size"]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return "size must be positive on every axis"
	for level: Variant in (checked.get("shell_lods", []) as Array):
		if not (level is Array) or (level as Array).size() != 2 \
				or not ResourceLoader.exists(str((level as Array)[0])):
			return "a shell_lods entry is [model path, metres], and its model must exist"
	return ""


static func drop_mod(owner_id: String) -> void:
	for id: String in _mod_shells.keys():
		if _mod_shells[id]["owner"] == owner_id:
			_mod_shells.erase(id)


static func has(id: String) -> bool:
	return ROWS.has(id)


## The unit's FIXED name. A unit's memory card id is minted from it and persisted
## (RetroExpansion), so it must not move with the player's region: anything shown
## to the player goes through display_label_of() instead.
static func label_of(id: String) -> String:
	var named: Variant = _field(id, "label")
	return id if named == null else str(named)


## The unit's name as the player's region calls it ("Mega-CD" in Europe).
static func display_label_of(id: String) -> String:
	return RegionalNames.addon_name(id, label_of(id))


static func host_of(id: String) -> String:
	return str(_field(id, "host"))


static func media_of(id: String) -> String:
	return str(_field(id, "media"))


## Other systems' media the unit's bay takes and hands straight to the console,
## as the 32X does a Genesis cartridge. Such a cartridge boots on the console's
## own core (ExpansionLaunch.expansion_boot).
static func passes_of(id: String) -> Array:
	return _field(id, "passes") as Array


static func mount_of(id: String) -> int:
	return int(_field(id, "mount"))


static func size_of(id: String) -> Vector3:
	return _field(id, "size")


## True when this unit opens with a hinged lid rather than sliding a tray out.
static func lid_of(id: String) -> bool:
	return bool(_field(id, "lid"))


static func loader_of(id: String) -> int:
	return int(_field(id, "loader"))


## True when this unit has no bay of its own and its media goes into the
## CONSOLE's cartridge slot instead.
static func media_in_host(id: String) -> bool:
	return bool(_field(id, "media_in_host"))


## The front panel this unit wears, if it wears one -- a scene, so what is on a
## machine's face is named beside the machine instead of branched on elsewhere.
static func panel_of(id: String) -> String:
	return str(_field(id, "panel"))


## The card family this unit keeps saves of its own in -- a Sega CD's backup
## memory -- or "" for a unit that keeps none.
static func memory_of(id: String) -> String:
	return str(_field(id, "memory"))


## Whether a unit that mounts as a cartridge wears its name on its front face
## rather than the one a console's slot turns away. See RetroExpansion._build_body.
static func label_front_of(id: String) -> bool:
	return bool(_field(id, "label_front"))


## Whether a unit wears its name along the top of its face, for one stood in a slot
## that swallows the lower half. See RetroExpansion._build_body.
static func label_top_of(id: String) -> bool:
	return bool(_field(id, "label_top"))


## The unit whose memory is this card family, or "" -- how a card shelf listing
## that memory knows what to put in the room.
static func unit_for_memory(family: String) -> String:
	if family.is_empty():
		return ""
	for id: String in ROWS:
		if memory_of(id) == family:
			return id
	return ""


## The GLB this unit wears, or "" for the primitive box.
static func shell_of(id: String) -> String:
	return str(_field(id, "shell"))


static func shell_albedo_of(id: String) -> String:
	return str(_field(id, "shell_albedo"))


## The shell's lower levels of detail, nearest first: [GLB path, metres from the
## camera where it takes over]. Empty for a shell that has one level. Each GLB must
## share the shell's bounds, since all of them are fitted with the shell's numbers.
static func shell_lods_of(id: String) -> Array:
	return _field(id, "shell_lods")


## Where the console's cartridge seat takes this unit, in the unit's own frame, or
## null to seat it on the console's roof (see RetroExpansion._aim_connector). Set
## by a unit whose modelled tongue goes INTO the slot the way a cartridge's does.
static func connector_of(id: String) -> Variant:
	return _field(id, "connector")


## Where a console standing on this unit rests, in the unit's frame, or NAN for
## the top of its box. See the row docs above.
static func seat_y_of(id: String) -> float:
	return float(_field(id, "seat_y"))


## How a LOADER_SLOT unit's media lies as it goes in, in the slot's frame (the
## slot rides it along its own -Z), or null for the flat disk's quarter turn back.
## See the row docs above.
static func slot_basis_of(id: String) -> Variant:
	return _field(id, "slot_basis")


## True when a LOADER_SLOT unit's media rides in until its MIDDLE is at the
## shell's SocketMarker, rather than to the disk's lip. See the row docs above.
static func slot_marker_depth_of(id: String) -> bool:
	return bool(_field(id, "slot_marker_depth"))


## The way a shell's own eject cap is pushed, in the unit's frame, or null for
## into the front face. See the row docs above.
static func eject_axis_of(id: String) -> Variant:
	return _field(id, "eject_axis")


## How far a shell's own eject cap travels, in metres; NAN for the default.
static func eject_travel_of(id: String) -> float:
	return float(_field(id, "eject_travel"))


## Degrees a cartridge-mounted unit is turned about its own +Y when seated, relative
## to a cartridge. See the row docs above.
static func seat_yaw_of(id: String) -> float:
	return float(_field(id, "seat_yaw"))


## The group of the clip-on accessory this unit takes, or "" for none. See the row
## docs above.
static func accessory_group_of(id: String) -> String:
	return str(_field(id, "accessory_group"))


## The swipe groove's frame in the unit's own frame, or null to cut the groove in
## the roof. Set by a shell with a card channel of its own, so the groove is where
## the model's channel is. CardSwipeSlit documents the frame's axes.
static func swipe_slit_of(id: String) -> Variant:
	return _field(id, "swipe_slit")


## Media systemids a console's OWN cartridge slot must take on top of its own,
## because the expansion that uses them has no mouth to put them in.
##
## Not gated on the unit being attached, deliberately. A BS-X cartridge works in
## a bare Super Famicom -- it boots its menu, it just has no broadcast to tune --
## and snes9x loads a .bs the same way with or without the base station. Gating
## it would mean a player holding the right cartridge for the machine in front of
## them gets a silent refusal, which is the failure mode this codebase least
## wants: a snap zone that declines an object simply does nothing.
static func host_slot_media(host: String) -> Array[String]:
	var out: Array[String] = []
	for id in ids_for_host(host):
		if media_in_host(id):
			var m := media_of(id)
			if not m.is_empty():
				out.append(m)
	return out


## True when this unit has a system tile of its own in the spawn menu.
##
## The test is whether the unit's media is a systemid of its OWN. A 64DD's disks
## are "nintendo_64dd" and a Mega-CD's discs are "sega_cd", so both are systems
## the core info knows, both appear in the systems list, and both therefore get a
## card that is the right place to spawn the unit from.
##
## Checked against libretro-core-info: media == id holds for eight of the eleven
## ids, and every one of those eight appears as a systemid in at least one .info
## file. The rule is not a coincidence of spelling -- a unit whose media is its
## own systemid IS a system as far as the rest of RetroXR is concerned, which is
## precisely what having a card means.
##
## The Jaguar CD names its discs through virtualjaguar's secondary_systemids,
## so it has a tile like the rest.
##
## The three that remain are exceptions on purpose, and no .info entry would fix
## them. A BS-X cartridge runs Satellaview downloads and a Super Game Boy runs
## Game Boy cartridges: the media each takes already belongs to another system,
## and minting an id for the ADAPTER would put a tile in the systems list for a
## machine nobody owns separately -- the imaginary-console mistake this whole file
## was written to undo. They are offered from the card of whatever they play.
static func has_own_card(id: String) -> bool:
	return media_of(id) == id


## The systemid whose card this unit is offered from.
##
## A unit with a tile of its own is offered from that tile. A unit WITHOUT one
## belongs on the card of the media it runs, because that is the card a player
## reaching for it is already on. The BS-X cartridge is the case that made this
## a rule: it runs Satellaview downloads, so it belongs on the Satellaview card
## and not on the Super Famicom's, where it sat beside a console it is only one
## third of and where a player who had never heard of the base station met it
## first. The Jaguar CD moved the same way and for the same reason: it used to
## sit among the Jaguar's pads because its discs were filed as Jaguar media, and
## now that they are jaguar_cd it is reached from the Jaguar CD's own card.
##
## `card` on a row overrides all of that, and the Super Game Boys are why. The
## media rule put them on the Game Boy card, which is arguable -- it is where you
## are standing when you want to play a Game Boy game -- and was tried. It failed
## the only test that counts: the person who asked for the feature went looking
## for it, on the Super Famicom card, and did not find it. A Super Game Boy IS a
## Super Famicom cartridge and goes into a Super Famicom slot, so that is where a
## hand reaches for it. An override rather than a change to the rule, because the
## rule is still right for the BS-X cartridge and the reasoning above still holds.
static func card_systemid(id: String) -> String:
	if has_own_card(id):
		return id
	var override := str(_field(id, "card"))
	if not override.is_empty():
		return override
	var m := media_of(id)
	return m if not m.is_empty() else host_of(id)


## The units offered from `systemid`'s card -- those with no tile of their own
## that are filed here. In ROWS order.
##
## Firmware is NOT filtered here: this answers where a unit belongs, and
## firmware_present answers whether a machine built with it can start. Keeping them apart
## means a unit does not silently change cards when a file appears on disk.
static func ids_carded_on(systemid: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ROWS:
		if not has_own_card(id) and card_systemid(id) == systemid:
			out.append(id)
	return out


## How many cartridges this unit holds at once. One unless the row says more.
##
## Clamped at the bottom rather than trusted: a row typo of 0 would build a unit
## with no bay at all, which reads as a solid box a player cannot load and gives
## no clue why.
static func bays_of(id: String) -> int:
	return maxi(1, int(_field(id, "bays")))


## Firmware this unit cannot work without, named exactly as the core's .info
## names it. Empty for every unit whose hardware is entirely ours to draw.
static func firmware_of(id: String) -> Array:
	return (_field(id, "firmware") as Array).duplicate()


## The unit a ROM in the library IS, or "" for an ordinary piece of media.
##
## A Super Game Boy dump is a perfectly good Super Famicom .sfc and sits in the
## snes folder with everything else, so without this it spawns as a cartridge --
## a slab with nowhere to put a Game Boy game in it. Same problem the BS-X shell
## had, and the same answer: recognise it on the way out of the library and spawn
## the unit instead.
##
## Matched on the ROM's INTERNAL HEADER, not its filename. That is what bsnes
## itself matches on to decide which adapter it is emulating, so the two agree by
## construction; a filename rule would disagree the moment somebody renamed a
## file, and would have to guess at "Super Game Boy (Japan, USA) (Rev 1)" versus
## "Super Game Boy 2 (Japan)" -- where the first two revisions are both an SGB1
## and only the third is a different machine.
##
## Both header positions are read because the position is a fact about the ROM
## rather than about the system, and a copier header is skipped: those add 512
## bytes on the front, which is exactly what a size that is not a whole number of
## kibibytes means.
static func adapter_for_rom(path: String) -> String:
	if path.is_empty():
		return ""
	var wanted := false
	for id: String in ROWS:
		if not str(ROWS[id].get("rom_title", "")).is_empty() \
				or not str(ROWS[id].get("rom_code", "")).is_empty():
			wanted = true
			break
	if not wanted:
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var length := f.get_length()
	var skip: int = 512 if (length % 1024) == 512 else 0
	var titles: Array[String] = []
	for base: int in [0x7FC0, 0xFFC0]:
		var at: int = base + skip
		if at + 21 > length:
			continue
		f.seek(at)
		titles.append(f.get_buffer(21).get_string_from_ascii().strip_edges())
	var code := _gba_game_code(f, length)
	f.close()
	for id: String in ROWS:
		var title := str(ROWS[id].get("rom_title", ""))
		if not title.is_empty() and titles.has(title):
			return id
		var want_code := str(ROWS[id].get("rom_code", ""))
		if not want_code.is_empty() and want_code == code:
			return id
	return ""


## The four-character game code at 0xAC, and "" for anything that is not a Game
## Boy Advance ROM.
##
## Gated on the fixed 0x96 at 0xB2, which every GBA header carries and the BIOS
## itself checks. Without it four bytes of a Super Famicom dump that happened to
## read "PEAJ" would spawn an e-Reader in place of somebody's game -- unlikely,
## but the check costs one byte and the failure would be baffling.
static func _gba_game_code(f: FileAccess, length: int) -> String:
	if length < 0xC0:
		return ""
	f.seek(0xB2)
	if f.get_8() != 0x96:
		return ""
	f.seek(0xAC)
	return f.get_buffer(4).get_string_from_ascii()


## Where this unit's own program lives when the unit IS its program.
##
## TWO SOURCES, and which one a unit uses is a fact about the hardware.
##
## A reader's cartridge dump is an ordinary Game Boy Advance ROM, so it comes out
## of the LIBRARY, found by the header code in `rom_code`. Nothing has to be
## installed and nothing has to be renamed; the copy the player already owns is
## the one that runs.
##
## The Super Game Boys still come from the core's system directory, because their
## dumps are declared as firmware in the VENDORED bsnes .info and there is no
## bsnes overlay to remove them from -- an overlay replaces an entry wholesale, so
## dropping two rows would mean forking an upstream file that keeps gaining them.
## The two adapters therefore work differently on purpose. Do not tidy one branch
## into the other; ereader_tests holds both.
##
## The firmware branch takes the FIRST name, not any that happens to be present.
## firmware_of is a list of alternatives for the gate, but a unit runs one
## program: the Super Game Boy 2 names SGB2.sfc and must not fall back to
## SGB1.sfc, or a player with both dumps would build one machine and be handed
## the other.
##
## Empty for a unit that is not its own program at all -- a BS-X cartridge
## carries a shell the player spawned it from, and answering with BS-X.bin here
## would quietly swap the cartridge in their hand for the one in the system
## directory.
##
## The firmware branch returns its path whether or not the file is there, since
## existence is firmware_present's question. The library branch cannot: it has
## nothing to name until it has found something.
static func firmware_rom_path(id: String) -> String:
	if not str(_field(id, "rom_code")).is_empty():
		return AdapterRoms.path_for(id)
	if not bool(_field(id, "rom_from_firmware")):
		return ""
	var wanted := firmware_of(id)
	if wanted.is_empty():
		return ""
	var core := str(boot_for(host_of(id), [id]).get("core", ""))
	if core.is_empty():
		return ""
	# The exception, by row: regional alternatives of one program, where any
	# installed one is the right one. A Sega CD's BIOS is.
	if bool(_field(id, "firmware_first_present")):
		var present := {}
		for status_row: Dictionary in FirmwareState.shared().evaluate(
				core, FirmwareRequirements.for_core(core)):
			var status := int(status_row.get("status", -1))
			if status == FirmwareState.Status.PRESENT or status == FirmwareState.Status.MISMATCH:
				present[str(status_row.get("path", ""))] = true
		return FirmwareRequirements.destination(core, pick_firmware(wanted, present))
	return FirmwareRequirements.destination(core, str(wanted[0]))


## The first of `wanted` that is in `present`, or the first of `wanted` when none
## is, so a refusal still names a file.
static func pick_firmware(wanted: Array, present: Dictionary) -> String:
	for name: Variant in wanted:
		if present.has(str(name)):
			return str(name)
	return str(wanted[0]) if not wanted.is_empty() else ""


## Can a machine built with this unit start -- is the program it runs on this
## machine? Read at power-on (missing_row), never to hide the unit from the menu.
##
## A unit whose program is a LIBRARY dump is present when a dump carrying its
## header code is on a shelf. That is the whole gate for the readers: no install,
## no BIOS row, no second copy under a name of ours.
##
## Everything below is the firmware branch, unchanged, and still the answer for
## the BS-X cartridge and the two Super Game Boys.
##
## True for a unit that names neither, which is most of them. Otherwise ANY
## of the group being on disk satisfies it -- alternatives, not a checklist.
##
## ON DISK, not verified, and this is where it parts company with BiosBoot. That
## one refuses a MISMATCH because a PS1 BIOS from the wrong region really does
## boot to a black screen, so offering the boot is worse than withholding it.
## BS-X.bin is the opposite case: snes9x runs whatever is under that name, and
## the dumps a player legitimately has -- Rev 0, or one of the fan translations
## the Satellaview scene actually uses -- are none of them the Rev 1 whose md5
## snes9x's .info publishes. Verifying here would hide the cartridge from the
## players most likely to want it, over a file that works.
##
## The core comes from the unit's own BOOT recipe rather than being named twice:
## a firmware path is a fact about the core that runs the combination, and that
## core is already written down above. A unit with no recipe cannot say whose
## system directory to look in, so it is not gated at all.
static func firmware_present(id: String) -> bool:
	if not str(_field(id, "rom_code")).is_empty():
		return not AdapterRoms.path_for(id).is_empty()
	var wanted := firmware_of(id)
	if wanted.is_empty():
		return true
	var core := str(boot_for(host_of(id), [id]).get("core", ""))
	if core.is_empty():
		return true

	var declared := false
	for status_row: Dictionary in FirmwareState.shared().evaluate(
			core, FirmwareRequirements.for_core(core)):
		if not wanted.has(str(status_row.get("path", ""))):
			continue
		declared = true
		var status := int(status_row.get("status", -1))
		if status == FirmwareState.Status.PRESENT \
				or status == FirmwareState.Status.MISMATCH:
			return true
	if declared:
		return false

	# The core's .info does not declare the file. Its location is still fixed --
	# the core looks in its own system directory and nowhere else -- so look
	# there rather than hiding hardware over a missing line of metadata.
	for name: Variant in wanted:
		if FileAccess.file_exists(FirmwareRequirements.destination(core, str(name))):
			return true
	return false


## What a machine built with this unit is missing, as a row of BiosBoot's
## missing_required shape ({path, desc, any_of?, where?}), or {} when nothing is.
##
## `any_of` only for a regional set (the Sega CD's three BIOSes), so a single
## dump reads "X is missing" rather than "No X BIOS is installed (X)". `where`
## overrides the toast's second line for the e-Readers, whose program is a GBA
## dump in the library rather than a file in a core's system directory.
static func missing_row(id: String) -> Dictionary:
	if firmware_present(id):
		return {}
	var label := display_label_of(id)
	var code := str(_field(id, "rom_code"))
	if not code.is_empty():
		return {"path": "%s dump (%s)" % [label, code], "desc": label, "dest": "",
			"where": "Put it in the %s games folder." % label_of_system(host_of(id))}
	var wanted := firmware_of(id)
	if wanted.is_empty():
		return {}
	var out := {"path": str(wanted[0]), "desc": "%s BIOS" % label, "dest": ""}
	if wanted.size() > 1:
		out["any_of"] = wanted
	return out


static func label_of_system(systemid: String) -> String:
	var info := SystemInfo.for_system(systemid)
	return info.display_name if info != null else systemid


## Every expansion that belongs to a console, in ROWS order.
static func ids_for_host(host: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ROWS:
		if str((ROWS[id] as Dictionary).get("host", "")) == host:
			out.append(id)
	return out


## The colour of this unit's top plate, or a fully transparent colour when the
## row names none — which is every unit but the Expansion Pak. Alpha is the
## "has one" test rather than a second field, since a plate you cannot see is
## the same thing as no plate.
static func cap_color_of(id: String) -> Color:
	return _field(id, "cap_color")


## The id of the unit that comes pre-installed on a bare `host` console, or ""
## if the host has none. There is never more than one per host — a console
## with two rows both marked default_occupant would be a data error, not a
## real machine — so the first match wins rather than asserting, the same
## tolerance every other lookup here extends to a malformed row.
static func default_occupant_for(host: String) -> String:
	for id: String in ids_for_host(host):
		if bool((ROWS[id] as Dictionary).get("default_occupant", false)):
			return id
	return ""


## True when this console has anything at all to bolt to it — what the console
## asks before growing an expansion port on its floor.
static func host_has_expansions(host: String) -> bool:
	return not ids_for_host(host).is_empty()


## True when something mounts ABOVE this console, so it needs a socket on its
## roof as well as a foot underneath (the Mega Drive, which is both). A unit with
## a socket of its own does not count: it grows that one instead.
static func host_takes_top_unit(host: String) -> bool:
	for id: String in ids_for_host(host):
		if mount_of(id) == MOUNT_ABOVE and socket_of(id).is_empty():
			return true
	return false


## Which console socket a MOUNT_ABOVE unit goes into: "" for the ExpansionSocket
## they share, else the name of one of its own. See the row docs above.
static func socket_of(id: String) -> String:
	return str(_field(id, "socket"))


## For a network adapter, the link-bus port its core attaches the Ethernet cable
## on (EthernetPort.link_port); -1 for a unit with no RJ45 socket. The row's
## `ethernet_port`.
static func ethernet_port_of(id: String) -> int:
	return int(_field(id, "ethernet_port"))


## The network adapter card a console takes, or "" for one that takes none. What a
## shell with the socket built in counts as having seated.
static func network_adapter_for(host: String) -> String:
	for id: String in ids_for_host(host):
		if ethernet_port_of(id) >= 0:
			return id
	return ""


## The size a console's socket of its own has to take: the largest unit that goes
## in it.
static func socket_size(host: String, socket: String) -> Vector3:
	var out := Vector3.ZERO
	for id: String in ids_for_host(host):
		if socket_of(id) == socket:
			out = out.max(size_of(id))
	return out


## The opening in its console's floor a MOUNT_BELOW unit plugs into (the row's
## `cover_socket`), or "" for a unit that names none.
static func cover_socket_of(id: String) -> String:
	return str(_field(id, "cover_socket"))


## The covered openings in this console's floor that a unit it stands on fills,
## in ROWS order and each once.
static func cover_sockets_for_host(host: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids_for_host(host):
		var socket := cover_socket_of(id)
		if mount_of(id) == MOUNT_BELOW and not socket.is_empty() and not out.has(socket):
			out.append(socket)
	return out


## The sockets of their own this console grows, beyond the shared one, in ROWS
## order and each once.
static func unit_sockets_for_host(host: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids_for_host(host):
		var socket := socket_of(id)
		if mount_of(id) == MOUNT_ABOVE and not socket.is_empty() and not out.has(socket):
			out.append(socket)
	return out


## True when the console itself stands on something — the reason it grows a foot
## and an expansion port on its underside.
static func host_stands_on_unit(host: String) -> bool:
	for id: String in ids_for_host(host):
		if mount_of(id) == MOUNT_BELOW:
			return true
	return false


## Sort a set of attached ids into ROWS order, which is the order BOOT keys are
## written in. Called on both sides so a tower assembled bottom-up and one
## assembled top-down produce the same key.
static func sorted_ids(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in ROWS:
		if ids.has(id):
			out.append(id)
	return out


static func save_owner_of(id: String) -> String:
	return str(_field(id, "save_owner"))


## The launch recipe for a console with these expansions attached, or an empty
## Dictionary when the combination has none. `ids` need not be sorted.
static func boot_for(host: String, ids: Array) -> Dictionary:
	var key := host
	for id in _sorted_ids_excluding_defaults(ids):
		if _names_a_recipe(id):
			key += "|" + id
	return BOOT.get(key, {})


## Ids some BOOT key names. A unit named by none (an Expansion Pak, whose whole
## effect is a forced core option) cannot change which recipe a stack resolves
## to, so it is left out of the key rather than making every recipe spell it
## out: an N64 on a 64DD with the pak in its roof still boots by the drive's.
static var _recipe_ids: Dictionary = {}

static func _names_a_recipe(id: String) -> bool:
	if _recipe_ids.is_empty():
		for key: String in BOOT:
			for part: String in key.split("|").slice(1):
				_recipe_ids[part] = true
	return _recipe_ids.has(id)


## sorted_ids with any default_occupant id (a Jumper Pak) filtered back out.
## A default occupant is functionally inert by definition — it exists so a
## socket is never empty on a fresh console, not so its mere presence changes
## which recipe a stack resolves to or what its nameplate reads. Without this,
## the N64's Jumper Pak would silently need every existing "nintendo_64|..."
## BOOT key rewritten to include it, and would still need rewriting again the
## day a second default-occupant row exists elsewhere.
static func _sorted_ids_excluding_defaults(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in sorted_ids(ids):
		if not bool((ROWS[id] as Dictionary).get("default_occupant", false)):
			out.append(id)
	return out


## The name a stack goes by — "Mega Drive + Mega-CD + 32X". Printed on the
## console's nameplate while anything is attached, so a player can see at a
## glance which machine they have actually built. A default occupant (a
## Jumper Pak) never appears here — see _sorted_ids_excluding_defaults.
static func stack_label(host_label: String, ids: Array) -> String:
	var parts := PackedStringArray([host_label])
	for id in _sorted_ids_excluding_defaults(ids):
		parts.append(display_label_of(id))
	return " + ".join(parts)
