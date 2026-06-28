shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ═══════════════════════════════════════════════════════════════
// CAVE RESONANCE SHADER v2
// ═══════════════════════════════════════════════════════════════
// Statische Energie-Adern mit wanderndem Lichtpuls.
// Die Adern selbst bewegen sich nicht.
// ═══════════════════════════════════════════════════════════════

// ── Basis-Material ──────────────────────────────────────────
group_uniforms Base;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(0.25, 0.22, 0.2, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float vertex_color_influence : hint_range(0.0, 1.0) = 1.0;

// ── Ader-Form ───────────────────────────────────────────────
group_uniforms Veins;
/// Größe der Voronoi-Zellen. Höher = weniger Adern.
uniform float vein_scale : hint_range(1.0, 15.0) = 5.0;
/// Breite der Adern
uniform float vein_width : hint_range(0.005, 0.15) = 0.04;
/// Weichheit der Kante
uniform float vein_softness : hint_range(0.005, 0.1) = 0.02;
/// Grundhelligkeit der Adern (wenn kein Puls durchläuft)
uniform float vein_ambient : hint_range(0.0, 1.0) = 0.15;
/// Farbe der Adern im Ruhezustand
uniform vec3 vein_color : source_color = vec3(0.45, 0.75, 1.0);

// ── Wandernder Lichtpuls ────────────────────────────────────
group_uniforms Pulse;
/// Farbe des Pulses (weiß-hellblau)
uniform vec3 pulse_color : source_color = vec3(0.9, 0.96, 1.0);
/// Geschwindigkeit des Pulses
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.5;
/// Breite des leuchtenden Bereichs (Meter in Worldspace)
uniform float pulse_width : hint_range(0.2, 5.0) = 1.5;
/// Weichheit des Puls-Rands
uniform float pulse_fade : hint_range(0.1, 3.0) = 0.8;
/// Helligkeit des Pulses
uniform float pulse_intensity : hint_range(0.0, 8.0) = 3.0;
/// Richtung in der der Puls wandert (XZ-Ebene, wird normalisiert)
uniform vec2 pulse_direction = vec2(1.0, 0.3);
/// Abstand zwischen Pulsen (Meter). Größer = seltener.
uniform float pulse_spacing : hint_range(2.0, 30.0) = 12.0;

// ── Glow ────────────────────────────────────────────────────
group_uniforms Glow;
/// Breite des sanften Glows um die Ader herum
uniform float glow_spread : hint_range(0.0, 0.3) = 0.08;
/// Wie stark der Puls die Roughness reduziert
uniform float roughness_reduction : hint_range(0.0, 1.0) = 0.4;

varying vec3 world_pos;
varying vec3 world_normal;


// ═══════════════════════════════════════════════════════════════
// VERTEX
// ═══════════════════════════════════════════════════════════════

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


// ═══════════════════════════════════════════════════════════════
// HASH — Deterministische Pseudo-Zufallszahlen
// ═══════════════════════════════════════════════════════════════

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}


// ═══════════════════════════════════════════════════════════════
// VORONOI — Statisches Zellmuster (bewegt sich NICHT)
// ═══════════════════════════════════════════════════════════════

void voronoi(vec2 uv, float scale,
        out float edge_dist, out vec2 cell_id) {

    vec2 p = uv * scale;
    vec2 ip = floor(p);
    vec2 fp = fract(p);

    float f1 = 10.0;
    float f2 = 10.0;
    cell_id = vec2(0.0);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 cell = ip + neighbor;

            // Fester Punkt pro Zelle — KEINE Animation
            vec2 point = hash22(cell);

            vec2 diff = neighbor + point - fp;
            float dist = length(diff);

            if (dist < f1) {
                f2 = f1;
                f1 = dist;
                cell_id = cell;
            } else if (dist < f2) {
                f2 = dist;
            }
        }
    }

    // Edge-Distanz = Abstand zur nächsten Zellgrenze
    edge_dist = f2 - f1;
}


// ═══════════════════════════════════════════════════════════════
// ADER-MASKE — Statisches Muster + wandernder Puls
// ═══════════════════════════════════════════════════════════════

void compute_vein(vec2 uv, float time,
        out float vein_mask, out float glow_mask, out float pulse_factor) {

    float edge_dist;
    vec2 cid;
    voronoi(uv, vein_scale, edge_dist, cid);

    // ── Ader-Maske (statisch) ──
    vein_mask = 1.0 - smoothstep(vein_width, vein_width + vein_softness, edge_dist);

    // Dickenvariation pro Segment
    float thickness_var = hash21(cid) * 0.4 + 0.6;
    vein_mask *= thickness_var;

    // Manche Adern komplett ausblenden (sparsamer)
    float visibility = step(0.3, hash21(cid * 13.37));
    vein_mask *= visibility;

    // ── Glow um die Ader (breiter, weicher) ──
    glow_mask = 1.0 - smoothstep(vein_width, vein_width + vein_softness + glow_spread, edge_dist);
    glow_mask *= glow_mask;
    glow_mask *= visibility;

    // ── Wandernder Puls ──
    // Ein Lichtband das in pulse_direction über die Oberfläche wandert
    vec2 dir = normalize(pulse_direction);
    float projected = dot(uv, dir);

    // Periodischer Puls mit pulse_spacing Abstand
    float moving = projected - time * pulse_speed;
    float wave = mod(moving, pulse_spacing);
    // Lichtband: hell in der Mitte, fadet zu beiden Seiten
    float band = 1.0 - smoothstep(0.0, pulse_width * 0.5, abs(wave - pulse_spacing * 0.5));
    // Weicherer Fade an den Rändern
    band = pow(band, 1.0 + pulse_fade);

    // Puls leuchtet nur dort wo auch eine Ader ist
    pulse_factor = band;
}


// ═══════════════════════════════════════════════════════════════
// FRAGMENT
// ═══════════════════════════════════════════════════════════════

void fragment() {
    // ── Basis-Material ganz normal laden ──
    vec3 albedo = texture(albedo_tex, UV).rgb * base_color.rgb;
    vec3 tex_normal = texture(normal_tex, UV).rgb;
    float tex_roughness = texture(roughness_tex, UV).r * base_roughness;

    // Vertex Colors (Farbvariation vom CavePiece)
    albedo *= mix(vec3(1.0), COLOR.rgb, vertex_color_influence);
    float vc_wetness = 1.0 - COLOR.a;
    tex_roughness = mix(tex_roughness, 0.3, vc_wetness * 0.7);

    // ── Projektion wählen (Boden vs. Wand) ──
    vec3 blend = abs(world_normal);
    blend = pow(blend, vec3(4.0));
    blend /= (blend.x + blend.y + blend.z);

    // Pro Projektion berechnen und blenden
    float total_vein = 0.0;
    float total_glow = 0.0;
    float total_pulse = 0.0;

    // XZ (Böden)
    if (blend.y > 0.01) {
        float vm, gm, pf;
        compute_vein(world_pos.xz, TIME, vm, gm, pf);
        total_vein += vm * blend.y;
        total_glow += gm * blend.y;
        total_pulse += pf * blend.y;
    }

    // XY (Wände in Z-Richtung)
    if (blend.z > 0.01) {
        float vm, gm, pf;
        compute_vein(world_pos.xy, TIME, vm, gm, pf);
        total_vein += vm * blend.z;
        total_glow += gm * blend.z;
        total_pulse += pf * blend.z;
    }

    // YZ (Wände in X-Richtung)
    if (blend.x > 0.01) {
        float vm, gm, pf;
        compute_vein(world_pos.yz, TIME, vm, gm, pf);
        total_vein += vm * blend.x;
        total_glow += gm * blend.x;
        total_pulse += pf * blend.x;
    }

    // ── Emission zusammenbauen ──
    // Ruhezustand: dezentes Glimmen in den Adern
    vec3 ambient_emission = vein_color * total_vein * vein_ambient;

    // Puls: helles Leuchten das durch die Ader wandert
    float pulse_on_vein = total_vein * total_pulse;
    // Farbe: Mitte des Pulses ist weißer
    vec3 pulse_col = mix(vein_color, pulse_color, pulse_on_vein * 0.5);
    vec3 pulse_emission = pulse_col * pulse_on_vein * pulse_intensity;

    vec3 total_emission = ambient_emission + pulse_emission;

    // ── Roughness: Adern sind etwas glatter ──
    float roughness_mod = total_glow * total_pulse * roughness_reduction;
    float final_roughness = mix(tex_roughness, 0.2, roughness_mod);

    // ── Output — Basis-Textur bleibt IMMER sichtbar ──
    ALBEDO = albedo;
    ROUGHNESS = final_roughness;
    EMISSION = total_emission;
    NORMAL_MAP = tex_normal;
    NORMAL_MAP_DEPTH = normal_strength;
    SPECULAR = mix(0.3, 0.6, total_glow * total_pulse);
}