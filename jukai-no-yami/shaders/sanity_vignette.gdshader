// Sanity Post-Processing Shader
// Applied to a full-screen ColorRect over the viewport.
// Parameters driven by SanitySystem.gd in real-time.

shader_type canvas_item;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.0;
uniform float desaturate        : hint_range(0.0, 1.0) = 0.0;
uniform float aberration        : hint_range(0.0, 0.05) = 0.0;
uniform float noise_strength    : hint_range(0.0, 0.2)  = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Simple hash for grain noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    // Chromatic aberration — splits RGB channels at edges
    vec2 offset = (uv - 0.5) * aberration;
    float r = texture(SCREEN_TEXTURE, uv + offset).r;
    float g = texture(SCREEN_TEXTURE, uv).g;
    float b = texture(SCREEN_TEXTURE, uv - offset).b;
    vec4 col = vec4(r, g, b, 1.0);

    // Vignette — dark oval at screen edges
    vec2 vig_uv = uv * (1.0 - uv.yx);
    float vignette = pow(vig_uv.x * vig_uv.y * 15.0, vignette_strength * 0.6);
    vignette = clamp(vignette, 0.0, 1.0);
    col.rgb *= mix(1.0, vignette, min(vignette_strength, 1.0));

    // Desaturation — drain color as sanity drops
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    col.rgb = mix(col.rgb, vec3(lum), desaturate);

    // Slight blue tint at high desaturation (ghost color grading)
    col.rgb = mix(col.rgb, col.rgb * vec3(0.85, 0.88, 1.0), desaturate * 0.4);

    // Film grain noise
    float grain = hash(uv + vec2(TIME * 0.1)) * noise_strength;
    col.rgb += grain - noise_strength * 0.5;

    COLOR = col;
}
