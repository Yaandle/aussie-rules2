shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Turf, mowing bands and the surrounds, all from world position on one
// flat plane. Doing it analytically means the ground is a single quad
// with no texture asset and no UV layout, which is the right trade while
// the project has no art pipeline yet (design doc §9). Swap this for
// real ground textures whenever those arrive; nothing depends on it.

uniform vec3 turf_a : source_color = vec3(0.247, 0.420, 0.204);
uniform vec3 turf_b : source_color = vec3(0.278, 0.459, 0.227);
uniform vec3 surround : source_color = vec3(0.204, 0.278, 0.176);
uniform float half_length = 82.5;
uniform float half_width = 67.5;
uniform float stripe_width = 9.0;
uniform float speckle : hint_range(0.0, 0.3) = 0.05;
uniform float turf_roughness : hint_range(0.0, 1.0) = 0.88;

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
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 normalised = vec2(world_pos.x / half_length, world_pos.z / half_width);
	float inside = 1.0 - smoothstep(0.998, 1.002, length(normalised));

	float band = step(0.5, fract(world_pos.x / (stripe_width * 2.0)));
	vec3 base = mix(surround, mix(turf_a, turf_b, band), inside);

	float grain = value_noise(world_pos.xz * 2.7) - 0.5;
	ALBEDO = clamp(base + grain * speckle, vec3(0.0), vec3(1.0));
	ROUGHNESS = turf_roughness;
	SPECULAR = 0.15;
}
