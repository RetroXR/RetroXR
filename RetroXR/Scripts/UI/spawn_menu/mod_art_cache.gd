## ModArtCache — preview images for the mod browser's tiles.
##
## RommArtCache's mechanism with a different key: bytes go straight to disk
## through HTTPRequest.download_file, the decode runs on WorkerThreadPool, and
## only ImageTexture.create_from_image touches the main thread, budgeted per
## frame. The reasons are that class's and are not repeated here.
##
## Keyed by the image's own address rather than a mod id, and a cached file is
## treated as immutable and never revalidated, as RomM covers are. That an
## author's replaced logo arrives under a new address is ASSUMED from the shape
## of mod.io's image paths, not measured; if it does not, the cost is a stale
## picture until user://modio_art is cleared.
##
## Cached in user://, not beside the mods: the mods root on a Quest may be a
## folder the app cannot write to, and a tile's picture is not worth a failed
## download over.
class_name ModArtCache
extends Node

signal art_ready(url: String, texture: Texture2D)

const MAX_CONCURRENT := 4
## A page of tiles is 24; this holds a few pages either side of the one on screen.
const MAX_TEXTURES := 120
const DECODE_BUDGET_PER_FRAME := 2
const CACHE_DIR := "user://modio_art"

var _textures: Dictionary = {}        ## url -> ImageTexture
var _lru_order: Array[String] = []
var _queue: Array[String] = []
var _active: Dictionary = {}          ## url -> HTTPRequest
var _decoding: Dictionary = {}        ## url -> WorkerThreadPool task id
var _decoded: Array[Dictionary] = []  ## [{url, image}] awaiting promotion
var _decoded_mutex := Mutex.new()
## Fetches that failed or decoded to nothing. Never retried this session; the
## tile keeps its placeholder.
var _dead: Dictionary = {}


func _process(_delta: float) -> void:
	_promote_decoded()
	while _active.size() < MAX_CONCURRENT and not _queue.is_empty():
		_start_fetch(_queue.pop_front())


## The texture for an image address if it is already in memory, else null (and
## a fetch starts, announced by art_ready).
func get_or_request(url: String) -> Texture2D:
	if url.is_empty():
		return null
	if _textures.has(url):
		_mark_used(url)
		return _textures[url]
	if _dead.has(url) or _active.has(url) or _decoding.has(url) or _queue.has(url):
		return null
	var disk := disk_path(url)
	if FileAccess.file_exists(disk):
		_start_decode(url, disk)
	else:
		_queue.append(url)
	return null


## Drop fetches nobody is waiting for any more -- a page that was turned away from.
func cancel_outside(keep: PackedStringArray) -> void:
	var kept: Array[String] = []
	for url: String in _queue:
		if keep.has(url):
			kept.append(url)
	_queue = kept


static func disk_path(url: String) -> String:
	var ext := url.get_slice("?", 0).get_extension().to_lower()
	if not (ext in ["png", "jpg", "jpeg", "webp"]):
		ext = "png"
	return CACHE_DIR.path_join("%s.%s" % [url.md5_text(), ext])


func _start_fetch(url: String) -> void:
	var disk := disk_path(url)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))

	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_file = disk
	http.timeout = 15.0
	add_child(http)
	_active[url] = http
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			_active.erase(url)
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
				_dead[url] = true
				if FileAccess.file_exists(disk):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(disk))
				return
			_start_decode(url, disk))
	if http.request(url) != OK:
		_active.erase(url)
		http.queue_free()
		_dead[url] = true


func _start_decode(url: String, path: String) -> void:
	if _decoding.has(url):
		return
	_decoding[url] = WorkerThreadPool.add_task(_decode_task.bind(url, path))


## Runs on a pool thread.
func _decode_task(url: String, path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	_decoded_mutex.lock()
	_decoded.append({"url": url, "image": img})
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

		var url := str(item["url"])
		if _decoding.has(url):
			WorkerThreadPool.wait_for_task_completion(_decoding[url])
			_decoding.erase(url)
		promoted += 1
		var img: Image = item["image"]
		if img == null or img.is_empty():
			_dead[url] = true
			continue
		var tex := ImageTexture.create_from_image(img)
		_textures[url] = tex
		_mark_used(url)
		while _lru_order.size() > MAX_TEXTURES:
			_textures.erase(_lru_order.pop_front())
		art_ready.emit(url, tex)


func _mark_used(url: String) -> void:
	_lru_order.erase(url)
	_lru_order.append(url)


func _exit_tree() -> void:
	for id: int in _decoding.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_decoding.clear()
