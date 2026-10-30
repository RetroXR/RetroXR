## VfdDisplay — a vacuum fluorescent display on an appliance's face (the RETRO XR VCR, DVD player, receiver).
##
## A quad drawn through its own SubViewport, redrawn ONLY when the owner calls refresh() — never every frame, never
## UPDATE_ALWAYS (a headless run hangs on that, and a Quest pays for it). The owner sets `painter`, a Callable taking
## (canvas: Control, size: Vector2), and draws with the static helpers below: seven-segment digits as hexagonal bars
## (lit pale blue-white, unlit a faint ghost of themselves, as on a real VFD), boxed status lamps and Michroma
## legends. Those match RetroXR-models' common/applkit/vfd.py, which drew the review renders the user approved.
class_name VfdDisplay
extends Node3D

const BG := Color8(4, 6, 8)
const LIT := Color8(176, 232, 255)
const GHOST := Color8(20, 30, 36)
const RED := Color8(255, 96, 62)
const RED_GHOST := Color8(38, 18, 14)
const FONT_PATH := "res://fonts/Michroma-Regular.ttf"

## Which of a..g each character lights.
const SEGS := {
	"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg", "7": "abc",
	"8": "abcdefg", "9": "abcdfg", "-": "g", " ": "",
}

## The panel's size (m); the quad faces this node's +Z.
@export var size_m: Vector2 = Vector2(0.126, 0.025)
## Texture resolution: pixels per millimeter of panel.
@export var px_per_mm: float = 10.0
## Brightness multiplier of the panel: a VFD behind a smoked window (alpha 0.45-0.6) reads gray at 1.0.
@export var glow: float = 1.0

## func(canvas: Control, size: Vector2) -> void
var painter: Callable

static var _font: Font

var _viewport: SubViewport
var _canvas: Control
var _quad: MeshInstance3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "VfdViewport"
	_viewport.size = Vector2i(roundi(size_m.x * 1000.0 * px_per_mm), roundi(size_m.y * 1000.0 * px_per_mm))
	_viewport.transparent_bg = false
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.size = Vector2(_viewport.size)
	_canvas.draw.connect(_on_draw)
	_viewport.add_child(_canvas)
	_quad = MeshInstance3D.new()
	_quad.name = "Screen"
	var q := QuadMesh.new()
	q.size = size_m
	_quad.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.albedo_color = Color(glow, glow, glow, 1.0)
	_quad.material_override = mat
	add_child(_quad)
	refresh()


## Draw the panel again (call when what it shows changes).
func refresh() -> void:
	if _canvas == null:
		return
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The quad (to set a visibility range on, or hide).
func screen() -> MeshInstance3D:
	return _quad


func _on_draw() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), BG)
	if painter.is_valid():
		painter.call(_canvas, _canvas.size)


# --- drawing helpers ------------------------------------------------------------------------------------------------

static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font


## Seven hexagonal bars of a digit in `box`, `t` thick, slanted like a VFD's.
static func seg_polys(box: Rect2, t: float, slant: float = 0.12) -> Dictionary:
	var x := box.position.x
	var y := box.position.y
	var w := box.size.x
	var h := box.size.y
	var g := t * 0.18
	var hl := w - t - 2.0 * g
	var vl := h / 2.0 - t / 2.0 - 2.0 * g
	var p := {
		"a": _bar_h(x + w / 2.0, y + t / 2.0, hl, t), "g": _bar_h(x + w / 2.0, y + h / 2.0, hl, t),
		"d": _bar_h(x + w / 2.0, y + h - t / 2.0, hl, t),
		"f": _bar_v(x + t / 2.0, y + h / 4.0 + t / 4.0, vl, t), "b": _bar_v(x + w - t / 2.0, y + h / 4.0 + t / 4.0, vl, t),
		"e": _bar_v(x + t / 2.0, y + 3.0 * h / 4.0 - t / 4.0, vl, t), "c": _bar_v(x + w - t / 2.0, y + 3.0 * h / 4.0 - t / 4.0, vl, t),
	}
	var ybase := y + h
	for k in p:
		var pts: PackedVector2Array = p[k]
		for i in pts.size():
			pts[i] = Vector2(pts[i].x + slant * (ybase - pts[i].y), pts[i].y)
		p[k] = pts
	return p


static func _bar_h(cx: float, cy: float, length: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - length / 2.0, cy), Vector2(cx - length / 2.0 + t / 2.0, cy - t / 2.0),
		Vector2(cx + length / 2.0 - t / 2.0, cy - t / 2.0), Vector2(cx + length / 2.0, cy),
		Vector2(cx + length / 2.0 - t / 2.0, cy + t / 2.0), Vector2(cx - length / 2.0 + t / 2.0, cy + t / 2.0)])


static func _bar_v(cx: float, cy: float, length: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx, cy - length / 2.0), Vector2(cx + t / 2.0, cy - length / 2.0 + t / 2.0),
		Vector2(cx + t / 2.0, cy + length / 2.0 - t / 2.0), Vector2(cx, cy + length / 2.0),
		Vector2(cx - t / 2.0, cy + length / 2.0 - t / 2.0), Vector2(cx - t / 2.0, cy - length / 2.0 + t / 2.0)])


## One character as seven segments; an unknown character shows all ghosts.
static func digit(ci: CanvasItem, ch: String, box: Rect2, t: float) -> void:
	var on: String = SEGS.get(ch, "")
	var polys := seg_polys(box, t)
	for k in polys:
		ci.draw_colored_polygon(polys[k], LIT if on.contains(k) else GHOST)


## A string of digits left to right, `pitch` apart (spaces keep their slot as ghosts).
static func digits(ci: CanvasItem, text: String, origin: Vector2, w: float, h: float, t: float, pitch: float) -> void:
	for i in text.length():
		digit(ci, text[i], Rect2(origin + Vector2(i * pitch, 0.0), Vector2(w, h)), t)


## Just the middle bar (a minus sign with no ghost digit behind it).
static func minus(ci: CanvasItem, box: Rect2, t: float, lit: bool) -> void:
	ci.draw_colored_polygon(seg_polys(box, t)["g"], LIT if lit else GHOST)


## A legend in Michroma; `pos` is the left of its baseline.
static func text(ci: CanvasItem, s: String, pos: Vector2, size: int, lit: bool, red: bool = false) -> void:
	var col := (RED if lit else RED_GHOST) if red else (LIT if lit else GHOST)
	ci.draw_string(font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## A boxed status lamp (PLAY, REC, ...): an outlined rounded box with its word centered.
static func boxed(ci: CanvasItem, s: String, box: Rect2, size: int, lit: bool, red: bool = false) -> void:
	var col := (RED if lit else RED_GHOST) if red else (LIT if lit else GHOST)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(6)
	sb.draw(ci.get_canvas_item(), box)
	var w := font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := font().get_ascent(size)
	ci.draw_string(font(), Vector2(box.position.x + (box.size.x - w) / 2.0, box.position.y + (box.size.y + asc * 0.72) / 2.0),
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
