shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec3 water_color : source_color = vec3(0.35, 0.65, 0.85);
uniform vec3 rim_color : source_color = vec3(0.9, 0.97, 1.0);
uniform float wobble_amp : hint_range(0.0, 0.5, 0.01) = 0.20;
uniform float wobble_freq : hint_range(1.0, 10.0, 0.5) = 4.0;
uniform float wobble_speed : hint_range(0.0, 6.0, 0.1) = 3.0;
uniform float rim_power : hint_range(0.5, 6.0, 0.1) = 2.5;
uniform float transparency : hint_range(0.0, 1.0, 0.01) = 0.6;

float wobble_noise(vec3 p, float t) {
    return sin(p.x * wobble_freq + t)
         * sin(p.y * wobble_freq * 1.3 + t * 1.1)
         * sin(p.z * wobble_freq * 0.9 + t * 0.7);
}

void vertex() {
    float t = TIME * wobble_speed;
    vec3 dir = normalize(VERTEX);
    float n = wobble_noise(dir, t);
    VERTEX += dir * n * wobble_amp * length(VERTEX);
    float n2 = wobble_noise(dir * 2.0, t * 1.7);
    VERTEX += dir * n2 * wobble_amp * 0.4 * length(VERTEX);
}

void fragment() {
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    ALBEDO = mix(water_color, rim_color, fresnel);
    ROUGHNESS = 0.2;
    METALLIC = 0.0;
    EMISSION = water_color * 0.2;

    // transparency = Deckkraft der Mitte (0.15 = sehr durchsichtig)
    // Rand etwas deckender für den Glasrand-Effekt, aber NICHT voll 1.0
    float core_alpha = transparency;          // z.B. 0.15
    float edge_alpha = min(transparency + 0.35, 0.7);  // Rand max 0.7, nicht 1.0
    ALPHA = mix(core_alpha, edge_alpha, fresnel);
}