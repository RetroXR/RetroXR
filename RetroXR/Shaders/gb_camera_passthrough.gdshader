// The real room behind a Game Boy Camera's picture, in passthrough.
//
// A quad under the lens's Camera3D (GbCameraEye) that covers its whole view at
// the far end of the depth range, so everything in the scene draws over it. Each
// pixel's ray out of the lens is followed to where it meets a sphere of RADIUS
// round the headset camera -- the room, taken to be that far from the face --
// and that point looked up in the headset camera's latest frame
// (PassthroughCamera.surface_point and project, the same steps). The sphere stays
// put while the cartridge moves, so a lens held out toward the room sees less of
// it, larger: it zooms the way a camera walked toward a wall does. What the
// headset camera did not see is black.
//
// Only the lens draws it. Its camera leaves out one layer no other camera does
// (GbCameraEye.LENS_ONLY_LAYER), and every other camera -- the player's own eyes
// first -- collapses the quad to nothing in the vertex stage.
shader_type spatial;
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

void fragment() {
	vec4 on_ray = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(on_ray.xyz / on_ray.w, 0.0)).xyz);
	// In the headset camera's space, where the sphere is centered: o + t d.
	vec3 o = (camera_from_world * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 d = mat3(camera_from_world) * dir;
	float b = dot(o, d);
	float disc = b * b - (dot(o, o) - radius * radius);
	vec3 color = vec3(0.0);
	// The far crossing: the lens is inside the sphere, a reach from the face.
	float t = disc >= 0.0 ? -b + sqrt(disc) : -1.0;
	vec3 p = o + d * t;
	float z = -p.z;
	if (t > 0.0 && z > 0.0001) {
		vec2 uv = vec2(intrinsics.x * p.x / z + intrinsics.z, intrinsics.y * -p.y / z + intrinsics.w);
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			float l = texture(feed, uv).r;
			color = vec3(l <= 0.04045 ? l / 12.92 : pow((l + 0.055) / 1.055, 2.4));
		}
	}
	ALBEDO = color;
}
