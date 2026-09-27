## ScrapedArtCache — async wheel/label/box art for the ROM browser.
##
## The sibling of [RommArtCache], for the art ScreenScraper puts on disk rather
## than the covers RomM serves. Same three rules, and for the same reason its
## header gives: decoding inline is how a scrolling grid stutters.
##
##  1. The files are already local, so there is nothing to fetch — this starts at
##     the decode.
##  2. Image.load_from_file and the downscale run on WorkerThreadPool.
##  3. Only ImageTexture.create_from_image touches the main thread, budgeted per
##     frame.
##
## Measured on a real library before this existed, decoding inline in the row
## binder: 2.4 ms per wheel, 4.1 ms per label, 13.2 ms per box, on a desktop.
## The label was not cached at all, so that cost was paid again for every row on
## every scroll step.
##
## Keyed on the absolute file path, so the same art shared by two rows — or by
## the browser and a spawned cartridge — decodes once.
class_name ScrapedArtCache
extends Node


## A texture became available. `key` is whatever the caller passed to
## get_or_request, so a row can tell whether the art is still the art it wants.
signal art_ready(key: String, texture: Texture2D)

## Modelled on RommArtCache. Scraped art is larger than a cover — a box can be
## 1.1 megapixels — so the ceiling is lower and the per-frame budget tighter.
const MAX_TEXTURES := 120
const DECODE_BUDGET_PER_FRAME := 2

## Extensions tried in order, matching what download_all_media writes.
const EXTENSIONS := [".png", ".jpg", ".jpeg", ".webp"]

## path -> ImageTexture (LRU; _lru_order holds the recency list)
var _textures: Dictionary = {}
var _lru_order: Array[String] = []

var _decoding: Dictionary = {}          ## path -> WorkerThreadPool task id
var _decoded: Array[Dictionary] = []    ## [{path, key, image}] awaiting promotion
var _decoded_mutex := Mutex.new()
## Paths that decoded to nothing. Never retried — the row falls back to its text.
var _dead: Dictionary = {}

## "<systemid>|<stem>|<kind>" -> [path or "", msec]: where resolve() last found
## the art, or that it found none. resolve() is up to four file_exists calls, a
## row asks for two kinds, and every pooled row is bound on each scroll step —
## on a headset's storage the stat calls were most of a bind, and a row with no
## art paid all eight every time. Kept briefly; forget() drops them the moment a
## scrape writes, and anything else that adds art is seen within the TTL.
var _resolved: Dictionary = {}
const RESOLVE_TTL_MS := 30000


func _process(_delta: float) -> void:
	_promote_decoded()


# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

## The art for one ROM if it is already in RAM, else null and a decode starts.
##
## `kind` is the media subdirectory (wheel/label/box). `box` is the size to fit
## within, or Vector2i.ZERO to keep the image whole. `mipmaps` is for art read at
## a glancing angle in 3D; a 2D icon drawn at one size does not want them.
func get_or_request(systemid: String, rom_name: String, kind: String,
					box: Vector2i = Vector2i.ZERO, mipmaps: bool = false) -> Texture2D:
	var path := _resolve_cached(systemid, rom_name, kind)
	if path.is_empty():
		return null
	if _textures.has(path):
		_mark_used(path)
		return _textures[path]
	if _dead.has(path) or _decoding.has(path):
		return null

	_decoding[path] = WorkerThreadPool.add_task(
		_decode_task.bind(path, box, mipmaps))
	return null


## Where a ROM's art of one kind lives, or "" when it has none.
##
## The extension is not fixed: download_all_media takes it from the URL it was
## handed, so the same kind is .png for one game and .jpg for the next.
static func resolve(systemid: String, rom_name: String, kind: String) -> String:
	var stem := rom_name.get_file().get_basename()
	if systemid.is_empty() or stem.is_empty():
		return ""
	var dir := RomLibrary.rom_dir_for_system(systemid).path_join("media").path_join(kind)
	for ext: String in EXTENSIONS:
		var path := dir.path_join(stem + ext)
		if FileAccess.file_exists(path):
			return path
	return ""


func _resolve_cached(systemid: String, rom_name: String, kind: String) -> String:
	var key := _resolved_key(systemid, rom_name, kind)
	var now := Time.get_ticks_msec()
	var seen: Array = _resolved.get(key, [])
	if not seen.is_empty() and now - int(seen[1]) < RESOLVE_TTL_MS:
		return str(seen[0])
	var path := resolve(systemid, rom_name, kind)
	_resolved[key] = [path, now]
	return path


static func _resolved_key(systemid: String, rom_name: String, kind: String) -> String:
	return "%s|%s|%s" % [systemid, rom_name.get_file().get_basename(), kind]


## Forget one ROM's art across every kind, so the next bind re-reads it.
##
## What a freshly scraped file needs, and all it needs. The whole cache used to
## be cleared for this, which threw away every other row's art and made one
## arriving wheel cost a full re-decode of everything on screen.
func forget(systemid: String, rom_name: String) -> void:
	for kind: String in ["wheel", "label", "box", "manual"]:
		_resolved.erase(_resolved_key(systemid, rom_name, kind))
		var path := resolve(systemid, rom_name, kind)
		if path.is_empty():
			continue
		_textures.erase(path)
		_lru_order.erase(path)
		_dead.erase(path)


func clear() -> void:
	_textures.clear()
	_lru_order.clear()
	_dead.clear()
	_resolved.clear()


# ---------------------------------------------------------------------------
# Decode
# ---------------------------------------------------------------------------

## Runs on a pool thread. The load and the downscale are the expensive parts;
## creating the texture is left to the main thread.
func _decode_task(path: String, box: Vector2i, mipmaps: bool) -> void:
	var img := Image.load_from_file(path)
	if img != null and not img.is_empty():
		if box.x > 0 and box.y > 0:
			_fit_within(img, box)
		if mipmaps:
			img.generate_mipmaps()
	_decoded_mutex.lock()
	_decoded.append({"path": path, "image": img})
	_decoded_mutex.unlock()


func _promote_decoded() -> void:
	var promoted := 0
	while promoted < DECODE_BUDGET_PER_FRAME:
		_decoded_mutex.lock()
		if _decoded.is_empty():
			_decoded_mutex.unlock()
			return
		var item: Dictionary = _decoded.pop_front()
		_decoded_mutex.unlock()

		var path := str(item["path"])
		if _decoding.has(path):
			WorkerThreadPool.wait_for_task_completion(_decoding[path])
			_decoding.erase(path)

		var img: Image = item["image"]
		if img == null or img.is_empty():
			_dead[path] = true
			promoted += 1
			continue

		var tex := ImageTexture.create_from_image(img)
		_textures[path] = tex
		_mark_used(path)
		_trim_textures()
		art_ready.emit(path, tex)
		promoted += 1


## Scale down to fit a box, preserving aspect. Lifted from spawn_view so the
## thread does the resize rather than the frame that asked for it.
static func _fit_within(img: Image, box: Vector2i) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0 or (w <= box.x and h <= box.y):
		return
	var scale: float = minf(float(box.x) / float(w), float(box.y) / float(h))
	img.resize(maxi(1, int(round(w * scale))), maxi(1, int(round(h * scale))),
		Image.INTERPOLATE_BILINEAR)


func _mark_used(path: String) -> void:
	_lru_order.erase(path)
	_lru_order.append(path)


func _trim_textures() -> void:
	while _lru_order.size() > MAX_TEXTURES:
		_textures.erase(_lru_order.pop_front())
