## SystemIcons — top-down console artwork keyed by systemid, drawn on the tiles
## in every SystemGridBrowser (Cartridges, Systems, Cores, Download).
##
## Art lives at res://Textures/SystemIcons/<systemid>.svg — see the ATTRIBUTIONS
## file beside it. A systemid with no art of its own falls back to _default.svg
## so every tile reserves the same space and the text stays aligned down the
## grid; has_icon() reports whether the art is genuinely that system's.
##
##   var tex := SystemIcons.for_system("nes")
##
## Each system also has a media form — the cartridge, disc or tape you actually
## put in it — at <systemid>-content.svg, for tiles that stand for a game rather
## than a machine. Use for_content() there; it falls back to the console.
##
##   var tex := SystemIcons.for_content("nes")
class_name SystemIcons
extends RefCounted

const ICON_DIR := "res://Textures/SystemIcons"
const DEFAULT_ID := "_default"
const CONTENT_SUFFIX := "-content"

# systemid -> Texture2D, or null when that systemid has no art. Null results are
# cached too, so a miss costs one ResourceLoader.exists() for the whole session.
static var _cache: Dictionary = {}


## Console art for a systemid, falling back to the generic device when that
## system has none. Null only if the fallback itself is missing.
static func for_system(systemid: String) -> Texture2D:
	var tex := _load(systemid)
	return tex if tex else _load(DEFAULT_ID)


## Media art for a systemid — its cartridge, disc, tape or card. Falls back to
## the console when that system has none, and then to the generic device.
static func for_content(systemid: String) -> Texture2D:
	var tex := _load(systemid + CONTENT_SUFFIX)
	return tex if tex else for_system(systemid)


## True when this systemid has art of its own, rather than the generic fallback.
static func has_icon(systemid: String) -> bool:
	return _load(systemid) != null


## True when this systemid has media art of its own, rather than falling back to
## the console.
static func has_content_icon(systemid: String) -> bool:
	return _load(systemid + CONTENT_SUFFIX) != null


## Forget the misses (and the hits) cached so far. A mod mounted mid-session can
## bring art for a systemid that was already looked up and found to have none.
static func forget() -> void:
	_cache.clear()


static func _load(systemid: String) -> Texture2D:
	if systemid.is_empty():
		return null
	if _cache.has(systemid):
		return _cache[systemid]
	var path := "%s/%s.svg" % [ICON_DIR, systemid]
	var tex: Texture2D = null
	# ResourceLoader, not FileAccess: res:// paths are remapped inside the pck and
	# FileAccess.file_exists() reports false for every one of them in an export.
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	_cache[systemid] = tex
	return tex
