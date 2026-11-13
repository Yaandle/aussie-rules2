shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Build 7's kit: the whole player is one mesh with one material, and this
// colours it. Each face carries a kit slot as the integer part of its UV2.x
// (SLOTS in tools/blender/build_7thbuild_mesh.py: keep the SLOT_* numbers
// below in step with it). The colours are per-instance parameters, which
// HumanoidRig._apply_kit_shader sets from the player's kit, so every
// player shares this one material and still wears their own team's
// colours, hair and number. A player is one draw (and one shadow draw per
// cascade) instead of the first Build 7's ten.
//
// The number: the guernsey faces on the back carry a planar projection of
// the number box in their UV (0..1, u from the viewer's left), and the
// digits are drawn here from outlines, as a signed distance, so they're
// crisp at any size without a texture. They fade out once a stroke is
// under about two pixels, where they'd only shimmer.

const int SLOT_SKIN = 0;
const int SLOT_JERSEY = 1;
const int SLOT_NUMBER = 2;
const int SLOT_TRIM = 3;
const int SLOT_SHORTS = 4;
const int SLOT_SOCKS = 5;
const int SLOT_BOOT = 6;
const int SLOT_SOLE = 7;
const int SLOT_STUDS = 8;
const int SLOT_HAIR = 9;
const int SLOT_EYES = 10;
const int SLOT_MOUTH = 11;

instance uniform vec4 kit_jersey : source_color = vec4(0.86, 0.72, 0.30, 1.0);
instance uniform vec4 kit_shorts : source_color = vec4(0.12, 0.12, 0.14, 1.0);
instance uniform vec4 kit_socks : source_color = vec4(0.86, 0.72, 0.30, 1.0);
instance uniform vec4 kit_boot : source_color = vec4(0.10, 0.10, 0.11, 1.0);
/// The model's own tone unless the kit names one (HumanoidRig.kit_skin).
instance uniform vec4 kit_skin : source_color = vec4(0.80, 0.56, 0.40, 1.0);
/// Collar and number: contrasting with the jersey (HumanoidRig._resolved_kit).
instance uniform vec4 kit_trim : source_color = vec4(0.94, 0.92, 0.86, 1.0);
instance uniform vec4 kit_hair : source_color = vec4(0.13, 0.09, 0.06, 1.0);
/// The guernsey number, 0-99.
instance uniform int kit_number = 17;

/// The number box's width over its height: NUMBER_SIZE in the generator.
const float NUMBER_BOX_ASPECT = 1.3846;
/// A digit cell's width (its height is 1) and the gap between two digits.
const float DIGIT_W = 0.62;
const float DIGIT_GAP = 0.12;

// Chamfered block numerals: each digit is closed outlines (its outside,
// then any counters) in a DIGIT_W x 1 cell, y up, as edges (x0, y0, x1, y1).
// Made by a script from point lists; any edit keeps every outline closed.
const vec4 EDGES[151] = {
	// 0
	vec4(0.09, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.91), vec4(0.62, 0.91, 0.53, 1.00), vec4(0.53, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.09), vec4(0.00, 0.09, 0.09, 0.00), vec4(0.24, 0.20, 0.38, 0.20), vec4(0.38, 0.20, 0.42, 0.24), vec4(0.42, 0.24, 0.42, 0.76), vec4(0.42, 0.76, 0.38, 0.80), vec4(0.38, 0.80, 0.24, 0.80), vec4(0.24, 0.80, 0.20, 0.76), vec4(0.20, 0.76, 0.20, 0.24), vec4(0.20, 0.24, 0.24, 0.20),
	// 1
	vec4(0.24, 0.00, 0.44, 0.00), vec4(0.44, 0.00, 0.44, 1.00), vec4(0.44, 1.00, 0.28, 1.00), vec4(0.28, 1.00, 0.10, 0.84), vec4(0.10, 0.84, 0.10, 0.70), vec4(0.10, 0.70, 0.24, 0.80), vec4(0.24, 0.80, 0.24, 0.00),
	// 2
	vec4(0.09, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.20), vec4(0.62, 0.20, 0.20, 0.20), vec4(0.20, 0.20, 0.20, 0.40), vec4(0.20, 0.40, 0.53, 0.40), vec4(0.53, 0.40, 0.62, 0.49), vec4(0.62, 0.49, 0.62, 0.91), vec4(0.62, 0.91, 0.53, 1.00), vec4(0.53, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.80), vec4(0.00, 0.80, 0.42, 0.80), vec4(0.42, 0.80, 0.42, 0.60), vec4(0.42, 0.60, 0.09, 0.60), vec4(0.09, 0.60, 0.00, 0.51), vec4(0.00, 0.51, 0.00, 0.09), vec4(0.00, 0.09, 0.09, 0.00),
	// 3
	vec4(0.09, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.91), vec4(0.62, 0.91, 0.53, 1.00), vec4(0.53, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.80), vec4(0.00, 0.80, 0.42, 0.80), vec4(0.42, 0.80, 0.42, 0.60), vec4(0.42, 0.60, 0.16, 0.60), vec4(0.16, 0.60, 0.16, 0.40), vec4(0.16, 0.40, 0.42, 0.40), vec4(0.42, 0.40, 0.42, 0.20), vec4(0.42, 0.20, 0.00, 0.20), vec4(0.00, 0.20, 0.00, 0.09), vec4(0.00, 0.09, 0.09, 0.00),
	// 4
	vec4(0.38, 0.00, 0.58, 0.00), vec4(0.58, 0.00, 0.58, 0.28), vec4(0.58, 0.28, 0.62, 0.28), vec4(0.62, 0.28, 0.62, 0.48), vec4(0.62, 0.48, 0.58, 0.48), vec4(0.58, 0.48, 0.58, 1.00), vec4(0.58, 1.00, 0.38, 1.00), vec4(0.38, 1.00, 0.38, 0.48), vec4(0.38, 0.48, 0.20, 0.48), vec4(0.20, 0.48, 0.20, 1.00), vec4(0.20, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.37), vec4(0.00, 0.37, 0.09, 0.28), vec4(0.09, 0.28, 0.38, 0.28), vec4(0.38, 0.28, 0.38, 0.00),
	// 5
	vec4(0.09, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.51), vec4(0.62, 0.51, 0.53, 0.60), vec4(0.53, 0.60, 0.20, 0.60), vec4(0.20, 0.60, 0.20, 0.80), vec4(0.20, 0.80, 0.62, 0.80), vec4(0.62, 0.80, 0.62, 1.00), vec4(0.62, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.40), vec4(0.00, 0.40, 0.42, 0.40), vec4(0.42, 0.40, 0.42, 0.20), vec4(0.42, 0.20, 0.00, 0.20), vec4(0.00, 0.20, 0.00, 0.09), vec4(0.00, 0.09, 0.09, 0.00),
	// 6
	vec4(0.09, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.51), vec4(0.62, 0.51, 0.53, 0.60), vec4(0.53, 0.60, 0.20, 0.60), vec4(0.20, 0.60, 0.20, 0.80), vec4(0.20, 0.80, 0.62, 0.80), vec4(0.62, 0.80, 0.62, 1.00), vec4(0.62, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.09), vec4(0.00, 0.09, 0.09, 0.00), vec4(0.20, 0.20, 0.42, 0.20), vec4(0.42, 0.20, 0.42, 0.40), vec4(0.42, 0.40, 0.20, 0.40), vec4(0.20, 0.40, 0.20, 0.20),
	// 7
	vec4(0.14, 0.00, 0.36, 0.00), vec4(0.36, 0.00, 0.62, 0.91), vec4(0.62, 0.91, 0.53, 1.00), vec4(0.53, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.80), vec4(0.00, 0.80, 0.36, 0.80), vec4(0.36, 0.80, 0.14, 0.00),
	// 8
	vec4(0.09, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.46), vec4(0.62, 0.46, 0.58, 0.50), vec4(0.58, 0.50, 0.62, 0.54), vec4(0.62, 0.54, 0.62, 0.91), vec4(0.62, 0.91, 0.53, 1.00), vec4(0.53, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.54), vec4(0.00, 0.54, 0.04, 0.50), vec4(0.04, 0.50, 0.00, 0.46), vec4(0.00, 0.46, 0.00, 0.09), vec4(0.00, 0.09, 0.09, 0.00), vec4(0.20, 0.20, 0.42, 0.20), vec4(0.42, 0.20, 0.42, 0.40), vec4(0.42, 0.40, 0.20, 0.40), vec4(0.20, 0.40, 0.20, 0.20), vec4(0.20, 0.60, 0.42, 0.60), vec4(0.42, 0.60, 0.42, 0.80), vec4(0.42, 0.80, 0.20, 0.80), vec4(0.20, 0.80, 0.20, 0.60),
	// 9
	vec4(0.53, 1.00, 0.09, 1.00), vec4(0.09, 1.00, 0.00, 0.91), vec4(0.00, 0.91, 0.00, 0.49), vec4(0.00, 0.49, 0.09, 0.40), vec4(0.09, 0.40, 0.42, 0.40), vec4(0.42, 0.40, 0.42, 0.20), vec4(0.42, 0.20, 0.00, 0.20), vec4(0.00, 0.20, 0.00, 0.00), vec4(0.00, 0.00, 0.53, 0.00), vec4(0.53, 0.00, 0.62, 0.09), vec4(0.62, 0.09, 0.62, 0.91), vec4(0.62, 0.91, 0.53, 1.00), vec4(0.42, 0.80, 0.20, 0.80), vec4(0.20, 0.80, 0.20, 0.60), vec4(0.20, 0.60, 0.42, 0.60), vec4(0.42, 0.60, 0.42, 0.80)
};
const int DIGIT_START[11] = {0, 16, 23, 41, 57, 73, 89, 105, 113, 135, 151};

varying flat int v_slot;

void vertex() {
	v_slot = int(UV2.x);
}

/// Signed distance from p (cell units) to digit d: negative inside.
float digit_distance(int d, vec2 p) {
	float best = 1e3;
	bool inside = false;
	for (int i = DIGIT_START[d]; i < DIGIT_START[d + 1]; i++) {
		vec4 e = EDGES[i];
		vec2 a = e.xy;
		vec2 ba = e.zw - a;
		vec2 pa = p - a;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		best = min(best, length(pa - ba * h));
		if ((a.y > p.y) != (e.w > p.y) && p.x < a.x + (p.y - a.y) * ba.x / ba.y) {
			inside = !inside;
		}
	}
	return inside ? -best : best;
}

/// How much of this pixel the number covers, 0..1. uv spans the number
/// box; two digits sit side by side, one digit is centred. duv is
/// fwidth(UV), taken before any branch on the slot (derivatives inside
/// divergent control flow aren't defined).
float number_coverage(vec2 uv, vec2 duv, int number) {
	int n = clamp(number, 0, 99);
	// Box units: the box is 1 high and NUMBER_BOX_ASPECT wide.
	vec2 p = vec2(uv.x * NUMBER_BOX_ASPECT, uv.y);
	float width = n >= 10 ? DIGIT_W * 2.0 + DIGIT_GAP : DIGIT_W;
	float x0 = (NUMBER_BOX_ASPECT - width) * 0.5;
	float sd;
	if (n >= 10) {
		float split = x0 + DIGIT_W + DIGIT_GAP * 0.5;
		bool second = p.x >= split;
		vec2 q = p - vec2(second ? x0 + DIGIT_W + DIGIT_GAP : x0, 0.0);
		sd = digit_distance(second ? n % 10 : n / 10, q);
	} else {
		sd = digit_distance(n, p - vec2(x0, 0.0));
	}
	float px = max(length(duv * vec2(NUMBER_BOX_ASPECT, 1.0)), 1e-5);
	float cover = clamp(0.5 - sd / px, 0.0, 1.0);
	// Strokes are 0.2 high: once that's under ~2 px the digits only shimmer.
	return cover * (1.0 - smoothstep(0.07, 0.14, px));
}

void fragment() {
	vec2 duv = fwidth(UV);
	vec3 c = kit_skin.rgb;
	float rough = 0.62;
	if (v_slot == SLOT_JERSEY) {
		c = kit_jersey.rgb;
		rough = 0.84;
	} else if (v_slot == SLOT_NUMBER) {
		// glTF's V runs top-down, Blender's (and the box's) bottom-up.
		vec2 box = vec2(UV.x, 1.0 - UV.y);
		c = mix(kit_jersey.rgb, kit_trim.rgb, number_coverage(box, duv, kit_number));
		rough = 0.84;
	} else if (v_slot == SLOT_TRIM) {
		c = kit_trim.rgb;
		rough = 0.8;
	} else if (v_slot == SLOT_SHORTS) {
		c = kit_shorts.rgb;
		rough = 0.78;
	} else if (v_slot == SLOT_SOCKS) {
		c = kit_socks.rgb;
		rough = 0.9;
	} else if (v_slot == SLOT_BOOT) {
		c = kit_boot.rgb;
		rough = 0.45;
	} else if (v_slot == SLOT_SOLE) {
		// A sole a shade off the boot: dark under a dark boot, grey under a
		// white one, never the bright fleck a fixed light sole was.
		c = mix(kit_boot.rgb, vec3(0.02), 0.6);
		rough = 0.7;
	} else if (v_slot == SLOT_STUDS) {
		c = vec3(0.32);
		rough = 0.5;
	} else if (v_slot == SLOT_HAIR) {
		c = kit_hair.rgb;
		rough = 0.85;
	} else if (v_slot == SLOT_EYES) {
		c = vec3(0.025, 0.025, 0.03);
		rough = 0.35;
	} else if (v_slot == SLOT_MOUTH) {
		c = kit_skin.rgb * vec3(0.62, 0.52, 0.5);
		rough = 0.6;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
