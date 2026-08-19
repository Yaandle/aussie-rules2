shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Turf, mowing bands and the surrounds, all from world position on one
// flat plane. Doing it analytically means the ground is a single quad
// with no texture asset and no UV layout, which is the right trade while
// the project has no art pipeline yet (design doc §9). Swap this for
// real ground textures whenever those arrive; nothing depends on it.
//
// ── Filtering ───────────────────────────────────────────────────────
// The ground is one 285x255m quad seen from a metre off the deck, so a
// single frame spans pixel footprints from a few millimetres in the
// foreground to tens of metres at the horizon. There is no mipmap chain
// to lean on — every value here is evaluated per pixel — so both ends of
// that range have to be handled explicitly, and neither was:
//
//   Up close, `value_noise` used the cubic smoothstep fade, which is
//   continuous but its *derivative* is not at cell boundaries. Where one
//   0.37m noise cell covered a hundred-odd screen pixels, those
//   derivative breaks showed up as flat-shaded facets with dead straight
//   edges — visible as angular patches across the near turf. The quintic
//   fade below is C2 and removes them for the cost of two extra multiplies.
//
//   Far away, the same noise and the mowing bands were sampled well below
//   Nyquist and shimmered as the camera moved. Both now fade themselves
//   out as their own screen-space frequency approaches a pixel, using
//   fwidth() to measure it — the standard analytic-texture answer to
//   having no mip levels, and the reason this can afford fine detail at
//   all without crawling.

uniform vec3 turf_a : source_color = vec3(0.345, 0.478, 0.294);
uniform vec3 turf_b : source_color = vec3(0.392, 0.541, 0.341);
uniform vec3 apron : source_color = vec3(0.549, 0.427, 0.365);
uniform vec3 surround : source_color = vec3(0.310, 0.396, 0.271);
uniform float half_length = 82.5;
uniform float half_width = 67.5;
uniform float stripe_width = 9.0;
// Ring width (m, roughly — the ellipse offset is a scale, not a true
// constant-width offset, close enough at this stylisation) of the
// running-track apron between the playing surface and the outer park.
uniform float apron_width = 6.0;
/// Amplitude of the slow tonal drift across the ground — the difference
/// between turf that reads as a stylised surface and turf that reads as
/// one flat fill. Deliberately gentle: the brief's target is a stylised
/// pitch, and anything strong enough to notice as texture reads as noise.
uniform float patchiness : hint_range(0.0, 0.3) = 0.075;
/// Metres across the widest band of that drift.
uniform float patch_scale = 11.0;
/// How much the mown bands differ. Kept low on purpose: the bands are a
/// scale cue, and at full contrast a striped pitch is the loudest thing
/// in frame.
uniform float band_strength : hint_range(0.0, 1.0) = 0.85;
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
	// Quintic (6t^5 - 15t^4 + 10t^3), not the cubic smoothstep: this one
	// has a zero second derivative at the cell edges as well as a zero
	// first, so neighbouring cells meet without a shading crease.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// 1 where one cycle of a feature `period` metres across still covers
/// several pixels, falling to 0 as it approaches one pixel. `footprint`
/// is how many metres of world the current pixel spans.
///
/// The ramp is deliberately wide (a factor of ~20 from full detail to
/// none, not the factor of 4 it started at). `footprint` comes from
/// dFdx/dFdy, which the hardware evaluates once per 2x2 pixel quad, so it
/// is a step function at quad boundaries rather than a smooth field — and
/// on a ground plane under a camera with no yaw it is very nearly
/// constant along a screen row, which makes those steps line up into long
/// straight screen-aligned edges. A steep ramp turns a one-quad step in
/// footprint into a visible seam in the output; a shallow one divides the
/// same step by the width of the ramp and puts it under the quantisation
/// floor. This is why the near turf had a crisp rectangle in it.
float detail_fade(float period, float footprint) {
	return 1.0 - smoothstep(period * 0.25, period * 5.0, footprint);
}

/// Rotates the sample plane before the noise lattice is laid over it.
vec2 rotated(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat2(vec2(c, -s), vec2(s, c)) * p;
}

/// Three octaves of value noise, each rotated and scaled off the last.
///
/// One octave of value noise on its own is not usable here, and that is
/// what the turf had. Value noise interpolates a square lattice, so its
/// contours run along the grid however smooth the interpolant is — the
/// result reads as square blotches rather than as variation, and on a
/// ground plane a metre off the deck those cells project to 40-60px
/// screen blocks. Quintic smoothing fixes the creases between cells but
/// not the fact that the pattern is a grid.
///
/// Rotating each octave by an irrational-ish angle before scaling it is
/// the cheap fix: the three lattices never line up with each other or
/// with the world axes, so the sum has no readable grid left. The
/// lacunarity is 2.17 rather than a clean 2.0 for the same reason —
/// doubling would put every octave's cell corners on the same points.
///
/// Each octave fades itself out by its own feature size, so the fine ones
/// disappear into the distance instead of aliasing there — the same
/// footprint test a mip chain would be doing if this were a texture.
float turf_variation(vec2 p, float period, float footprint) {
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
	// How much ground this pixel covers, straight from the derivative of
	// the interpolated world position — small in the foreground, metres
	// at the horizon.
	float footprint = max(length(vec2(dFdx(world_pos.x), dFdy(world_pos.x))),
		length(vec2(dFdx(world_pos.z), dFdy(world_pos.z))));

	vec2 normalised = vec2(world_pos.x / half_length, world_pos.z / half_width);
	float oval = length(normalised);
	// Edge softness tracks the footprint too, so the boundary stays a
	// clean line up close and does not stair-step at a distance.
	float edge = max(0.004, footprint / half_width);
	float inside_oval = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, oval);

	vec2 normalised_apron = vec2(world_pos.x / (half_length + apron_width),
		world_pos.z / (half_width + apron_width));
	float inside_apron = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, length(normalised_apron));

	// Mown bands, as a softened square wave rather than step(): a hard
	// edge on a surface this large aliases into a moire the moment the
	// camera moves. The 0.06 is the band edge's own softness as a
	// fraction of a cycle; the fade takes the whole pattern out once a
	// full cycle no longer covers a pixel.
	float cycle = fract(world_pos.x / (stripe_width * 2.0));
	float wave = smoothstep(0.5 - 0.06, 0.5 + 0.06, cycle)
		- smoothstep(1.0 - 0.06, 1.0, cycle);
	float band = mix(0.5, wave, detail_fade(stripe_width * 2.0, footprint));
	vec3 playing_turf = mix(turf_a, turf_b, band * band_strength + (1.0 - band_strength) * 0.5);

	// Layered outside-in: park grass, then the running-track apron ring,
	// then the striped playing surface — a stadium reads as "oval" partly
	// because the boundary is not just a painted line, it is a material
	// change (grass -> track -> grass).
	vec3 base = mix(surround, apron, inside_apron);
	base = mix(base, playing_turf, inside_oval);

	// Applied as a brightness scale rather than an additive tint, so the
	// variation follows whichever surface it lands on — playing turf,
	// apron or park grass — instead of pushing all three toward the same
	// colour.
	float variation = turf_variation(rotated(world_pos.xz, 0.41), patch_scale, footprint);

	ALBEDO = clamp(base * (1.0 + variation * patchiness), vec3(0.0), vec3(1.0));
	ROUGHNESS = turf_roughness;
	SPECULAR = 0.1;
}
