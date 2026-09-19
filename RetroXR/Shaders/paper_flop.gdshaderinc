// How a half of the book hangs from its binding: the bend BookFlop solves for,
// applied to geometry.
//
// Shared by paper.gdshader (sheets, covers, the turning leaf, the fan) and
// page_edge.gdshader (the block under them) for the same reason paper_rest is:
// everything on one side of the gutter has to move as one body, and the block
// surfacing through the page on top of it is a bug this book has shipped twice.
//
// Works in the (s, z) plane of one half:
//   s = metres out from the gutter along the flat sheet, always >= 0
//   z = height above the book's neutral plane (book-local Z)
// and wraps it round three pieces in series out from the gutter — a tight arc at
// the binding, a straight run out to the hand supporting that half, and a long
// shallow arc over the rest of the sheet — then moves the whole half with the
// gutter. Circular arcs conserve paper length exactly, the same trick as the
// fold wrap.
//
// flop = (angle at the gutter, page curvature, support distance, gutter
// displacement). The gutter angle is the free hinge, or the slope of a spread
// sagging between two hands; the displacement is that sag, and is the one
// number both halves share, which is what keeps them joined at the binding.
// Angles are positive toward +Z. book_flop.gd mirrors this on the CPU
// (BookFlop.bend_sz) — change one and book_flop_tests goes red until the other
// follows.

const float FLOP_HINGE_LEN = 0.012;
const float FLOP_LIFT_SPREAD = 2.5;

void flop_arc(float len, float k, out vec2 p, out float ang) {
	ang = k * len;
	if (abs(ang) < 1e-4) {
		p = vec2(len, 0.5 * k * len * len);
	} else {
		p = vec2(sin(ang), 1.0 - cos(ang)) / k;
	}
}

// A sheet lying on the book bends over FLOP_HINGE_LEN at the binding. A sheet
// LIFTED off it cannot: z above a bend of radius R it is on the outside of the
// curve and would have to cover (R + z) / R times the paper it has — 5 cm over
// a drooping spine, nearly four times. So the leaf being turned, and only that,
// spreads the same turn over an arc that widens with its height, which keeps
// the radius large beside the lift. On the page plane this is FLOP_HINGE_LEN
// again, so a landed page lies exactly on its block.
float flop_hinge_len(float z, float lifted) {
	return max(FLOP_HINGE_LEN, lifted * FLOP_LIFT_SPREAD * z);
}

// Returns the angle the sheet has turned through at this point, for the normal.
float paper_flop(inout float s, inout float z, vec4 flop, float hinge_len) {
	if (flop.x == 0.0 && flop.y == 0.0 && flop.w == 0.0) {
		return 0.0;
	}
	float l1 = clamp(s, 0.0, hinge_len);
	vec2 p;
	float ang;
	flop_arc(l1, flop.x / hinge_len, p, ang);
	float rest = s - l1;
	if (rest > 0.0) {
		float l2 = min(rest, max(flop.z, hinge_len) - hinge_len);
		p += vec2(cos(ang), sin(ang)) * l2;
		float l3 = rest - l2;
		if (l3 > 0.0) {
			vec2 p3;
			float a3;
			flop_arc(l3, flop.y, p3, a3);
			float c = cos(ang);
			float sn = sin(ang);
			p += vec2(c * p3.x - sn * p3.y, sn * p3.x + c * p3.y);
			ang += a3;
		}
	}
	s = p.x - sin(ang) * z;
	z = p.y + cos(ang) * z + flop.w;
	return ang;
}
