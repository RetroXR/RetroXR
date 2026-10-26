shader_type spatial;
render_mode cull_disabled;

// Paper page: a double-sided sheet that bows off its stack, dives into the
// gutter, and can be folded around a hand-driven fold line.
//
// All geometry is derived from two normalised page coordinates:
//   u = 0 at the gutter (spine) edge, 1 at the fore edge
//   v = 0 at the bottom edge, 1 at the top edge
// u is built from VERTEX.x rather than UV so the maths is independent of how
// the quad happens to be UV-mapped, and spine_sign flips it for the left page
// (and for the covers, which the book rotates 180 degrees about Y).

uniform sampler2D front_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D back_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 paper_tint : source_color = vec4(0.98, 0.96, 0.92, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.82;
// How much the fibre texture breaks up the roughness. Coated stock is smooth
// and even, so gloss finishes want almost none of this.
uniform float roughness_variation : hint_range(0.0, 0.4) = 0.06;

// Page frame.
uniform vec2 page_size = vec2(0.18, 0.25);   // metres
uniform float spine_sign = 1.0;              // +1: gutter at local -X, -1: gutter at +X

// Rest shape.
uniform float gutter_dive : hint_range(0.0, 0.02) = 0.004;
uniform float gutter_falloff : hint_range(1.0, 40.0) = 12.0;
uniform float bow_amount : hint_range(0.0, 0.02) = 0.0025;
uniform float fore_droop : hint_range(0.0, 0.02) = 0.0015;
uniform float edge_curl : hint_range(0.0, 0.02) = 0.002;

// Fold-line cylinder wrap. fold_normal points from the fold line toward the
// part of the sheet that curls over; fold_strength 0 disables the whole branch.
uniform float fold_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 fold_origin = vec2(0.0);        // page-local metres
uniform vec2 fold_normal = vec2(1.0, 0.0);   // unit
uniform float curl_radius = 0.01;
uniform float curl_taper : hint_range(0.0, 4.0) = 1.2;

// How this half of the book hangs from the binding (paper_flop.gdshaderinc):
// (angle at the gutter, page curvature, support distance, gutter displacement),
// solved by BookFlop. The far
// half's is here too because a page being turned lays its flap across the
// gutter, and that part has to ride the OTHER half.
uniform vec4 flop_own = vec4(0.0);
uniform vec4 flop_far = vec4(0.0);
// The bend is about the book's gutter, not this mesh's origin: how far the page
// starts from it, where this mesh sits in book-local Z, and whether its own +Z
// is the book's (the covers are turned 180 degrees about Y).
uniform float flop_gutter_gap = 0.00175;
uniform float flop_origin_z = 0.0;
uniform float flop_z_sign = 1.0;
// 1 on the leaf being turned, 0 on everything else. A flap lifted over a
// drooping spine is on the OUTSIDE of the binding's tight bend and was stretched
// into a flat tongue longer than the page; the turning leaf spreads that turn
// over an arc that widens with its height (flop_hinge_len). Nothing else may: a
// sheet lying on its block would then disagree with the block under it.
uniform float flop_cross = 0.0;
// The turning leaf's own hinge: a page pulled UP swings about the gutter toward
// the hand instead of rolling over flat. A RIGID rotation about the gutter line
// at the leaf's own plane, applied BEFORE the book's droop — a page's hinge at
// the binding is a true hinge. It was first folded into the droop as one more
// angle over that widened arc, which gave the high parts of the sheet only a
// fraction of the lift; the "leaf's frame" was then not a frame, and the solver
// wanted curls starting 6 cm behind the binding. Solved from the hand by
// PDFBook._solve_leaf_lift.
uniform float flop_lift = 0.0;

// Where this sheet lies in the pile on its half: the block's top page 1, the loose
// leaves above it, the page being turned above all of them (PDFBook sets it; 0 =
// no nudge, the covers). By the spine every sheet comes down to the same line, a
// fraction of a millimetre apart, and any small difference between two sheets'
// bends — the turning page's widened hinge, the gutter dive, a tilt moving the
// fan — let the lower one through the upper one there. Each sheet is drawn
// moved towards the eye by its place times STACK_STEP, seen from the side its
// half faces (away from the eye seen from underneath, nothing edge-on), so where
// two sheets are that close the one above is drawn above. Only POSITION moves:
// lighting, the bend and the CPU's mirrors of it are untouched.
uniform float stack_layer = 0.0;
// How much of the mesh's columns to gather toward the spine edge (0 = as built,
// evenly). Everything that bends a sheet hard is in its first two centimetres —
// the binding's 12 mm hinge, the dive into the gutter, the blend off the block's
// bend — and a loose leaf's 12 even columns drew that as one or two straight
// chords, millimetres off the curve and off the turning page's (32 columns) over
// it, so the leaf came up through the page at the spine. The texture follows the
// vertex (UV moves with it); the shape is the same function of u, only sampled
// where it curves.
uniform float spine_density = 0.0;
// The bend of the BLOCK of each half (this sheet's own and the far one), for which
// way is up in the pile. From the sheet's own bend, a page taken off a fan 44
// degrees up had its up turned so far from the leaf under it that at a grazing
// view one was nudged towards the eye and the other away, and the leaf came
// through the page. Every sheet on a half has to agree on up.
uniform vec4 stack_own = vec4(0.0);
uniform vec4 stack_far = vec4(0.0);
// Moving along the eye ray changes depth only, never where on screen a sheet is
// drawn. 0.3 mm a place left a page lifting off a 400-page book 0.69 mm under the
// leaf below it, 3 cm from the spine (each sheet's bend pivots on the book's
// middle, a centimetre below the top of a thick block). PDFBook.STACK_STEP must
// match.
const float STACK_STEP = 0.0005;
const float STACK_GRAZE = 0.15;
// Every sheet of a half leaves the binding on its BLOCK's bend and only peels away
// from it over this far out from the gutter: there they are ordered by height
// alone, which is the pile's order. Each on its own bend, a page and the leaf
// under it, a centimetre off the book's middle on a thick block, swung through
// each other by millimetres in the binding (every bend pivots on the middle).
// BookFlop.BIND_SPREAD must match.
const float BIND_SPREAD = 0.02;

// Surface.
uniform float gutter_ao : hint_range(0.0, 1.0) = 0.55;
uniform float gutter_ao_falloff : hint_range(1.0, 40.0) = 9.0;
uniform sampler2D grain_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 grain_tile = vec2(6.0, 8.0);
uniform float fibre_strength : hint_range(0.0, 1.0) = 0.25;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.22;
uniform float sheen : hint_range(0.0, 1.0) = 0.18;

varying float v_u;

const float PI_ = 3.14159265;
const float PAPER_PI = 3.14159265;

#include "res://Shaders/paper_rest.gdshaderinc"
#include "res://Shaders/paper_flop.gdshaderinc"

void vertex() {
	float w = max(page_size.x, 1e-5);
	float h = max(page_size.y, 1e-5);
	if (spine_density != 0.0) {
		float t = clamp(0.5 + spine_sign * VERTEX.x / w, 0.0, 1.0);
		t += spine_density * (t * t - t);
		VERTEX.x = spine_sign * (t - 0.5) * w;
		UV.x = 0.5 + VERTEX.x / w;
	}
	float u = clamp(0.5 + spine_sign * VERTEX.x / w, 0.0, 1.0);
	float v = clamp(0.5 + VERTEX.y / h, 0.0, 1.0);
	v_u = u;

	float gutter;
	float sag;
	float lift;
	paper_rest_parts(u, v, gutter_dive, gutter_falloff, bow_amount, fore_droop, edge_curl,
		gutter, sag, lift);
	float dzdu;
	float dzdv;
	paper_rest_slope(u, v, gutter_dive, gutter_falloff, bow_amount, fore_droop, edge_curl,
		dzdu, dzdv);

	// A page turned over on its hinge (flop_lift, the turning leaf only) takes
	// its rest shape with it, so a page that FELL over onto the far half bowed
	// down into the page it landed on, which bows up to meet it: 5.9 mm through,
	// until the turn finished. A sheet bows up off whatever it lies on, so the
	// rest shape goes as cos(lift): itself lying on its own half, none standing
	// upright, and turned back up again once it lies on the far half.
	float rest_turn = cos(flop_lift);
	dzdu *= rest_turn;
	dzdv *= rest_turn;
	// Along the BOOK's +Z, not this mesh's: a cover turned 180 degrees about Y has
	// its own +Z pointing down out of the book, and sagged INTO its block.
	// The dive into the gutter is not the sheet's shape but where the binding
	// pulls its spine edge, straight down into the valley whichever way the page
	// is turned: on a page on its hinge it goes on AFTER the hinge. Turned with it,
	// a page falling over from a thick half swung its 9 mm dive out sideways and
	// landed it 3.6 mm from the spine, under the page it came down on.
	float hinged_dive = flop_lift != 0.0 ? gutter : 0.0;
	VERTEX.z += flop_z_sign * ((gutter - hinged_dive) + (sag + lift) * rest_turn);

	// Arc-length conservation: the sheet dipping into the gutter is longer than
	// the flat span it covers, so a material point sits nearer the spine than
	// its flat position. Doing this in geometry (rather than squeezing UVs)
	// keeps the texture attached to the paper.
	VERTEX.x -= spine_sign * gutter_dive * exp(-u * gutter_falloff) * 0.5;

	// dz/dx and dz/dy from du/dx = spine_sign/w, dv/dy = 1/h.
	vec3 n = normalize(vec3(-flop_z_sign * dzdu * spine_sign / w, -flop_z_sign * dzdv / h, 1.0));

	if (fold_strength > 0.0) {
		vec2 fn = normalize(fold_normal);
		vec2 ft = vec2(-fn.y, fn.x);
		float d = dot(VERTEX.xy - fold_origin, fn);
		if (d > 0.0) {
			// Looser curl toward the spine, where the binding stiffens the sheet.
			float r = max(curl_radius * (1.0 + curl_taper * (1.0 - u)), 1e-4);
			vec2 fold_pt = VERTEX.xy - fn * d;
			float arc = d / r;
			if (arc < PI_) {
				VERTEX.xy = fold_pt + fn * (r * sin(arc));
				VERTEX.z += r * (1.0 - cos(arc));
			} else {
				// Past the half-cylinder the sheet is flat again, upside down.
				VERTEX.xy = fold_pt - fn * (d - PI_ * r);
				VERTEX.z += 2.0 * r;
			}
			// Rotate the rest normal about the fold axis by the same angle.
			float a = clamp(arc, 0.0, PI_);
			float ca = cos(a);
			float sa = sin(a);
			float nn = dot(n.xy, fn);
			float nt = dot(n.xy, ft);
			float nz = n.z;
			float nn2 = nn * ca - nz * sa;
			float nz2 = nn * sa + nz * ca;
			n = normalize(vec3(fn * nn2 + ft * nt, nz2));
		}
	}

	// Last, because it carries everything above with it: the whole half hanging
	// from the binding. s is measured out from the book's gutter, so a flap the
	// fold has laid across it comes out negative and takes the far half's bend.
	// Which way is up off the half this point lies on (the bend without the
	// leaf's own hinge), for stack_layer.
	float up_ang = 0.0;
	if (flop_own != vec4(0.0) || flop_far != vec4(0.0) || flop_lift != 0.0) {
		// Signed: positive on this sheet's own half, negative past the gutter —
		// which only the turning leaf's flap ever is, and there it rides the far
		// half's bend, mirrored in and out. The two maps meet at the gutter (the
		// turn starts from zero there), so nothing has to be blended.
		float s = spine_sign * VERTEX.x + 0.5 * w + flop_gutter_gap;
		float z_new = flop_z_sign * VERTEX.z;
		// The leaf's own hinge first, rigidly, about the gutter at its own plane.
		float lift_c = cos(flop_lift);
		float lift_s = sin(flop_lift);
		float s_lifted = s * lift_c - z_new * lift_s;
		z_new = flop_origin_z + s * lift_s + z_new * lift_c + hinged_dive;
		float side = s_lifted < 0.0 ? -1.0 : 1.0;
		float s_new = abs(s_lifted);
		float s_up = s_new;
		float z_up = z_new;
		up_ang = side * paper_flop(s_up, z_up, side > 0.0 ? stack_own : stack_far, FLOP_HINGE_LEN);
		vec4 bend = side > 0.0 ? flop_own : flop_far;
		vec4 block_bend = side > 0.0 ? stack_own : stack_far;
		if (block_bend != vec4(0.0)) {
			bend = mix(block_bend, bend, smoothstep(0.0, BIND_SPREAD, s_new - flop_gutter_gap));
		}
		float ang = flop_lift + side * paper_flop(s_new, z_new, bend,
			flop_hinge_len(z_new, flop_cross));
		s_new *= side;
		VERTEX.x = spine_sign * (s_new - 0.5 * w - flop_gutter_gap);
		VERTEX.z = (z_new - flop_origin_z) * flop_z_sign;
		// Turn the normal through the same angle, in the same (s, z) plane.
		float ns = spine_sign * n.x;
		float nz = flop_z_sign * n.z;
		float ca = cos(ang);
		float sa2 = sin(ang);
		n.x = spine_sign * (ns * ca - nz * sa2);
		n.z = flop_z_sign * (ns * sa2 + nz * ca);
	}

	NORMAL = n;

	// Written on every path: a shader that writes POSITION anywhere draws nothing
	// for a vertex that does not (the covers, at 0, vanished).
	vec3 up_model = vec3(-spine_sign * sin(up_ang), 0.0, flop_z_sign * cos(up_ang));
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 up_view = normalize((MODELVIEW_MATRIX * vec4(up_model, 0.0)).xyz);
	vec3 to_eye = -normalize(view_pos.xyz);
	// A separation ACROSS the paper is that over the cosine of the view along the
	// eye ray: at a grazing look into the gutter 0.8 mm across was several mm
	// along it, and a flat nudge lost. So each place is worth STACK_STEP across
	// the paper from any angle, up to STACK_GRAZE's limit, and nothing at all
	// exactly edge-on (where the sign turns over) — negative from underneath.
	float c = dot(up_view, to_eye);
	float gain = c / (c * c + STACK_GRAZE * STACK_GRAZE);
	view_pos.xyz += to_eye * (stack_layer * STACK_STEP * gain);
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	vec4 color;
	if (FRONT_FACING) {
		color = texture(front_texture, UV) * paper_tint;
	} else {
		// Mirror UV horizontally for back face so text reads correctly
		vec2 back_uv = vec2(1.0 - UV.x, UV.y);
		color = texture(back_texture, back_uv) * paper_tint;
	}

	// Gutter shadow — the single cheapest cue that this is a bound book.
	float shade = 1.0 - gutter_ao * exp(-v_u * gutter_ao_falloff);
	color.rgb *= shade;

	// Deliberately no ALPHA write. Writing ALPHA at all moves a spatial material
	// into the transparent pipeline, where it stops writing depth — and two
	// depth-less page surfaces sort per-triangle against each other, so the page
	// underneath punched through the one turning over it in patches. Paper is
	// opaque; it belongs in the opaque pass.
	ALBEDO = color.rgb;

	// Fibre grain, applied through the mesh tangent frame. One fetch from a
	// small tiling texture rather than value noise: the procedural version cost
	// sixteen hash calls per fragment across four page surfaces, which is the
	// wrong shape for a tile GPU on a scene already over its frame budget.
	// RG carry the fibre gradient, B a slow roughness variation.
	vec3 grain = texture(grain_texture, UV * grain_tile).rgb;
	if (fibre_strength > 0.0) {
		NORMAL = normalize(NORMAL
			+ (TANGENT * (grain.r - 0.5) + BINORMAL * (grain.g - 0.5)) * fibre_strength);
	}

	ROUGHNESS = clamp(roughness - grain.b * roughness_variation, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = sheen;
	// Paper is thin: light reaching the far side bleeds through.
	BACKLIGHT = vec3(backlight_amount) * color.rgb * shade;
}
