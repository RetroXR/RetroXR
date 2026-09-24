// Soft patches fixed to a cartridge shell, for the uneven milkiness of moulded
// clear plastic. Shared by both clear-plastic passes so the filter's denser
// patches and the surface's brighter scatter are the same patches.
// cloud_noise() is 0..1, averaging 0.5; `p` is the mesh's own position.

float cloud_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float cloud_value(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(cloud_hash(i), cloud_hash(i + vec3(1, 0, 0)), f.x),
			mix(cloud_hash(i + vec3(0, 1, 0)), cloud_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(cloud_hash(i + vec3(0, 0, 1)), cloud_hash(i + vec3(1, 0, 1)), f.x),
			mix(cloud_hash(i + vec3(0, 1, 1)), cloud_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float cloud_noise(vec3 p, float size_mm) {
	vec3 q = p / (size_mm * 0.001);
	return cloud_value(q) * 0.5 + cloud_value(q * 2.7 + 11.0) * 0.3 + cloud_value(q * 7.3 + 29.0) * 0.2;
}
