shader_type canvas_item;

/// Menu mode-card artwork: clips the photo to a rounded rect (StyleBoxFlat's
/// own border sits exactly on top, so the two need to agree on `radius`) and
/// blends between a muted, tinted greyscale ("not selected") and the full
/// photo ("selected/hovered") via `saturation`, animated from main_menu.gd
/// through SoftBrutalist-style Tweens rather than snapping instantly.

uniform sampler2D image : source_color, filter_linear;
uniform vec2 rect_size = vec2(400.0, 300.0);
uniform vec2 image_size = vec2(400.0, 300.0);   // source pixel size, for the cover-crop below
uniform float radius = 14.0;
uniform float saturation : hint_range(0.0, 1.0) = 0.0;
uniform vec4 muted_tint : source_color = vec4(0.145, 0.176, 0.157, 1.0);
uniform float dim : hint_range(0.0, 1.0) = 0.35;   // how much the grey state darkens vs. the full photo

float rounded_box_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * rect_size;
	float dist = rounded_box_sdf(px - rect_size * 0.5, rect_size * 0.5, radius);
	float mask = 1.0 - smoothstep(-1.0, 1.0, dist);

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
	float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 muted = mix(vec3(grey), muted_tint.rgb, 0.55) * (1.0 - dim);
	vec3 shown = mix(muted, tex.rgb, saturation);

	COLOR = vec4(shown, tex.a * mask);
}
