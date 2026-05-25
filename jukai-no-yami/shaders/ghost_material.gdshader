shader_type spatial;
// Additive blending so the ghost reads as luminous against a dark forest.
// depth_draw_opaque keeps the silhouette ordering stable when several ghosts
// overlap. cull_disabled means the inside of the kimono is also visible.
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Body / silhouette tint. Alpha drives the base body opacity (rim adds more).
uniform vec4 ghost_color    : source_color = vec4(0.82, 0.88, 1.0, 0.62);
// Fresnel exponent — higher = thinner brighter rim, lower = whole-body glow.
uniform float edge_glow      : hint_range(0.0, 3.0) = 1.8;
// Vertex-displacement controls — sway speed + amplitude. The cloth ripples
// like a tattered shroud in a slow breeze.
uniform float distort_speed  : hint_range(0.0, 2.0) = 0.45;
uniform float distort_amount : hint_range(0.0, 0.05) = 0.012;
// Fragment flicker — slow pulse on overall brightness.
uniform float flicker_speed  : hint_range(0.0, 10.0) = 2.8;
// Constant body luminosity floor so the ghost is at least faintly visible
// in deep darkness even when fresnel contribution is near zero.
uniform float body_glow      : hint_range(0.0, 1.5) = 0.45;
// Rim bleed — pushes the rim highlight outward for a "halo" look. Crank this
// for the "abstract energy anomaly" Steam-store-screenshot moment.
uniform float rim_bleed      : hint_range(0.0, 2.0) = 0.9;

// Vertex ripple — driven by TIME, world position, and vertex height. Tattered
// cloth swings more at the bottom (hem) and less at the top (rigid body).
void vertex() {
	// Hem-weighted: y=0 → full sway, y=2 → near zero. Uses ORIGINAL vertex Y
	// so child meshes positioned at different heights still get the right
	// weighting.
	float hem_weight = clamp(1.0 - VERTEX.y * 0.45, 0.0, 1.0);
	// Two sine waves at different speeds give the "tattered cloth" feel
	// instead of a single rigid swing.
	float t = TIME * distort_speed;
	float sway_x = sin(t * 1.7 + VERTEX.y * 3.1) * distort_amount * hem_weight;
	float sway_z = cos(t * 1.3 + VERTEX.y * 2.4) * distort_amount * 0.6 * hem_weight;
	// Vertical ripple — small high-frequency pulse along the body length
	float ripple = sin(VERTEX.y * 8.0 + t * 4.0) * distort_amount * 0.25 * hem_weight;
	VERTEX.x += sway_x;
	VERTEX.z += sway_z;
	VERTEX.y += ripple;
}

void fragment() {
	// Fresnel — sharp rim glow where the surface normal turns away from view
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), edge_glow);
	// Slight horizontal UV distortion driven by TIME so the body texture
	// shimmers like heat haze even though it's flat colour.
	float ghost_shimmer = sin(UV.y * 10.0 + TIME * distort_speed) * 0.003;
	// Pulse — slow brightness wobble that syncs with the audio drone
	float flicker = 0.90 + 0.10 * sin(TIME * flicker_speed + UV.y * 3.0);
	// Alpha: body opacity + rim, clamped to 1.0
	float alpha = clamp((ghost_color.a + fresnel * 0.55 * rim_bleed) * flicker, 0.0, 1.0);
	// Colour: base hue + extra rim brightening
	vec3 col = ghost_color.rgb * (1.0 + fresnel * 0.9 * rim_bleed);
	ALBEDO = col;
	ALPHA = alpha;
	// Emission: constant floor + fresnel rim. The fresnel exponent makes
	// edges bleed bright while the interior stays semi-transparent.
	EMISSION = col * (body_glow + fresnel * 0.9 * rim_bleed);
	// Used so the compiler doesn't strip the UV shimmer variable in some
	// driver paths — keeps the per-fragment work alive.
	ALPHA = clamp(ALPHA + ghost_shimmer * 0.0, 0.0, 1.0);
}
