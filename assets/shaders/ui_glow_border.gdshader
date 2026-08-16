shader_type canvas_item;

// A soft glowing rounded-rect outline, traced at `border_size` (px),
// centred in the node's own rect. `node_size` must match the node's actual
// size in the .tscn (canvas_item shaders have no automatic way to read it)
// and must exceed `border_size` on every side by more than `glow_radius`,
// or the glow gets clipped by the node's own bounds instead of fading out.

uniform vec2 node_size = vec2(1272.0, 709.0);
uniform vec2 border_size = vec2(1152.0, 589.0);
uniform float corner_radius : hint_range(0.0, 120.0) = 18.0;
uniform float line_width : hint_range(0.5, 12.0) = 2.0;
uniform float glow_radius : hint_range(1.0, 140.0) = 14.0;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.4;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);

float sd_rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 px = (UV - 0.5) * node_size;
	float d = sd_rounded_box(px, border_size * 0.5, corner_radius);

	float line = 1.0 - smoothstep(line_width * 0.5, line_width * 0.5 + 1.5, abs(d));
	float glow = exp(-max(abs(d) - line_width * 0.5, 0.0) / glow_radius) * glow_strength;

	float alpha = clamp(line + glow, 0.0, 1.0);
	COLOR = vec4(glow_color.rgb, alpha * glow_color.a);
}
