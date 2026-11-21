// The picture's color as the INPUT delivers it, not as the tube draws it.
//
// Included by both tiers' CRT includes (crt_filter, crt_mobile), so every shader
// that wears the tube stage has the uniform, and applied whether or not the tube
// stage is on: a component input with only its Y jack cabled is black and white
// on any set, with or without the CRT look.
//
// crt_chroma is TvSignal.Chroma, pushed by TvDisplay from the selected input's
// wiring:
//   0  FULL     the color the core drew
//   1  MONO     no color-difference signal reached the set: Y alone in a component
//               input (a yellow composite cord in the green jack, or a component
//               lead with its blue and red left out)
//   2  SWAPPED  Pb in the Pr jack and Pr in the Pb jack: the two color-difference
//               signals trade places, which turns skin green and sky orange
//
// BT.601 Y'PbPr, applied to the color the shader holds. That color is linear
// here (TvDisplay binds the sRGB view), and the real decode ran on gamma-encoded
// signals, so a swapped picture's hues are close to, not exactly, a real one's;
// MONO's luma weights are the same either way to within what reads on a CRT.
uniform int crt_chroma : hint_range(0, 2) = 0;

vec3 crt_chroma_apply(vec3 c) {
	if (crt_chroma == 0) {
		return c;
	}
	float y = dot(c, vec3(0.299, 0.587, 0.114));
	if (crt_chroma == 1) {
		return vec3(y);
	}
	// Pb = (B - Y) / 1.772, Pr = (R - Y) / 1.402; swapped, each goes back out
	// through the other's matrix row.
	float pb = (c.b - y) / 1.772;
	float pr = (c.r - y) / 1.402;
	float r = y + 1.402 * pb;
	float b = y + 1.772 * pr;
	float g = (y - 0.299 * r - 0.114 * b) / 0.587;
	return max(vec3(r, g, b), vec3(0.0));
}
