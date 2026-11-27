## KavitaArtCache: series and book covers for the Books tab's Kavita list.
##
## The RomM cache's arrangement, cut down: a cover is downloaded straight to disk
## (user://kavita_cache/<server+key>/covers/), decoded on WorkerThreadPool, and
## only the texture is made on the main thread, a few a frame. Covers on disk are
## kept for good; a book whose file changed gets a new name through `revision`.
##
## Kavita serves covers from /api/Image/*-cover and reads the key from the
## `apiKey` query parameter (an <img> tag cannot send a header), so the key goes
## in the URL as well as the header. Neither URL nor key is ever logged.
class_name KavitaArtCache
extends Node


## A cover is ready for a row: kind is "series" or "chapter".
signal art_ready(kind: String, id: int, texture: Texture2D)

const MAX_CONCURRENT := 4
const DECODE_BUDGET_PER_FRAME := 4
const MAX_TEXTURES := 200

## Decoded covers outlive one browser (the Books tab is rebuilt on every visit).
static var _textures: Dictionary = {}   ## "<identity>|<kind>:<id>" -> Texture2D
static var _order: Array[String] = []

var _config: KavitaConfig
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}     ## key -> HTTPRequest
var _decoding: Dictionary = {}   ## key -> WorkerThreadPool task id
var _decoded: Array[Dictionary] = []
var _decoded_mutex := Mutex.new()
var _dead: Dictionary = {}
var _failed_logged := false


func setup(config: KavitaConfig) -> void:
	_config = config


## The cover if it is in memory, else null and a fetch starts; art_ready follows.
func get_or_request(kind: String, id: int, revision: String = "") -> Texture2D:
	if _config == null or id <= 0:
		return null
	var key := _key(kind, id)
	if _textures.has(key):
		return _textures[key]
	if _dead.has(key) or _active.has(key) or _decoding.has(key):
		return null
	var disk := _disk_path(kind, id, revision)
	if FileAccess.file_exists(disk):
		_start_decode(key, kind, id, disk)
		return null
	for job: Dictionary in _queue:
		if job.key == key:
			return null
	var param := "seriesId" if kind == "series" else "chapterId"
	var url := "%s/api/Image/%s-cover?%s=%d&apiKey=%s" % [
		_config.base_url, kind, param, id, _config.auth_key.uri_encode()]
	_queue.append({"key": key, "kind": kind, "id": id, "url": url, "path": disk})
	return null


func _process(_delta: float) -> void:
	_promote_decoded()
	while _active.size() < MAX_CONCURRENT and not _queue.is_empty():
		_start_fetch(_queue.pop_front())


func _exit_tree() -> void:
	# Every pool task is waited on: one left unclaimed outlives GDScript at quit.
	for key: String in _decoding.keys():
		WorkerThreadPool.wait_for_task_completion(_decoding[key])
	_decoding.clear()
	for http: HTTPRequest in _active.values():
		if is_instance_valid(http):
			http.cancel_request()
	_active.clear()
	_queue.clear()


func _identity() -> String:
	return (_config.base_url + "\n" + _config.auth_key).md5_text()


func _key(kind: String, id: int) -> String:
	return "%s|%s:%d" % [_identity(), kind, id]


func _disk_path(kind: String, id: int, revision: String) -> String:
	var name := "%s_%d" % [kind, id]
	if not revision.is_empty():
		name += "_" + revision.md5_text().left(12)
	return "user://kavita_cache/%s/covers/%s.img" % [_identity(), name]


func _start_fetch(job: Dictionary) -> void:
	var disk := str(job.path)
	DirAccess.make_dir_recursive_absolute(disk.get_base_dir())
	var part := disk + ".part"
	var http := HTTPRequest.new()
	http.use_threads = true
	http.max_redirects = 0
	http.timeout = 15.0
	http.download_file = part
	add_child(http)
	_active[job.key] = http
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			_active.erase(job.key)
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 \
					or DirAccess.rename_absolute(part, disk) != OK:
				DirAccess.remove_absolute(part)
				_dead[job.key] = true
				# Once per browser: a server with no covers would say it 40 times a page.
				if not _failed_logged:
					_failed_logged = true
					print("[Kavita] %s cover %d not fetched (HTTP %d, result %d); its row keeps its title only"
						% [job.kind, job.id, code, result])
				return
			_start_decode(job.key, job.kind, job.id, disk))
	if http.request(job.url, _config.auth_headers()) != OK:
		_active.erase(job.key)
		http.queue_free()
		_dead[job.key] = true


func _start_decode(key: String, kind: String, id: int, path: String) -> void:
	if _decoding.has(key):
		return
	_decoding[key] = WorkerThreadPool.add_task(_decode_task.bind(key, kind, id, path))


## Pool thread. Kavita stores covers as PNG, JPEG or WebP, so the format is read
## from the bytes, never from a file name.
func _decode_task(key: String, kind: String, id: int, path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match KavitaClient.image_extension(bytes):
		"png": err = img.load_png_from_buffer(bytes)
		"jpg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
	_decoded_mutex.lock()
	_decoded.append({"key": key, "kind": kind, "id": id, "image": img if err == OK else null})
	_decoded_mutex.unlock()


func _promote_decoded() -> void:
	for i in DECODE_BUDGET_PER_FRAME:
		_decoded_mutex.lock()
		if _decoded.is_empty():
			_decoded_mutex.unlock()
			return
		var item: Dictionary = _decoded.pop_front()
		_decoded_mutex.unlock()
		var key := str(item.key)
		if _decoding.has(key):
			WorkerThreadPool.wait_for_task_completion(_decoding[key])
			_decoding.erase(key)
		var img: Image = item.image
		if img == null or img.is_empty():
			_dead[key] = true
			continue
		var tex := ImageTexture.create_from_image(img)
		_textures[key] = tex
		_order.append(key)
		while _order.size() > MAX_TEXTURES:
			_textures.erase(_order.pop_front())
		art_ready.emit(str(item.kind), int(item.id), tex)
