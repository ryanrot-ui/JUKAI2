shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 ghost_color    : source_color = vec4(0.82, 0.88, 1.0, 0.62);
uniform float edge_glow      : hint_range(0.0, 3.0) = 1.8;
uniform float distort_speed  : hint_range(0.0, 2.0) = 0.45;
uniform float distort_amount : hint_range(0.0, 0.05) = 0.012;
uniform float flicker_speed  : hint_range(0.0, 10.0) = 2.8;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), edge_glow);
	float distort = sin(UV.y * 10.0 + TIME * distort_speed) * distort_amount;
	vec2 uv_d = UV + vec2(distort, 0.0);
	float flicker = 0.88 + 0.12 * sin(TIME * flicker_speed + UV.y * 3.0);
	float alpha = clamp((ghost_color.a + fresnel * 0.45) * flicker, 0.0, 0.92);
	vec3 col = ghost_color.rgb * (1.0 + fresnel * 0.7);
	ALBEDO = col;
	ALPHA = alpha;
	EMISSION = col * fresnel * 0.5;
}
