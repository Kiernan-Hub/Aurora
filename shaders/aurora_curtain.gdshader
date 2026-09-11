shader_type canvas_item;
render_mode unshaded, blend_add;

// The director supplies time: pausing must freeze folds as well as the reveal.
// Reuse the baked hem/rays; one displaced texture lookup, no extra fullscreen pass.
uniform float event_elapsed = 0.0;
uniform float band_phase = 0.0;
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
varying vec4 curtain_tint;

void vertex() {
	// Fragment COLOR already includes the unwarped texture. Keep the raw tint here
	// so sampling the displaced texture doesn't multiply the bake into itself twice.
	curtain_tint = COLOR;
}

void fragment() {
	float phase = UV.x * 19.0 + band_phase;
	float fold = sin(phase + event_elapsed * 0.19);
	float secondary = sin(UV.x * 37.0 - event_elapsed * 0.13 + band_phase);
	vec2 displaced = UV + vec2(
		0.014 * sin(phase * 0.7 + event_elapsed * 0.11 + UV.y * 2.0),
		0.035 * fold + 0.018 * secondary
	);
	vec4 curtain = texture(TEXTURE, clamp(displaced, vec2(0.0), vec2(1.0)));
	// Feather the texture boundary instead of stretching its last row during warp.
	float texture_edge = smoothstep(0.0, 0.035, displaced.y)
		* (1.0 - smoothstep(0.965, 1.0, displaced.y));
	// Arrival belongs to the viewport, not the overscanned/drifting texture UV.
	// At the endpoints the frontier is entirely beyond the screen.
	float frontier = mix(1.16, -0.16, reveal_progress);
	float scallop = 0.025 * sin(SCREEN_UV.y * 24.0 + band_phase);
	float reveal = smoothstep(frontier - 0.09, frontier + 0.09,
		SCREEN_UV.x + scallop);
	COLOR = curtain * curtain_tint;
	COLOR.a *= texture_edge * reveal;
}
