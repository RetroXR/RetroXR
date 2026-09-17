// Moulded plastic with metallic flake in it: a coloured resin base and fine,
// sparse flakes, each a small metallic mirror at its own tilt. A flake glints only
// when its tilt lines a light up with the eye, so the sparkle moves with the light
// and the viewer, never with time.
//
// Flakes live in object-space cells, so the pattern is fixed to the shell. Once a
// flake is smaller than a pixel it is replaced by the average it would have
// contributed, which is what keeps a distant cartridge from shimmering.
//
// The albedo, roughness, specular, normal-map and UV uniforms carry the values of
// the StandardMaterial3D this replaces (CartridgeColor copies them across).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.64, 0.55, 0.35, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform bool normal_enabled = false;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

group_uniforms flakes;
uniform vec4 flake_color : source_color = vec4(0.95, 0.86, 0.63, 1.0);
// Share of cells holding a flake.
uniform float flake_density : hint_range(0.0, 1.0) = 0.25;
// Cell edge in millimetres of the mesh's own space; a flake is about half a cell across.
uniform float flake_size_mm : hint_range(0.02, 2.0) = 0.35;
uniform float flake_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float flake_roughness : hint_range(0.0, 1.0) = 0.22;
// Largest tilt, as the tangent-space offset of the flake normal.
uniform float flake_tilt : hint_range(0.0, 0.9) = 0.4;
// Cells per pixel at which flakes start and finish handing over to their average.
uniform float flake_fade_start : hint_range(0.0, 2.0) = 0.45;
uniform float flake_fade_end : hint_range(0.0, 4.0) = 1.2;

varying vec3 obj_pos;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec2 base_uv = UV * uv1_scale.xy + uv1_offset.xy;
	vec2 bump = vec2(0.0);
	if (normal_enabled) {
		bump = (texture(texture_normal, base_uv).xy * 2.0 - 1.0) * normal_scale;
	}

	vec3 p = obj_pos / (flake_size_mm * 0.001);
	vec3 cell = floor(p);
	vec3 h = hash33(cell);
	vec3 centre = 0.3 + 0.4 * hash33(cell + 17.0);
	float radius = 0.2 + 0.08 * h.y;
	float footprint = length(fwidth(p));
	float present = step(h.x, flake_density);
	float d = length(fract(p) - centre);
	// Brightest at the middle and fading to its rim, so a flake reads as one fleck
	// rather than a disc with an outline.
	float mask = present * (1.0 - smoothstep(radius * 0.35 - footprint, radius + footprint, d));

	vec3 t = hash33(cell + 41.0) * 2.0 - 1.0;
	vec2 tilt = normalize(t.xy + vec2(1e-4)) * flake_tilt * sqrt(abs(t.z));

	float fade = 1.0 - smoothstep(flake_fade_start, flake_fade_end, footprint);
	// A plane through the cells cuts flakes in proportion to their volume:
	// density x (4/3) pi r^3, r averaging 0.24 of a cell.
	float coverage = flake_density * 0.058;
	float glint = mask * fade;
	float sheen = coverage * (1.0 - fade);
	float k = (glint + sheen) * flake_intensity;

	// Flakes sit in the resin rather than on it, so even a fully covered texel keeps
	// some diffuse: a flake turned away from every light dims instead of going black.
	ALBEDO = mix(albedo.rgb, flake_color.rgb, k);
	METALLIC = k * 0.7;
	ROUGHNESS = mix(roughness, flake_roughness, glint + sheen * 0.5);
	SPECULAR = specular;

	vec2 n = bump + tilt * glint;
	float len = length(n);
	if (len > 0.95) {
		n *= 0.95 / len;
	}
	NORMAL_MAP = vec3(n * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
