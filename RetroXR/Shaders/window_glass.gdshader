// The bedroom window's panes: one blended, unshaded quad each, cheap on a headset.
//
// Glass shows the room more as the view grazes it (Schlick's Fresnel from 4% head-on), and more at night, when
// the street behind it is dark and the room is the brightest thing about (bedroom_exterior.gd drives `reflection`
// from the time lever). The room is not rendered twice: its reflection is a soft gradient in the room's own
// light, warm under the ceiling, darker toward the floor, with a lamp's glint. A little dust and a couple of
// smudges catch the light the same way, and a faint green-gray tint sits in the glass, as in any float glass.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 room_light : source_color = vec3(0.95, 0.82, 0.66);
uniform float reflection : hint_range(0.0, 1.0) = 0.08;
uniform float tint : hint_range(0.0, 0.2) = 0.035;
uniform sampler2D dust : hint_default_black, filter_linear_mipmap;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.22;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float c = abs(dot(v, n));
	float fresnel = 0.04 + 0.96 * pow(1.0 - c, 5.0);
	// the room as the pane mirrors it: the reflected ray's height picks ceiling-warm or floor-dark
	vec3 r = reflect(-v, n);
	float up = r.y * 0.5 + 0.5;
	vec3 room = room_light * mix(0.25, 1.0, smoothstep(0.2, 0.9, up));
	room += room_light * 2.0 * pow(max(dot(r, normalize(vec3(0.5, 0.55, 0.65))), 0.0), 60.0);   // the lamp's glint
	float d = texture(dust, UV).r;
	float smudge = d * dust_amount;
	float k = clamp(fresnel * (0.35 + reflection * 4.0) + smudge * (0.12 + reflection), 0.0, 0.85);
	ALBEDO = room * (1.0 + smudge) + vec3(0.62, 0.68, 0.64) * tint;
	ALPHA = clamp(k + tint, 0.0, 0.9);
}
