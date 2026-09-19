shader_type spatial;

// Fore-edge of a page stack: the striped block of paper edges you see from the
// side of a closed (or half-open) book. Drawn on the existing BoxMesh so the
// stack keeps its cheap geometry — the stripes and the silhouette bulge are
// both shader-side.
//
// The box is authored at stack_depth on Z and scaled on Z by the book to match
// the current leaf count, so VERTEX.z is always in +/- stack_depth/2 and the
// stripe pitch follows leaf_count directly.

uniform vec4 edge_color : source_color = vec4(0.93, 0.90, 0.82, 1.0);
uniform vec4 groove_color : source_color = vec4(0.62, 0.58, 0.49, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float stack_depth = 0.005;
uniform float leaf_count = 64.0;

// The block has to curve into the binding along with the sheet on top of it.
// Left flat, the box's top face stood proud of the diving top page near the
// spine and showed as a flat pale strip with the page passing through it.
// Matches the rest shape in paper.gdshader.
uniform vec2 page_size = vec2(0.18, 0.25);
uniform float spine_sign = 1.0;
uniform float gutter_dive = 0.0;
uniform float gutter_falloff : hint_range(1.0, 40.0) = 12.0;
// The book scales this box on Z per leaf count, so a world-space dive has to be
// divided back out to stay put once that scale is applied.
uniform float z_scale = 1.0;
// The block's gutter-facing side sits at the bottom of the valley. Unshaded it
// read as a pale band down the middle of the spread, brighter than the pages
// either side of it.
uniform float gutter_ao : hint_range(0.0, 1.0) = 0.8;
// The sheet's own sag terms, so the block moves with it at the fore edge too.
uniform float bow_amount = 0.0;
uniform float fore_droop = 0.0;
uniform float edge_curl = 0.0;

const float PAPER_PI = 3.14159265;

#include "res://Shaders/paper_rest.gdshaderinc"
#include "res://Shaders/paper_flop.gdshaderinc"
// Peak outward swell at mid-stack, in metres.
uniform float bulge : hint_range(0.0, 0.01) = 0.0006;

// The half this block belongs to, hanging from the binding. Has to be the very
// same numbers the sheets on this side are given, or the block comes through
// them. A block never crosses the gutter, so it has no far half.
uniform vec4 flop_own = vec4(0.0);
uniform float flop_gutter_gap = 0.00175;
uniform float flop_origin_z = 0.0;

varying float v_t;      // 0..1 through the stack
varying float v_side;   // 1 on the page-edge faces, 0 on the flat top/bottom
varying float v_u;      // 0 at the gutter, 1 at the fore edge

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float depth = max(stack_depth, 1e-5);
	float t = clamp(VERTEX.z / depth + 0.5, 0.0, 1.0);
	v_t = t;
	v_side = step(abs(NORMAL.z), 0.5);

	v_u = clamp(0.5 + spine_sign * VERTEX.x / max(page_size.x, 1e-5), 0.0, 1.0);

	// Follow the sheet above. The block SAGS as one lump at the fore edge, so
	// every vertex takes that; it THINS into the binding, so only the top ring
	// takes the gutter dive. `lift` is deliberately not followed — that is the
	// sheet leaving the block behind, not the block moving.
	//
	// The gutter term is unclamped on purpose: on a thin block the top has to
	// travel further than the block is deep, and clamping it to the block's own
	// underside left the sheet diving past a top face that had stopped
	// following. Overshoot collapses the box locally, under the page.
	float v_v = clamp(0.5 + VERTEX.y / max(page_size.y, 1e-5), 0.0, 1.0);
	float gutter;
	float sag;
	float lift;
	paper_rest_parts(v_u, v_v, gutter_dive, gutter_falloff, bow_amount, fore_droop, edge_curl,
		gutter, sag, lift);
	float follow = sag + (VERTEX.z > 0.0 ? gutter : 0.0);
	VERTEX.z += follow / max(z_scale, 1e-4);

	if (v_side > 0.5 && bulge > 0.0) {
		float e = 2.0 * t - 1.0;
		float profile = 1.0 - e * e;              // 0 at the covers, 1 mid-stack
		float dprofile = -4.0 * e / depth;        // d(profile)/dz
		vec2 face = normalize(NORMAL.xy);
		VERTEX.xy += face * (bulge * profile);
		// Surface is base + face * b(z), so the normal tilts by -b'(z) on Z.
		NORMAL = normalize(vec3(face, -bulge * dprofile));
	}

	// The whole half hanging from the binding, last so it carries the rest. The
	// bend is in book metres and this box is scaled on Z, so go out through
	// z_scale and come back; the normal goes through its inverse, as the
	// engine's own normal matrix will on the way to the world.
	if (flop_own != vec4(0.0)) {
		float zs = max(z_scale, 1e-4);
		float s = max(spine_sign * VERTEX.x + 0.5 * page_size.x + flop_gutter_gap, 0.0);
		float zb = flop_origin_z + VERTEX.z * zs;
		float ang = paper_flop(s, zb, flop_own, FLOP_HINGE_LEN);
		VERTEX.x = spine_sign * (s - 0.5 * page_size.x - flop_gutter_gap);
		VERTEX.z = (zb - flop_origin_z) / zs;
		float ns = spine_sign * NORMAL.x;
		float nz = NORMAL.z / zs;
		float ca = cos(ang);
		float sa = sin(ang);
		NORMAL = normalize(vec3(spine_sign * (ns * ca - nz * sa), NORMAL.y, (ns * sa + nz * ca) * zs));
	}
}

void fragment() {
	// Same falloff the pages use, so the block darkens into the binding at the
	// same rate as the sheet lying on it.
	float valley = 1.0 - gutter_ao * exp(-v_u * gutter_falloff);

	if (v_side < 0.5) {
		ALBEDO = edge_color.rgb * valley;
		ROUGHNESS = roughness;
		METALLIC = 0.0;
	} else {
		float f = v_t * max(leaf_count, 1.0);
		// One stripe per leaf, analytically softened. Past ~2 leaves per screen
		// pixel the pattern is pure aliasing, so fade it into its own average
		// rather than letting it shimmer. On anything but a very thick book
		// held very close this fades out entirely — which is why it is not the
		// only thing giving the fore-edge its texture.
		float w = fwidth(f);
		float stripe = abs(fract(f) - 0.5) * 2.0;
		stripe = smoothstep(0.0, clamp(w * 2.0, 0.08, 1.0), stripe);
		float fade = clamp(1.0 - w * 1.5, 0.0, 1.0);
		float g = mix(0.5, stripe, fade);

		// Low-frequency structure that survives at any distance: leaves never
		// stack perfectly, so a real fore-edge reads as soft irregular banding
		// rather than a clean white block.
		float along = UV.x;
		float wave = vnoise(vec2(v_t * 9.0, along * 2.5)) * 0.5
			+ vnoise(vec2(v_t * 31.0, along * 6.0)) * 0.25;
		g *= 1.0 - 0.30 * wave;

		// The outermost leaves sit against the covers and pick up grime and
		// shadow; the block is lightest through its middle.
		g *= 1.0 - 0.34 * exp(-v_t * 9.0) - 0.34 * exp(-(1.0 - v_t) * 9.0);

		ALBEDO = mix(groove_color.rgb, edge_color.rgb, clamp(g, 0.0, 1.0)) * valley;
		ROUGHNESS = roughness;
		METALLIC = 0.0;
	}
}
