shader_type spatial;

render_mode 
    blend_premul_alpha,
    depth_prepass_alpha,
    cull_back,
    diffuse_burley,
    specular_schlick_ggx;

uniform sampler2D height_map : hint_default_black;
uniform sampler2D normal_map : hint_normal;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable;

uniform float parallax_scale = 0.06;
uniform int parallax_steps = 32;

uniform float ior = 1.45;
uniform vec3 absorption_color = vec3(0.2, 0.7, 1.0);
uniform float absorption_strength = 2.0;

uniform float roughness = 0.08;
uniform float refraction_strength = 0.15;

varying vec3 v_world_pos;
varying mat3 v_tbn_ws;

vec2 pom(vec2 uv, vec3 view_dir_ts) {
    int steps = max(parallax_steps, 8);
    float layer_depth = 1.0 / float(steps);
    float current_layer = 0.0;

    vec2 delta_uv =
        (view_dir_ts.xy / max(view_dir_ts.z, 0.001)) *
        (parallax_scale / float(steps));

    vec2 cur_uv = uv;
    float h = texture(height_map, cur_uv).r;

    for (int i = 0; i < steps; i++) {
        if (current_layer >= h) break;
        cur_uv -= delta_uv;
        h = texture(height_map, cur_uv).r;
        current_layer += layer_depth;
    }

    return cur_uv;
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // TBN in World Space
    vec3 Nws = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    vec3 Tws = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
    vec3 Bws = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);

    v_tbn_ws = mat3(Tws, Bws, Nws);
}

void fragment() {
    // World-space view dir (from fragment to camera)
    vec3 Vws = normalize(CAMERA_POSITION_WORLD - v_world_pos);

    // Convert to tangent space
    vec3 Vts = normalize(transpose(v_tbn_ws) * Vws);

    vec2 uv_p = pom(UV, Vts);

    // Normal mapping (Godot expects tangent-space normal map here)
    NORMAL_MAP = texture(normal_map, uv_p).rgb;
    NORMAL_MAP_DEPTH = 1.0;

    // Fresnel
    float F0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
    float NoV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float fresnel = F0 + (1.0 - F0) * pow(1.0 - NoV, 5.0);

    // Screen-space refraction
    vec2 screen_uv = SCREEN_UV + NORMAL.xy * refraction_strength;
    vec3 refracted = texture(screen_tex, screen_uv).rgb;

    // Absorption (Beer–Lambert)
    float thickness = (1.0 - texture(height_map, uv_p).r) * parallax_scale;
    vec3 transmittance = exp(-absorption_color * absorption_strength * thickness);
    refracted *= transmittance;

    ALBEDO = refracted;
    METALLIC = 0.0;
    ROUGHNESS = roughness;
    SPECULAR = 1.0;

    EMISSION = refracted * fresnel * 0.25;
    ALPHA = 0.85;
}
