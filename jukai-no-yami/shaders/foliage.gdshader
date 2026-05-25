// Dark canopy silhouettes — visible mainly in flashlight beam (Chillas Art style)
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, unshaded;

uniform vec4 canopy_color : source_color = vec4(0.012, 0.018, 0.010, 1.0);
uniform vec4 edge_color     : source_color = vec4(0.028, 0.035, 0.022, 1.0);
uniform float alpha_cutoff  : hint_range(0.0, 1.0) = 0.52;
uniform float wind_str      : hint_range(0.0, 0.1)  = 0.008;

varying vec3 wpos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = wpos.x * 0.4 + wpos.z * 0.35;
	float sway = sin(TIME * 0.9 + phase) * wind_str;
	float hfac = max(0.0, VERTEX.y - 4.0) * 0.15;
	VERTEX.x += sway * hfac;
	VERTEX.z += sway * hfac * 0.4;
}

void fragment() {
	float mask = n2(wpos.xz * 1.8 + wpos.y * 0.4) * 0.65 + n2(wpos.xz * 4.5) * 0.35;
	if (mask < alpha_cutoff) {
		discard;
	}
	float edge = n2(wpos.xz * 0.9);
	vec3 col = mix(canopy_color.rgb, edge_color.rgb, edge * 0.35);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
