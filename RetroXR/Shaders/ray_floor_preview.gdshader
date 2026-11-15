shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 footprint_size = vec2(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.12, 0.82, 1.0, 1.0);

// The quad's +Y maps to the object's +Z: the authored front of room objects.
// Use mesh coordinates so the arrow cannot be inverted by the quad's UV origin.
varying vec2 floor_position;

void vertex() {
	floor_position = VERTEX.xy;
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

void fragment() {
	vec2 edge = (vec2(0.5) - abs(UV - vec2(0.5))) * footprint_size;
	float d = min(edge.x, edge.y);
	float width = min(0.006, min(footprint_size.x, footprint_size.y) * 0.10);
	float aa = max(fwidth(d), 0.00015);
	float border = 1.0 - smoothstep(width - aa, width + aa, d);
	float corner_length = min(0.06, min(footprint_size.x, footprint_size.y) * 0.22);
	float corners = 1.0 - smoothstep(corner_length, corner_length + aa, max(edge.x, edge.y));
	float bracket = corners * (1.0 - smoothstep(width * 2.0 - aa, width * 2.0 + aa, d));
	float halo = exp(-max(d, 0.0) / max(width * 3.0, 0.0001));
	float shimmer = 0.90 + 0.10 * sin((UV.x + UV.y) * 9.0 - TIME * 1.8);
	// A centered arrow, comfortably inside even a narrow footprint. Rounded,
	// antialiased strokes match the border without needing another mesh.
	float arrow_length = min(0.35, min(footprint_size.x, footprint_size.y) * 0.55);
	vec2 tip = vec2(0.0, arrow_length * 0.45);
	float arrow_d = segment_distance(floor_position, vec2(0.0, -arrow_length * 0.45), tip);
	arrow_d = min(arrow_d, segment_distance(floor_position, tip, arrow_length * vec2(-0.27, 0.08)));
	arrow_d = min(arrow_d, segment_distance(floor_position, tip, arrow_length * vec2(0.27, 0.08)));
	float arrow_width = arrow_length * 0.045;
	float arrow_aa = max(fwidth(arrow_d), 0.00015);
	float arrow = 1.0 - smoothstep(arrow_width - arrow_aa, arrow_width + arrow_aa, arrow_d);
	ALBEDO = mix(tint.rgb, vec3(0.8, 0.98, 1.0), max(bracket * 0.75, arrow * 0.65));
	ALPHA = opacity * tint.a * clamp(0.055 + halo * 0.15 + border * 0.65 * shimmer + bracket * 0.6 + arrow * 0.9, 0.0, 1.0);
}
