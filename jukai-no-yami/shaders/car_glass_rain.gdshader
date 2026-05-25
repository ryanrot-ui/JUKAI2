shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 glass_tint : source_color = vec4(0.14, 0.18, 0.24, 0.42);
uniform float rain_streaks : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec3 n = normalize(NORMAL);
	float fresnel = pow(1.0 - max(dot(n, VIEW), 0.0), 2.8);
	float streak = sin(UV.x * 80.0) * sin(UV.y * 140.0 + UV.x * 6.0);
	streak = smoothstep(0.55, 1.0, streak * 0.5 + 0.5) * rain_streaks;

	vec3 col = glass_tint.rgb;
	col += vec3(0.08, 0.10, 0.14) * fresnel;
	col += vec3(0.12, 0.14, 0.18) * streak * 0.15;

	ALBEDO = col;
	ALPHA = glass_tint.a + fresnel * 0.18;
	ROUGHNESS = 0.06 + streak * 0.08;
	METALLIC = 0.15;
	SPECULAR = 0.85;
}
