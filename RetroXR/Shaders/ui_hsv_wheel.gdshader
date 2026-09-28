// The disc of HsvWheel (Scripts/UI/widgets/hsv_wheel.gd): hue by angle,
// counter-clockwise from red at three o'clock; saturation by distance from the
// centre, white there and pure at the rim; the whole disc at brightness `value`.
shader_type canvas_item;

uniform float value : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float hue = fract(atan(-p.y, p.x) / TAU);
	vec3 pure = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	vec3 rgb = value * mix(vec3(1.0), pure, min(r, 1.0));
	float edge = fwidth(r);
	COLOR = vec4(rgb, 1.0 - smoothstep(1.0 - edge, 1.0, r));
}
