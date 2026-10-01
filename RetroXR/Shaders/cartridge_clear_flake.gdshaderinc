// Metal glitter moulded into clear plastic, as in Pokemon Crystal's shell: sparse
// flakes, each a small metallic mirror at its own tilt, in object-space cells so
// the pattern is fixed to the shell, placed exactly as
// cartridge_flake_plastic.gdshader places them in a solid one. Shared by both
// clear-plastic passes: the surface pass lights a flake and the filter, drawn
// after it, lets that flake's light through untinted. flake_amount 0 is plain
// clear plastic, and costs one branch.

// Share of cells holding a flake.
uniform float flake_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flake_color : source_color = vec4(0.92, 0.92, 0.94, 1.0);
// Cell edge in millimetres of the mesh's own space; a flake is about half a cell across.
uniform float flake_size_mm : hint_range(0.02, 2.0) = 0.25;
uniform float flake_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float flake_roughness : hint_range(0.0, 1.0) = 0.22;
// Largest tilt, as the tangent-space offset of the flake normal.
uniform float flake_tilt : hint_range(0.0, 0.9) = 0.4;
// Cells per pixel at which flakes start and finish handing over to their average,
// which keeps a distant cartridge from shimmering.
uniform float flake_fade_start : hint_range(0.0, 2.0) = 0.45;
uniform float flake_fade_end : hint_range(0.0, 4.0) = 1.2;

vec3 clear_flake_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// x: the flake under this pixel while flakes are larger than a pixel (glint);
// y: their average once they are not (sheen); zw: that flake's tilt.
vec4 clear_flake(vec3 p_mesh) {
	if (flake_amount <= 0.0) {
		return vec4(0.0);
	}
	vec3 p = p_mesh / (flake_size_mm * 0.001);
	vec3 cell = floor(p);
	vec3 h = clear_flake_hash(cell);
	vec3 centre = 0.3 + 0.4 * clear_flake_hash(cell + 17.0);
	float radius = 0.2 + 0.08 * h.y;
	float footprint = length(fwidth(p));
	float present = step(h.x, flake_amount);
	float d = length(fract(p) - centre);
	float mask = present * (1.0 - smoothstep(radius * 0.35 - footprint, radius + footprint, d));
	vec3 t = clear_flake_hash(cell + 41.0) * 2.0 - 1.0;
	vec2 tilt = normalize(t.xy + vec2(1e-4)) * flake_tilt * sqrt(abs(t.z));
	float fade = 1.0 - smoothstep(flake_fade_start, flake_fade_end, footprint);
	// A plane through the cells cuts flakes in proportion to their volume.
	float coverage = flake_amount * 0.058;
	return vec4(mask * fade, coverage * (1.0 - fade), tilt);
}
