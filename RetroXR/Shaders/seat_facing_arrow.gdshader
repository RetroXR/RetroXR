// The seat facing arrow (SeatFacingArrow): one flat quad lying over the cushion, the arrow drawn in it as a distance
// field -- a bright outline with a soft glow round it, a dim fill crossed by scanlines that run toward the tip, and a
// slow pulse. Unshaded, seen through the seat's own cushion and back (no depth test), faded in and out by `fade`.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.62, 0.12, 1.0);
// The quad's size in metres (across, along), so the field is in metres whatever the quad.
uniform vec2 quad_size = vec2(0.24, 0.62);
uniform float shaft_half = 0.026;
uniform float head_half = 0.085;
uniform float head_length = 0.17;
// Kept clear of the quad's edges so the glow is not cut off.
uniform float margin = 0.035;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Inigo Quilez's isosceles triangle: tip at the origin, opening down -y, q = (half base, height).
float sd_tri_isosceles(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

void fragment() {
	// x across the arrow, y along it from the tail (0) to the tip; PlaneMesh's v runs toward +Z and the tip leads -Z.
	vec2 p = vec2((UV.x - 0.5) * quad_size.x, (1.0 - UV.y) * quad_size.y);
	float tip = quad_size.y - margin;
	float tail = margin;
	float neck = tip - head_length;
	float shaft = sd_box(p - vec2(0.0, (tail + neck) * 0.5), vec2(shaft_half, (neck - tail) * 0.5 + 0.004));
	float head = sd_tri_isosceles(vec2(p.x, tip - p.y), vec2(head_half, head_length));
	float d = min(shaft, head);
	float aa = fwidth(d) * 1.2;
	float pulse = 0.82 + 0.18 * sin(TIME * 3.0);
	// The outline: a 4 mm line on the edge.
	float edge = 1.0 - smoothstep(0.002, 0.002 + aa, abs(d));
	// A soft glow outside it.
	float glow = exp(-max(d, 0.0) * 55.0) * 0.45 * step(0.0, d);
	// Inside: a dim fill crossed by scanlines that run toward the tip.
	float inside = 1.0 - smoothstep(-aa, 0.0, d);
	float lines = 0.5 + 0.5 * sin((p.y * 90.0 - TIME * 5.0));
	lines = smoothstep(0.35, 0.65, lines);
	float fill = inside * (0.22 + 0.22 * lines);
	float a = max(max(edge, glow * pulse), fill * pulse);
	// The outline burns whiter than the fill, as a lit tube's edge does.
	vec3 c = mix(color.rgb, vec3(1.0, 0.93, 0.78), edge * 0.55);
	ALBEDO = c;
	ALPHA = clamp(a * fade * color.a, 0.0, 1.0);
}
