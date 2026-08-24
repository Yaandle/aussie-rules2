shader_type canvas_item;

/// Menu mode-card artwork: clips the photo to a rounded rect (StyleBoxFlat's
/// own border sits exactly on top, so the two need to agree on `radius`) and
/// blends between a muted, tinted greyscale ("not selected") and the full
/// photo ("selected/hovered") via `saturation`, animated from main_menu.gd
/// through SoftBrutalist-style Tweens rather than snapping instantly.
///
/// The bottom-of-card darkening that the title/subtitle text sits on is
/// computed here too, rather than as a separate scrim TextureRect layered
/// on top — a plain rectangular overlay doesn't know about `radius` and
/// its square corners poke out past the photo's rounded ones.

uniform sampler2D image : source_color, filter_linear;
uniform vec2 rect_size = vec2(400.0, 300.0);
uniform vec2 image_size = vec2(400.0, 300.0);   // source pixel size, for the cover-crop below
uniform float radius = 14.0;
uniform float saturation : hint_range(0.0, 1.0) = 0.0;
// The colour an unselected card settles toward. Light, not dark: the
// screen is a cream page, and a card that mutes by going near-black is
// the heaviest object on it — the opposite of the calm, airy read the
// design is after.
uniform vec4 muted_tint : source_color = vec4(0.82, 0.83, 0.80, 1.0);
// How far the muted state travels toward that tint. Doubles as the
// hierarchy between "not selected" and "locked": further along the ramp
// is flatter and quieter, without either state being dark.
uniform float dim : hint_range(0.0, 1.0) = 0.35;

float rounded_box_sdf(vec2 p, vec2 half_size, float r) {
	r = min(r, min(half_size.x, half_size.y));
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float dither(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

// Mirrors the 3-stop gradient main_menu.gd's old _bottom_scrim_texture()
// built (offsets 0.3/0.62/1.0, alpha 0/0.22/0.62): transparent through the
// top ~30%, then two linear ramps down to 62% black at the bottom edge.
float bottom_scrim(float uv_y) {
	if (uv_y < 0.3) {
		return 0.0;
	} else if (uv_y < 0.62) {
		return mix(0.0, 0.22, (uv_y - 0.3) / (0.62 - 0.3));
	}
	return mix(0.22, 0.62, (uv_y - 0.62) / (1.0 - 0.62));
}

void fragment() {
	vec2 px = UV * rect_size;
	float dist = rounded_box_sdf(px - rect_size * 0.5, rect_size * 0.5, radius);
	// Feathered over one *screen* pixel rather than one card pixel. The
	// card is scaled up when selected and the whole canvas is scaled by
	// the project's `canvas_items` stretch, so a fixed +/-1.0 band is a
	// different width on screen in each of those states — visibly softer
	// on a scaled-up card, and aliased on a window smaller than the
	// design size. fwidth() is that band measured after both transforms.
	float aa = max(fwidth(dist), 0.0001);
	float mask = 1.0 - smoothstep(-aa, aa, dist);

	// Cover-crop (CSS background-size:cover): scale the source image up
	// just enough that it fills rect_size on both axes, centred, cropping
	// whichever axis overflows — source art isn't pre-cropped to the
	// card's aspect ratio, so sampling raw UV would stretch it.
	vec2 cover_scale = max(rect_size / image_size, vec2(0.0001));
	float scale = max(cover_scale.x, cover_scale.y);
	vec2 scaled_image = image_size * scale;
	vec2 offset = (scaled_image - rect_size) * 0.5;
	vec2 cover_uv = (px + offset) / scaled_image;

	vec4 tex = texture(image, cover_uv);
	// Rec.709 luma rather than the older Rec.601 weights: the artwork is
	// sRGB, and 601 renders greens too dark, which on a set of cards that
	// are mostly grass reads as three muddy tiles.
	float grey = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 muted = mix(vec3(grey), muted_tint.rgb, dim);
	vec3 shown = mix(muted, tex.rgb, saturation);

	shown = mix(shown, vec3(0.0), bottom_scrim(UV.y));

	// The muted state is a near-flat tinted grey over a large area, which
	// is where 8-bit quantisation shows as blotchy contours in the
	// artwork's smooth regions.
	shown += dither(FRAGCOORD.xy) / 255.0;

	COLOR = vec4(shown, tex.a * mask);
}
