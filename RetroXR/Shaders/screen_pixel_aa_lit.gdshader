// screen_pixel_aa, lit by the room instead of by itself.
//
// For the handhelds whose real panel was a REFLECTIVE LCD with no light of its own
// (Game Boy, GBC, GBA, Neo Geo Pocket, WonderSwan, Pokemon mini, Supervision, and
// a GBA SP with its light switched off): the picture is the panel's colour, so it
// is as bright as the light falling on it and dark in a dark room. Used unless
// Options "Self-Lit Handheld Screens" is on (RetroSystemModelHandheld.screen_self_lit).
shader_type spatial;
render_mode cull_disabled, fog_disabled;

#include "res://Shaders/screen_pixel_aa.gdshaderinc"

void fragment() {
	ALBEDO = screen_pixel_aa(UV);
	// The plastic window over the panel: a soft gloss, never a mirror.
	ROUGHNESS = 0.4;
	SPECULAR = 0.5;
}
