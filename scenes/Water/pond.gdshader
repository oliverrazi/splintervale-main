shader_type spatial;
render_mode blend_mix;

uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// --- Farben (teichig: grün-türkis, schnell dunkel) ---
uniform vec4 color_shallow : source_color = vec4(0.15, 0.42, 0.38, 1.0);
uniform vec4 color_deep    : source_color = vec4(0.04, 0.10, 0.14, 1.0);
uniform vec4 color_fresnel : source_color = vec4(0.50, 0.75, 0.80, 1.0);
uniform vec4 foam_color    : source_color = vec4(0.88, 0.94, 0.90, 1.0);

// --- Foam ---
uniform float edge_scale     : hint_range(0.0, 3.0, 0.01) = 0.35;
uniform float foam_sharpness : hint_range(1.0, 8.0, 0.1)  = 4.0;

// --- Tiefe (höheres beers_law = schneller trüb) ---
uniform float beers_law    : hint_range(0.1, 10.0, 0.05) = 5.0;
uniform float depth_offset = -0.3;

// --- Wellen (sehr subtil für stehende Gewässer) ---
uniform sampler2D wave            : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D texture_normal  : hint_normal,        filter_linear, repeat_enable;
uniform sampler2D texture_normal2 : hint_normal,        filter_linear, repeat_enable;
uniform vec2  wave_direction  = vec2(0.3,  0.15);
uniform vec2  wave_direction2 = vec2(-0.1, 0.25);
uniform float time_scale     : hint_range(0.0, 0.2, 0.005) = 0.008;
uniform float noise_scale    = 12.0;
uniform float height_scale   = 0.04;   // kaum Wellenhöhe
uniform float normal_strength : hint_range(0.0, 2.0, 0.05) = 0.5;

// --- Fresnel (stärker = spiegeliger) ---
uniform float fresnel_power : hint_range(1.0, 12.0, 0.1) = 6.5;
uniform float fresnel_blend : hint_range(0.0, 1.0, 0.01) = 0.55;

// --- Refraktion ---
uniform float refraction_strength : hint_range(0.0, 1.0, 0.01) = 0.08;

// --- Caustics (AAA-Feature für stehende Gewässer) ---
uniform float caustic_scale  : hint_range(0.5, 10.0, 0.1) = 3.0;
uniform float caustic_speed  : hint_range(0.0, 2.0, 0.05) = 0.4;
uniform float caustic_power  : hint_range(0.5, 6.0, 0.1)  = 2.5;
uniform float caustic_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform vec3  caustic_color  : source_color = vec3(0.55, 0.90, 0.85);

// --- Surface ---
uniform float metallic  : hint_range(0.0, 1.0) = 0.08;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;

varying float height;
varying vec3  world_pos;

// -------------------------------------------------------

float fresnel_f(float power, vec3 normal, vec3 view) {
    return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), power);
}

// Zwei überlagerte Sinuswellen → Caustic-Interferenzmuster
float caustic_pattern(vec2 uv, float t) {
    vec2 p = uv * caustic_scale;
    float a = sin(p.x * 2.8 + t * caustic_speed + sin(p.y * 2.3 + t * caustic_speed * 0.7)) * 0.5 + 0.5;
    float b = sin(p.y * 3.1 - t * caustic_speed * 0.9 + sin(p.x * 3.5 - t * caustic_speed * 1.1)) * 0.5 + 0.5;
    return pow(clamp((a + b) * 0.5, 0.0, 1.0), caustic_power);
}

// -------------------------------------------------------

void vertex() {
    world_pos  = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    height     = texture(wave, world_pos.xz / noise_scale + TIME * time_scale).r;
    VERTEX.y  += height * height_scale;
}

void fragment() {
    // --- Tiefe (Reverse-Z-safe) ---
    float raw_depth  = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    vec4  scene_ndc  = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
    vec4  scene_view = INV_PROJECTION_MATRIX * scene_ndc;
    scene_view      /= scene_view.w;
    float scene_z    = scene_view.z;
    float water_z    = VERTEX.z;
    float depth_diff = max(water_z - scene_z, 0.0);

    float depth_blend       = clamp(1.0 - exp(depth_diff * -beers_law), 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    // --- Foam ---
    float foam = pow(clamp(1.0 - depth_diff / edge_scale, 0.0, 1.0), foam_sharpness);

    // --- Normalmaps ---
    vec2 t1 = TIME * wave_direction  * time_scale;
    vec2 t2 = TIME * wave_direction2 * time_scale;
    vec3 n1 = texture(texture_normal,  world_pos.xz / noise_scale + t1).rgb;
    vec3 n2 = texture(texture_normal2, world_pos.xz / noise_scale + t2).rgb;
    vec3 normal_map_val = mix(n1, n2, 0.5);
    vec2 normal_offset  = (normal_map_val.xy * 2.0 - 1.0) * normal_strength;

    // --- Fresnel ---
    float fr = fresnel_f(fresnel_power, NORMAL, VIEW);

    // --- Refraktion (in Shore-Zone unterdrückt) ---
    float shore_fade = pow(clamp(1.0 - depth_diff / (edge_scale * 4.0), 0.0, 1.0), 1.5);
    float refr_fade  = (1.0 - depth_blend_power) * refraction_strength * 0.015 * (1.0 - shore_fade);
    vec2  ref_uv     = SCREEN_UV + normal_offset * refr_fade;
    vec3  screen_col = textureLod(SCREEN_TEXTURE, ref_uv, depth_blend_power * 2.5).rgb;

    // --- Caustics (nur in flachen, durchsichtigen Bereichen sichtbar) ---
    float c1 = caustic_pattern(world_pos.xz, TIME);
    float c2 = caustic_pattern(world_pos.xz * 1.3 + vec2(3.7, 1.2), TIME * 0.8);
    float caustics = max(c1, c2);                       // zwei Layer überlagert
    float caustic_fade = (1.0 - depth_blend_power);    // nur in flachem Wasser
    caustic_fade *= (1.0 - foam);                       // nicht in Foam-Zone
    vec3 caustic_contribution = caustic_color * caustics * caustic_strength * caustic_fade;

    // --- Wasserfarbe ---
    vec3 depth_col = mix(color_shallow.rgb, color_deep.rgb, depth_blend_power);
    vec3 water_col = mix(screen_col, depth_col, depth_blend_power * 0.9);
    water_col      = mix(water_col, color_fresnel.rgb, fr * fresnel_blend);

    // Caustics additiv auf den Untergrund
    water_col += caustic_contribution;

    // Shore + Foam
    vec3 final_col = mix(water_col, color_shallow.rgb, shore_fade * 0.6);
    final_col      = mix(final_col, foam_color.rgb, foam);

    // --- Alpha ---
    float water_alpha = mix(0.72, 0.95, depth_blend_power);
    ALPHA      = mix(water_alpha, 1.0, foam);
    ALBEDO     = final_col;
    METALLIC   = metallic;
    ROUGHNESS  = roughness;
    NORMAL_MAP = normal_map_val;
}