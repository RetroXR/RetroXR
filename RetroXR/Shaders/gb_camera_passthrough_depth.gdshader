// The real room behind a Game Boy Camera's picture, on the room's real surfaces.
//
// gb_camera_passthrough assumes the room is a sphere 1.5 m from the face; this
// asks Meta's depth (EnvironmentDepth) where it really is. Each pixel's ray out of
// the lens is marched through the left eye's depth map until it passes behind a
// measured surface, narrowed there, and that point looked up in the headset
// camera's frame -- so a hand at 30 cm and the far wall both land where they are.
// PassthroughCamera.march_depth is the same march. Where the depth says nothing
// along a ray (off its map, no data) the sphere is used, as before.
//
// Names the plugin's META_ENVIRONMENT_DEPTH_* globals, which exist only while its
// extension is on: the lens loads this only once EnvironmentDepth.is_running().
shader_type spatial;

#include "res://Shaders/gb_camera_passthrough_common.gdshaderinc"

// Layer 0 is the left eye. The plugin's own occlusion shader reads it nearest.
global uniform highp sampler2DArray META_ENVIRONMENT_DEPTH_TEXTURE : filter_nearest;
// The tracking space to the left eye's depth clip space (GL-style, z -1..1).
global uniform mat4 META_ENVIRONMENT_DEPTH_PROJECTION_VIEW_LEFT;

// The world to the tracking space the depth matrices are in: the XROrigin's
// inverse (EnvironmentDepth's note on which space they are in).
uniform mat4 tracking_from_world;

// PassthroughCamera.MARCH_*.
const float MARCH_NEAR = 0.05;
const float MARCH_FAR = 4.0;
const int MARCH_STEPS = 48;
const int MARCH_REFINE = 4;

// 1 behind the measured surface, 0 in front of it, -1 where there is no depth.
int behind(vec3 world) {
	vec4 c = META_ENVIRONMENT_DEPTH_PROJECTION_VIEW_LEFT * tracking_from_world * vec4(world, 1.0);
	if (c.w <= 0.0) {
		return -1;
	}
	vec3 n = c.xyz / c.w;
	vec2 uv = n.xy * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return -1;
	}
	float stored = texture(META_ENVIRONMENT_DEPTH_TEXTURE, vec3(uv, 0.0)).r;
	if (stored <= 0.0) {
		return -1;
	}
	return n.z * 0.5 + 0.5 > stored ? 1 : 0;
}

void fragment() {
	vec3 origin;
	vec3 dir;
	lens_ray(INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, origin, dir);
	float ratio = pow(MARCH_FAR / MARCH_NEAR, 1.0 / float(MARCH_STEPS));
	float t_prev = 0.0;
	float t = MARCH_NEAR;
	float found = -1.0;
	for (int i = 0; i < MARCH_STEPS; i++) {
		// No depth here (off its view, a hole) is passed over, not given up at:
		// a lens held out to the side comes into the depth's view farther out.
		int answer = behind(origin + dir * t);
		if (answer == 1) {
			float lo = t_prev;
			float hi = t;
			for (int j = 0; j < MARCH_REFINE; j++) {
				float mid = (lo + hi) * 0.5;
				if (behind(origin + dir * mid) == 1) {
					hi = mid;
				} else {
					lo = mid;
				}
			}
			found = hi;
			break;
		}
		t_prev = t;
		t *= ratio;
	}
	if (found > 0.0) {
		ALBEDO = feed_at(origin + dir * found);
	} else {
		vec4 hit = sphere_hit(origin, dir);
		ALBEDO = hit.w > 0.0 ? feed_at(hit.xyz) : vec3(0.0);
	}
}
