## Paginate an EPUB once and render individual pages through a single viewport.
extends Node

const RENDERER := preload("res://Scripts/Data/epub/text_page_renderer.gd")
const PACKAGE := preload("res://Scripts/Data/epub/epub_package.gd")

var package = PACKAGE.new()
var renderer: SubViewport
var pages: Array[Dictionary] = []
var chapters: Array[String] = []
var cover: Image


func prepare(path: String) -> bool:
	if not package.open(path):
		return false
	renderer = RENDERER.create()
	add_child(renderer)
	renderer.configure(Vector2(0.65, 1.0), Color(0.95, 0.93, 0.87))
	cover = package.cover_image()
	if cover != null:
		pages.append({"cover": true})
	for index in package.spine.size():
		var text: String = package.chapter_text(index)
		chapters.append(text)
		# A chapter of pictures and next to no text (a title page, or a whole
		# comic): each picture is a page of its own.
		if text.contains("[image omitted]") and text.replace("[image omitted]", "").strip_edges().length() <= 40:
			var members: PackedStringArray = package.chapter_images(index)
			if not members.is_empty():
				for member: String in members:
					pages.append({"chapter": index, "image": true, "member": member})
				if members.size() > 1:
					print("[EPUB] %s: %d pictures, a page each" % [package.spine[index].get_file(), members.size()])
				await get_tree().process_frame
				continue
		var starts: PackedInt32Array = renderer.paginate(text)
		if starts.is_empty():
			starts.append(0)
		for line in starts:
			pages.append({"chapter": index, "line": line})
		# Large books are laid out incrementally to keep the room responsive.
		await get_tree().process_frame
	return not pages.is_empty()


## Width over height for a book that is mostly pictures (a comic or graphic
## novel made into an EPUB): its cover's, else its first picture's. 0 for a book
## of text, which keeps the text page's shape.
func picture_aspect() -> float:
	var pictures := pages.filter(func(p: Dictionary) -> bool: return p.has("image") or p.has("cover"))
	if pictures.size() * 2 < pages.size():
		return 0.0
	var img: Image = cover
	if img == null:
		for p: Dictionary in pages:
			if p.has("image"):
				img = package.image_at(str(p["member"]))
				break
	if img == null or img.get_height() <= 0:
		return 0.0
	return float(img.get_width()) / float(img.get_height())


func render(index: int) -> Image:
	if index < 0 or index >= pages.size():
		return null
	var page := pages[index]
	if page.has("cover"):
		return cover.duplicate() as Image
	if page.has("image"):
		return package.image_at(str(page["member"]))
	var texture: ImageTexture = await renderer.render_page(
		chapters[int(page["chapter"])], int(page["line"]), str(index + 1))
	return texture.get_image() if texture != null else null
