shader_type particles;

// Aufsteigende Rauch-Wolken mit Wirbel und Verblassen
// Für GPUParticles3D am Kessel

uniform vec4 smoke_color_bottom : source_color = vec4(0.4, 0.8, 0.5, 0.6);  // leicht grünlich (Gebräu)
uniform vec4 smoke_color_top    : source_color = vec4(0.7, 0.7, 0.7, 0.0);  // grau, transparent
uniform float swirl_strength    : hint_range(0.0, 5.0) = 1.5;
uniform float rise_speed        : hint_range(0.1, 3.0) = 0.6;
uniform float spread_radius     : hint_range(0.0, 1.0) = 0.18;

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(127.1, 311.7))) * 43758.5453);
}

void start() {
    // Startposition: zufällig innerhalb des Kesselrands
    float angle = rand(vec2(float(INDEX), 1.0)) * TAU;
    float r     = sqrt(rand(vec2(float(INDEX), 2.0))) * spread_radius;
    TRANSFORM[3].x = cos(angle) * r;
    TRANSFORM[3].y = 0.0;
    TRANSFORM[3].z = sin(angle) * r;

    // Startgröße zufällig variieren
    float s = mix(0.04, 0.10, rand(vec2(float(INDEX), 3.0)));
    TRANSFORM[0].x = s;
    TRANSFORM[1].y = s;
    TRANSFORM[2].z = s;

    VELOCITY = vec3(0.0, rise_speed * mix(0.7, 1.3, rand(vec2(float(INDEX), 4.0))), 0.0);
    COLOR = smoke_color_bottom;
}

void process() {
    float t = CUSTOM.y; // normierte Lebenszeit 0..1

    // Leichter Wirbel: dreht sich beim Aufsteigen
    float swirl_angle = t * swirl_strength * (CUSTOM.x > 0.5 ? 1.0 : -1.0);
    float cx = cos(swirl_angle);
    float sx = sin(swirl_angle);
    vec2 xz = vec2(TRANSFORM[3].x, TRANSFORM[3].z);
    xz = vec2(cx * xz.x - sx * xz.y, sx * xz.x + cx * xz.y);
    TRANSFORM[3].x = xz.x;
    TRANSFORM[3].z = xz.y;

    // Horizontale Ausbreitung mit der Zeit
    float spread = t * t * 0.15;
    TRANSFORM[0].x += spread * 0.01;
    TRANSFORM[2].z += spread * 0.01;
    TRANSFORM[1].y += spread * 0.005;

    // Farbe & Alpha: unten farbig → oben grau & transparent
    COLOR = mix(smoke_color_bottom, smoke_color_top, smoothstep(0.0, 1.0, t));

    // Leichte horizontale Drift (Wind)
    VELOCITY.x += sin(TIME * 0.8 + float(INDEX)) * 0.008;
    VELOCITY.z += cos(TIME * 0.6 + float(INDEX) * 1.3) * 0.005;
}
