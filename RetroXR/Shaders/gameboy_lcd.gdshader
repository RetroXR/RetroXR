// Game Boy (DMG) LCD display filter for the RetroXR handheld screen.
//
// Reproduces the classic dot-matrix look — a 4-shade green palette plus the
// faint pixel grid of the reflective LCD — as a `spatial` material on the
// handheld's built-in screen mesh (sampling the core's picture via source_tex),
// the same way crt_effect.gdshader wraps the TV tube. render_mode unshaded so
// the screen reads self-lit.
//
// Effect inspired by ivanskodje's godot-gameboy-shaders (MIT); that project is
// Godot 2.x (its shaders ship as old-format .tres and can't run in Godot 4), so
// the two effects — 4-colour quantise + LCD grid — are re-implemented natively.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://Shaders/gameboy_lcd.gdshaderinc"

void fragment() {
	ALBEDO = gameboy_lcd(UV);
}
