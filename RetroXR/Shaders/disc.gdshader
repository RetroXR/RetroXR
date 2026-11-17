// One optical disc: CD, DVD, PS1, PS2. Both faces, one surface, one draw call.
//
// Reads what Tools/gen_disc.gd bakes:
//   UV     planar over the disc's bounding square, so the scraped 600x600 label
//          art maps 1:1. That art is authored full-bleed to the rim WITH its own
//          transparent centre hole, correctly sized per system, so it is blended
//          straight on rather than fitted — and no synthetic print ring is
//          imposed, which would fight the alpha the art already carries.
//   UV2.x  face class: 1.0 label / 0.0 data / 0.5 rim and bore.
// The radius is derived here from length(VERTEX.xz) rather than baked: exact,
// one vertex instruction, and immune to attribute compression and node scale.
//
// The printed and metallised areas are OPAQUE — the art composites into ALBEDO, so
// unlike the floating transparent quad this replaces it cannot z-fight the face
// below it. But a disc is a clear polycarbonate substrate with aluminium sputtered
// onto the MIDDLE of it, so the wide hub annulus inside 22 mm, the outer rim past
// 58 mm, the bore wall and the edge are genuinely see-through, and faking them as
// opaque grey was the giveaway.
//
// ALPHA is therefore written, gated on the aluminium mask, with depth_prepass_alpha
// so the solid part still lays down depth and only the clear ring blends. Note this
// puts the whole material in the transparent queue; that is the price of the clear
// hub and is why poly_alpha is per-system — a PS1's dyed substrate is nearly opaque
// and must not go glassy.
//
// The rainbow is an ANALYTIC diffraction grating, not an environment reflection.
// It has to be: every room runs ambient_light_source = COLOR with no radiance map,
// one ReflectionProbe in one scene, no SDFGI and no SSR. There is nothing to
// reflect. Tools/plug_materials.gd already documents this as the reason the house
// metal standard is metallic 0.80 rather than 1.0 — which applies here too, since
// the ambient term is computed outside light() from ALBEDO/METALLIC/ROUGHNESS.
//
// A custom light() is what makes it correct rather than faked: Godot exposes no
// light data in fragment(), and the grating needs both the light and view vectors.
// Verified supported on the Mobile renderer the Quest build uses — forward_mobile
// includes the same scene_forward_lights_inc.glsl that honours LIGHT_CODE_USED.
// Two consequences worth knowing:
//   * defining light() compiles OUT the whole built-in BRDF, including the
//     clearcoat lobe. The lacquer coat below is hand-written for that reason, and
//     CLEARCOAT is deliberately never written.
//   * the docs claim light() is skipped on mobile because Force Vertex Shading is
//     on by default there. That is a Godot 3 carryover; in 4.7 the setting
//     defaults false and this project does not set it. Do not "fix" this.
//
// Because the grating is rotationally symmetric the pattern does NOT rotate when
// system.gd spins a seated disc — which is what a real spinning disc looks like.
shader_type spatial;
render_mode cull_back, depth_prepass_alpha;

// --- surface ---------------------------------------------------------------
// The data side's reflective layer, seen through the substrate. PS1 is near-black
// (black-dyed polycarbonate), PS2 CD-ROM blue, a DVD silver-violet, a CD silver.
uniform vec3 data_color : source_color = vec3(0.78, 0.80, 0.84);
// Bare polycarbonate: the bore, the outer rim, the edge, and the wide clear
// annulus inside the metal. This is what carries a PS1 disc's black edge.
uniform vec3 poly_color : source_color = vec3(0.09, 0.10, 0.12);
// The unprinted label side — lacquer over the aluminium.
uniform vec3 lacquer_color : source_color = vec3(0.80, 0.81, 0.84);
// Opacity of the bare substrate. A normal disc's hub is a window (~0.28); a PS1's
// black-dyed polycarbonate is not, so it stays near-solid. Per-system for exactly
// that reason.
uniform float poly_alpha : hint_range(0.0, 1.0) = 0.28;
// The 1.2 mm lateral edge is not the same as a flat clear face. You are looking
// THROUGH the substrate the long way, the aluminium layer is sandwiched in there
// edge-on, and polycarbonate pipes light out of a cut edge the way acrylic does.
// At poly_alpha it vanished completely — a near-black colour at 28% over the
// background is nothing, and the specular that should sell it gets scaled by the
// same alpha.
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.70;
// Glass goes mirror at grazing incidence. Without this the clear zones read as a
// flat wash and the disc has no crisp silhouette.
uniform float glass_fresnel : hint_range(0.0, 1.0) = 0.85;

// Zone radii in metres. Defaults are a pressed 120 mm CD; disc.gd overrides them
// per system — see MediaDimensions.disc_zones, which carries the ECMA-130 and
// ECMA-267 clause references these came from. A DVD is silvered far closer to the
// bore than a CD, so the two are NOT interchangeable.
uniform float r_metal_start = 0.0195;   // clear polycarbonate ends, aluminium starts
uniform float r_data_start = 0.0230;    // mirror band ends, pits start
uniform float r_data_end = 0.0580;      // pits end, clear outer rim starts

// --- label -----------------------------------------------------------------
// hint_default_transparent matters: an unassigned sampler2D otherwise returns
// opaque white and would paint the whole label side blank.
uniform sampler2D label_tex : source_color, hint_default_transparent,
	filter_linear_mipmap_anisotropic, repeat_disable;
// Where printing starts, metres from the centre. A scraped scan carries its own
// hole and leaves this 0; art with none (an album cover printed full-bleed, an
// audio CD's own face) sets it to the mirror band's edge so the hub stays clear.
uniform float label_r_in = 0.0;

// --- diffraction -----------------------------------------------------------
// Track pitch in MICROMETRES, and it does real work. At 1.6 (CD) four diffraction
// orders land in the visible band, giving the repeating spectral bands a CD
// shows; at 0.74 (DVD) one does, giving the single broad sweep a DVD shows. The
// difference between a PS1 disc and a Wii disc is this one number.
uniform float track_pitch = 1.6;
// How many diffraction orders to sum. Not a quality dial — it is the number that
// is actually REACHABLE, and it differs by format because the order spacing scales
// with pitch. u = |L.g + V.g| cannot exceed 2, so with the spectral support running
// 0.370..0.705 um:
//   CD  1.6 um  — m=1..4 reach u 0.231..1.762. Four is right.
//   DVD 0.74 um — m=4 needs u >= 2.000 and is unreachable ENTIRELY, so a DVD
//                 summing four orders spends a quarter of the loop on nothing.
// Verified by rendering, not just arithmetic: at a grazing view a DVD at THREE
// orders is byte-identical to four, while dropping to two moves 0.57% of its
// pixels by up to 65/255 — the orders SUM, so m=3 still tints where m=2 already
// covers. Three is the lossless setting; two is not. disc.gd sets it from pitch.
uniform int irid_orders : hint_range(1, 4) = 4;
uniform float irid_strength : hint_range(0.0, 4.0) = 0.5;
// Per-disc jitter, 0..1, seeded from save_id in disc.gd. Without it every Saturn
// CD in the room is pixel-identical and a stack of them reads as cloned. Tiny on
// purpose: a few percent of tint and a little iridescence, nothing that would
// make one disc look like a different disc.
uniform float disc_seed : hint_range(0.0, 1.0) = 0.5;
// The label side's unprinted lacquer shows a much fainter rainbow of its own.
uniform float irid_label : hint_range(0.0, 1.0) = 0.10;
// A view-only floor. A DVD's single order needs |L.g + V.g| >= 0.51 before any
// colour appears at all, so held flat under a ceiling light it would otherwise be
// a plain mirror. Small enough not to glow inside a shut console tray.
uniform float irid_ambient : hint_range(0.0, 1.0) = 0.10;
// Widens the spectral response, standing in for a light that is not a point.
// Narrow reads as a laser; too wide washes to white.
uniform float spectral_width : hint_range(0.5, 3.0) = 0.85;
// Extra band widening from the screen-space derivative. This is a STEREO fix as
// much as an aliasing one: with openxr/multiview each eye computes its own view
// vector, so tight bands land in different places per eye and produce genuine
// binocular rivalry. Tune it in the headset, not on a monitor.
uniform float band_aa : hint_range(0.0, 4.0) = 1.5;

// --- fake environment ------------------------------------------------------
// A disc is mostly REFLECTED ROOM, and these rooms have no radiance map at all —
// ambient_light_source = COLOR, one ReflectionProbe in one scene. A mirror with
// nothing to reflect is why the metal read airbrushed no matter how good the
// diffraction got. This is a three-stop vertical ramp sampled by the reflection
// vector: ceiling above, wall at the horizon, floor below. No probe, no texture
// fetch, no screen read — about a dozen ALU.
uniform vec3 env_ceiling : source_color = vec3(0.55, 0.58, 0.66);
uniform vec3 env_horizon : source_color = vec3(0.20, 0.21, 0.26);
uniform vec3 env_floor : source_color = vec3(0.05, 0.05, 0.06);
uniform float env_strength : hint_range(0.0, 3.0) = 1.0;

// --- lighting --------------------------------------------------------------
uniform float disc_specular : hint_range(0.0, 1.0) = 0.6;
uniform float light_gain : hint_range(0.0, 4.0) = 1.0;
uniform float spec_gain : hint_range(0.0, 4.0) = 0.45;
uniform float varnish : hint_range(0.0, 2.0) = 0.35;

varying vec3 v_radial;    // view-space radial = the grating vector
varying float v_radius;   // model-space distance from the spindle, in metres
varying vec3 v_irid;      // iridescence mask x substrate tint, read in light()
varying float v_blur;     // spectral widening from the derivative, ditto


void vertex() {
	v_radius = length(VERTEX.xz);
	// Never degenerate: there is a 15 mm hole where the singularity would be.
	v_radial = normalize((MODELVIEW_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 0.0)).xyz);
}


// A quartic bump standing in for a gaussian. Deliberately not exp(): four orders
// times three lobes is twelve transcendentals per light per pixel, and this is a
// Quest target. Reaches exactly zero at |x - mu| = hw, which also removes the
// need for a separate visible-band window.
float bump(float x, float mu, float hw) {
	float t = (x - mu) / hw;
	float k = max(0.0, 1.0 - t * t);
	return k * k;
}


// Wavelength in MICROMETRES to linear RGB. Three lobes, plus a second red term for
// the violet end of the spectrum — without it short wavelengths come out blue
// instead of purple, which is the giveaway of a cheap rainbow.
//
// That fourth lobe is 25% of this function and was a candidate for removal, but
// measured against a grazing render it moved 8% of the disc's pixels by up to
// 122/255: the magenta bands collapse to plain blue. Kept, because on-device
// measurement put a held disc at ~0.5 ms of a 13.9 ms budget — the headroom is
// there and this is the one saving that costs looks.
vec3 spectral(float w, float blur) {
	float k = spectral_width;
	return vec3(
		bump(w, 0.600, 0.105 * k + blur) + 0.30 * bump(w, 0.425, 0.055 * k + blur),
		bump(w, 0.540, 0.110 * k + blur),
		bump(w, 0.455, 0.095 * k + blur)
	);
}


// Reflective diffraction off concentric tracks.
//
//   lambda_m = pitch * |L.g + V.g| / m
//
// g is the radial direction because the tracks are circles, so the grating lines
// run azimuthally. The absolute value is not cosmetic: g points outward, so
// without it the sign flips across the disc and only half of it would light up.
//
// The zeroth order falls out for free — at the mirror direction L and V have
// opposite tangential components, the sum goes to zero, and there is no colour.
// That is why the specular streak stays white and the spectrum appears either
// side of it, as on a real disc.
//
// The order count comes in per call: the lit term wants every reachable order
// (see irid_orders), while the ambient floor below only needs the first.
vec3 grating(vec3 L, vec3 V, vec3 g, float blur, int orders) {
	float u = abs(dot(L, g) + dot(V, g));
	vec3 acc = vec3(0.0);
	for (int m = 1; m <= orders; m++) {
		float fm = float(m);
		// Higher orders are dimmer and, being compressed in wavelength, blur more.
		acc += spectral(track_pitch * u / fm, blur / fm) / fm;
	}
	// Normalised by the FOUR-order sum(1/m) whatever the count actually summed.
	// Deliberate: normalising by the orders present would rescale the survivors
	// (2.08/1.5 = +39% for a two-order DVD) and change how the disc looks, when
	// the whole point is to stop computing terms that contribute nothing. Dropping
	// an order must SUBTRACT its energy, not redistribute it.
	return acc * (1.0 / 2.0833);
}


// Reflected room. Rw is the reflection in WORLD space — the ramp is vertical, so
// it has to be, and NORMAL/VIEW are view-space. Rough surfaces converge on the
// average of the three stops, which is what blurring an environment does.
// inv_view is passed in rather than read directly: Godot exposes built-ins only
// inside vertex()/fragment()/light(), never in a helper.
vec3 env_reflect(vec3 N, vec3 V, float ndv, float rough, vec3 f0, mat4 inv_view) {
	vec3 Rw = (inv_view * vec4(reflect(-V, N), 0.0)).xyz;
	float up = clamp(Rw.y, -1.0, 1.0);
	vec3 c = up > 0.0 ? mix(env_horizon, env_ceiling, up)
					  : mix(env_horizon, env_floor, -up);
	c = mix(c, (env_ceiling + env_horizon + env_floor) * (1.0 / 3.0), rough);
	float fres = pow(1.0 - ndv, 5.0);
	return c * (f0 + (1.0 - f0) * fres) * env_strength;
}


void fragment() {
	float face = UV2.x;
	float r = v_radius;

	// The aluminium layer, and the pitted area inside it that actually diffracts.
	float metal = smoothstep(r_metal_start - 0.0004, r_metal_start + 0.0004, r)
		* (1.0 - smoothstep(r_data_end, r_data_end + 0.0010, r));
	float pits = smoothstep(r_data_start - 0.0004, r_data_start + 0.0004, r)
		* (1.0 - smoothstep(r_data_end - 0.0008, r_data_end, r));

	vec3 V = normalize(VIEW);
	vec3 g = normalize(v_radial);
	// Shared by the alpha ramp and the reflected room below. Both wanted the same
	// normalize and the same dot, and computing them twice was pure waste.
	vec3 nrm = normalize(NORMAL);
	float ndv = clamp(dot(nrm, V), 0.0, 1.0);
	// Derivatives must be taken here, not in light(): under the per-light loop
	// they sit in non-uniform control flow, which is undefined on real hardware.
	// Clamped: g swings fastest near the bore, and an unbounded blur there washes
	// the inner bands to grey.
	v_blur = min(track_pitch * fwidth(dot(V, g)) * band_aa, 0.12);

	float base_a = 1.0;
	if (face > 0.75) {
		// --- label side ---
		vec4 art = texture(label_tex, UV);
		// A real disc leaves an unprinted rim. The scraped scans crop anywhere
		// from 0.97 to 1.00 of half-width, so trimming here makes every title
		// finish at the same radius and lets the rim read as polycarbonate.
		art.a *= 1.0 - smoothstep(r_data_end, r_data_end + 0.0015, r);
		art.a *= smoothstep(label_r_in - 0.0004, label_r_in, r);
		vec3 base = mix(poly_color, lacquer_color, metal);
		ALBEDO = mix(base, art.rgb, art.a);
		// Matte ink against glossy unprinted lacquer. This one contrast is the
		// single biggest cue that a printed disc is a printed disc.
		METALLIC = mix(0.75 * metal, 0.0, art.a);
		ROUGHNESS = mix(mix(0.09, 0.14, metal), 0.52, art.a);
		// Printed ink hides the substrate; so does the aluminium under it.
		base_a = mix(poly_alpha, 1.0, max(art.a, metal));
		v_irid = vec3(pits * irid_label * irid_strength * (1.0 - art.a))
			* sqrt(lacquer_color);
	} else if (face > 0.25) {
		// --- lateral edge and bore wall ---
		// Carries the reflective layer edge-on, so it is neither bare plastic nor
		// bare metal. Glossy and part-metallic so it actually catches a highlight;
		// the mix keeps a PS1's dyed edge black, since both its colours are dark.
		ALBEDO = mix(poly_color, data_color, 0.35);
		METALLIC = 0.30;
		ROUGHNESS = 0.05;
		base_a = max(poly_alpha, edge_alpha);
		v_irid = vec3(0.0);
	} else {
		// --- data side ---
		// Inside the metal there is nothing but substrate, so it is a real window.
		vec3 dc = data_color * vec3(1.0 + (disc_seed - 0.5) * 0.11, 1.0,
			1.0 - (disc_seed - 0.5) * 0.11);
		ALBEDO = mix(poly_color, dc, metal);
		// The mirror band and the data area are the same aluminium, so they share an
		// albedo — what separates them is SMOOTHNESS. The band is unpitted, i.e. an
		// actual mirror, so it returns the room and little else; the pit structure
		// next to it scatters light back from every direction at once. In a dim room
		// that makes the mirror band the DARKER of the two, and giving both the same
		// roughness was what left it reading as flat bright silver.
		METALLIC = mix(0.05, mix(0.86, 0.80, pits), metal);
		ROUGHNESS = mix(0.07, mix(0.035, 0.13, pits), metal);
		base_a = mix(poly_alpha, 1.0, metal);
		// Tinted by the substrate. The diffracted ray makes the same two-pass trip
		// through the dye as the specular one, so a PS1's black disc must dim its
		// own rainbow — untinted it blows out to white and stops reading as black.
		// sqrt, not the colour itself: data_color is the double-pass reflectance,
		// and taking it straight leaves the PS1 too dark to read as a disc at all.
		float jit = disc_seed - 0.5;
		v_irid = vec3(pits * irid_strength * (1.0 + jit * 0.40)) * sqrt(data_color);
	}

	SPECULAR = disc_specular;

	// Fresnel: at grazing incidence glass stops transmitting and starts mirroring.
	// This is what gives the clear rim a bright outline instead of letting it
	// disappear, and it fires strongest exactly where the edge is visible.
	ALPHA = mix(base_a, 1.0, pow(1.0 - ndv, 4.0) * glass_fresnel);

	// The reflected room. Added here rather than in light() because it is not a
	// per-light term — with no radiance map Godot's own ambient contributes almost
	// nothing to a metal, which is the gap this fills.
	EMISSION += env_reflect(nrm, V, ndv, ROUGHNESS,
		mix(vec3(0.08 * disc_specular), ALBEDO, METALLIC), INV_VIEW_MATRIX);

	// View-only floor, so a disc never goes completely dead in a room whose lights
	// happen to miss the grating condition. L = V is the retroreflective case.
	if (dot(v_irid, vec3(1.0)) > 0.003) {
		EMISSION += grating(V, V, g, v_blur, 1) * v_irid * irid_ambient;
	}
}


void light() {
	vec3 N = normalize(NORMAL);
	vec3 L = normalize(LIGHT);
	vec3 V = normalize(VIEW);
	float ndl = max(dot(N, L), 0.0);
	vec3 radiance = LIGHT_COLOR * ATTENUATION;

	// Lambert. Metal has no diffuse lobe.
	DIFFUSE_LIGHT += ALBEDO * radiance * ndl * (1.0 - METALLIC) * light_gain;

	// Normalised Blinn-Phong standing in for GGX. The exponent is clamped because
	// a mirror-smooth roughness sends it to six figures.
	vec3 H = normalize(L + V);
	float ndh = max(dot(N, H), 0.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.0025);
	float shine = clamp(2.0 / (a * a) - 2.0, 1.0, 2048.0);
	vec3 f0 = mix(vec3(0.08 * disc_specular), ALBEDO, METALLIC);
	vec3 fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(V, H), 0.0), 5.0);
	// Normalisation clamped: at mirror roughness the Blinn-Phong term reaches 82x,
	// which clipped a broad region of the disc to flat white instead of leaving a
	// tight highlight. The reflected room now supplies the brightness that was
	// coming from this being cranked.
	SPECULAR_LIGHT += radiance * ndl * fres * pow(ndh, shine)
		* min((shine + 8.0) / 25.13, 26.0) * spec_gain;

	// The lacquer coat, hand-written because defining light() compiles the
	// built-in clearcoat lobe out.
	SPECULAR_LIGHT += radiance * ndl * varnish * pow(ndh, 220.0);

	// Diffraction. Gated on the light reaching this side, so a disc in a shut
	// tray stays dark rather than glowing.
	if (dot(v_irid, vec3(1.0)) > 0.003 && dot(N, V) > 0.0) {
		SPECULAR_LIGHT += radiance * ndl * v_irid
			* grating(L, V, normalize(v_radial), v_blur, irid_orders);
	}
}
