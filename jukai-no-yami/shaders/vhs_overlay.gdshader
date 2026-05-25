shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float grain_str     : hint_range(0.0, 0.12)  = 0.042;
uniform float scanline_str  : hint_range(0.0, 1.0)   = 0.20;
uniform float chroma_str    : hint_range(0.0, 0.025) = 0.007;
uniform float tracking_str  : hint_range(0.0, 1.0)   = 0.24;
uniform float bleed_str     : hint_range(0.0, 0.05)  = 0.014;
uniform float sanity_drain  : hint_range(0.0, 1.0)   = 0.0;

// ── PRNG ─────────────────────────────────────────────────────────────────────
float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float h3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// ── Chromatic aberration — R/G/B lens fringing from screen center ─────────────
vec3 chromatic(vec2 uv, float strength) {
	vec2 d = uv - 0.5;
	float r = texture(SCREEN_TEXTURE, uv + d * strength * 1.20).r;
	float g = texture(SCREEN_TEXTURE, uv + d * strength * 0.30).g;
	float b = texture(SCREEN_TEXTURE, uv - d * strength * 0.85).b;
	return vec3(r, g, b);
}

// ── NTSC horizontal chroma bleed — right-bleeding colour ghost ────────────────
vec3 chroma_bleed(vec2 uv) {
	float r = texture(SCREEN_TEXTURE, uv + vec2(-bleed_str, 0.0)).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv + vec2( bleed_str, 0.0)).b;
	return vec3(r, g, b);
}

// ── VHS tracking noise — sparse drifting bands ────────────────────────────────
float tracking_noise(vec2 uv) {
	float t   = TIME * 0.50;
	float b1  = step(0.9988, fract(uv.y * 2.6 + t * 0.12));
	float b2  = step(0.9978, fract(uv.y * 5.8 - t * 0.09));
	float n   = h2(vec2(floor(uv.y * 155.0 + t), floor(t * 1.6)));
	return (b1 + b2) * n;
}

// ── VHS head-switching artifact — noise bar at bottom ~3% ────────────────────
float head_switch(vec2 uv) {
	float zone = step(0.968, uv.y);
	float n    = h2(vec2(floor(TIME * 3.3), floor(uv.y * 70.0)));
	return zone * n * 0.09;
}

// ── CRT scanlines ─────────────────────────────────────────────────────────────
float scanlines(vec2 uv) {
	float line = fract(uv.y * 360.0);
	return 1.0 - smoothstep(0.42, 0.88, line) * scanline_str;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// ── 1. Chromatic aberration ───────────────────────────────────────────────
	float ca = chroma_str + sanity_drain * 0.018;
	vec3 col  = chromatic(uv, ca);

	// ── 2. NTSC horizontal chroma bleed ───────────────────────────────────────
	col = mix(col, chroma_bleed(uv), 0.52);

	// ── 3. VHS colour grade ───────────────────────────────────────────────────
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// Tape lowers chroma fidelity: partial desaturate
	col = mix(col, vec3(lum), 0.11);
	// VHS green-yellow midtone warmth cast
	col.g += lum * (1.0 - lum) * 0.030;
	col.r += lum * (1.0 - lum) * 0.016;
	// Black crush — VHS noise floor (~18 IRE)
	col = max(col, vec3(0.016, 0.014, 0.018));
	// White clip — VHS peak white (~90 IRE)
	col = min(col, vec3(0.93));
	// Gentle contrast bump
	col = (col - 0.5) * 1.07 + 0.478;
	col = clamp(col, 0.0, 1.0);

	// ── 4. CRT scanlines ─────────────────────────────────────────────────────
	col *= scanlines(uv);

	// ── 5. VHS tracking distortion ───────────────────────────────────────────
	float track = tracking_noise(uv) * tracking_str;
	col += vec3(track * 0.38);
	// Sparse horizontal jitter lines
	float warp_n = h2(vec2(floor(uv.y * 155.0 + TIME * 0.6), floor(TIME * 2.0)));
	float warp_m = step(0.984, warp_n);
	float warp   = (warp_n - 0.5) * 0.0026 * warp_m;
	col = mix(col, texture(SCREEN_TEXTURE, uv + vec2(warp, 0.0)).rgb, warp_m * 0.26);

	// ── 6. Head-switch artifact ───────────────────────────────────────────────
	col += vec3(head_switch(uv));

	// ── 7. Temporal film grain — updates at 24 fps ────────────────────────────
	float t_frame = floor(TIME * 24.0);
	float grain   = h3(vec3(uv * vec2(1280.0, 720.0), t_frame)) * 2.0 - 1.0;
	col += grain * grain_str;

	// ── 8. Cinematic vignette ─────────────────────────────────────────────────
	vec2 vc  = (uv - 0.5) * vec2(1.0, 1.38);
	float vig = 1.0 - dot(vc, vc) * 2.12;
	vig = clamp(pow(max(vig, 0.0), 0.44), 0.0, 1.0);
	col *= vig;

	// ── 9. Sanity horror layer ────────────────────────────────────────────────
	if (sanity_drain > 0.10) {
		float si  = sanity_drain;
		float fl2 = dot(col, vec3(0.299, 0.587, 0.114));
		// Cold blue desaturation — fear drains warmth from vision
		col = mix(col, vec3(fl2) * vec3(0.68, 0.76, 1.0), si * 0.72);
		// Heavy organic grain burst
		float pg = h3(vec3(uv * 1050.0, floor(TIME * 30.0))) * 2.0 - 1.0;
		col += pg * si * 0.095;
		// Tunnelling vignette as sanity collapses
		col *= mix(1.0, vig * 0.48, si * 0.68);
		// VHS warp bands — only at severe drain
		if (si > 0.38) {
			float t2       = (si - 0.38) / 0.62;
			float line_warp = sin(uv.y * 48.0 + TIME * 6.5) * 0.0058 * t2;
			vec3 warped     = texture(SCREEN_TEXTURE, uv + vec2(line_warp, 0.0)).rgb;
			col = mix(col, warped, t2 * 0.52);
		}
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
