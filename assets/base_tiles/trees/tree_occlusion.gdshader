shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

global uniform vec3 player_world_position;
global uniform vec3 camera_world_position;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic  : hint_range(0.0, 1.0) = 0.0;
uniform float specular  : hint_range(0.0, 1.0) = 0.5;

// Occlusion-Form
uniform float occlusion_radius   : hint_range(0.0, 30.0) = 3.5;
uniform float occlusion_softness : hint_range(0.01, 10.0) = 2.0;
uniform float min_alpha          : hint_range(0.0, 1.0)  = 0.0;

// Höhe
uniform float height_threshold : hint_range(-2.0, 5.0) = 0.3;
uniform float height_softness  : hint_range(0.01, 3.0) = 0.8;

// Camera-aware: wie weit hinter dem Player noch occluden
uniform float behind_player_falloff : hint_range(0.1, 8.0) = 1.5;

// Edge-Noise
uniform sampler2D edge_noise : hint_default_white, filter_linear, repeat_enable;
uniform float noise_scale      : hint_range(0.1, 5.0)  = 1.2;
uniform float noise_strength   : hint_range(0.0, 0.6)  = 0.22;
uniform float noise_scale_2    : hint_range(0.1, 10.0) = 4.5;
uniform float noise_strength_2 : hint_range(0.0, 0.4)  = 0.10;
uniform float wobble_speed     : hint_range(0.0, 2.0)  = 0.35;
uniform float wobble_scale     : hint_range(0.0, 1.0)  = 0.12;

uniform float wind_strength    : hint_range(0.0, 1.0)  = 0.04;  // max. Ausschlag in Metern
uniform float wind_speed       : hint_range(0.0, 4.0)  = 0.15;   // Tempo der großen Schwingung
uniform float wind_flutter     : hint_range(0.0, 1.0)  = 0.08;  // feines Blatt-Zittern
uniform float wind_flutter_speed : hint_range(0.0, 12.0) = 7.0; // Tempo des Zitterns
uniform vec2  wind_direction   = vec2(1.0, 0.3);                // Hauptwindrichtung (X,Z)
uniform float wind_height_falloff : hint_range(0.1, 10.0) = 2.0;

// Inner Rim Light
uniform vec3  rim_color    : source_color = vec3(0.55, 0.8, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0)  = 0.45;
uniform float rim_width    : hint_range(0.02, 0.4) = 0.12;

uniform bool debug_occlusion = false;

varying vec3 v_world_pos;

instance uniform vec3 instance_tint = vec3(1.0);

instance uniform float wind_enabled = 1.0;

void vertex() {
    float wind_mask = wind_enabled;

    // Pro Blatt-Objekt eine eigene Phase, damit nicht alle synchron sind.
    // Aus dem Objekt-Ursprung abgeleitet (MODEL_MATRIX), NICHT pro Vertex.
    float obj_phase = sin(MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3) * 6.28;

    // Böigkeit: zwei langsame Sinus mit ungleichen Frequenzen überlagern.
    // Das erzeugt ein unregelmäßiges An- und Abschwellen statt gleichmäßigem Wabern.
    float t = TIME * wind_speed;
    float gust = sin(t + obj_phase) * 0.6
               + sin(t * 0.37 + obj_phase * 1.7) * 0.4;

    // Hauptbewegung: ganzes Blatt-Objekt wiegt sich als Einheit
    vec2 dir = normalize(wind_direction);
    float sway = gust * wind_strength * wind_mask;

    // Feines Flattern: deutlich reduziert und langsamer, nur als Akzent.
    // Nutzt obj_phase statt VERTEX-Position -> kein Verwabern mehr.
    float flutter = sin(t * wind_flutter_speed + obj_phase) * wind_flutter * wind_mask;

    VERTEX.x += dir.x * (sway + flutter);
    VERTEX.z += dir.y * (sway + flutter);
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 base = texture(albedo_texture, UV) * albedo_color;

    // 3D-Sichtlinie Kamera -> Player
    vec3 cam = camera_world_position;
    vec3 ply = player_world_position;
    vec3 axis = ply - cam;
    float axis_len = length(axis);
    vec3 axis_dir = (axis_len > 0.001) ? axis / axis_len : vec3(0.0, 0.0, 1.0);

    // Fragment relativ zur Kamera
    vec3 to_frag = v_world_pos - cam;

    // Projektion auf die Achse: t=0 an Kamera, t=axis_len am Player
    float t = dot(to_frag, axis_dir);

    // Senkrechter 3D-Abstand zur Sichtlinie (rundherum gleich)
    vec3 closest = cam + axis_dir * t;
    float perpendicular = length(v_world_pos - closest);

    // Nur im Segment ZWISCHEN Kamera und Player aktiv
    float in_segment = smoothstep(0.0, behind_player_falloff, t)
                 * (1.0 - smoothstep(axis_len - behind_player_falloff, axis_len, t));

     // t normalisiert: 0 = Kamera, 1 = Player
    float t_norm = clamp(t / axis_len, 0.0, 1.0);

    // Radius verjüngt sich zum Player hin (und leicht zur Kamera),
    // breit in der Mitte der Sichtlinie. sin(pi*x) = 0 an beiden Enden, 1 in der Mitte.
    float radius_profile = sin(t_norm * 3.14159);
    float dynamic_radius = occlusion_radius * radius_profile;

    float radial = smoothstep(
        dynamic_radius - occlusion_softness,
        dynamic_radius + occlusion_softness,
        perpendicular
    );
    radial = mix(1.0, radial, in_segment);

    // 3) Zwei-oktavige Noise mit Wobble
    vec2 wobble_offset = vec2(
        sin(TIME * wobble_speed) * wobble_scale,
        cos(TIME * wobble_speed * 0.7) * wobble_scale
    );
    vec2 nuv_a = v_world_pos.xz * (noise_scale   * 0.1) + wobble_offset;
    vec2 nuv_b = v_world_pos.xz * (noise_scale_2 * 0.1) - wobble_offset * 0.6;
    float n_a = texture(edge_noise, nuv_a).r - 0.5;
    float n_b = texture(edge_noise, nuv_b).r - 0.5;
    float n_combined = n_a * noise_strength + n_b * noise_strength_2;

    float edge_factor = 1.0 - abs(radial - 0.5) * 2.0;
    radial = clamp(radial + n_combined * edge_factor, 0.0, 1.0);

    // 4) Höhenmaske
    float h_above = v_world_pos.y - (player_world_position.y + height_threshold);
    float h_mask  = smoothstep(0.0, height_softness, h_above);

    // 5) Final Alpha
    float occlusion   = (1.0 - radial) * h_mask;
    float final_alpha = mix(1.0, min_alpha, occlusion);

    // 6) Rim Light — schmaler Ring exakt am Übergang, NUR wo wir occluden
    //    rim_band ist nur dort > 0, wo radial in [0.5-w, 0.5+w] liegt
    float rim_band = (1.0 - smoothstep(rim_width, rim_width * 2.0, abs(radial - 0.5)))
                   * h_mask * in_segment;
    vec3 rim_emission = rim_color * rim_band * rim_strength;
	
	if (debug_occlusion) {
        // occlusion = 1.0 -> wird ausgeblendet (rot), 0.0 -> sichtbar (grün)
        ALBEDO = vec3(occlusion, 1.0 - occlusion, 0.0);
        EMISSION = vec3(occlusion, 1.0 - occlusion, 0.0) * 0.5;
        ALPHA = 1.0;  // alles sichtbar lassen zum Debuggen
          // restliche Berechnung überspringen
    } else {
	    ALBEDO = base.rgb * instance_tint;
	    EMISSION = rim_emission;
	    ALPHA    = base.a * final_alpha;
	    ALPHA_HASH_SCALE = 1.0;
	}



}