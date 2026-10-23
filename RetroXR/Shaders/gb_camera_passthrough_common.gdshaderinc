// What the two Game Boy Camera backdrops share (gb_camera_passthrough and its
// depth variant): the quad that only the lens draws, its ray out of the lens,
// the room taken to be a sphere round the headset camera, and the look-up of a
// point in the headset camera's frame.
//
// A quad under the lens's Camera3D (GbCameraEye) covers its whole view at the far
// end of the depth range, so everything in the scene draws over it. Only the lens
// draws it: its camera leaves out one layer no other camera does
// (GbCameraEye.LENS_ONLY_LAYER), and every other camera -- the player's own eyes
// first -- collapses the quad to nothing in the vertex stage.

render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Bit 18: layer 19 in the editor. GbCameraEye.LENS_ONLY_LAYER.
const uint LENS_ONLY = 262144u;
// Reverse Z: 0 is the far plane. A hair inside it, past anything in a room.
const float FAR_DEPTH = 0.00001;

// Luma, gamma-encoded as the camera gives it. Not source_color: a one-channel
// texture has no sRGB format to decode through, so it is decoded below.
uniform sampler2D feed : filter_linear, repeat_disable;
// The frame's camera, world to camera: x right, y up, looking down -z.
uniform mat4 camera_from_world;
// fu, fv, cu, cv: x/z and y/z to 0..1 UVs, v down (PassthroughCamera.intrinsics).
uniform vec4 intrinsics;
// How far the room is taken to be from the headset camera, in meters.
uniform float radius = 1.5;

varying vec2 ndc;

void vertex() {
	if ((CAMERA_VISIBLE_LAYERS & LENS_ONLY) != 0u) {
		POSITION = vec4(0.0);
	} else {
		// A 2x2 QuadMesh: its corners are the screen's.
		ndc = VERTEX.xy;
		POSITION = vec4(VERTEX.xy, FAR_DEPTH, 1.0);
	}
}

// This pixel's ray out of the lens, in the world.
void lens_ray(mat4 inv_projection, mat4 inv_view, out vec3 origin, out vec3 dir) {
	vec4 on_ray = inv_projection * vec4(ndc, 1.0, 1.0);
	dir = normalize((inv_view * vec4(on_ray.xyz / on_ray.w, 0.0)).xyz);
	origin = inv_view[3].xyz;
}

// Where the ray meets a sphere of `radius` round the headset camera, the far
// crossing (the lens is inside it, a reach from the face): world point in xyz, w
// 1 when it does and 0 when not. PassthroughCamera.surface_point.
vec4 sphere_hit(vec3 origin, vec3 dir) {
	vec3 o = (camera_from_world * vec4(origin, 1.0)).xyz;
	vec3 d = mat3(camera_from_world) * dir;
	float b = dot(o, d);
	float disc = b * b - (dot(o, o) - radius * radius);
	float t = disc >= 0.0 ? -b + sqrt(disc) : -1.0;
	return vec4(origin + dir * t, t > 0.0 ? 1.0 : 0.0);
}

// What the headset camera saw at a world point, linear: black where it did not
// see. PassthroughCamera.project.
vec3 feed_at(vec3 world) {
	vec3 p = (camera_from_world * vec4(world, 1.0)).xyz;
	float z = -p.z;
	if (z <= 0.0001) {
		return vec3(0.0);
	}
	vec2 uv = vec2(intrinsics.x * p.x / z + intrinsics.z, intrinsics.y * -p.y / z + intrinsics.w);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec3(0.0);
	}
	float l = texture(feed, uv).r;
	return vec3(l <= 0.04045 ? l / 12.92 : pow((l + 0.055) / 1.055, 2.4));
}
