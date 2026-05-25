shader_type spatial;
// Additive blending so the ghost reads as luminous against a dark forest.
// no_depth_test was tempting but causes ordering issues with multiple ghosts;
// keeping depth_draw_opaque maintains correct silhouette.
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 ghost_color    : source_color = vec4(0.82, 0.88, 1.0, 0.62);
uniform float edge_glow      : hint_range(0.0, 3.0) = 1.8;
uniform float distort_speed  : hint_range(0.0, 2.0) = 0.45;
uniform float distort_amount : hint_range(0.0, 0.05) = 0.012;
uniform float flicker_speed  : hint_range(0.0, 10.0) = 2.8;
// Constant brightness floor — guarantees the ghost is at least faintly
// visible even in the darkest forest, instead of disappearing entirely.
uniform float body_glow      : hint_range(0.0, 1.5) = 0.45;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), edge_glow);
	float distort = sin(UV.y * 10.0 + TIME * distort_speed) * distort_amount;
	float flicker = 0.90 + 0.10 * sin(TIME * flicker_speed + UV.y * 3.0);
	// Brighter alpha — old shader maxed at 0.92; ghost was washing out in fog.
	float alpha = clamp((ghost_color.a + fresnel * 0.55) * flicker, 0.0, 1.0);
	vec3 col = ghost_color.rgb * (1.0 + fresnel * 0.9);
	ALBEDO = col;
	ALPHA = alpha;
	// Constant + fresnel emission so the body silhouette is always faintly
	// luminous, with bright rim highlight on edges.
	EMISSION = col * (body_glow + fresnel * 0.9);
}
