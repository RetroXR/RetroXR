// The pick-up outline of something that is bent in the vertex stage.
//
// PickableHighlight draws its outline from a flat, smoothed COPY of each source
// mesh, kept on the source node's transform. That is right for everything rigid
// and wrong for a book: its blocks and covers hang from the binding by a bend
// that exists only in paper.gdshader / page_edge.gdshader, so the outline stayed
// on the flat book while the book drooped away underneath it and floated in the
// air as an empty rectangle.
//
// So the *_bent outline shaders run the very same bend (paper_flop) on the copy
// before they inflate it. The numbers arrive as PER-INSTANCE uniforms, because
// the highlight shares one material across all of an object's overlays and each
// overlay (left block, right block, each cover) hangs by its own side's bend.
// All zero — every overlay that was never given any, the rigid spine included —
// leaves the vertex alone.

#include "res://Shaders/paper_flop.gdshaderinc"

// (angle at the gutter, page curvature, support distance, gutter displacement):
// BookFlop.params() for the side this mesh hangs from.
instance uniform vec4 flop_own = vec4(0.0);
// Where this mesh sits in the book: (origin Z, which way its own +Z points in
// the book's, which way its own +X points away from the gutter, its Z scale).
instance uniform vec4 flop_frame = vec4(0.0, 1.0, 1.0, 1.0);
// (page width, gap from the gutter to the page's inner edge).
instance uniform vec2 flop_page = vec2(0.18, 0.00175);

void outline_flop(inout vec3 vertex, inout vec3 normal) {
	if (flop_own == vec4(0.0)) {
		return;
	}
	float zs = max(flop_frame.w, 1e-4);
	float s = max(flop_frame.z * vertex.x + 0.5 * flop_page.x + flop_page.y, 0.0);
	float zb = flop_frame.x + flop_frame.y * vertex.z * zs;
	float ang = paper_flop(s, zb, flop_own, FLOP_HINGE_LEN);
	vertex.x = flop_frame.z * (s - 0.5 * flop_page.x - flop_page.y);
	vertex.z = (zb - flop_frame.x) * flop_frame.y / zs;
	// The normal goes through the inverse of the node's Z scale, as the engine's
	// own normal matrix will on the way to the world.
	float ns = flop_frame.z * normal.x;
	float nz = flop_frame.y * normal.z / zs;
	float ca = cos(ang);
	float sa = sin(ang);
	normal = normalize(vec3(flop_frame.z * (ns * ca - nz * sa), normal.y, flop_frame.y * (ns * sa + nz * ca) * zs));
}
