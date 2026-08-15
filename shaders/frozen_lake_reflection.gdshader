shader_type canvas_item;

// THE FROZEN LAKE'S SURFACE. Not a mirror -- a painted sheet of ice that happens to carry a
// reflection near its shore. This is the project's second shader (shaders/ice.gdshader is the
// other) and its first screen-reading one.
//
// EVERYTHING HERE IS AUTHORED FROM ONE REFERENCE, "Glossy Frozen Lake.png" in the repo root,
// measured rather than eyeballed. Three earlier passes were built by eye and all three were
// wrong in the same way -- they assumed a mirror. What the reference actually contains, sampled
// column by column:
//
//   1. A SMOOTH VERTICAL GRADIENT, RGB(154,197,238) just under the shelf to RGB(86,123,173) at
//      the bottom of the frame. Monotonic. Note it is BRIGHTER than the sky at the horizon
//      (116,149,193) and about as bright as the sky overhead: the lake glows, it does not recede.
//   2. A 1:1 MIRROR, blurred and fading with depth. Column measurements show strong vertical
//      coherence -- at x=80 every row below the shore reads ~15 units darker than its own row
//      mean, at x=300 every row ~20 brighter -- and THAT COHERENCE IS THE MIRROR, because what
//      stands above the shore is tall pines and ridges. Reading it as a "smear" instead, and
//      building one, was the wrong turn of 2026-08-14: it turned the player into a stripe running
//      the height of the lake. The reflections in the reference are tree-SHAPED and about full
//      size. Compressing them is equally wrong for the same reason.
//   3. The reflection fades out with depth rather than being clipped: near the shore it is clear
//      enough to read as pines, by the bottom of the frame it is gone.
//   4. A BRIGHT SHELF at the waterline -- a BAND, not a line. It runs 3.6% of the frame height
//      (y 421-448 of 746), peaks at RGB(178,213,244), and is strongly irregular along its length:
//      luma sampled across it runs 201,196,190,209,213,220,240,254,254,251 and then drops to
//      ~150 where a mountain reaches the water. Modelling it as a thin rim, as this shader did
//      until 2026-08-15, throws away most of what makes the shore read as snow rather than as an
//      edge.
//   5. VERY FAINT HORIZONTAL BANDING across the sheet, +/-1 to 2.6 luma out of 255 -- an order of
//      magnitude subtler than it looks, and concentrated in the 61-71% band just below the shelf.
//      Overdo this and the ice reads as corrugated metal.
//
// ANY DETAIL THAT VARIES ALONG X MUST BE KEYED ON WORLD X, never on SCREEN_UV.x. The player is
// moving at up to 750 px/s: a pattern keyed on screen position would sit perfectly still while
// the world slid past underneath it, which reads as dirt on the lens rather than as ice.
//
// THE LAKE LOOKS THE SAME IN EVERY BIOME, by the owner's decision (2026-08-14). The sky, ridges
// and pines above the line are still the biome's -- and they are what the mirror reflects, so the
// lake picks up the biome's light without any palette value being applied to it. No ice tile
// reaches it at all.
//
// THE ITEM THIS RUNS ON IS ALWAYS A FULL-SCREEN RECT. Declaring hint_screen_texture makes the
// renderer insert a backbuffer copy sized from the item's rect, and rect-region copies are the
// known-buggy path on the Mobile renderer; a full-screen rect is the universally exercised case.
// So the top half is clipped HERE rather than by making the quad smaller.
//
// EVERYTHING IS IN SCREEN_UV, NOT UV. The item's own UVs are meaningless (it is an untextured
// rect). The waterline arrives as a screen fraction from lake_reflection.gd, which recomputes it
// every frame from the terrain's WORLD y -- so world rebasing and the camera's vertical follow
// are handled upstream and neither is visible here.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Where the ice surface is, as a fraction down the screen. Never used at its default: the real
// one is written every frame from the terrain, and main.gd's LAKE_HORIZON_FRACTION (0.56, the
// measurement off the full-size reference) is what actually puts the shore there.
uniform float waterline : hint_range(0.0, 1.0) = 0.56;

// How present the lake is: the director's entry/exit ramp, 0 off the sheet and 1 across the
// middle of a crossing. At 1 this surface is opaque and the terrain's own ice is not visible
// through it at all; the ramp is what keeps the handover at each shore from being an event.
uniform float lake_amount : hint_range(0.0, 1.0) = 1.0;

// The gradient's two ends, pushed from GDScript so TerrainGenerator's LAKE_ICE_SURFACE and
// LAKE_ICE_DEPTH stay the single source of truth -- the ice under this quad is painted with the
// same two colours, so whatever shows through during the ramp already matches.
uniform vec4 shore_color : source_color = vec4(0.56, 0.68, 0.82, 1.0);
uniform vec4 far_color : source_color = vec4(0.37, 0.49, 0.66, 1.0);

// --- The mirror (traits 2 and 3 above) -------------------------------------------------------
// 1.0 is a true 1:1 flip and IS THE DEFAULT AND THE INTENT. The uniform exists because two
// earlier passes moved it in both directions and both were visibly wrong -- below 1.0 spreads the
// reflection down the screen (the pines ended up at the bottom of the frame), above 1.0 squashes
// it into a sliver at the shore. It is kept only so the reason is written down next to the knob.
uniform float reflection_compression : hint_range(0.5, 4.0) = 1.0;
// How much of the mirror is mixed over the ice at the shore, before the depth fade.
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.55;
// Screen fraction over which the reflection decays to nothing. Exponential, so it is strong and
// legible at the shore and gone by the lower third without a readable edge anywhere.
uniform float reflection_fade_depth : hint_range(0.02, 1.0) = 0.22;
// Vertical spread of the mirror's three taps, in screen fractions, AT THE FAR END of the fade.
// Ice is not glass, and a little blur is also what stops the reflected pine tips aliasing into a
// dotted line as the player moves -- but this is a fraction of SCREEN HEIGHT, so it costs about
// (value x viewport height) pixels of smear and the three taps double that. Shipped at 0.006
// once, which is ~8px on a 1300px-tall window and doubled to ~16: the owner's word for it was
// "blurry" and they were right.
//
// SCALED BY DEPTH at the use site, so the reflection is nearly sharp where it meets the shore --
// which is both what the reference shows and how still water behaves, since the disturbance a
// reflection travels through grows with the distance it travels.
uniform float reflection_blur : hint_range(0.0, 0.02) = 0.0022;

// --- The shore shelf (trait 4) ---------------------------------------------------------------
// Depth is the band's full thickness in screen fractions; the reference's is 0.036. The
// irregularity is what stops it reading as a drawn line: the shelf brightens and dims along its
// length on a world-x noise, so it passes the player rather than following them.
uniform float shelf_depth : hint_range(0.001, 0.2) = 0.036;
uniform float shelf_strength : hint_range(0.0, 1.0) = 0.85;
uniform float shelf_irregularity : hint_range(0.0, 1.0) = 0.45;
uniform vec4 shelf_color : source_color = vec4(0.70, 0.84, 0.96, 1.0);

// --- The faint horizontal banding (trait 5) --------------------------------------------------
// Measured at +/-2.6 luma of 255, so ~0.010 in shader units. Deliberately expressed that small:
// every earlier guess at "faint" was an order of magnitude too strong.
uniform float band_strength : hint_range(0.0, 0.1) = 0.012;
uniform float band_frequency : hint_range(1.0, 400.0) = 90.0;
uniform float band_fade_depth : hint_range(0.02, 1.0) = 0.34;

// World-space mapping for every x-varying feature: the world x at SCREEN_UV.x = 0, and how many
// world px the screen spans. Pushed each frame by lake_reflection.gd. See the header on why
// nothing here may key on SCREEN_UV.x alone.
uniform float world_left_x = 0.0;
uniform float world_width = 1382.0;

// --- Glare and ripple ------------------------------------------------------------------------
// Broad soft bands of brightening, the "glossy" part. Static in depth and drifting sideways with
// the ripple clock, because a lake's glare comes from the surface tilting, not from anything
// moving through it.
uniform float glare_strength : hint_range(0.0, 0.5) = 0.035;
uniform float glare_depth : hint_range(0.0, 1.0) = 0.12;
uniform float glare_softness : hint_range(0.01, 1.0) = 0.16;

// Advanced by lake_reflection.gd, NOT read from TIME. TIME keeps running while the tree is
// paused, so a TIME-driven ripple would animate behind the pause overlay; the node that writes
// this is pause-frozen by its process_mode, so it stops for free.
uniform float wobble_time = 0.0;
uniform float wobble_amplitude : hint_range(0.0, 0.05) = 0.0035;
// In sqrt(screen-fraction) units, not screen fractions -- see the sqrt in fragment().
uniform float wobble_frequency : hint_range(0.0, 200.0) = 24.0;
uniform float wobble_speed : hint_range(0.0, 20.0) = 1.6;


// Cheap 1D value noise on world x, wrapped so the hash never sees a large coordinate: world x is
// never rebased and grows without bound over a session, and fract()-based hashing loses its
// fractional bits entirely once the input gets big -- the same trap ice.gdshader's MASK_PERIOD
// exists for, and the same fix.
float hash11(float cell) {
	float wrapped = mod(cell, 512.0);
	return fract(sin(wrapped * 12.9898) * 43758.5453);
}


float noise11(float point) {
	float cell = floor(point);
	float f = fract(point);
	float blend = f * f * (3.0 - 2.0 * f);
	return mix(hash11(cell), hash11(cell + 1.0), blend);
}


// Three vertical taps, so what comes back is a soft reflection rather than a hard second copy of
// the frame. `spread` is passed in already scaled by depth -- see reflection_blur. Every tap is
// clamped into the frame, and the caller decides whether the sample was legal at all (in_frame).
//
// WEIGHTED, NOT A FLAT AVERAGE. The centre tap carries half: a flat third-each average of three
// samples 2 x spread apart is a box blur, which smears edges into steps, while 1/4-1/2-1/4 is one
// step of a binomial kernel and reads as softness rather than as a triple image.
vec3 sample_mirror(vec2 uv, float spread) {
	vec3 total = texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb * 2.0;
	total += texture(screen_tex, clamp(uv + vec2(0.0, spread), vec2(0.0), vec2(1.0))).rgb;
	total += texture(screen_tex, clamp(uv - vec2(0.0, spread), vec2(0.0), vec2(1.0))).rgb;
	return total * 0.25;
}


void fragment() {
	// Distance BELOW the waterline, in screen fractions. Negative above it.
	float depth = SCREEN_UV.y - waterline;
	if (depth <= 0.0) {
		// Above the shore this item contributes nothing at all. Alpha 0 rather than discard: the
		// backbuffer copy has already happened either way, and a uniform blend keeps the whole
		// rect on one path.
		COLOR = vec4(0.0);
	} else {
		// Normalised over the lake's share of the screen, so the gradient always finishes at the
		// bottom of the frame whatever height the waterline sits at.
		float depth_norm = clamp(depth / max(1.0 - waterline, 0.001), 0.0, 1.0);

		// The world x this pixel sits over. Every x-varying feature below keys on this and never
		// on SCREEN_UV.x -- see the header.
		float world_x = world_left_x + SCREEN_UV.x * world_width;

		// THE sqrt IS THE PERSPECTIVE. Phase advancing as sqrt(depth) rather than depth means the
		// wavelength GROWS toward the bottom of the frame while the amplitude grows with it -- so
		// ripples are small and tight near the shore and broad and slow up close. That is the
		// strongest cue that a surface is a plane going away from you rather than a wall facing
		// you, and it costs one sqrt.
		float ripple_phase = sqrt(depth) * wobble_frequency + wobble_time * wobble_speed;
		float wobble = sin(ripple_phase) * wobble_amplitude * depth_norm;

		vec3 surface = mix(shore_color.rgb, far_color.rgb, depth_norm);

		// The mirror: this pixel's height below the line, flipped to the same height above it.
		vec2 mirror_uv = vec2(SCREEN_UV.x + wobble, waterline - depth * reflection_compression);
		// ZEROED OUTSIDE [0,1], not just clamped. Without this, a pixel whose mirror lies above
		// the top of the frame samples the clamped edge row and paints a smear of it across the
		// ice -- and a waterline near the top of the screen would wrap the sky in from the bottom.
		vec2 inside = step(vec2(0.0), mirror_uv) * step(mirror_uv, vec2(1.0));
		// Nearly sharp at the shore, softening with distance from it -- see reflection_blur. The
		// 0.15 floor keeps a touch of softness everywhere so the pine tips never alias.
		vec3 mirrored = sample_mirror(mirror_uv,
				reflection_blur * (0.15 + clamp(depth / reflection_fade_depth, 0.0, 1.0)));
		// Exponential decay with depth, matching the reference: legible pines at the shore, gone
		// by the lower third, and no readable edge anywhere in between.
		float reflection_weight = reflection_strength * inside.x * inside.y
				* exp(-depth / reflection_fade_depth);
		surface = mix(surface, mirrored, reflection_weight);

		// Glare: a soft, wide brightening at a tunable depth, breathing with the ripple clock.
		// SQUARED BY MULTIPLICATION, never pow(x, 2.0): this base goes negative everywhere above
		// the band's centre, and pow() with a negative base is undefined in GLSL -- on some
		// drivers a NaN, which blend-propagates and can take the whole quad with it.
		float glare_offset = (depth - glare_depth) / glare_softness;
		float glare = exp(-glare_offset * glare_offset) * (0.75 + 0.25 * sin(ripple_phase));
		surface += vec3(glare * glare_strength);

		// THE SHELF. A band of the shelf's own thickness rather than a rim: full strength at the
		// shore, easing out across shelf_depth, and modulated along its length by world-x noise so
		// it brightens and dims the way settled snow does. Two octaves, both keyed on world x, so
		// the pattern travels with the world instead of with the camera.
		float shelf_noise = noise11(world_x / 260.0) * 0.65 + noise11(world_x / 70.0) * 0.35;
		float shelf = (1.0 - smoothstep(0.0, shelf_depth, depth))
				* shelf_strength * (1.0 - shelf_irregularity * shelf_noise);
		surface = mix(surface, shelf_color.rgb, shelf);

		// The faint horizontal banding. The world-x term is a slow PHASE offset, not an amplitude:
		// that makes each band drift and bend along its length like a stress line in ice rather
		// than sitting as a perfectly straight ruled row.
		float band_phase = depth * band_frequency + noise11(world_x / 900.0) * 6.28;
		float bands = sin(band_phase) * band_strength * exp(-depth / band_fade_depth);
		surface += vec3(bands);

		// Opaque across the middle of a crossing: at lake_amount 1 this IS the lake, and nothing
		// the terrain drew below the waterline shows through it.
		COLOR = vec4(clamp(surface, vec3(0.0), vec3(1.0)), lake_amount);
	}
}
