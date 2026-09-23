// Dyed clear plastic, first pass: the filter. Whatever is already drawn behind
// the shell (the board inside, the other half, the room) is multiplied by the
// dye, so it keeps its own light and detail and only loses the colours the dye
// absorbs, which is what clear plastic does and alpha blending does not (a blend
// washes the background toward the shell colour and fades its reflections too).
//
// The path through the wall lengthens toward the silhouette, so the edges read
// thicker and deeper in colour. Multiplying commutes, so the two halves and any
// number of shells give the same result in any draw order: no sorting artefacts.
//
// The reflections and the light scattered in the plastic are the next pass,
// cartridge_clear_plastic_surface.gdshader. CartridgeColor sets both.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, fog_disabled;

// The dye's colour. Only its hue and saturation filter: see fragment().
uniform vec4 tint : source_color = vec4(0.76, 0.05, 0.1, 1.0);
// How strongly one wall filters: 0 is colourless, 1 is `tint` itself.
uniform float density : hint_range(0.0, 4.0) = 0.6;
// Longest path, as a multiple of the straight-on one, reached at the silhouette.
uniform float edge_depth : hint_range(1.0, 8.0) = 3.0;

void fragment() {
	// A dye passes its own colour almost whole and absorbs the rest, so the
	// filter is the tint scaled until its strongest channel is 1.
	vec3 pass_colour = max(tint.rgb / max(max(tint.r, tint.g), max(tint.b, 0.001)), vec3(0.001));
	float facing = clamp(abs(dot(NORMAL, VIEW)), 1.0 / edge_depth, 1.0);
	ALBEDO = pow(pass_colour, vec3(density / facing));
}
