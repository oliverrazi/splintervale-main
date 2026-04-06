shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.75;
uniform vec4 ring_gradient_start  : source_color = vec4(0.0, 0.53, 0.53, 1.0);
uniform vec4 ring_gradient_end  : source_color = vec4(0.0, 0.53, 0.53, 1.0);
uniform vec4 ring_inactive_color : source_color = vec4(0.25, 0.25, 0.25, 0.8);
uniform float ring_width : hint_range(0.01, 0.2) = 0.07;

uniform vec4 bg_color_a : source_color = vec4(0.05, 0.03, 0.12, 1.0); // tiefes Lila
uniform vec4 bg_color_b : source_color = vec4(0.12, 0.06, 0.22, 1.0); // etwas heller
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float time_scale : hint_range(0.0, 1.0) = 0.08; // sehr langsam für subtile Animation

// -- Noise Hilfsfunktionen --
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f); // Smoothstep

    float a = fract(sin(dot(i + vec2(0,0), vec2(127.1, 311.7))) * 43758.5453);
    float b = fract(sin(dot(i + vec2(1,0), vec2(127.1, 311.7))) * 43758.5453);
    float c = fract(sin(dot(i + vec2(0,1), vec2(127.1, 311.7))) * 43758.5453);
    float d = fract(sin(dot(i + vec2(1,1), vec2(127.1, 311.7))) * 43758.5453);

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    // Mehrere Noise-Layer überlagert (Fractal Brownian Motion)
    float v = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amplitude * value_noise(p);
        p *= 2.1;
        amplitude *= 0.5;
    }
    return v;
}


void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    float outer = 0.5;
    float inner = outer - ring_width;
    float portrait_radius = inner - 0.01;

    if (dist <= portrait_radius) {
        // Noise Hintergrund
        vec2 noise_uv = UV * noise_scale + vec2(TIME * time_scale);
        float n = fbm(noise_uv);
        n = mix(1.0, n, noise_intensity);

        // Radiales Vignette-Darkening zur Mitte
        float vignette = 1.0 - smoothstep(0.0, portrait_radius, dist) * 0.4;

        vec4 bg = mix(bg_color_a, bg_color_b, n * vignette);

        // Portrait drüber blenden
        vec4 portrait = texture(TEXTURE, UV);
        float edge = 1.0 - smoothstep(portrait_radius - 0.03, portrait_radius, dist);
        portrait.a *= edge;

        COLOR = mix(bg, portrait, portrait.a);
        COLOR.a = 1.0;

    } else if (dist <= outer) {
        float angle = atan(uv.x, -uv.y);
        float normalized = (angle / (PI * 2.0)) + 0.5;

        if (normalized <= progress) {
            float t = normalized / max(progress, 0.001);
            COLOR = mix(ring_gradient_start, ring_gradient_end, t);
        } else {
            COLOR = ring_inactive_color;
        }

    } else {
        COLOR = vec4(0.0);
    }
}