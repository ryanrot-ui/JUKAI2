// Chillas Art / Fears to Fathom style — subtle grain + vignette, no VHS artifacts
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float grain_amount   : hint_range(0.0, 0.08)  = 0.018;
uniform float vignette_power : hint_range(0.0, 2.0)   = 0.48;
uniform float desaturate     : hint_range(0.0, 1.0)   = 0.12;
uniform float contrast_boost : hint_range(0.9, 1.3)   = 1.04;
uniform float sanity_drain   : hint_range(0.0, 1.0)   = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(SCREEN_TEXTURE, uv).rgb;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = desaturate + sanity_drain * 0.45;
	col = mix(col, vec3(lum) * vec3(0.88, 0.91, 0.98), sat);

	float c = contrast_boost + sanity_drain * 0.08;
	col = (col - 0.5) * c + 0.5;
	col *= mix(1.02, 0.94, sanity_drain * 0.28);

	vec2 d = (uv - 0.5) * vec2(1.0, 1.22);
	float vig = 1.0 - dot(d, d) * vignette_power * 2.4;
	vig = smoothstep(0.0, 1.0, clamp(vig, 0.0, 1.0));
	col *= vig;

	float g = hash(uv * 800.0 + floor(TIME * 20.0)) * 2.0 - 1.0;
	col += g * grain_amount * (1.0 + sanity_drain * 0.6);

	// Flashlight warmth in screen center (player view)
	vec2 fc = uv - 0.5;
	float flash_mask = 1.0 - smoothstep(0.0, 0.38, length(fc * vec2(0.9, 1.1)));
	col += vec3(0.08, 0.07, 0.03) * flash_mask * 0.62;

	if (sanity_drain > 0.25) {
		col.b += sanity_drain * 0.04;
		col *= mix(1.0, vig * 0.55, (sanity_drain - 0.25) * 1.1);
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
