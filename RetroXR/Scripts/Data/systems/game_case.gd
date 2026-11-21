## GameCase — which case a disc game came in: a CD jewel case or a DVD-style keep case (GameCaseModel), by system,
## the market it was sold in, how many discs it has and the shape of its scraped box art.
##
## {family, variant, color}: family "jewel" or "keep", variant a key of that family's contract
## (imported-assets/media/*_case/*_contract.json), color a GameCaseModel preset ("" for the variant's own).
##
## The early American long box (Sega CD, Saturn, the first PlayStation games) is told from the box art itself: a
## ScreenScraper box-texture of a long box is laid out back | spine | front at about 931 x 680 (1.37 wide for its
## height), a jewel case's at 1509-1622 x 680 (2.2-2.4). With no scan, the US release date decides against a
## per-system cutoff (LONGBOX_BEFORE, estimated: the switch to jewel cases was gradual).
class_name GameCase
extends RefCounted

## A box-texture narrower than this (width / height) is a long box's.
const LONG_BOX_RATIO := 1.8
## Systems whose American releases started out in the long box, and the month (YYYY-MM) from which a game without a
## scan is taken to be in a jewel case [E].
const LONGBOX_BEFORE := {"psx": "1996-04", "saturn": "1997-01", "segacd": "1994-01"}

## Per system: the case in each market ("us", "eu", "jp"; "*" any). A row is [family, variant, color].
const SYSTEMS := {
	"psx": {"us": ["jewel", "single", ""], "eu": ["jewel", "pal", ""], "jp": ["jewel", "single", ""]},
	"saturn": {"us": ["jewel", "single", ""], "eu": ["keep", "saturn_pal", ""], "jp": ["jewel", "single", ""]},
	"segacd": {"us": ["jewel", "single", ""], "eu": ["jewel", "fatbox2", ""], "jp": ["jewel", "fatbox2", ""]},
	"dreamcast": {"us": ["jewel", "single", ""], "eu": ["jewel", "dc_pal", ""], "jp": ["jewel", "single", ""]},
	"3do": {"us": ["keep", "3do_long", ""], "*": ["jewel", "single", ""]},
	"cdi": {"*": ["jewel", "cdi", ""]},
	"ps2": {"*": ["keep", "ps2", ""]},
	"gc": {"jp": ["keep", "gc_jp", ""], "*": ["keep", "gc", ""]},
	"xbox": {"*": ["keep", "single", "lime"]},
	"xbox360": {"*": ["keep", "x360", ""]},
	"wii": {"*": ["keep", "single", "white"]},
	"wiiu": {"*": ["keep", "wiiu", ""]},
	"ps3": {"*": ["keep", "bluray_game", "clear"]},
	"psp": {"*": ["keep", "umd", ""]},
}
## Disc systems with no row above: a plain jewel case (PC Engine CD, Neo Geo CD, PC-FX, CD32, CDTV, Jaguar CD, the
## computers' CD-ROMs).
const DEFAULT_ROW := ["jewel", "single", ""]
## How many discs each multi-disc case holds.
const CAPACITY := {"double": 2, "fatbox2": 2, "fatbox4": 4, "pal_multi2": 2, "pal_multi4": 4, "triple": 3,
	"multi5": 5}


## The case for a game. `market` "us", "eu" or "jp" (anything else counts as "us"); `discs` how many it has;
## `box_size` its box-texture's size in pixels (Vector2i.ZERO when there is none); `release` its scraped release
## date (YYYY-MM-DD, may be empty), read only when there is no box art to go by.
static func pick(systemid: String, market: String, discs := 1, box_size := Vector2i.ZERO, release := "") -> Dictionary:
	var sys := SystemIds.canonical(systemid)
	var m := market if market in ["us", "eu", "jp"] else "us"
	var rows: Dictionary = SYSTEMS.get(sys, {})
	var row: Array = rows.get(m, rows.get("*", DEFAULT_ROW))
	var out := {"family": str(row[0]), "variant": str(row[1]), "color": str(row[2])}
	var mod_row := MediaDimensions.mod_case(sys)
	if not mod_row.is_empty():
		out = {"family": str(mod_row.get("family", "jewel")), "variant": str(mod_row.get("variant", "single")),
			"color": str(mod_row.get("color", ""))}
	if m == "us" and LONGBOX_BEFORE.has(sys) and discs <= 1 and is_long_box(sys, box_size, release):
		out["family"] = "jewel"
		out["variant"] = "longbox"
		return out
	if discs > 1:
		var multi := _multi_variant(sys, m, str(out["family"]), str(out["variant"]), discs)
		out["family"] = multi[0]
		out["variant"] = multi[1]
	return out


## Whether a US game came in the long box: from its box art's shape, else its release date.
static func is_long_box(systemid: String, box_size: Vector2i, release := "") -> bool:
	# A scan ScreenScraper normalized to 1024 x 680 (its Sega CD long boxes, every keep case) says nothing by its
	# shape: only one kept at its own proportions does.
	if box_size.x > 0 and box_size.y > 0 and not is_normalized_scan(box_size):
		return float(box_size.x) / float(box_size.y) < LONG_BOX_RATIO
	var cutoff := str(LONGBOX_BEFORE.get(SystemIds.canonical(systemid), ""))
	var month := release.substr(0, 7)
	return not cutoff.is_empty() and month.length() == 7 and month < cutoff


## The case for a game of several discs, or the single's variant when that family has nothing bigger (a GameCube,
## an Xbox 360 or a UMD case holds one; the others' extra discs travel loose).
static func _multi_variant(sys: String, market: String, family: String, single: String, discs: int) -> Array:
	if family == "keep":
		if single in ["single", "ps2"]:
			return ["keep", "double" if discs == 2 else ("triple" if discs == 3 else "multi5")]
		if sys == "saturn":                 # the PAL Saturn's multi-disc games came in jewel cases
			return ["jewel", "fatbox4" if discs > 2 else "double"]
		return ["keep", single]
	if sys == "psx" and market == "eu":
		return ["jewel", "pal_multi2" if discs == 2 else "pal_multi4"]
	if discs == 2:
		return ["jewel", "fatbox2" if sys in ["psx", "segacd"] else "double"]
	return ["jewel", "fatbox4"]


## ScreenScraper's 1024 x 680 box-texture, whatever the box's own proportions (1.45-1.55 wide for its height).
static func is_normalized_scan(box_size: Vector2i) -> bool:
	if box_size.y <= 0:
		return false
	var r := float(box_size.x) / float(box_size.y)
	return r > 1.45 and r < 1.55


static func capacity(variant: String) -> int:
	return int(CAPACITY.get(variant, 1))


## The market a game was sold in: the region tag in its file name (Redump and No-Intro name the dump's own), else
## its scraped region, else the player's. The name comes first: ScreenScraper filed Sonic CD (USA) under Europe
## while handing over the American long box's scan.
static func market_of(systemid: String, rom_path: String) -> String:
	var found := SnesCartShell.filename_market(rom_path)
	if found.is_empty():
		found = N64CartShell.market_of_region(str(CartRomInfo.scraped_rom(systemid, rom_path).get("region", "")))
	if found.is_empty():
		found = RegionalNames.cart_market()
	return found


static func release_of(systemid: String, rom_path: String) -> String:
	return str(CartRomInfo.scraped_rom(systemid, rom_path).get("releasedate", ""))


## Every disc of the game `rom_path` is one of, in order: the files a .m3u lists, or the files beside it whose names
## differ only in their "(Disc N)" tag. A single-disc game is itself alone.
static func discs_of(rom_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if rom_path.get_extension().to_lower() == "m3u":
		var text := FileAccess.get_file_as_string(rom_path)
		for line in text.split("\n"):
			var entry := line.strip_edges()
			if entry.is_empty() or entry.begins_with("#"):
				continue
			out.append(entry if entry.is_absolute_path() else rom_path.get_base_dir().path_join(entry))
		return out if not out.is_empty() else PackedStringArray([rom_path])
	var name := rom_path.get_file()
	if MenuIcons.disc_number(name) <= 0:
		return PackedStringArray([rom_path])
	var re := RegEx.create_from_string("(?i)([(\\[]\\s*(?:dis[ck]|cd)\\s*)(\\d+)")
	var m := re.search(name)
	var dir := DirAccess.open(rom_path.get_base_dir())
	if m == null or dir == null:
		return PackedStringArray([rom_path])
	var head := name.substr(0, m.get_start(2))
	var tail := name.substr(m.get_end(2))
	var found := {}
	for f in dir.get_files():
		if f.begins_with(head) and f.ends_with(tail):
			var n := f.substr(head.length(), f.length() - head.length() - tail.length())
			if n.is_valid_int():
				found[int(n)] = rom_path.get_base_dir().path_join(f)
	var keys := found.keys()
	keys.sort()
	for k: int in keys:
		out.append(found[k])
	return out if not out.is_empty() else PackedStringArray([rom_path])


## The games row's picture of a game's case (MenuIcons.case_icon): "square" or "tall" by the case's own proportions
## (every keep case and the long box are tall), with "_multi" when the case holds several discs. Kept per game: a
## row is bound on every scroll.
static var _icon_cache := {}


static func icon_of(systemid: String, rom_path: String) -> String:
	var key := "%s|%s" % [systemid, rom_path]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var discs := maxi(discs_of(rom_path).size(), disc_total_of(systemid, rom_path))
	var market := market_of(systemid, rom_path)
	var size := Vector2i.ZERO
	# Only the long box is told from the scan, and only its header is read for that.
	if discs <= 1 and not market in ["eu", "jp"] and LONGBOX_BEFORE.has(SystemIds.canonical(systemid)):
		size = image_size(RetroGameCase.box_art_path(systemid, rom_path))
	var found := pick(systemid, market, discs, size, release_of(systemid, rom_path))
	var name := "tall" if is_tall(str(found["family"]), str(found["variant"])) else "square"
	if capacity(str(found["variant"])) > 1:
		name += "_multi"
	_icon_cache[key] = name
	return name


## Whether a case stands taller than it is wide (its contract's size).
static func is_tall(family: String, variant: String) -> bool:
	var mm: Array = GameCaseModel.variant_contract(family, variant).get("size_mm", [])
	if mm.size() < 2:
		return family == "keep"
	return float(mm[1]) > float(mm[0]) * 1.2


## A PNG's or JPEG's size from its header, without decoding it (Vector2i.ZERO for anything else).
static func image_size(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if f == null:
		return Vector2i.ZERO
	f.big_endian = true
	var head := f.get_buffer(24)
	if head.size() == 24 and head[0] == 0x89 and head[1] == 0x50:
		return Vector2i((head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19],
			(head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23])
	if head.size() < 4 or head[0] != 0xFF or head[1] != 0xD8:
		return Vector2i.ZERO
	f.seek(2)
	while f.get_position() + 9 < f.get_length():
		if f.get_8() != 0xFF:
			continue
		var marker := f.get_8()
		if marker == 0xFF or marker == 0x00 or (marker >= 0xD0 and marker <= 0xD9):
			continue
		var length := f.get_16()
		if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
			f.get_8()
			var h := f.get_16()
			return Vector2i(f.get_16(), h)
		f.seek(f.get_position() + length - 2)
	return Vector2i.ZERO


## Its box art changed (a scrape): work the picture out again at the row's next binding.
static func forget_icon(systemid: String, rom_path: String) -> void:
	_icon_cache.erase("%s|%s" % [systemid, rom_path])


## How many discs the game shipped on, as its scrape recorded it (0 when it was not scraped, or scraped before the
## count was kept).
static func disc_total_of(systemid: String, rom_path: String) -> int:
	return int(CartRomInfo.scraped_rom(systemid, rom_path).get("disc_total", 0))


## The game's discs by seat: `total` long at least, each disc on this device at its own number's place (the number
## in its name, else its place in the list), "" for one that is not here.
static func disc_slots(rom_path: String, total := 0) -> PackedStringArray:
	var found := discs_of(rom_path)
	var out := PackedStringArray()
	out.resize(maxi(found.size(), total))
	var loose := PackedStringArray()
	for path in found:
		var n := MenuIcons.disc_number(path.get_file())
		if n >= 1 and n <= out.size() and out[n - 1].is_empty():
			out[n - 1] = path
		else:
			loose.append(path)
	for path in loose:
		var at := out.find("")
		if at >= 0:
			out[at] = path
	return out
