shader_type spatial;

// The headset lighting path for a PROP — a console, a television, a table.
//
// The shell got this treatment first and the props were left on Godot's
// lighting, which turned out to be where the frame went next. Measured on a
// Quest 3 at eye buffer 1.75x with the shell already baked: the shell is 22% of
// the frame, and the props are 24% — five high-polygon draws carrying the
// machines and the sets. Substituting a constant-colour fragment shader for
// that pipeline took 21.6% off the whole frame, which is more than the shell was
// still worth.
//
// Unlike `pbr_surface_unshaded` this samples the prop's OWN maps through its own
// UVs, because a console's albedo is authored art rather than a tiling surface.
// Everything else is the same idea: no light loop, no shadow maps, no probes —
// the lighting comes from the room's baked irradiance volume, indexed by world
// position, at two texture fetches and no arithmetic.
//
// A prop that is picked up and carried keeps working, and correctly: it samples
// the volume wherever it now is, so a console lifted toward the ceiling globe
// brightens. That is the whole reason the volume is indexed by position rather
// than baked per-object.

render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform bool has_albedo_tex = false;
uniform bool has_normal_tex = false;
uniform bool has_emission_tex = false;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
// The source material's metallic and roughness (scalars; a prop with a metallic
// MAP keeps 0 here, see PropLighting._translate). A metal has no diffuse at all:
// its colour is what it reflects, tinted by its albedo. Left out, a near-white
// metal (the closet door's knob: albedo 0.95, metallic 1) was drawn as matte
// white paint on a headset while the desktop showed it chrome.
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

#ifdef SURFACE_UV
// A prop on `pbr_surface` (the table's wood, the storage box's cardboard) has
// no authored UVs worth the name: its meshes are BoxMeshes, whose UVs run 0..1
// per face whatever the size. PropLighting builds this variant for them with
// `#define SURFACE_UV` prepended, so the UV is picked from position exactly as
// `pbr_surface_common.gdshaderinc` `shell_uv()` does on the desktop, and the
// colour is `shell_albedo()`'s tint / paint-over. Props without the define pay
// nothing for it: no extra varyings, no branch.
uniform float tiles_per_metre = 0.75;
uniform bool object_space = false;
uniform bool swap_uv = false;
uniform vec2 uv_offset = vec2(0.0);
uniform float paint_over : hint_range(0.0, 1.0) = 0.0;
varying vec3 v_local_pos;
varying vec3 v_local_normal;
#endif

// The room's baked irradiance volume, shared with the shell.
uniform sampler3D gi_irr : filter_linear, repeat_disable;
uniform sampler3D gi_dir : filter_linear, repeat_disable;
uniform vec3 gi_min = vec3(0.0);
uniform vec3 gi_size = vec3(1.0);
// The shell's daylight scale, so a prop darkens with the walls when the time
// lever or the blinds move. See `shell_gi.gdshaderinc`.
uniform vec3 gi_tint = vec3(1.0);

// Lambert to black at the terminator reads as a seam on a large flat panel like
// a television's side. Same small wrap the shell uses.
uniform float diffuse_wrap : hint_range(0.0, 1.0) = 0.12;

// A prop that leaves the volume — carried out of the room, or a machine spawned
// beyond it — would otherwise clamp to the volume's edge texel and take that
// wall's lighting with it. This is the level it falls back to instead.
uniform vec3 outside_light : source_color = vec3(0.35, 0.33, 0.30);

// How far inside the volume's face that fallback is fully faded out. A hand's
// width: enough that a prop leaving the room does not pop, small enough that a
// surface standing ON the boundary - which every wall in a room does, since the
// volume is fitted to the shell - still reads its own baked lighting.
const float GI_FADE_METRES = 0.125;

// What a metal reflects where it is not catching the light: the room around it,
// whose mean radiance is roughly the irradiance times a room's mean albedo. A
// guess at that albedo, judged against the desktop's Godot-lit render of the
// knob (`bedroom_probe --stills=closet_knob`, with and without --shell-unshaded).
const float METAL_ROOM_ALBEDO = 0.35;
// Cap on the highlight, as a multiple of the irradiance: a smooth metal's lobe
// normalised to its width runs to hundreds, and the mobile framebuffer clips.
const float METAL_HIGHLIGHT_MAX = 3.0;
// The reflected room's level looking down and looking up, about METAL_ROOM_ALBEDO.
const float METAL_FLOOR = 0.3;
const float METAL_CEILING = 1.6;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_world_tangent;
varying vec3 v_world_binormal;


void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_world_tangent = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_world_binormal = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
#ifdef SURFACE_UV
	v_local_pos = VERTEX;
	v_local_normal = normalize(NORMAL);
#endif
}


void fragment() {
	vec2 uv = UV;
#ifdef SURFACE_UV
	{
		vec3 an = abs(object_space ? v_local_normal : v_world_normal);
		vec3 p = object_space ? v_local_pos : v_world_pos;
		if (an.y > max(an.x, an.z)) {
			uv = p.xz;
		} else if (an.x > an.z) {
			uv = p.zy;
		} else {
			uv = p.xy;
		}
		if (swap_uv) {
			uv = uv.yx;
		}
		uv = uv * tiles_per_metre + uv_offset;
	}
#endif
	vec3 albedo = albedo_color.rgb;
	if (has_albedo_tex) {
		albedo *= texture(albedo_tex, uv).rgb;
	}
#ifdef SURFACE_UV
	albedo = mix(albedo, albedo_color.rgb, paint_over);
#endif

	vec3 n = normalize(v_world_normal);
	if (has_normal_tex) {
		// Z reconstructed, not read: a hint_normal map compresses to two-channel
		// EAC_RG11 here, and taking a blue channel that does not exist points
		// every normal into the surface. The shell shader learned this the
		// expensive way - it zeroed N.L on every light in the room.
		vec2 nxy = (texture(normal_tex, uv).rg * 2.0 - 1.0) * normal_scale;
		vec3 tn = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
		n = normalize(mat3(v_world_tangent, v_world_binormal, v_world_normal) * tn);
	}

	// Where the fragment sits in the room's volume, and whether it is in it at
	// all. `inside` goes to 0 across the last texel rather than at the boundary,
	// so a prop carried out of the room fades to the fallback instead of popping.
	vec3 uvw = (v_world_pos - gi_min) / gi_size;
	// The fade band is a fixed DISTANCE, not a fraction of the volume. `* 8.0`
	// made it an eighth of the room - 0.6 m in the bedroom, where every prop
	// stands well clear of the walls, but 1.35 m in the arcade, wide enough that
	// the walls themselves sat inside it and rendered as 70% of `outside_light`,
	// a constant that has nothing to do with the room they are in. Measured: the
	// arcade's walls came out about half the brightness of the desktop path.
	vec3 slack = clamp(min(uvw, vec3(1.0) - uvw) * gi_size / GI_FADE_METRES,
		vec3(0.0), vec3(1.0));
	float inside = min(min(slack.x, slack.y), slack.z);

	vec3 c = clamp(uvw, vec3(0.0), vec3(1.0));
	vec4 dr = texture(gi_dir, c);
	vec3 l = normalize(dr.rgb * 2.0 - 1.0);
	float ndl = clamp((dot(n, l) + diffuse_wrap) / (1.0 + diffuse_wrap), 0.0, 1.0);
	vec3 irr = texture(gi_irr, c).rgb * gi_tint;
	vec3 lit = irr * mix(1.0, ndl, dr.a);

	vec3 light = mix(outside_light, lit, inside);
	vec3 colour = albedo * light;
	if (metallic > 0.0) {
		// A metal mirrors the room instead of scattering into it. No probe or
		// cube map here: the volume's dominant light direction stands in for
		// the bright part of the room (a highlight that tightens with
		// smoothness) and the irradiance for the rest. Per-eye VIEW, so the
		// highlight sits right in each eye.
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 r = reflect(-v, n);
		float gloss = 1.0 - roughness;
		float power = exp2(10.0 * gloss + 1.0);
		float lobe = pow(max(dot(r, l), 0.0), power) * (power + 2.0) * 0.125 * dr.a;
		// A broad sheen around the highlight, so a curved metal shows its form.
		float sheen = pow(max(dot(r, l), 0.0), max(power * 0.0625, 1.0)) * dr.a;
		// The room a ray sees is lighter above (walls, ceiling, the lamp) than
		// below (floor, furniture tops): a flat constant made the knob a disc.
		float sky = mix(METAL_FLOOR, METAL_CEILING, smoothstep(-0.7, 0.8, r.y));
		vec3 room = mix(outside_light, irr, inside);
		vec3 fresnel = mix(albedo, vec3(1.0), pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0));
		vec3 mirror = fresnel * room
			* (METAL_ROOM_ALBEDO * (sky + sheen) + min(lobe, METAL_HIGHLIGHT_MAX));
		colour = mix(colour, mirror, metallic);
	}
	vec3 emission = emission_color * emission_energy;
	if (has_emission_tex) {
		emission *= texture(emission_tex, uv).rgb;
	}

	ALBEDO = colour + emission;
	// Opaque props must not write ALPHA: even 1.0 selects the transparent pass
	// and depth_draw_opaque then stops writing depth.
}
