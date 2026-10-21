## ArcadeCabinetArt — the art a cabinet wears for the game in its bay.
##
## The marquee takes the game's WHEEL (its logo, usually with alpha), else its cover; the two sides take
## the COVER. The cover is the front of the scraped box, else the scraped label, else the RomM cover the
## spawn menu already cached; nothing is fetched here, so a game with none of them leaves the cabinet as
## it was. Synchronous, like the cartridge's own label (cartridge.gd `_apply_label_art`).
class_name ArcadeCabinetArt
extends RefCounted

## The scraper's folder for a wheel (rom_media.gd SCRAPED_DIRS).
const WHEEL := "wheel"

## RomM ids by lower-case file name, per ROM folder, read once: the sidecars are a line per row.
static var _romm_ids: Dictionary = {}
## ROM path -> { "wheel", "cover" } for a suite: it hangs art on a board without writing the player's
## data root. Empty in the app.
static var test_art: Dictionary = {}


## { "wheel": Texture2D or null, "cover": Texture2D or null } for one ROM.
static func for_rom(systemid: String, rom_path: String) -> Dictionary:
	var out := {"wheel": null, "cover": null}
	if test_art.has(rom_path):
		return test_art[rom_path]
	if systemid.is_empty() or rom_path.is_empty():
		return out
	out["wheel"] = MediaDimensions.load_media_texture(systemid, rom_path, WHEEL)
	var cover := ArcadeProfiles.board_art(MediaDimensions.load_media_image(systemid, rom_path, "box"),
		MediaDimensions.load_media_image(systemid, rom_path, "label"))
	if cover == null:
		cover = _romm_cover(systemid, rom_path)
	if cover != null:
		cover.generate_mipmaps()
		out["cover"] = ImageTexture.create_from_image(cover)
	return out


## Where `tex` goes inside a `box` (metres) at its own proportions: the largest size that fits.
static func fit(tex_size: Vector2, box: Vector2) -> Vector2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return box
	var s := minf(box.x / tex_size.x, box.y / tex_size.y)
	return tex_size * s


## The RomM cover the spawn menu cached (`media/romm/<id>_s.*`), or null. Looked for in every folder
## the system's ROMs live under: an arcade library synced from `mame/` has its index and covers there.
static func _romm_cover(systemid: String, rom_path: String) -> Image:
	for dir in RomLibrary.rom_dirs_for_system(systemid):
		var id := romm_id(dir, rom_path)
		if id <= 0:
			continue
		var covers := dir.path_join("media").path_join(RomMedia.ROMM_DIR)
		var prefix := "%d_" % id
		for f in DirAccess.get_files_at(covers):
			if f.begins_with(prefix):
				var img := Image.load_from_file(covers.path_join(f))
				if img != null and not img.is_empty():
					return img
	return null


## The server's id for a ROM file in this ROM folder, or 0 (no index, or not on the server).
static func romm_id(rom_dir: String, rom_path: String) -> int:
	if not _romm_ids.has(rom_dir):
		_romm_ids[rom_dir] = _read_ids(rom_dir)
	var by_name: Dictionary = _romm_ids[rom_dir]
	return int(by_name.get(rom_path.get_file().to_lower(), 0))


## Forget what was read (a sync rewrote the index; tests).
static func forget_romm() -> void:
	_romm_ids.clear()


static func _read_ids(rom_dir: String) -> Dictionary:
	var dir := rom_dir.path_join(".romm")
	var id_path := dir.path_join("index.ids")
	var fs_path := dir.path_join("index.fsnames")
	var ext_path := dir.path_join("index.exts")
	if not (FileAccess.file_exists(id_path) and FileAccess.file_exists(fs_path)):
		return {}
	var f := FileAccess.open(id_path, FileAccess.READ)
	if f == null:
		return {}
	var ids := f.get_buffer(f.get_length()).to_int32_array()
	return ids_by_name(ids, RommCatalog._read_lines(fs_path), RommCatalog._read_lines(ext_path))


## `file name -> id` from the three sidecars (a line per row; an empty extension is a folder), or
## nothing when they do not line up, which is a half-written index.
static func ids_by_name(ids: PackedInt32Array, names: PackedStringArray, exts: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	if names.size() != ids.size():
		return out
	# fsnames are the lower-case basenames and exts the extensions, so "sf2.zip" is the pair.
	for i in ids.size():
		var ext := exts[i] if i < exts.size() else ""
		out[names[i] if ext.is_empty() else "%s.%s" % [names[i], ext]] = ids[i]
	return out
