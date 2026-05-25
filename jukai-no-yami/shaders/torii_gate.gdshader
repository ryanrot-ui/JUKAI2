shader_type spatial;
// ─── Torii Gate Shader ───────────────────────────────────────────────────
// Flat un-lit colour with a procedural noise-flicker so the wood reads as
// sharp, intentional geometric art rather than a 3D lit prop. Designed to
// pair with the high-contrast arthouse look — no smooth gradients, just
// crisp colour fields with a low-frequency time wobble.

render_mode unshaded, cull_back;

// Base timber colour. Defaults to weathered dark vermilion (rotted red).
uniform vec4 wood_color : source_color = vec4(0.18, 0.07, 0.05, 1.0);
// Highlight colour for the grain noise pattern.
uniform vec4 grain_color : source_color = vec4(0.42, 0.12, 0.08, 1.0);

// Grain noise strength — 0 = flat colour, 1 = full grain pattern.
uniform float grain_strength : hint_range(0.0, 1.0) = 0.32;
// Flicker speed and depth — a slow brightness wobble like an old lantern.
uniform float flicker_speed  : hint_range(0.0, 6.0) = 1.4;
uniform float flicker_amount : hint_range(0.0, 0.3) = 0.06;

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	// Grain — quantised hash so the noise reads as chunky woodgrain blocks,
	// not soft fuzz. Quantising VERTEX position before the hash gives the
	// flat geometric look (no expensive bilinear blending).
	float n = hash13(floor(VERTEX * 14.0));
	// Slow flicker pulse over the whole surface
	float pulse = 0.5 + 0.5 * sin(TIME * flicker_speed);
	float flick = pulse * flicker_amount;
	vec3 col = mix(wood_color.rgb, grain_color.rgb, n * grain_strength);
	col *= 1.0 + flick;
	ALBEDO = col;
}
