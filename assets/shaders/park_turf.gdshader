shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Park turf: the playing surface of a suburban oval, which isn't mown in
// bands the way a stadium's is (playtest 2026-10-30: "its grass is in
// strips; make it look more like a normal park: no lines, a bit of
// texture"). OvalEnvironment puts this on the Blender grass's Turf_Oval in
// place of its two stripe materials, and feeds it their colours: the
// darker and lighter of the pair become the two ends of a slow drift of
// worn and lush patches, with a fine grain on top. A stadium keeps its
// stripes (OvalEnvironment.turf_stripes).
//
// All from world position, like turf.gdshader, whose noise and filtering
// this reuses unchanged — see its header for why each octave fades out by
// its own screen footprint and why the lattices are rotated.

uniform vec3 turf_dark : source_color = vec3(0.31, 0.45, 0.26);
uniform vec3 turf_light : source_color = vec3(0.37, 0.52, 0.31);
/// Metres across the widest worn/lush patch.
uniform float patch_scale = 16.0;
/// How far a patch swings between turf_dark and turf_light.
uniform float patch_strength : hint_range(0.0, 1.0) = 0.7;
/// Metres across the coarsest grain octave: clumps of grass, not patches.
uniform float grain_scale = 0.8;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.09;
uniform float turf_roughness : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float detail_fade(float period, float footprint) {
	return 1.0 - smoothstep(period * 0.25, period * 5.0, footprint);
}

vec2 rotated(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat2(vec2(c, -s), vec2(s, c)) * p;
}

float variation(vec2 p, float period, float footprint) {
	float total = 0.0;
	float amplitude = 1.0;
	float normalisation = 0.0;
	for (int i = 0; i < 3; i++) {
		total += (value_noise(p / period) - 0.5) * amplitude * detail_fade(period, footprint);
		normalisation += amplitude;
		p = rotated(p, 1.71);
		period /= 2.17;
		amplitude *= 0.55;
	}
	return total / max(normalisation, 0.0001);
}

void fragment() {
	float footprint = max(length(vec2(dFdx(world_pos.x), dFdy(world_pos.x))),
		length(vec2(dFdx(world_pos.z), dFdy(world_pos.z))));
	// Patches: 0.5 is the midpoint between the two turf colours, so with
	// the fine octaves faded at a distance the far field settles on an even
	// mid-green rather than a stripe of either.
	float patches = 0.5 + variation(rotated(world_pos.xz, 0.41), patch_scale, footprint) * 2.0 * patch_strength;
	vec3 base = mix(turf_dark, turf_light, clamp(patches, 0.0, 1.0));
	float grain = variation(rotated(world_pos.xz, 2.3), grain_scale, footprint);
	ALBEDO = clamp(base * (1.0 + grain * 2.0 * grain_strength), vec3(0.0), vec3(1.0));
	ROUGHNESS = turf_roughness;
	SPECULAR = 0.1;
}
