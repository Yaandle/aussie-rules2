shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Turf, mowing bands and the surrounds, all from world position on one
// flat plane. Doing it analytically means the ground is a single quad
// with no texture asset and no UV layout, which is the right trade while
// the project has no art pipeline yet (design doc §9). Swap this for
// real ground textures whenever those arrive; nothing depends on it.

uniform vec3 turf_a : source_color = vec3(0.302, 0.560, 0.243);
uniform vec3 turf_b : source_color = vec3(0.354, 0.631, 0.271);
uniform vec3 apron : source_color = vec3(0.55, 0.33, 0.22);
uniform vec3 surround : source_color = vec3(0.235, 0.360, 0.196);
uniform float half_length = 82.5;
uniform float half_width = 67.5;
uniform float stripe_width = 9.0;
// Ring width (m, roughly — the ellipse offset is a scale, not a true
// constant-width offset, close enough at this stylisation) of the
// running-track apron between the playing surface and the outer park.
uniform float apron_width = 6.0;
uniform float speckle : hint_range(0.0, 0.3) = 0.045;
uniform float turf_roughness : hint_range(0.0, 1.0) = 0.82;

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
	float inside_oval = 1.0 - smoothstep(0.998, 1.002, length(normalised));

	vec2 normalised_apron = vec2(world_pos.x / (half_length + apron_width),
		world_pos.z / (half_width + apron_width));
	float inside_apron = 1.0 - smoothstep(0.998, 1.002, length(normalised_apron));

	float band = step(0.5, fract(world_pos.x / (stripe_width * 2.0)));
	vec3 playing_turf = mix(turf_a, turf_b, band);

	// Layered outside-in: park grass, then the running-track apron ring,
	// then the striped playing surface — a stadium reads as "oval" partly
	// because the boundary isn't just a painted line, it's a material
	// change (grass -> track -> grass).
	vec3 base = mix(surround, apron, inside_apron);
	base = mix(base, playing_turf, inside_oval);

	float grain = value_noise(world_pos.xz * 2.7) - 0.5;
	ALBEDO = clamp(base + grain * speckle, vec3(0.0), vec3(1.0));
	ROUGHNESS = turf_roughness;
	SPECULAR = 0.15;
}
