// The sky behind the street's layers: the render's sky with the trees and houses painted out, on a dome far
// enough away that it never moves. See street_projection.gdshaderinc.
shader_type spatial;

#include "res://Shaders/street_projection.gdshaderinc"

void fragment() {
	vec2 uv = pano_uv();
	vec3 c = texture(key_a, uv).rgb;
	if (blend > 0.0) {
		c = mix(c, texture(key_b, uv).rgb, blend);
	}
	ALBEDO = decode(c) * exposure;
}
