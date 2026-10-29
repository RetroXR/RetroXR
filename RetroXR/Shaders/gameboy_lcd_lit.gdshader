// gameboy_lcd, lit by the room instead of by itself — the DMG's panel was a
// reflective LCD with no light of its own, readable only by the light falling on
// it. Used unless Options "Self-Lit Handheld Screens" is on
// (RetroSystemModelHandheld.screen_self_lit). Same uniforms as gameboy_lcd.
shader_type spatial;
render_mode cull_disabled, fog_disabled;

#include "res://Shaders/gameboy_lcd.gdshaderinc"

void fragment() {
	ALBEDO = gameboy_lcd(UV);
	// The plastic window over the panel: a soft gloss, never a mirror.
	ROUGHNESS = 0.4;
	SPECULAR = 0.5;
}
