shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.55;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.12;
uniform float metallic : hint_range(0.0, 1.0) = 0.72;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.38;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = max(dot(n, v), 0.0);

	float grain = hash(UV * 48.0) * 0.08;
	float streak = sin(UV.y * 120.0 + UV.x * 18.0) * 0.5 + 0.5;
	float dirt = dirt_amount * (0.35 + grain + streak * 0.25);
	float rust = rust_amount * smoothstep(0.2, 0.9, 1.0 - UV.y) * hash(UV * 12.0);

	vec3 base = paint_color.rgb;
	base = mix(base, base * vec3(0.55, 0.52, 0.48), dirt);
	base = mix(base, vec3(0.42, 0.28, 0.18), rust);

	float rough = roughness_base + dirt * 0.35 - wetness * 0.22 * (1.0 - ndv);
	rough = clamp(rough, 0.12, 0.95);

	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metallic * (1.0 - dirt * 0.4);
	SPECULAR = 0.45 + wetness * 0.25;
}
