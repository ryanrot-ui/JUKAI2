// Flashlight Volumetric Beam Shader
// Applied to a cone mesh (CylinderMesh, top_radius=0) parented to the SpotLight3D.
// Simulates volumetric light scattering in fog — very cheap, no ray marching.
// render_mode blend_add keeps it purely additive; no overdraw darkening.

shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded, shadows_disabled, ambient_light_disabled;

uniform vec4  beam_color     : source_color = vec4(0.88, 0.84, 0.72, 1.0);
uniform float density        : hint_range(0.0, 1.0)  = 0.28;
uniform float dust_speed     : hint_range(0.0, 3.0)  = 0.25;
uniform float dust_scale     : hint_range(1.0, 20.0) = 9.0;
uniform float flicker_amount : hint_range(0.0, 1.0)  = 0.0;  // driven by Flashlight.gd

// Cheap 3D value noise via hash
float hash3(vec3 p) {
	p = fract(p * vec3(443.8975, 397.2973, 491.1871));
	p += dot(p, p.yxz + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i),              hash3(i + vec3(1,0,0)), f.x),
		    mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		    mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void fragment() {
	// UV.y: 0 at cone tip (camera), 1 at cone base (far end)
	// UV.x: wraps 0..1 around circumference
	float along = UV.y;                          // depth along beam
	float radial = abs(UV.x * 2.0 - 1.0);       // 0 at center, 1 at edge

	// Depth fade: bright near tip, dim at far end (atmospheric scatter)
	float depth_fade = pow(1.0 - along, 0.6) * 0.6 + pow(along, 1.4) * 0.1;

	// Radial falloff: soft cone edge
	float edge_fade = pow(1.0 - radial, 1.4);

	// Animated dust/particle noise — gives "foggy beam" look
	vec3 dust_uv = vec3(UV * dust_scale, TIME * dust_speed);
	float dust   = noise3(dust_uv);
	dust = smoothstep(0.25, 0.75, dust);

	// Combine
	float alpha = depth_fade * edge_fade * density * (0.6 + dust * 0.4);

	// Flicker: modulate alpha by a fast sine + noise (set from GDScript)
	float flicker = 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * 18.0));
	alpha *= flicker;

	ALBEDO = beam_color.rgb;
	ALPHA  = clamp(alpha, 0.0, 0.6);
}
