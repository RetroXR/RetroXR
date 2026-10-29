// Plain core-picture display filter: the emulator frame, pixel-AA sampled.
//
// This is the default wrapper for a built-in screen with no device-specific look
// (GBA, PSP, …). It does nothing but sample — the whole point is the sampling; see
// pixel_aa.gdshaderinc for why neither hardware filter is right for a small fixed
// pixel grid on a 3D surface. Devices with their own panel look (the DMG's
// gameboy_lcd) use that shader instead, and it samples the same way.
//
// render_mode unshaded so the screen reads as self-lit, matching the emissive
// StandardMaterial3D the C++ VideoHandler installs and that this replaces.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://Shaders/screen_pixel_aa.gdshaderinc"

void fragment() {
	ALBEDO = screen_pixel_aa(UV);
}
