shader_type canvas_item;

// Replace the authored clothing hue, retaining texture alpha, shading and shield tint.
uniform vec4 outfit_color : source_color = vec4(1.0);
uniform float clothing_hue = 0.97;
uniform float hue_radius = 0.04;
uniform float saturation_floor = 0.08;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float high = max(max(texel.r, texel.g), texel.b);
	float low = min(min(texel.r, texel.g), texel.b);
	float chroma = high - low;
	float hue = 0.0;
	if (chroma > 0.001) {
		if (high == texel.r) hue = mod((texel.g - texel.b) / chroma, 6.0);
		else if (high == texel.g) hue = (texel.b - texel.r) / chroma + 2.0;
		else hue = (texel.r - texel.g) / chroma + 4.0;
		hue = fract(hue / 6.0 + 1.0);
	}
	float distance = abs(hue - clothing_hue);
	distance = min(distance, 1.0 - distance);
	float mask = (1.0 - smoothstep(hue_radius, hue_radius + 0.012, distance)) * smoothstep(saturation_floor, saturation_floor + 0.04, chroma / max(high, 0.001));
	// Jackets occupy this band in every normalised frame. Keep hair, blades and ice intact.
	mask *= smoothstep(0.30, 0.34, UV.y) * (1.0 - smoothstep(0.64, 0.68, UV.y));
	vec3 dyed = outfit_color.rgb * high;
	COLOR = vec4(mix(texel.rgb, dyed, mask), texel.a) * sprite_tint;
}
