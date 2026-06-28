// fountain_water.gdshader
// Stilisierter Brunnen-Wassershader fuer Griffinblade.
// Zwei Modi: Parabel-Krone (0) und Ueberlaufschleier (1).
// Kein SCREEN_TEXTURE - stilisiert mit Fresnel-Kante, passend zum Resonanzen-Look.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// --- Modus ---
// 0 = Parabel-Krone (UV.v laeuft entlang Bogenlaenge -> ungleichfoermige Geschwindigkeit)
// 1 = Ueberlaufschleier (linearer vertikaler Fall)
uniform int fountain_mode : hint_range(0, 1) = 0;

// --- Farben (white-blue Resonanzen) ---
uniform vec4 color_deep : source_color = vec4(0.45, 0.72, 0.92, 0.55);
uniform vec4 color_shallow : source_color = vec4(0.78, 0.92, 0.99, 0.35);
uniform vec4 color_foam : source_color = vec4(0.96, 0.99, 1.0, 1.0);

// --- Flow ---
uniform float flow_speed = 1.6;            // UV-Scroll-Geschwindigkeit entlang v
uniform float flow_speed_variation = 0.35; // Streifen laufen leicht unterschiedlich schnell
uniform sampler2D flow_noise : hint_default_black, repeat_enable;
uniform vec2 noise_tiling = vec2(3.0, 1.0);

// --- Schaum ---
uniform float foam_top = 0.12;     // Schaumband am Ursprung (oben)
uniform float foam_bottom = 0.18;  // Schaumband am Auftreffpunkt (unten)
uniform float foam_sharpness = 2.5;

// --- Fresnel / Transparenz ---
uniform float fresnel_power = 2.2;
uniform float edge_fade = 0.08;        // weicher Rand an den u-Kanten (Mesh-Naht)
uniform float tip_fade = 0.25;         // Strahlspitze duennt aus (nur Modus 0)

// --- Diskrete Strahlen (nur Modus 0) ---
uniform int jet_count = 0;             // 0 = geschlossener Schleier; >0 = N Strahlen
uniform float jet_gap : hint_range(0.0, 1.0) = 0.45; // Anteil Luecke zwischen Strahlen
uniform float jet_softness = 0.06;

varying float v_arc; // 0..1 entlang Wasserlauf (kommt aus Mesh-UV.y)

void vertex() {
    v_arc = UV.y;
}

// Weicher Streifenschnitt fuer diskrete Strahlen, periodisch in u.
float jet_mask(float u) {
    if (jet_count <= 0) {
        return 1.0;
    }
    float cell = fract(u * float(jet_count));
    // Strahl in Zellmitte, Luecke an den Raendern.
    float half_jet = (1.0 - jet_gap) * 0.5;
    float d = abs(cell - 0.5);
    return 1.0 - smoothstep(half_jet, half_jet + jet_softness, d);
}

void fragment() {
    vec2 uv = UV;

    // Pro-Streifen-Versatz: jede u-Saeule scrollt leicht anders -> organische Rinnsale.
    float lane = floor(uv.x * noise_tiling.x);
    float lane_phase = fract(sin(lane * 91.17) * 4193.7);
    float speed = flow_speed * (1.0 + (lane_phase - 0.5) * 2.0 * flow_speed_variation);

    // Scroll entlang v (Wasser laeuft vom Ursprung weg).
    vec2 flow_uv = uv * noise_tiling;
    flow_uv.y -= TIME * speed;

    float n = texture(flow_noise, flow_uv).r;
    float n2 = texture(flow_noise, flow_uv * 1.9 + vec2(0.3, 0.0)).r;
    float flow = mix(n, n2, 0.5);

    // --- Schaumbaender ---
    // foam_top am Ursprung (v=0), foam_bottom am Auftreffen (v=1).
    float foam_o = 1.0 - smoothstep(0.0, foam_top, v_arc);
    float foam_i = smoothstep(1.0 - foam_bottom, 1.0, v_arc);
    float foam = clamp(foam_o + foam_i, 0.0, 1.0);
    foam = pow(foam, foam_sharpness) + flow * 0.15 * foam_i;
    foam = clamp(foam, 0.0, 1.0);

    // --- Tiefenfarbe entlang Lauf ---
    vec4 water = mix(color_shallow, color_deep, smoothstep(0.0, 0.6, v_arc));
    vec3 albedo = mix(water.rgb, color_foam.rgb, foam);

    // --- Fresnel (Kanten heller/opaker) ---
    float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

    // --- Alpha-Aufbau ---
    float alpha = mix(water.a, color_foam.a, foam);
    alpha = max(alpha, fres * 0.6);

    // Weiche u-Kanten (Mesh-Naht unsichtbar machen).
    float edge = smoothstep(0.0, edge_fade, uv.x) * smoothstep(0.0, edge_fade, 1.0 - uv.x);
    alpha *= edge;

    // Modus 0: Strahlspitze ausduennen + optional diskrete Strahlen.
    if (fountain_mode == 0) {
        alpha *= mix(1.0 - tip_fade, 1.0, smoothstep(0.0, 0.35, v_arc));
        alpha *= jet_mask(uv.x);
    }

    // Flow-Variation in Sichtbarkeit fuer lebendige Struktur.
    alpha *= 0.75 + flow * 0.25;

    ALBEDO = albedo;
    ALPHA = clamp(alpha, 0.0, 1.0);
    EMISSION = albedo * foam * 0.25; // Schaum glimmt leicht (Resonanzen-Akzent)
    ROUGHNESS = 0.15;
    METALLIC = 0.0;
    SPECULAR = 0.6;
}