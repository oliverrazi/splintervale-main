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

// Inner Rim Light
uniform vec3  rim_color    : source_color = vec3(0.55, 0.8, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0)  = 0.45;
uniform float rim_width    : hint_range(0.02, 0.4) = 0.12;

varying vec3 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 base = texture(albedo_texture, UV) * albedo_color;

    // 1) Camera→Player-Achse berechnen
    vec2 cam_xz    = camera_world_position.xz;
    vec2 player_xz = player_world_position.xz+0.7;
    vec2 frag_xz   = v_world_pos.xz;

    vec2 cam_to_player = player_xz - cam_xz;
    float cp_len = length(cam_to_player);
    vec2 line_dir = (cp_len > 0.001) ? cam_to_player / cp_len : vec2(0.0, 1.0);

    vec2 to_frag = frag_xz - player_xz;
    // Senkrechte Distanz zur Sichtachse — das wird unsere "Aussparungs-Säule"
    float perpendicular = abs(to_frag.x * line_dir.y - to_frag.y * line_dir.x);
    // Position entlang der Achse: < 0 vor Player (Camera-seitig), > 0 hinter Player
    float along = dot(to_frag, line_dir);

    // Hinter dem Player wird der Effekt sanft ausgeschaltet
    float forward_mask = 1.0 - smoothstep(0.0, behind_player_falloff, along);

    // 2) Basis-Sichtbarkeit aus perpendicular-Distanz
    float radial = smoothstep(
        occlusion_radius - occlusion_softness,
        occlusion_radius + occlusion_softness,
        perpendicular
    );
    radial = mix(1.0, radial, forward_mask);

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
                   * h_mask * forward_mask;
    vec3 rim_emission = rim_color * rim_band * rim_strength;

    ALBEDO   = base.rgb;
    EMISSION = rim_emission;
    ALPHA    = base.a * final_alpha;
    ALPHA_HASH_SCALE = 1.0;
}