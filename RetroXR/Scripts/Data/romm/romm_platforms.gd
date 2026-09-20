## RommPlatforms — maps RomM platform slugs to project systemids.
##
## RomM identifies a platform two ways: `slug` (IGDB-style, e.g. "genesis-slash-
## megadrive") and `fs_slug` (the folder name on the server, e.g. "megadrive").
## Either can appear, and users pick their own folder names, so the map below
## carries every alias worth recognising and lookup tries both.
##
## A systemid is required, not cosmetic: it decides cart-vs-disc
## (MediaDimensions.is_disc_system), physical size, and which 3D model spawns.
## Platforms that don't resolve are reported to the user rather than dropped, so
## they can add a RommConfig.platform_overrides entry.
##
## Mirrors the shape of screenscraper_systems.gd.
class_name RommPlatforms
extends RefCounted


## RomM slug (or fs_slug), lowercase → project systemid.
const SLUG_MAP := {
	# Nintendo
	"nes": "nes",
	"famicom": "famicom",
	"fc": "famicom",
	"fds": "fds",
	"snes": "snes",
	"sfc": "snes",
	"superfamicom": "snes",
	"snes-msu1": "snes",
	"satellaview": "satellaview",
	"sufami": "sufami",
	"sufamiturbo": "sufami",
	# A Super Game Boy release is a GAME BOY cartridge that happens to light up
	# extra colours and a border in the adapter. The file is a .gb, so filing it
	# under snes put it in a folder whose extensions do not include it and
	# nothing scanned it -- and it belongs in the handheld library anyway, which
	# is what fills a Super Game Boy's bay.
	"sgb": "gb",
	# The MSU-1 variant is a Game Boy cartridge too, despite sitting beside
	# snes-msu1 in every platform list. Checked against a real library rather than
	# reasoned from the name: the folder declares ".gb .gbc .zip .7z .squashfs",
	# so what is filed there is handheld ROMs with streamed audio beside them, not
	# the .sfc that snes-msu1 holds.
	"sgb-msu1": "gb",
	"n64": "n64",
	"n64dd": "n64dd",
	"gb": "gb",
	"gb2players": "gb",
	# The project has no separate Game Boy Color systemid — gambatte reports
	# "gb" for both, and the cart shell is the same.
	"gbc": "gb",
	"gbc2players": "gb",
	"gba": "gba",
	"nds": "nds",
	"3ds": "n3ds",
	"gc": "gc",
	"wii": "wii",
	"wiiware": "wii",
	"gamecube": "gc",
	"triforce": "gc",
	"virtualboy": "virtualboy",
	"pokemini": "pokemini",

	# Sony
	"psx": "psx",
	"ps": "psx",
	"ps1": "psx",
	"playstation": "psx",
	"ps2": "ps2",
	"playstation-2": "ps2",
	"psp": "psp",

	# Microsoft. "xbox" is both IGDB's slug and ES-DE's folder; the rest are what
	# people call the folder to keep it apart from the 360.
	"xbox": "xbox",
	"xbox-original": "xbox",
	"original-xbox": "xbox",
	"microsoft-xbox": "xbox",
	"xboxog": "xbox",

	# Sega
	"megadrive": "genesis",
	"megadrive-msu": "genesis",
	"msu-md": "genesis",
	"genesis": "genesis",
	"genesis-slash-megadrive": "genesis",
	"md": "genesis",
	"mastersystem": "mastersystem",
	"sms": "mastersystem",
	"gamegear": "gamegear",
	"segacd": "segacd",
	"megacd": "segacd",
	"mega-cd": "segacd",
	"sega-cd": "segacd",
	"sega32": "sega32x",
	"sega32x": "sega32x",
	"32x": "sega32x",
	"sg1000": "sg-1000",
	"sg-1000": "sg-1000",
	# No bare "pico": that is PICO-8's folder name as often as it is this
	# machine's, and the two are unrelated.
	"sega-pico": "sega_pico",
	"segapico": "sega_pico",
	"saturn": "saturn",
	"sega-saturn": "saturn",
	"dreamcast": "dreamcast",
	"dc": "dreamcast",
	"vmu": "vmu",

	# Atari
	"atari2600": "atari2600",
	"atari5200": "atari5200",
	"atari7800": "atari7800",
	"atarilynx": "atarilynx",
	"lynx": "atarilynx",
	"atarijaguar": "atarijaguar",
	"jaguar": "atarijaguar",
	"atarijaguarcd": "atarijaguarcd",
	"jaguarcd": "atarijaguarcd",
	"atari-jaguar-cd": "atarijaguarcd",
	"atarist": "atarist",

	# NEC
	"pcengine": "tg16",
	"pce": "tg16",
	"pcenginecd": "tg-cd",
	"pcecd": "tg-cd",
	"turbografx-cd": "tg-cd",
	"supergrafx": "supergrafx",
	"turbografx-16-slash-pc-engine": "tg16",
	"pcfx": "pcfx",
	"pc88": "pc88",
	"pc80": "pc88",
	"pc98": "pc98",

	# SNK
	"neogeo": "neogeo",
	"neogeocd": "neogeocd",
	"neo-geo-cd": "neogeocd",
	"ngp": "ngp",
	"ngpc": "ngp",

	# Bandai / Watara / other handhelds
	#
	# Game & Watch resolves to gameandwatch, not an id of its own: `gw` is
	# the only core that plays these, and it covers Tiger and Acclaim LCD games
	# under the same id.
	"g-and-w": "gameandwatch",
	"gameandwatch": "gameandwatch",
	"wonderswan": "wonderswan",
	"wswan": "wonderswan",
	"wonderswancolor": "wonderswan",
	"wswanc": "wonderswan",
	"supervision": "supervision",
	"megaduck": "megaduck",

	# Consoles, misc
	"3do": "3do",
	"cdi": "cdi",
	"cdimono1": "cdi",
	"channelf": "channelf",
	"fairchild-channel-f": "channelf",
	"colecovision": "colecovision",
	"coleco": "colecovision",
	"intellivision": "intellivision",
	"odyssey2": "odyssey2",
	"o2em": "odyssey2",
	"videopac": "odyssey2",
	"videopacplus": "odyssey2",
	"vectrex": "vectrex",
	"arcadia": "arcadia",
	"uzebox": "uzebox",

	# Arcade
	"arcade": "mame",
	"mame": "mame",
	"mame-libretro": "mame",
	"mame-advmame": "mame",
	"mame-mame4all": "mame",
	"naomi": "mame",
	"naomi2": "mame",
	"atomiswave": "mame",
	"model3": "mame",
	"fba": "fbneo",
	"fbneo": "fbneo",

	# Computers
	"c64": "c64",
	"commodore-64": "c64",
	"c128": "commodore_c128",
	"c20": "vic20",
	"amiga": "amiga",
	"amiga500": "amiga",
	"amiga1200": "amiga",
	"amigacd32": "amigacd32",
	"cd32": "amigacd32",
	"amigacdtv": "cdtv",
	"cdtv": "cdtv",
	"amstradcpc": "amstradcpc",
	"cpc": "amstradcpc",
	"gx4000": "amstradcpc",
	"zxspectrum": "zxspectrum",
	"zx-spectrum": "zxspectrum",
	"spectrum": "zxspectrum",
	"zx81": "zx81",
	"msx": "msx",
	"msx1": "msx",
	"msx2": "msx",
	"msx2+": "msx",
	"msxturbor": "msx",
	"x68000": "x68000",
	"x1": "x1",
	"apple2": "apple2",
	"atari8bit": "atari800",
	"atari800": "atari800",
	"svi": "spectravideo",
	"spectravideo": "spectravideo",
	"dos": "dos",
	"pc": "dos",

	# Engines / fantasy consoles
	"scummvm": "scummvm",
	"pico8": "pico8",
	"tic80": "tic80",
}


## Resolve a RomM platform object to a project systemid, or "" when unmapped.
##
## Precedence: explicit user override (by either slug), then fs_slug, then slug.
## fs_slug beats slug because it's the folder the user named themselves — it may
## already BE our systemid (e.g. a folder literally called "snes"), one of
## ES-DE's other names for it ("sfc"), or the id it had before the rename
## ("super_nes"), which SystemIds reads. An override saved before the rename
## holds an old id too.
static func systemid_for(platform: Dictionary, overrides: Dictionary = {}) -> String:
	var slug_v: Variant = platform.get("slug")
	var fs_v: Variant = platform.get("fs_slug")
	var slug := ("" if slug_v == null else str(slug_v)).to_lower().strip_edges()
	var fs_slug := ("" if fs_v == null else str(fs_v)).to_lower().strip_edges()

	for key: String in [slug, fs_slug]:
		if not key.is_empty() and overrides.has(key):
			return SystemIds.canonical(str(overrides[key]))

	for key: String in [fs_slug, slug]:
		if key.is_empty():
			continue
		if SLUG_MAP.has(key):
			return str(SLUG_MAP[key])

	for key: String in [fs_slug, slug]:
		if key.is_empty():
			continue
		var folder_owner := SystemIds.systemid_for_folder(key)
		if SystemInfo.for_system(folder_owner) != null:
			return folder_owner

	return ""


## Display name for a platform, preferring RomM's own resolved label.
static func display_name(platform: Dictionary) -> String:
	for key: String in ["display_name", "custom_name", "name", "slug"]:
		var v := str(platform.get(key, "")).strip_edges()
		if not v.is_empty():
			return v
	return "Unknown platform"


## Split a /api/platforms response into mapped and unmapped.
## Returns {mapped: Array[Dictionary], unmapped: Array[Dictionary]} where each
## mapped entry gains a "systemid" key. Platforms with no ROMs are dropped —
## an empty platform is noise in both lists.
static func partition(platforms: Array, overrides: Dictionary = {}) -> Dictionary:
	var mapped: Array[Dictionary] = []
	var unmapped: Array[Dictionary] = []

	for p: Dictionary in platforms:
		# rom_count can arrive as JSON null; Dictionary.get()'s default only
		# covers an absent key, and int(null) is a hard error.
		var count: Variant = p.get("rom_count")
		if count == null or int(count) <= 0:
			continue
		var sid := systemid_for(p, overrides)
		if sid.is_empty():
			unmapped.append(p)
		else:
			var entry := p.duplicate()
			entry["systemid"] = sid
			mapped.append(entry)

	return {"mapped": mapped, "unmapped": unmapped}


## Collapse partition()'s mapped LIST into a systemid -> platform dictionary.
##
## Several RomM slugs legitimately share one systemid — snes/sfc/sgb, the nine
## arcade slugs, gb/gbc — so this is a real contest, not an anomaly. Keying the
## dict directly kept whichever arrived last, which made the winner a function
## of the server's array order: a platform could vanish and reappear between
## syncs with nothing said.
##
## Biggest library wins, deterministically. The platforms it displaces come back
## as `shadowed` rather than disappearing; their remedy is the same
## RommConfig.platform_overrides entry an unmapped platform needs.
##
## Returns {platforms: Dictionary, shadowed: Array}.
static func collapse_by_systemid(mapped: Array) -> Dictionary:
	var platforms: Dictionary = {}
	var shadowed: Array = []
	for p: Dictionary in mapped:
		var sid := str(p.get("systemid", ""))
		if sid.is_empty():
			continue
		var prev: Dictionary = platforms.get(sid, {})
		if prev.is_empty():
			platforms[sid] = p
		elif int(p.get("rom_count", 0)) > int(prev.get("rom_count", 0)):
			platforms[sid] = p
			shadowed.append(prev)
		else:
			shadowed.append(p)
	return {"platforms": platforms, "shadowed": shadowed}
