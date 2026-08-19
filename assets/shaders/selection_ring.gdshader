shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The ring the previewed player stands inside. Drawn on one flat quad
// from UV distance rather than as ring geometry, so the bright inner
// edge and the soft outer bloom are the same primitive at two falloffs
// and neither needs its own mesh.
//
// blend_mix, not blend_add. Additive made sense when this sat on a
// near-black pitch: the ring was light cast on dark turf, and adding was
// how it read. The studio is a bright overcast box now, and adding to an
// already-pale ground does almost nothing — a cyan ring at these gains
// simply vanished against lit grass. Mixing paints the ring on instead,
// which holds at any ground brightness, and it means the colour on screen
// is the colour in `ring_colour` rather than whatever it happened to sum
// to.
//
// Recoloured to the Soft Brutalist accent green for the same reason the
// rest of the screen moved: an electric cyan was the one hue in the app
// that belonged to no palette.

uniform vec3 ring_colour : source_color = vec3(0.306, 0.624, 0.357);
/// Radius in UV space; 0.5 would touch the edge of the quad.
uniform float radius : hint_range(0.0, 0.5) = 0.41;
uniform float edge_width : hint_range(0.001, 0.05) = 0.006;
uniform float edge_gain : hint_range(0.0, 2.0) = 0.85;
uniform float glow_width : hint_range(0.005, 0.3) = 0.045;
uniform float glow_gain : hint_range(0.0, 2.0) = 0.3;
/// Fades the whole thing out before it reaches the quad's edge, so the
/// quad's own square boundary can never show.
uniform float cutoff : hint_range(0.0, 0.5) = 0.49;

void fragment() {
	float from_centre = length(UV - vec2(0.5));
	float d = abs(from_centre - radius);

	float edge = 1.0 - smoothstep(0.0, edge_width, d);
	float glow = exp(-d / glow_width) * glow_gain;
	float mask = 1.0 - smoothstep(cutoff - 0.08, cutoff, from_centre);

	ALBEDO = ring_colour;
	// Coverage, not brightness, now that the ring is mixed rather than
	// added — the two falloffs stack into one alpha and the colour stays
	// put. Clamped because edge and glow overlap at the ring itself.
	ALPHA = clamp(edge * edge_gain + glow, 0.0, 1.0) * mask;
}
