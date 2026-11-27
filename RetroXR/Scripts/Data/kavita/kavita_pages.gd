## KavitaPages: a comic or PDF read straight off a Kavita server, page by page,
## with nothing downloaded first. A PDFBook whose path is `kavita://chapter/<id>`
## opens one of these instead of a file.
##
## Kavita renders every page of any archive (CBR, CB7, CBZ) and of a PDF as an
## image through /api/Reader/image, and says each page's size through
## /api/Reader/file-dimensions, so the book knows its shape before the first page
## arrives. EPUBs are not streamed: Kavita's book reader serves HTML, not pages.
##
## A fetched page lands in the book's own page cache like any rendered one, so a
## page read once opens from disk after that.
class_name KavitaPages
extends RefCounted


const SCHEME := "kavita://chapter/"
## Pages fetched at once. A turn prefetches about fifteen, and every one is a
## full-size scan: four at a time keeps the server and a Quest's network busy
## without queueing fifteen requests behind each other.
const MAX_FETCHES := 4

var config := KavitaConfig.new()
var chapter_id := 0
var page_total := 0
## The first page's size in pixels, the book's page shape.
var page_size := Vector2i(2, 3)
## A PDF on the server: its pages are asked for as images (extractPdf).
var is_pdf := false
var _active := 0


static func is_remote(path: String) -> bool:
	return path.begins_with(SCHEME)


static func path_for(chapter: int) -> String:
	return SCHEME + str(chapter)


static func chapter_of(path: String) -> int:
	return path.trim_prefix(SCHEME).get_slice("/", 0).get_slice("?", 0).to_int() if is_remote(path) else 0


## Learn the chapter's page count and shape. "" when it opened, else why not.
func open(host: Node, path: String) -> String:
	chapter_id = chapter_of(path)
	config.load_config()
	if chapter_id <= 0:
		return "Not a Kavita book"
	if not config.is_configured():
		return "Kavita is not set up"
	var info: Dictionary = await KavitaClient.request_json(host, config,
		"/api/Reader/chapter-info?chapterId=%d" % chapter_id)
	if not info.ok or not (info.data is Dictionary):
		return "Kavita: " + KavitaClient.describe_error(info)
	var data: Dictionary = info.data
	page_total = int(data.get("pages", 0))
	is_pdf = str(data.get("fileName", "")).get_extension().to_lower() == "pdf"
	if page_total <= 0:
		return "Kavita lists no pages"
	var dims: Dictionary = await KavitaClient.request_json(host, config,
		"/api/Reader/file-dimensions?chapterId=%d&extractPdf=%s" % [chapter_id, "true" if is_pdf else "false"])
	if dims.ok and dims.data is Array and not (dims.data as Array).is_empty():
		var first: Dictionary = (dims.data as Array)[0]
		var w := int(first.get("width", 0))
		var h := int(first.get("height", 0))
		if w > 0 and h > 0:
			page_size = Vector2i(w, h)
	print("[Kavita] streaming chapter %d: %d pages, %dx%d%s" % [chapter_id, page_total,
		page_size.x, page_size.y, ", a PDF" if is_pdf else ""])
	return ""


## Fetch one page's image into `to_path`. {ok, code, error}. Waits its turn
## behind MAX_FETCHES others.
func fetch_page(host: Node, page: int, to_path: String) -> Dictionary:
	while _active >= MAX_FETCHES:
		if not is_instance_valid(host) or not host.is_inside_tree():
			return {"ok": false, "code": 0, "error": "book gone", "data": null}
		await host.get_tree().process_frame
	_active += 1
	# apiKey in the query as well as the header: Kavita's image endpoints read it there.
	var res: Dictionary = await KavitaClient.download(host, config,
		"/api/Reader/image?chapterId=%d&page=%d&extractPdf=%s&apiKey=%s" % [chapter_id, page,
		"true" if is_pdf else "false", config.auth_key.uri_encode()], to_path)
	_active -= 1
	return res


## A page's bytes as an image, on any thread. Null when they are not one.
static func decode(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match KavitaClient.image_extension(bytes):
		"png": err = img.load_png_from_buffer(bytes)
		"jpg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
	return img if err == OK and not img.is_empty() else null
