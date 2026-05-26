shader_type spatial;
// ─── Glitching Anomaly ─────────────────────────────────────────────────
// Replaces the "white snowman" corpse look with a matte-black silhouette
// edged by a razor-thin neon-crimson Fresnel rim. Vertex shader adds
// asymmetric sin-driven displacement so limbs glitch and twist
// non-uniformly mid-air — strips the doll appearance.
//
// Apply as material_override on every visible MeshInstance3D of the
// corpse hierarchy.

render_mode unshaded, cull_back, depth_draw_opaque;

// Core body colour — deep matte black by default.
uniform vec4 core_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Rim emission colour — neon crimson is the cinematic default; pass
// pale white if you want the cold-yurei variant.
uniform vec4 rim_color  : source_color = vec4(0.95, 0.05, 0.08, 1.0);
// Fresnel sharpness. Higher = thinner rim, lower = wider glow halo.
uniform float rim_power : hint_range(0.5, 12.0) = 5.0;
// Rim brightness multiplier — pushes the rim into bloom territory.
uniform float rim_bleed : hint_range(0.0, 6.0) = 2.4;
// Vertex glitch amplitude.
uniform float jitter_amp  : hint_range(0.0, 0.10) = 0.018;
// Base TIME multiplier — drives the sin frequency.
uniform float jitter_freq : hint_range(0.0, 12.0) = 4.0;
// Per-axis frequency multipliers so X, Y, Z never resonate. Asymmetric
// motion is the whole point — keeping these prime-ratio'd avoids the
// "doll bouncing on a spring" look.
uniform float freq_x_mul : hint_range(0.5, 4.0) = 1.0;
uniform float freq_y_mul : hint_range(0.5, 4.0) = 1.6;
uniform float freq_z_mul : hint_range(0.5, 4.0) = 0.7;

void vertex() {
	// Asymmetric per-axis displacement. Each axis uses its OWN sin with
	// a different phase seed (VERTEX.y, VERTEX.x, VERTEX.z) so no two
	// vertices move identically. Hem-weighted so feet jitter more than
	// the head — exactly the cloth-in-breeze feel.
	float hem = clamp(1.0 - VERTEX.y * 0.30, 0.0, 1.0);
	float t = TIME * jitter_freq;
	VERTEX.x += sin(t * freq_x_mul + VERTEX.y * 3.7) * jitter_amp * hem;
	VERTEX.y += sin(t * freq_y_mul + VERTEX.x * 5.1) * jitter_amp * 0.35 * hem;
	VERTEX.z += sin(t * freq_z_mul + VERTEX.z * 4.3) * jitter_amp * 0.85 * hem;
	// Twist about the Y axis driven by another sin so limbs sway
	// independently of the translation — this is the "asymmetric"
	// part of the brief.
	float twist = sin(t * 0.83 + VERTEX.y * 2.1) * jitter_amp * 1.5 * hem;
	float cs = cos(twist);
	float sn = sin(twist);
	float vx = VERTEX.x;
	float vz = VERTEX.z;
	VERTEX.x = vx * cs - vz * sn;
	VERTEX.z = vx * sn + vz * cs;
}

void fragment() {
	// Fresnel — 1.0 at silhouette edges, 0 at surfaces facing the camera.
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), rim_power);
	// Sharp matte-black core with a bright rim halo. Mix between core
	// and rim by the Fresnel mask; emission carries the rim glow into
	// the post-process bloom.
	vec3 col = mix(core_color.rgb, rim_color.rgb * rim_bleed, fres);
	ALBEDO = col;
	EMISSION = rim_color.rgb * fres * rim_bleed;
}
