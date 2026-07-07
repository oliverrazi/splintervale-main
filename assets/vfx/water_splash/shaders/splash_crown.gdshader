shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded, depth_test_disabled;

uniform float splash_time = 0.0;
uniform float lifetime = 0.55;
uniform float intensity = 1.0;

uniform vec3 water_color : source_color = vec3(0.85, 0.93, 0.98);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform sampler2D noise_tex : hint_default_white;

uniform float finger_freq_a : hint_range(3.0, 15.0, 1.0) = 7.0;
uniform float finger_freq_b : hint_range(3.0, 20.0, 1.0) = 13.0;
uniform float burst_reach   : hint_range(0.2, 0.5, 0.01) = 0.40;
uniform float core_size     : hint_range(0.02, 0.15, 0.01) = 0.07;
uniform float finger_sharp  : hint_range(0.02, 0.15, 0.01) = 0.05;

varying float v_life01;

// Wind-Waker-Rhythmus: schnell raus, kurz halten, weg
float life_curve(float t) {
    float up = smoothstep(0.0, 0.18, t);
    float down = 1.0 - smoothstep(0.5, 1.0, t);
    return up * down;
}

void vertex() {
    v_life01 = clamp(splash_time / lifetime, 0.0, 1.0);
}

void fragment() {
    vec2 centered = UV - vec2(0.5);
    float dist = length(centered);
    float angle = atan(centered.y, centered.x);   // -PI..PI

    float env = life_curve(v_life01);
    float scl = 0.6 + 0.4 * intensity;

    // --- Finger: pro Winkel eigene Reichweite (überlagerte Sinus + Noise) ---
    float f = 0.5
        + 0.3 * sin(angle * finger_freq_a + 1.3)
        + 0.2 * sin(angle * finger_freq_b + 4.1);
    // Noise bricht die Regelmäßigkeit auf → keine perfekten Sinus-Zacken
    float ang01 = angle / 6.2831 + 0.5;
    float n = texture(noise_tex, vec2(ang01 * 2.0, v_life01 * 0.2)).r;
    f = clamp(mix(f, n, 0.35), 0.0, 1.0);

    // Front schießt über die Zeit nach außen
    float front = (core_size + burst_reach * smoothstep(0.0, 0.85, v_life01)) * scl;
    float reach = front * (0.45 + 0.55 * f);

    // --- Silhouette: innerhalb reach = Wasser, scharfe Fingerkante außen ---
    float body = 1.0 - smoothstep(reach - finger_sharp, reach, dist);
    // Zentrum aushöhlen (hohle Krone), aber Kern-Fuß solide lassen
    float hollow = smoothstep(0.0, front * 0.5, dist);
    float core = 1.0 - smoothstep(0.0, core_size, dist);
    float shape = clamp(max(body * hollow, core * env), 0.0, 1.0);

    // --- Foam an den Fingerspitzen, klareres Wasser zur Basis ---
    float tip = smoothstep(reach - 0.10, reach, dist);
    vec3 col = mix(water_color, foam_color, tip);

    float alpha = shape * env;
    alpha = clamp(alpha * 1.7, 0.0, 1.0);

    ALBEDO = col;
    ALPHA = alpha;
    EMISSION = foam_color * 0.12;   // leichter Cartoon-Pop
}