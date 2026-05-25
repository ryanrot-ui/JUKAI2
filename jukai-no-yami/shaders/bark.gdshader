shader_type spatial;

uniform vec4 bark_light : source_color = vec4(0.10, 0.08, 0.06, 1.0);
uniform vec4 bark_dark  : source_color = vec4(0.02, 0.015, 0.012, 1.0);
uniform vec4 moss_col   : source_color = vec4(0.03, 0.05, 0.025, 1.0);
uniform float moss_amt  : hint_range(0.0, 1.0) = 0.12;

varying vec3 wpos;
varying vec3 wnorm;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 grain_uv = vec2(wpos.x * 3.5 + wpos.z * 2.2, wpos.y * 1.4);
	float pattern = n2(grain_uv) * 0.6 + n2(grain_uv * 4.0) * 0.4;
	vec3 col = mix(bark_dark.rgb, bark_light.rgb, pattern);

	float up = clamp(wnorm.y * 1.4, 0.0, 1.0);
	float m_mask = smoothstep(0.55, 0.72, n2(wpos.xz * 1.8)) * up * moss_amt;
	col = mix(col, moss_col.rgb, m_mask);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
