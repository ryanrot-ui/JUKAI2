shader_type spatial;
// ─── Corpse Anomaly Shader ────────────────────────────────────────────────
// Turns static primitive stacks into a glitching, glowing energy anomaly.
//
//   VERTEX:   sin(TIME) displacement so the body subtly jitters / warps
//             in space. A small step() also fires occasional sharp glitch
//             snaps so the silhouette never reads as fully rigid.
//   FRAGMENT: Fresnel rim-glow. The outer edges bleed light intensely
//             (alpha → 1 + bright emission); the interior fades toward
//             core_alpha so the body reads as semi-transparent.
//
// Additive blending so the anomaly is LUMINOUS against the dark forest
// rather than a solid mesh.

render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Base hue of the anomaly. Default neon vermilion; swap for pale white
// (0.92, 0.94, 0.98) or void purple (0.42, 0.18, 0.62) per encounter.
uniform vec4 anomaly_color : source_color = vec4(0.95, 0.08, 0.06, 1.0);

// Vertex-jitter frequency and amplitude.
uniform float jitter_freq : hint_range(0.0, 20.0) = 6.5;
uniform float jitter_amp  : hint_range(0.0, 0.08) = 0.015;

// Fresnel exponent — higher = thinner rim, lower = whole-body glow.
uniform float rim_exponent : hint_range(0.5, 4.0) = 1.8;
// Core opacity. 0.0 = invisible core (only rim shows), 1.0 = solid body.
uniform float core_alpha   : hint_range(0.0, 1.0) = 0.22;
// How aggressively the rim bleeds out past the silhouette.
uniform float rim_bleed    : hint_range(0.0, 3.0) = 1.6;

// Cheap deterministic hash for the glitch pulse.
float hash11(float x) {
	return fract(sin(x * 91.27) * 47453.531);
}

void vertex() {
	// Hem weighting — bottom of the mesh jitters more than the head, so
	// kimono / robe pieces ripple while the head only twitches slightly.
	float hem_weight = clamp(1.0 - VERTEX.y * 0.35, 0.0, 1.0);
	float t = TIME * jitter_freq;
	// Two-axis dual-sine displacement
	VERTEX.x += sin(t + VERTEX.y * 4.2) * jitter_amp * hem_weight;
	VERTEX.z += cos(t * 0.83 + VERTEX.y * 3.1) * jitter_amp * 0.7 * hem_weight;
	VERTEX.y += sin(t * 1.7 + VERTEX.y * 5.0) * jitter_amp * 0.25 * hem_weight;
	// Glitch snap — every ~2-3 seconds, fire a tiny sideways jump that
	// makes the silhouette flicker like a corrupted video frame.
	float glitch_gate = step(0.985, hash11(floor(TIME * 3.7)));
	float glitch_dir = sign(sin(TIME * 41.0));
	VERTEX.x += glitch_gate * glitch_dir * 0.022 * hem_weight;
}

void fragment() {
	// Fresnel — surface normal vs. view direction. 1.0 at silhouette edge.
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), rim_exponent);
	// Alpha — semi-transparent core, opaque rim
	float a = mix(core_alpha, 1.0, fres) * anomaly_color.a;
	// Colour — base hue at the core, bright bloomed rim at the edge
	vec3 col = anomaly_color.rgb * (0.40 + fres * rim_bleed);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	// Emission lets the additive blend actually carry light into the scene
	EMISSION = col * (0.30 + fres * rim_bleed);
}
