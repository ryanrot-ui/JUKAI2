// TV Static Overlay Shader
// Brief burst of noise during jump scares — J-horror distorted signal effect.
// Applied to a full-screen ColorRect set to visible=false by default.
// UIManager toggles visibility for 0.06–0.18 seconds on each scare.

shader_type canvas_item;

uniform float intensity  : hint_range(0.0, 1.0) = 0.85;
uniform float line_freq  : hint_range(1.0, 80.0) = 40.0;
uniform vec4  tint_color : source_color = vec4(0.9, 0.85, 0.8, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Random grain at high frequency
	float grain = hash(SCREEN_UV * 800.0 + vec2(TIME * 120.0, TIME * 97.0));

	// Horizontal scan lines
	float lines = step(0.5, fract(SCREEN_UV.y * line_freq + TIME * 0.4));
	lines = mix(1.0, lines, 0.3);

	// Vertical band noise (like VHS tracking)
	float band = hash(vec2(SCREEN_UV.y * 20.0 + TIME * 3.0, 0.5));
	band = step(0.8, band) * 0.3;

	float static_val = grain * lines + band;
	float a = static_val * intensity;

	COLOR = vec4(tint_color.rgb * static_val, a);
}
