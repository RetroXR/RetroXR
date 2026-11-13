## ArcadePanelGlow — how a player's panel says "this one is yours to take": a glow on the deck in the player's own colour
## (the stick ball's: 1P red, 2P blue, 3P green, 4P yellow) and a "1P" bouncing over it, while it is aimed at or a hand is
## near; once taken, the glow goes and the glyph settles into a small steady badge that stays while it is played.
##
## One additive quad over the panel, drawn by a shader from a signed distance to the panel's rounded outline (or to a
## wheel's rim), so there is nothing to sort and no mesh to rebuild when a form changes its size. `style` picks the look.
class_name ArcadePanelGlow
extends Node3D

enum Style { RIM_SWEEP, POOL, MARCH }

## The look every panel uses.
static var style := Style.RIM_SWEEP

## How far the glow reaches beyond the panel's edge (the quad is this much bigger all round), metres.
const PAD := 0.035
## The glyph's height over the panel's middle, the bounce on top of it, and bounces a second.
const GLYPH_RISE := 0.12
const BOUNCE := 0.03
const BOUNCE_HZ := 1.5
## The badge (taken, not aimed at): this size, this high.
const BADGE_SCALE := 0.75
const BADGE_RISE := 0.13
## How fast the glow fades in and out (strength per second).
const FADE := 6.0

const _SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform vec2 half_size = vec2(0.14, 0.09);
uniform vec2 quad_half = vec2(0.17, 0.12);
uniform float corner = 0.02;
uniform int style = 0;
uniform float strength = 1.0;
uniform float ring_r = 0.0;
uniform float ring_w = 0.06;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * quad_half;
	p.y = -p.y;
	float d = ring_r > 0.0 ? abs(length(p) - ring_r) - ring_w * 0.5 : sd_box(p, half_size, corner);
	float inside = 1.0 - smoothstep(-0.002, 0.002, d);
	float g = 0.0;
	if (style == 0) {
		// A bright rim on the outline, a faint fill, and a band of light sweeping across.
		float rim = exp(-abs(d) / 0.004) + 0.5 * exp(-max(d, 0.0) / 0.012) * (1.0 - inside);
		float fill = inside * 0.10 * (0.5 + 0.5 * smoothstep(-0.05, 0.0, d));
		float span = (ring_r > 0.0 ? ring_r + ring_w : half_size.x) + 0.08;
		float sx = mix(-span, span, fract(TIME * 0.55));
		float sweep = inside * 0.5 * exp(-pow((p.x - p.y * 0.35 - sx) / 0.025, 2.0));
		g = rim + fill + sweep;
	} else if (style == 1) {
		// A pool of light that breathes, brightest toward its edge, with a halo round it.
		float pulse = 0.55 + 0.45 * sin(TIME * 4.0);
		float pool = inside * (0.18 + 0.35 * smoothstep(-0.07, 0.0, d));
		float halo = (1.0 - inside) * 0.6 * exp(-max(d, 0.0) / 0.012);
		g = (pool + halo) * pulse;
	} else {
		// Marquee bulbs chasing round, on a line 9 mm inside the edge.
		float s;
		if (ring_r > 0.0) {
			s = (atan(p.y, p.x) + PI) * ring_r;
		} else {
			vec2 b = half_size;
			if (b.x - abs(p.x) > b.y - abs(p.y)) {
				s = p.y < 0.0 ? p.x + b.x : 2.0 * b.x + 2.0 * b.y + (b.x - p.x);
			} else {
				s = p.x > 0.0 ? 2.0 * b.x + (p.y + b.y) : 4.0 * b.x + 2.0 * b.y + (b.y - p.y);
			}
		}
		float spacing = 0.022;
		float ph = s / spacing - TIME * 6.0;
		float along = (fract(ph) - 0.5) * spacing;
		float dist = length(vec2(along, d + 0.009));
		float lit = mod(floor(ph), 3.0) < 1.0 ? 1.0 : 0.22;
		g = (smoothstep(0.0048, 0.0025, dist) + exp(-dist / 0.004) * 0.35) * lit + inside * 0.05;
	}
	ALBEDO = tint.rgb * 1.6;
	ALPHA = clamp(g * strength, 0.0, 1.0);
}
"""

static var _shader: Shader = null
static var _font: Font = null

var panel_size := Vector2(0.285, 0.185)
## Where the glow goes, in the grip's XY, when it is not the whole panel: round the stick and the buttons only.
var rect := Rect2()
var ring_radius := 0.0
var ring_width := 0.06
var player := 0
var color := Color(0.85, 0.10, 0.10)

var _quad: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _glyph: Label3D = null
var _strength := 0.0
var _aimed := false
var _taken := false
var _t := 0.0
var _pop := 0.0


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_quad = MeshInstance3D.new()
	_quad.name = "Glow"
	var quad := QuadMesh.new()
	_quad.mesh = quad
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.visible = false
	add_child(_quad)
	_glyph = Label3D.new()
	_glyph.name = "Glyph"
	_glyph.top_level = true
	_glyph.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_glyph.double_sided = true
	_glyph.font_size = 128
	_glyph.outline_size = 28
	_glyph.pixel_size = 0.0004
	if _font == null and ResourceLoader.exists("res://fonts/Michroma-Regular.ttf"):
		_font = load("res://fonts/Michroma-Regular.ttf") as Font
	if _font != null:
		_glyph.font = _font
	_glyph.visible = false
	add_child(_glyph)
	refresh_shape()
	set_process(false)


## The panel's size and its player, again (a form that changes the panel calls this).
func refresh_shape() -> void:
	if _quad == null:
		return
	# Only where the stick and the buttons are, when the panel says (`rect`, in the grip's XY); else the whole panel.
	var size := rect.size if rect.has_area() else panel_size
	_quad.position = Vector3(rect.get_center().x, rect.get_center().y, 0.0) if rect.has_area() else Vector3.ZERO
	var half := size * 0.5
	if ring_radius > 0.0:
		var r := ring_radius + ring_width * 0.5
		half = Vector2(r, r)
	var quad_half := half + Vector2(PAD, PAD)
	(_quad.mesh as QuadMesh).size = quad_half * 2.0
	_mat.set_shader_parameter("half_size", size * 0.5)
	_mat.set_shader_parameter("quad_half", quad_half)
	_mat.set_shader_parameter("corner", clampf(minf(size.x, size.y) * 0.15, 0.005, 0.025))
	_mat.set_shader_parameter("ring_r", ring_radius)
	_mat.set_shader_parameter("ring_w", ring_width)
	_mat.set_shader_parameter("tint", color)
	_mat.set_shader_parameter("style", int(style))
	_glyph.text = "%dP" % (player + 1)
	_glyph.modulate = color.lightened(0.35)
	_glyph.outline_modulate = Color(color.darkened(0.75), 0.9)


## Whether it shows anything: the glow (aimed at) or the badge (taken).
func is_lit() -> bool:
	return _aimed or _taken


## Aimed at (or a hand near), and taken (attached or held).
func set_state(aimed: bool, taken: bool) -> void:
	if taken and not _taken:
		_pop = 1.0
	_aimed = aimed
	_taken = taken
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_strength = move_toward(_strength, 1.0 if _aimed else 0.0, delta * FADE)
	_pop = maxf(0.0, _pop - delta * 4.0)
	_mat.set_shader_parameter("strength", _strength)
	_mat.set_shader_parameter("style", int(style))
	_quad.visible = _strength > 0.001
	_glyph.visible = _aimed or _taken
	if _glyph.visible:
		var rise := BADGE_RISE
		var scale_v := Vector3.ONE * BADGE_SCALE
		if _aimed:
			# A ball's bounce: fast off the floor, slow at the top, squashed for a moment where it lands.
			var h := absf(sin(_t * PI * BOUNCE_HZ))
			var squash := 1.0 - 0.2 * (1.0 - smoothstep(0.0, 0.3, h))
			rise = GLYPH_RISE + BOUNCE * h
			scale_v = Vector3(2.0 - squash, squash, 1.0)
		scale_v *= 1.0 + 0.6 * _pop
		# Over the middle of the glow (the stick and the buttons), not of the whole panel.
		_glyph.global_transform = Transform3D(Basis.from_scale(scale_v), _quad.global_position + Vector3.UP * rise)
	elif _strength <= 0.0:
		set_process(false)
