shader_type canvas_item;

// The ice band's shader, and the ONLY shader in this project. It exists for the three things
// vertex colours provably cannot do; everything they CAN do still rides vertex_colors, exactly
// as biomes.md's "Why colour is still not a shader's job" describes. Do not grow this remit.
//
//   1. Cross-dissolve two ice tiles on a noise mask (replaces the second, alpha-faded
//      second Polygon2D that used to exist per ground run -- one node fewer, and a
//      patchy dissolve instead of a uniform fade).
//   2. Contrast against the tile, independent of hue.
//   3. A gloss/sheen uniform, parameterised and left at 0 for a later flat-lake biome.
//
// EVERY UNIFORM'S DEFAULT IS AN EXACT IDENTITY. At overlay_weight 0 / contrast 1 /
// gloss_strength 0 this renders pixel-identical to the no-material Polygon2D it replaced --
// max delta 0/255 over 9 bands at each of three world positions, measured by swapping the
// material in place inside a single frozen frame (comparing two separate RUNS is not sound
// here; see docs/research/ice_shader_color_semantics.md). Each mix() below is written so its
// default argument is literally 0.0 or 1.0, because GLSL mix(a, b, 0.0) returns `a` exactly
// rather than approximately.
//
// -------------------------------------------------------------------------------------------
// THE TRAP THIS FILE WAS BORN FROM (2026-08-10). In a canvas_item shader COLOR is IN-OUT, and
// on entry to fragment() it ALREADY holds `vertex_color * texture(TEXTURE, UV)` -- the built-in
// code samples the texture for you before your fragment() runs. So the identity body is
// `COLOR = COLOR;` (or an empty fragment()), NOT
//
//     COLOR = texture(TEXTURE, UV) * COLOR;      // <-- WRONG, multiplies the tile in TWICE
//
// which is the 3D/ALBEDO convention and looks like the obvious no-op. It squares the texture.
// Squaring is a no-op at 1.0 and maximal at the dark end, and this tile's V axis is depth with
// a 1.0 -> ~0.38 ramp down it -- so the symptom is ice that looks right at the ride line and
// progressively too dark with depth. Measured: up to 55/255 too dark, and the darkening
// matched tex*tex to within 1/255. Nothing to do with colour spaces, render_mode or how
// Polygon2D feeds vertex_colors; all three were ruled out by measurement. No render_mode line
// is needed here -- blend_mix is already the default and there are no 2D lights in this project.
//
// Because of that in-out semantic, this shader cannot read the raw vertex tint in fragment():
// COLOR there is pre-multiplied by the tile. The tint is captured in vertex() instead, where
// COLOR is still the untouched interpolated vertex colour, and carried across in `ice_tint`.
// -------------------------------------------------------------------------------------------

varying vec4 ice_tint;

// The INCOMING tile during a biome transition. TEXTURE stays the node's own (outgoing) tile,
// which is also what makes Polygon2D normalise `uv` by the tile size -- the band writes uv in
// texture PIXELS, so a null node texture would feed raw pixel values through as UVs.
// Both tiles are the same size by gate (biome_schedule_check's EXPECTED_ICE_TILE_SIZE), which
// is what lets one set of UVs address both.
// repeat_enable/filter_linear restate the node's own texture_repeat + the project's default
// canvas filter; a uniform sampler does not inherit either from the CanvasItem.
uniform sampler2D overlay_tile : repeat_enable, filter_linear;

// 0 = base tile only, 1 = overlay tile only. Driven by the ice channel's crossfade weight.
uniform float overlay_weight : hint_range(0.0, 1.0) = 0.0;
// Width of the dissolve's soft edge, in mask units.
uniform float dissolve_softness : hint_range(0.02, 0.5) = 0.12;

// 1.0 = the tile untouched. Pushes the tile's own light/dark structure away from (>1) or
// toward (<1) a fixed pivot, WITHOUT touching hue -- the one thing the palette's
// ice_surface/ice_depth cannot express, since those are a hue ramp by contract (biomes.md).
uniform float contrast : hint_range(0.0, 2.0) = 1.0;

// Sheen for a later flat-lake biome. Left at 0; parameterised now so the band's geometry and
// UV contract do not have to be revisited then.
uniform float gloss_strength : hint_range(0.0, 1.0) = 0.0;
uniform float gloss_depth : hint_range(0.0, 1.0) = 0.16;
uniform float gloss_softness : hint_range(0.02, 1.0) = 0.12;

// Mid-point of the tile's own 1.0 -> ~0.38 depth ramp, so contrast pivots around roughly the
// tile's average value and does not read as a brightness change.
const float CONTRAST_PIVOT = 0.62;

// Contrast and gloss must both reach EXACTLY zero effect before the band's bottom row, because
// build_fill_vertex_colors()/get_deep_fill_color() hardcode that row as
// ICE_TILE_DEPTH_FLOOR * ice_depth_tint so the flat deep fill meets it without a seam. Anything
// that moved the bottom row would open a visible step across the whole world at ICE_BAND_DEPTH.
// Fading them out with depth is also the truer read: both are surface phenomena, the same
// argument that keeps the hue drift on the surface row only.
const float SURFACE_FADE_START = 0.55;
const float SURFACE_FADE_END = 0.95;

// The mask's lattice wraps on this period so the hash never sees a large coordinate. UV.x is
// world_x / ICE_TILE_WORLD_WIDTH and world_x is never rebased, so it grows without bound over a
// long session -- and fract()-based hashing loses its fractional bits entirely once the input
// gets big, which would degrade the mask into flat blocks late in a run. Wrapping the integer
// cell instead of the sample point keeps it seamless. The period is ~76 800 world px, longer
// than a whole biome (75 000), and a dissolve only lasts 12 000, so it can never read as a
// repeat.
const float MASK_PERIOD = 64.0;
// Cells per UV unit. UV.x is world_x / ICE_TILE_WORLD_WIDTH and UV.y spans ICE_BAND_DEPTH, so
// these work out at roughly 200 x 155 world px per cell -- about six patches across a ~1150px
// viewport. Measured, not guessed: at (3.0, 1.6) only ~3 cells covered the screen and the
// "dissolve" read as one screen-sized soft wipe, with 74% of pixels stuck mid-blend at weight
// 0.5 (i.e. barely distinguishable from the uniform alpha fade this replaced).
const vec2 MASK_SCALE = vec2(6.0, 2.2);

// THE MASK'S DISTRIBUTION IS LEFT ALONE ON PURPOSE. Two octaves of interpolated value noise are
// bell-shaped rather than uniform, so a threshold sweeping linearly through them dissolves
// 1/9/34/64/85/96% of the screen at weights 0.2..0.8 -- an S, not a straight line. Two attempts
// to flatten that into a linear progression were measured and both were worse:
//
//   * Widening the distribution about its median (clamped) linearised the numbers, but the
//     clamp gives every pixel in the flattened tails the SAME mask value, so ~20% of the screen
//     moved in lockstep at the end of the window -- a localised copy of the uniform fade this
//     whole change exists to remove.
//   * Easing the threshold sweep instead (monotone, no clamp, so no lockstep) only cut the mean
//     deviation from linear 0.137 -> 0.092, and bought that with a plateau across the middle
//     third where the dissolve visibly stalls (0.59 -> 0.64 -> 0.69 over weights 0.4..0.6).
//
// The S is also just correct: it eases the pattern change in and out, which is the same reason
// every channel in biome_director.gd is a smoothstep rather than a linear ramp -- a linear ramp
// has a corner at each end of the window and both corners are readable as events.


float hash21(vec2 cell) {
	vec2 p = fract(cell * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


// Value noise on a wrapped integer lattice, smoothstep-interpolated.
float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = point - cell;
	vec2 blend = f * f * (3.0 - 2.0 * f);
	vec2 c0 = mod(cell, MASK_PERIOD);
	vec2 c1 = mod(cell + 1.0, MASK_PERIOD);
	float a = hash21(c0);
	float b = hash21(vec2(c1.x, c0.y));
	float c = hash21(vec2(c0.x, c1.y));
	float d = hash21(c1);
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}


// Two octaves so the patches are not all one size. Kept cheap deliberately: this runs on every
// ice pixel, which is most of the lower half of the frame, on a Mobile-renderer target.
float dissolve_mask(vec2 uv) {
	vec2 point = uv * MASK_SCALE;
	return value_noise(point) * 0.65 + value_noise(point * 2.3 + 11.0) * 0.35;
}


void vertex() {
	// COLOR is still the raw interpolated vertex colour here. See the header.
	ice_tint = COLOR;
}


void fragment() {
	vec4 tile = texture(TEXTURE, UV);

	// Uniform-valued branch, so the whole draw takes one side of it -- outside a transition
	// (which is most of a run, and every headless frame) the overlay is never sampled at all.
	if (overlay_weight > 0.0) {
		float mask = dissolve_mask(UV);
		// Remapped so the threshold clears the mask's full range: at weight 0 nothing has
		// dissolved and at weight 1 everything has, both EXACTLY, whatever the softness.
		// Without the remap a soft edge would leave slivers of the outgoing tile at weight 1,
		// and the handoff to the next frame's weight-0-with-the-tile-already-swapped would pop.
		float edge = max(dissolve_softness, 0.001);
		float threshold = overlay_weight * (1.0 + 2.0 * edge) - edge;
		float blend = smoothstep(mask - edge, mask + edge, threshold);
		tile = mix(tile, texture(overlay_tile, UV), blend);
	}

	float surface_weight = 1.0 - smoothstep(SURFACE_FADE_START, SURFACE_FADE_END, UV.y);

	vec3 shaded = mix(vec3(CONTRAST_PIVOT), tile.rgb, 1.0 + (contrast - 1.0) * surface_weight);

	// max() guards the divide: the hint_range floor is only advisory, and a 0 pushed in through
	// set_shader_parameter() would put a NaN on every ice pixel in the world.
	float sheen = exp(-pow((UV.y - gloss_depth) / max(gloss_softness, 0.001), 2.0));
	shaded = mix(shaded, vec3(1.0), gloss_strength * sheen * surface_weight);

	// The multiply the built-in path does for free, done explicitly because `tile` is no longer
	// what TEXTURE holds. Alpha stays tile.a * tint.a, exactly as the built-in path had it.
	COLOR = vec4(clamp(shaded, 0.0, 1.0), tile.a) * ice_tint;
}
