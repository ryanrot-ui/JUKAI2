// Light Rain Screen Overlay Shader
// Simulates rain streaks on a camera lens — very cheap, no particles.
// Apply to a full-screen CanvasLayer ColorRect.

shader_type canvas_item;

uniform float rain_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float streak_speed   : hint_range(0.5, 5.0) = 2.2;
uniform vec4  rain_color     : source_color = vec4(0.7, 0.75, 0.9, 0.08);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    // Streak cells — each cell is a rain column
    float cell_width = 0.015;
    float cell_x = floor(uv.x / cell_width);
    float col_offset = hash(vec2(cell_x, 0.0));

    // Animated drop position
    float drop_y = fract(uv.y * 3.0 + TIME * streak_speed * (0.7 + col_offset * 0.6) + col_offset);
    float streak = smoothstep(0.0, 0.04, drop_y) * smoothstep(0.25, 0.18, drop_y);
    streak *= rain_intensity * (0.5 + col_offset * 0.5);

    // Only show streaks in ~30% of columns
    float active = step(0.7, hash(vec2(cell_x, 1.0)));
    streak *= active;

    COLOR = vec4(rain_color.rgb, rain_color.a * streak);
}
