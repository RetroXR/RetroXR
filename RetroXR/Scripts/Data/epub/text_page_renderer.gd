extends SubViewport
## Lays out and renders text (epub) pages for the 3D reader. One chapter's BBCode goes
## into the RichTextLabel at page width; paginate() cuts its lines into page-sized runs
## (src/ui/text_paginator.gd) and render_page() draws one run onto cream paper with a
## folio, capturing the viewport into an ImageTexture the book rig can map onto a sheet.
## Renders are serialized (one viewport), callers await render_page().

const TextPaginator := preload("res://Scripts/Data/epub/text_paginator.gd")

const BASE_HEIGHT_PX := 1536
const MARGIN_X := 0.09
const MARGIN_TOP := 0.08
const MARGIN_BOTTOM := 0.1
const FONT_FRACTION := 0.028
const INK := Color(0.16, 0.13, 0.11)

signal render_finished

@onready var _paper: ColorRect = $Paper
@onready var _clip: Control = $Paper/Clip
@onready var _label: RichTextLabel = $Paper/Clip/Text
@onready var _folio: Label = $Paper/Folio

var _rendering: bool = false
var _current_text: String = ""
var _page_px: Vector2i = Vector2i(680, BASE_HEIGHT_PX)


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_DISABLED


## Builds a renderer in code (the node tree reader.tscn used to carry): Paper > Clip >
## Text, plus a Folio label. Used by book_page_provider.gd so a world book can render
## text pages without a scene of its own.
static func create() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "TextRenderer"
	viewport.disable_3d = true
	viewport.size = Vector2i(680, BASE_HEIGHT_PX)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var paper := ColorRect.new()
	paper.name = "Paper"
	paper.size = Vector2(680, BASE_HEIGHT_PX)
	paper.color = Color(0.95, 0.91, 0.82)
	viewport.add_child(paper)
	var clip := Control.new()
	clip.name = "Clip"
	clip.clip_contents = true
	clip.position = Vector2(60, 80)
	clip.size = Vector2(560, 840)
	paper.add_child(clip)
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.fit_content = false
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size = Vector2(560, 1000000)
	clip.add_child(text)
	var folio := Label.new()
	folio.name = "Folio"
	folio.position = Vector2(0, 950)
	folio.size = Vector2(680, 40)
	folio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paper.add_child(folio)
	viewport.set_script(load("res://Scripts/Data/epub/text_page_renderer.gd"))
	return viewport


## Sizes the page for a kind: `page_size_m` fixes the aspect, `paper` the background,
## `text_scale` the body size relative to the default (pocket books run smaller).
func configure(page_size_m: Vector2, paper: Color, text_scale: float = 1.0) -> void:
	var aspect: float = page_size_m.x / maxf(page_size_m.y, 0.001)
	_page_px = Vector2i(maxi(int(round(BASE_HEIGHT_PX * aspect)), 64), BASE_HEIGHT_PX)
	size = _page_px
	_paper.color = paper
	_paper.position = Vector2.ZERO
	_paper.size = Vector2(_page_px)
	var margin_x: float = _page_px.x * MARGIN_X
	_clip.position = Vector2(margin_x, _page_px.y * MARGIN_TOP)
	_clip.size = Vector2(_page_px.x - 2.0 * margin_x, _page_px.y * (1.0 - MARGIN_TOP - MARGIN_BOTTOM))
	var font_px: int = maxi(int(round(BASE_HEIGHT_PX * FONT_FRACTION * text_scale)), 8)
	for override_name in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		_label.add_theme_font_size_override(override_name, font_px)
	_label.add_theme_color_override("default_color", INK)
	_label.position = Vector2.ZERO
	_label.size = Vector2(_clip.size.x, 1000000.0)
	_folio.add_theme_font_size_override("font_size", maxi(int(font_px * 0.75), 8))
	_folio.add_theme_color_override("font_color", INK.lerp(paper, 0.35))
	_folio.position = Vector2(0.0, _page_px.y * (1.0 - MARGIN_BOTTOM * 0.7))
	_folio.size = Vector2(_page_px.x, font_px)
	_current_text = ""
	_label.text = ""


func page_height() -> float:
	return _clip.size.y


func page_pixels() -> Vector2i:
	return _page_px


## First line index of every page `bbcode` needs at the current page size.
func paginate(bbcode: String) -> PackedInt32Array:
	_set_text(bbcode)
	var count: int = _label.get_line_count()
	var offsets := PackedFloat32Array()
	for i in range(count):
		offsets.append(_label.get_line_offset(i))
	return TextPaginator.page_starts(offsets, float(_label.get_content_height()), page_height())


func line_count() -> int:
	return _label.get_line_count()


## Renders the page starting at `first_line` of `bbcode`. Returns null when the viewport
## produced no image (headless), in which case the rig shows blank paper.
func render_page(bbcode: String, first_line: int, folio_text: String) -> ImageTexture:
	while _rendering:
		await render_finished
	_rendering = true
	_set_text(bbcode)
	var offset: float = 0.0
	if first_line > 0 and first_line < _label.get_line_count():
		offset = _label.get_line_offset(first_line)
	_label.position = Vector2(0.0, -offset)
	_folio.text = folio_text
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var result: ImageTexture = null
	var viewport_texture: ViewportTexture = get_texture()
	if viewport_texture != null:
		var image: Image = viewport_texture.get_image()
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			result = ImageTexture.create_from_image(image)
	_rendering = false
	render_finished.emit()
	return result


func _set_text(bbcode: String) -> void:
	if bbcode == _current_text:
		return
	_current_text = bbcode
	_label.text = bbcode
