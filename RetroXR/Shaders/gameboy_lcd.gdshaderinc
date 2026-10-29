// The DMG LCD look, shared by gameboy_lcd.gdshader (self-lit) and
// gameboy_lcd_lit.gdshader (lit by the room, as the real reflective panel is).
// The includer declares the render_mode; this is the colour alone.

#include "res://Shaders/pixel_aa.gdshaderinc"

// filter_linear is REQUIRED by pixel_aa (it does the sub-pixel ramp).
uniform sampler2D source_tex : source_color, filter_linear, repeat_disable;

// Native panel resolution the grid aligns to (DMG = 160x144).
uniform vec2 gb_resolution = vec2(160.0, 144.0);

// DMG green palette, darkest → lightest (default = the real hardware greens).
uniform vec4 gb_c0 : source_color = vec4(0.059, 0.220, 0.059, 1.0);
uniform vec4 gb_c1 : source_color = vec4(0.188, 0.384, 0.188, 1.0);
uniform vec4 gb_c2 : source_color = vec4(0.545, 0.675, 0.059, 1.0);
uniform vec4 gb_c3 : source_color = vec4(0.608, 0.737, 0.059, 1.0);

// Pixel-grid darkening between cells (the reflective-LCD gap).
uniform float gb_grid_strength : hint_range(0.0, 1.0) = 0.22;
uniform float gb_grid_width : hint_range(0.0, 0.5) = 0.08;

vec3 gameboy_lcd(vec2 uv) {
	vec3 src = pixel_aa(source_tex, uv).rgb;

	// Quantise luminance into the 4 DMG shades (dark image → dark green).
	float luma = dot(src, vec3(0.299, 0.587, 0.114));
	vec3 col;
	if (luma < 0.25) {
		col = gb_c0.rgb;
	} else if (luma < 0.50) {
		col = gb_c1.rgb;
	} else if (luma < 0.75) {
		col = gb_c2.rgb;
	} else {
		col = gb_c3.rgb;
	}

	// Faint pixel grid: darken toward each source pixel's borders.
	vec2 cell = fract(uv * gb_resolution);
	float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	float inside = smoothstep(0.0, gb_grid_width, edge);
	col *= mix(1.0 - gb_grid_strength, 1.0, inside);

	return col;
}
