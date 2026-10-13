uniform sampler2D source_tex : source_color, filter_linear, repeat_disable;
uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Added to the sample x for the RIGHT eye (0 = mono source).
uniform float eye_shift = 0.0;
// Stereo presentation (set by the connected RetroTV's 3D button; no-op when
// eye_shift is 0): 0 = per-eye stereo, 1 = left eye only, 2 = right eye only.
uniform int stereo_mode = 0;

// Chained CRT display stage (set by a connected RetroTV when its CRT is on).
uniform bool crt_enabled = false;

// On-screen display from the connected TV, composited before the CRT stage.
uniform sampler2D osd_tex : source_color, filter_linear, repeat_disable;
uniform bool osd_enabled = false;

void fragment() {
	vec2 wuv = crt_enabled ? crt_warp(UV) : UV;
	vec4 rect = source_rect;
	if (stereo_mode == 2 || (stereo_mode == 0 && VIEW_INDEX == VIEW_RIGHT)) {
		rect.x += eye_shift;
	}
	// suv is the single-tap position the notch and glow taps sit around; the picture
	// comes from pixel_aa, which averages the pixel's footprint under minification.
	vec2 wrect_uv = rect.xy + wuv * rect.zw;
	vec2 suv = pixel_aa_uv(source_tex, wrect_uv);

	// Every footprint tap stays inside this screen's last texel centre. Clamping
	// merely to rect's geometric edge would still let bilinear filtering mix the
	// top screen's final row into the bottom screen's first row (and vice versa).
	#ifdef CRT_FAST
	vec3 col = pixel_aa_fast_rect(source_tex, wrect_uv, rect).rgb;
#else
	vec3 col = pixel_aa_rect(source_tex, wrect_uv, rect).rgb;
#endif
	#ifndef CRT_FAST
	vec3 glow = vec3(0.0);
	if (crt_enabled) {
		col = crt_notch_sample_rect(source_tex, suv, col, rect);
		// Clamp the halation taps to this screen's window so a DS panel can't
		// bleed glow in from the other screen packed into the same framebuffer.
		glow = crt_glow_rect(source_tex, suv, rect);
	}

	#endif

	if (osd_enabled) {
		vec4 osd = texture(osd_tex, wuv);
		col = mix(col, osd.rgb, osd.a);
	}
	if (crt_enabled) {
		#ifdef CRT_FAST
		col = crt_apply(col, wuv);
		#else
		col = crt_apply_full(col, glow, wuv);
		#endif
		#ifndef CRT_FAST
		ALPHA = crt_border(wuv);
		#endif
	}
	#ifdef CRT_FAST
	float border = crt_enabled ? crt_border(wuv) : 1.0;
	col *= border;
	vec3 picture = clamp(col, 0.0, 1.0);
	ALBEDO = crt_glass_albedo(wuv) + picture + crt_glass_sheen(picture, NORMAL, VIEW);
	ALPHA = border;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	#else
	vec3 picture = clamp(col, 0.0, 1.0);
	float glass_wear = crt_glass_wear_mask(wuv);
	ALBEDO = crt_glass_albedo(wuv);
	EMISSION = picture + crt_glass_sheen(picture, NORMAL, VIEW, glass_wear, INV_VIEW_MATRIX);
	METALLIC = 0.0;
	SPECULAR = crt_glass_specular_value(glass_wear);
	ROUGHNESS = crt_glass_roughness_value(glass_wear);
	CLEARCOAT = crt_glass_clearcoat_value(glass_wear);
	CLEARCOAT_ROUGHNESS = crt_glass_clearcoat_roughness_value(glass_wear);
	#endif
}
