## RomMedia — every artwork/document file that belongs to one ROM.
##
## Two naming schemes live side by side under `roms/<systemid>/media/`, because
## two different fetchers put them there:
##
##   wheel|box|label|manual/<rom basename>.<ext>   ScreenScraper, keyed by the
##                                                 ROM's filename without its
##                                                 extension
##   romm/<rom id>_s.<ext>                         RommArtCache, keyed by the
##                                                 server's numeric id
##
## Neither is discoverable from the other, and the extension is not fixed —
## ScreenScraper takes it from the URL it was handed, so a box can be .png or
## .jpg. Both facts mean a caller cannot compose a path and unlink it; it has to
## look, which is what this class is for.
##
## Nothing here deletes. It answers "what belongs to this ROM" and leaves the
## decision to StorageCleanup, so the scan and the delete cannot drift apart.
class_name RomMedia
extends RefCounted


## Subdirectories keyed by ROM basename.
## "title" and "video" come from a cabinet's attract mode (ArcadeAttract); the storage cleanup sees them too.
const SCRAPED_DIRS := ["wheel", "box", "label", "manual", "title", "video"]
## Subdirectory keyed by RomM rom id.
const ROMM_DIR := "romm"


static func media_root(systemid: String) -> String:
	return RomLibrary.rom_dir_for_system(systemid).path_join("media")


## Every scraped file for one ROM, across all extensions.
##
## `rom_name` may be a filename, a ROM-relative path or a bare basename — only
## the basename is used, which is the key ScreenScraper wrote under. A ROM
## nested in a folder ("Game (Disc 1)/Game.cue") still scrapes under the leaf.
static func scraped_for_rom(systemid: String, rom_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var stem := rom_name.get_file().get_basename()
	if stem.is_empty():
		return out

	var root := media_root(systemid)
	for sub: String in SCRAPED_DIRS:
		var dir_path := root.path_join(sub)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			# Compared without the extension: the same art is .png or .jpg
			# depending on what the scraper was served.
			if not dir.current_is_dir() and fname.get_basename() == stem:
				out.append(dir_path.path_join(fname))
			fname = dir.get_next()
		dir.list_dir_end()
	return out


## The cached RomM cover for one server id, across all extensions.
static func romm_art_for_id(systemid: String, rom_id: int) -> PackedStringArray:
	var out := PackedStringArray()
	if rom_id <= 0:
		return out
	var dir_path := media_root(systemid).path_join(ROMM_DIR)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var prefix := "%d_" % rom_id
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		# "%d_s.<ext>" today; the prefix match keeps a future "_l" variant from
		# being left behind by a delete that only knew about "_s".
		if not dir.current_is_dir() and fname.begins_with(prefix):
			out.append(dir_path.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()
	return out


## Everything for one ROM, scraped and RomM alike. `rom_id` is 0 for a ROM that
## did not come from a server.
static func all_for_rom(systemid: String, rom_name: String, rom_id: int = 0) -> PackedStringArray:
	var out := scraped_for_rom(systemid, rom_name)
	out.append_array(romm_art_for_id(systemid, rom_id))
	return out


## Every media file this system holds, as { absolute path: key }, where key is
## the ROM basename for scraped art and "romm:<id>" for a cached cover.
##
## Built once per scan so the orphan sweep is one directory walk rather than one
## per ROM — a 59k-ROM platform makes that difference the whole runtime.
static func index(systemid: String) -> Dictionary:
	var out: Dictionary = {}
	var root := media_root(systemid)

	for sub: String in SCRAPED_DIRS:
		var dir_path := root.path_join(sub)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				out[dir_path.path_join(fname)] = fname.get_basename()
			fname = dir.get_next()
		dir.list_dir_end()

	var romm_path := root.path_join(ROMM_DIR)
	var romm_dir := DirAccess.open(romm_path)
	if romm_dir != null:
		romm_dir.list_dir_begin()
		var fname := romm_dir.get_next()
		while fname != "":
			if not romm_dir.current_is_dir():
				# "12345_s.webp" -> "romm:12345". A name that is not in that
				# shape yields "romm:" and matches no live ROM, so it reads as an
				# orphan rather than being silently kept forever.
				var stem := fname.get_basename()
				var cut := stem.rfind("_")
				out[romm_path.path_join(fname)] = "romm:" + (
					stem.substr(0, cut) if cut > 0 else stem)
			fname = romm_dir.get_next()
		romm_dir.list_dir_end()

	return out
