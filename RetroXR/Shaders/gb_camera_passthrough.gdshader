// The real room behind a Game Boy Camera's picture, in passthrough.
//
// Each pixel's ray out of the lens is followed to where it meets a sphere of
// RADIUS round the headset camera -- the room, taken to be that far from the
// face -- and that point looked up in the headset camera's latest frame
// (PassthroughCamera.surface_point and project, the same steps). The sphere stays
// put while the cartridge moves, so a lens held out toward the room sees less of
// it, larger: it zooms the way a camera walked toward a wall does. What the
// headset camera did not see is black.
//
// Where Meta's depth is running the lens uses gb_camera_passthrough_depth
// instead, which finds the real surfaces; this is the shader everywhere else.
shader_type spatial;

#include "res://Shaders/gb_camera_passthrough_common.gdshaderinc"

void fragment() {
	vec3 origin;
	vec3 dir;
	lens_ray(INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, origin, dir);
	vec4 hit = sphere_hit(origin, dir);
	ALBEDO = hit.w > 0.0 ? feed_at(hit.xyz) : vec3(0.0);
}
