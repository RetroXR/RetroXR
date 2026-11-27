extends Node

const PACKAGE := preload("res://Scripts/Data/epub/epub_package.gd")
const PROVIDER := preload("res://Scripts/Data/epub/epub_page_provider.gd")
const FIXTURE := "user://__epub_package_test.epub"
var failures := 0
var checks := 0


func _ready() -> void:
	var zip := ZIPPacker.new()
	_check(zip.open(FIXTURE) == OK, "create fixture")
	_add(zip, "META-INF/container.xml", '<container><rootfiles><rootfile full-path="OPS/package.opf"/></rootfiles></container>')
	_add(zip, "OPS/package.opf", '<package xmlns:dc="urn:test"><metadata><dc:title>Example</dc:title></metadata><manifest><item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/><item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/></manifest><spine><itemref idref="b"/><itemref idref="a"/><itemref idref="c"/></spine></package>')
	_add(zip, "OPS/text/a.xhtml", '<html><body><img src="../cover.png"/></body></html>')
	_add(zip, "OPS/text/b.xhtml", "<html><body><p>Second chapter</p></body></html>")
	# A comic as one chapter: three pictures, a page each.
	_add(zip, "OPS/text/c.xhtml", '<html><body><div><img src="../cover.png"/></div><div><img src="../p2.png"/></div><p><img src="../cover.png"/></p></body></html>')
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	zip.start_file("OPS/cover.png")
	zip.write_file(image.save_png_to_buffer())
	zip.close_file()
	var blue := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	zip.start_file("OPS/p2.png")
	zip.write_file(blue.save_png_to_buffer())
	zip.close_file()
	zip.close()
	var epub = PACKAGE.new()
	_check(epub.open(FIXTURE), "open package")
	_check(epub.title == "Example", "read title")
	_check(epub.spine == PackedStringArray(["OPS/text/b.xhtml", "OPS/text/a.xhtml", "OPS/text/c.xhtml"]), "spine order")
	_check(epub.chapter_images(2) == PackedStringArray(["OPS/cover.png", "OPS/p2.png", "OPS/cover.png"]),
		"every picture of a chapter, in order")
	_check(epub.chapter_text(0).contains("Second chapter"), "read chapter text in spine order")
	_check(epub.cover_image() != null, "read cover")
	_check(epub.chapter_image(1) != null, "read image-only chapter")
	_check(PACKAGE._resolve("OPS/text", "../images/cover.png") == "OPS/images/cover.png", "resolve relative path")
	_check(PACKAGE._resolve("OPS", "../../outside") == "", "reject archive escape")
	_check(PACKAGE._resolve("OPS", "https://example.com/x") == "", "reject external URL")
	var provider := PROVIDER.new()
	add_child(provider)
	_check(await provider.prepare(FIXTURE), "prepare text pages")
	_check(provider.pages.size() >= 3, "cover and chapters produce pages")
	# Mostly pictures (the cover, a picture chapter and three more): the cover's
	# 2x2 shape, not the text page's 0.65.
	_check(is_equal_approx(provider.picture_aspect(), 1.0), "a book of pictures takes its art's shape")
	_check(provider.pages.back().has("image"), "image-only chapter becomes a page")
	var comic := provider.pages.filter(func(p: Dictionary) -> bool: return int(p.get("chapter", -1)) == 2)
	_check(comic.size() == 3, "a chapter of three pictures is three pages")
	var second: Image = await provider.render(provider.pages.find(comic[1]))
	_check(second != null and second.get_pixel(0, 0).is_equal_approx(Color.BLUE), "each picture page shows its own picture")
	provider.queue_free()
	DirAccess.remove_absolute(FIXTURE)
	# The summary line Tools/run_tests.py reads (TestSuite's format).
	print("[epub] RESULT %d passed, %d failed: %s" % [checks - failures, failures, "FAIL" if failures else "PASS"])
	get_tree().quit(1 if failures else 0)


func _add(zip: ZIPPacker, name: String, contents: String) -> void:
	zip.start_file(name)
	zip.write_file(contents.to_utf8_buffer())
	zip.close_file()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("[epub] FAIL ", message)
