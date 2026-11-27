## Reads the package and reading order of an EPUB without extracting it to disk.
## Paths are archive-relative and must resolve within the ZIP.
class_name EpubPackage
extends RefCounted

const XHTML := preload("res://Scripts/Data/epub/xhtml_to_bbcode.gd")

var path: String = ""
var title: String = ""
var spine: PackedStringArray = []
var error: String = ""
var cover_path: String = ""


func open(file_path: String) -> bool:
	path = ""
	title = ""
	spine.clear()
	cover_path = ""
	error = ""
	var zip := ZIPReader.new()
	if zip.open(file_path) != OK:
		return _fail("Could not open EPUB")
	var files := zip.get_files()
	if not files.has("META-INF/container.xml"):
		zip.close()
		return _fail("EPUB has no container")
	var root := _rootfile(zip.read_file("META-INF/container.xml"))
	if root.is_empty() or not files.has(root):
		zip.close()
		return _fail("EPUB package is missing")
	var ok := _read_package(zip.read_file(root), root.get_base_dir(), files)
	zip.close()
	if ok:
		path = file_path
	return ok


func _rootfile(data: PackedByteArray) -> String:
	var xml := XMLParser.new()
	if xml.open_buffer(data) != OK:
		return ""
	while xml.read() == OK:
		if xml.get_node_type() == XMLParser.NODE_ELEMENT and _local(xml.get_node_name()) == "rootfile":
			var name := _attr(xml, "full-path")
			return ArchiveSafety.safe_member(name)
	return ""


func _read_package(data: PackedByteArray, base: String, files: PackedStringArray) -> bool:
	var xml := XMLParser.new()
	if xml.open_buffer(data) != OK:
		return _fail("Unreadable EPUB package")
	var manifest := {}
	var images := {}
	var cover_id := ""
	var order: PackedStringArray = []
	var in_title := false
	var read_error := OK
	while true:
		read_error = xml.read()
		if read_error != OK:
			break
		var kind := xml.get_node_type()
		if kind == XMLParser.NODE_ELEMENT:
			var tag := _local(xml.get_node_name())
			if tag == "title" and title.is_empty():
				in_title = true
			elif tag == "item":
				var id := _attr(xml, "id")
				var href := _attr(xml, "href")
				var media_type := _attr(xml, "media-type")
				if not id.is_empty() and media_type in ["application/xhtml+xml", "text/html"]:
					manifest[id] = _resolve(base, href)
				elif not id.is_empty() and media_type.begins_with("image/"):
					var image_path := _resolve(base, href)
					images[id] = image_path
					if _attr(xml, "properties").split(" ", false).has("cover-image"):
						cover_path = image_path
			elif tag == "meta" and _attr(xml, "name") == "cover":
				cover_id = _attr(xml, "content")
			elif tag == "itemref" and _attr(xml, "linear") != "no":
				order.append(_attr(xml, "idref"))
		elif kind == XMLParser.NODE_TEXT and in_title:
			title += xml.get_node_data()
		elif kind == XMLParser.NODE_ELEMENT_END and _local(xml.get_node_name()) == "title":
			in_title = false
	if read_error != ERR_FILE_EOF:
		return _fail("Malformed EPUB package")
	for id: String in order:
		var member := str(manifest.get(id, ""))
		if member.is_empty() or not files.has(member):
			spine.clear()
			return _fail("EPUB reading order references a missing chapter")
		spine.append(member)
	if spine.is_empty():
		return _fail("EPUB has no readable chapters")
	if cover_path.is_empty():
		cover_path = str(images.get(cover_id, ""))
	if not files.has(cover_path):
		cover_path = ""
	title = title.strip_edges()
	return true


func chapter_text(index: int) -> String:
	if index < 0 or index >= spine.size() or path.is_empty():
		return ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return ""
	var data := zip.read_file(spine[index])
	zip.close()
	return XHTML.convert(data.get_string_from_utf8())


func cover_image() -> Image:
	if cover_path.is_empty() or path.is_empty():
		return null
	return _image_at(cover_path)


func chapter_image(index: int) -> Image:
	var members := chapter_images(index)
	return _image_at(members[0]) if not members.is_empty() else null


## One archive member decoded, or null.
func image_at(member: String) -> Image:
	return _image_at(member)


## Every image a chapter shows, in document order, as archive members. A comic
## made into an EPUB is often ONE chapter of a few hundred pictures (Seconds is
## 327 in one file, Silverwing 203 in its Chapter 1); each is a page.
func chapter_images(index: int) -> PackedStringArray:
	var members := PackedStringArray()
	if index < 0 or index >= spine.size() or path.is_empty():
		return members
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return members
	var xhtml := zip.read_file(spine[index]).get_string_from_utf8()
	zip.close()
	var regex := RegEx.new()
	regex.compile("(?i)<img[^>]*?\\ssrc\\s*=\\s*[\"']([^\"']+)[\"']|<image[^>]*?\\s(?:xlink:)?href\\s*=\\s*[\"']([^\"']+)[\"']")
	for found: RegExMatch in regex.search_all(xhtml):
		var href := found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2)
		var member := _resolve(spine[index].get_base_dir(), href)
		if not member.is_empty():
			members.append(member)
	return members


func _image_at(member: String) -> Image:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return null
	if not zip.get_files().has(member):
		zip.close()
		return null
	var data := zip.read_file(member)
	zip.close()
	var img := Image.new()
	var err := ERR_UNAVAILABLE
	match member.get_extension().to_lower():
		"png": err = img.load_png_from_buffer(data)
		"jpg", "jpeg": err = img.load_jpg_from_buffer(data)
		"webp": err = img.load_webp_from_buffer(data)
		"svg": err = img.load_svg_from_buffer(data)
	return img if err == OK and not img.is_empty() else null


static func _resolve(base: String, href: String) -> String:
	var relative := href.get_slice("#", 0).get_slice("?", 0).uri_decode()
	if relative.is_empty() or relative.begins_with("/") or relative.contains(":") or relative.contains("\\"):
		return ""
	var parts: Array[String] = []
	if not base.is_empty() and base != ".":
		for part: String in base.split("/", false):
			parts.append(part)
	for part: String in relative.split("/", true):
		if part == "..":
			if parts.is_empty():
				return ""
			parts.pop_back()
		elif part != "." and not part.is_empty():
			parts.append(part)
	return ArchiveSafety.safe_member("/".join(parts))


static func _local(name: String) -> String:
	return name.get_slice(":", 1) if name.contains(":") else name


static func _attr(xml: XMLParser, name: String) -> String:
	return xml.get_named_attribute_value_safe(name)


func _fail(message: String) -> bool:
	error = message
	return false
