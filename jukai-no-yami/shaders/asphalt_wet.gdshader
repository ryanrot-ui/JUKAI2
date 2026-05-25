shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 asphalt_color : source_color = vec4(0.11, 0.11, 0.12, 1.0);
uniform float wet_patches : hint_range(0.0, 1.0) = 0.7;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = max(dot(n, v), 0.0);

	float patch = hash(floor(UV * 14.0));
	float wet = wet_patches * smoothstep(0.35, 0.85, patch + sin(UV.x * 22.0) * 0.12);
	float crack = hash(UV * 90.0) * 0.04;

	vec3 col = asphalt_color.rgb * (0.92 + crack);
	float rough = 0.94 - wet * 0.55 * pow(1.0 - ndv, 1.6);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.08, 0.98);
	METALLIC = wet * 0.08;
	SPECULAR = 0.2 + wet * 0.35;
}
