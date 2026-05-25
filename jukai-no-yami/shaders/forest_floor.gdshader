shader_type spatial;

uniform vec4 dirt_col  : source_color = vec4(0.05, 0.04, 0.035, 1.0);
uniform vec4 moss_col  : source_color = vec4(0.04, 0.06, 0.03, 1.0);
uniform vec4 leaf_col  : source_color = vec4(0.07, 0.05, 0.03, 1.0);
uniform vec4 mud_col   : source_color = vec4(0.04, 0.03, 0.025, 1.0);

varying vec3 wpos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += n2(p) * a;
		p = p * 2.1 + vec2(1.7, 0.9);
		a *= 0.5;
	}
	return v;
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 uv = wpos.xz;
	float moss_f = fbm(uv * 0.12);
	float moss_mask = smoothstep(0.35, 0.58, moss_f);
	float leaf_mask = smoothstep(0.62, 0.76, n2(uv * 0.8 + 2.0)) * 0.35;
	float mud_mask = smoothstep(0.55, 0.70, fbm(uv * 0.22 + 5.0)) * (1.0 - moss_mask * 0.7);

	vec3 col = dirt_col.rgb;
	col = mix(col, moss_col.rgb, moss_mask * 0.55);
	col = mix(col, leaf_col.rgb, leaf_mask);
	col = mix(col, mud_col.rgb, mud_mask * 0.35);
	col += (n2(uv * 6.0) - 0.5) * 0.015;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
