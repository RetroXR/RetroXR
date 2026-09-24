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

// What one wall passes, seen straight on, at density 1. Clear cartridge plastic
// is dense: this is darker and greyer than the dye looks lit from the front.
uniform vec4 tint : source_color = vec4(0.76, 0.05, 0.1, 1.0);
// How strongly one wall filters: 0 is colourless, 1 is `tint` itself.
uniform float density : hint_range(0.0, 4.0) = 0.6;
// Longest path, as a multiple of the straight-on one, reached at the silhouette.
uniform float edge_depth : hint_range(1.0, 8.0) = 3.0;
// Patchy density, the same patches as the surface pass's scatter: 0 even, 1
// patches from half to one and a half times `density`.
uniform float cloud : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_size_mm : hint_range(0.5, 20.0) = 1.8;

varying vec3 obj_pos;

#include "res://Shaders/cartridge_clear_cloud.gdshaderinc"

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 1.0 / edge_depth, 1.0);
	float patchy = 1.0 + cloud * (cloud_noise(obj_pos, cloud_size_mm) - 0.5);
	ALBEDO = pow(max(tint.rgb, vec3(0.001)), vec3(density * patchy / facing));
}
