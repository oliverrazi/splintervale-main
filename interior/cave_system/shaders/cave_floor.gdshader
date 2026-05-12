shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Basis-Textur
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : filter_linear_mipmap, repeat_enable;

// Optionaler Detail-Layer (kleine Risse, Poren)
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_normal_strength : hint_range(0.0, 1.0) = 0.3;
uniform float detail_uv_scale = 4.0;

// Basis-Werte
uniform vec4 base_color : source_color = vec4(0.25, 0.22, 0.2, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.3;

// Vertex Color Einfluss
uniform float color_influence : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    // Basis-Textur
    vec4 albedo = texture(albedo_tex, UV);
    vec3 tex_normal = texture(normal_tex, UV).rgb;
    float tex_roughness = texture(roughness_tex, UV).r;

    // Detail-Normal (höhere UV-Frequenz für Mikro-Detail)
    vec3 detail_n = texture(detail_normal_tex, UV * detail_uv_scale).rgb;

    // Vertex Color auslesen
    // RGB = Farb/Helligkeitsmodulation
    // Alpha = Trockenheit (1 = trocken, 0 = nass)
    vec3 vc_rgb = COLOR.rgb;
    float dryness = COLOR.a;

    // ── Albedo ──
    vec3 final_albedo = albedo.rgb * base_color.rgb;
    // Vertex Color multiplizieren (hell/dunkel + Farbshift)
    final_albedo *= mix(vec3(1.0), vc_rgb, color_influence);
    // Nasse Stellen abdunkeln
    float wetness = 1.0 - dryness;
    final_albedo *= mix(1.0, 1.0 - wet_darkening, wetness);

    // ── Roughness ──
    float final_roughness = tex_roughness * base_roughness;
    // Nasse Stellen glatter
    final_roughness = mix(final_roughness, wet_roughness, wetness * 0.7);

    // ── Normalen ──
    // Basis + Detail-Layer mischen
    vec3 base_n = tex_normal * 2.0 - 1.0;
    vec3 det_n = detail_n * 2.0 - 1.0;
    det_n.xy *= detail_normal_strength;
    // Reoriented Normal Mapping (besseres Blending)
    vec3 combined_n;
    combined_n.xy = base_n.xy + det_n.xy;
    combined_n.z = base_n.z;
    combined_n = normalize(combined_n);

    ALBEDO = final_albedo;
    ROUGHNESS = final_roughness;
    NORMAL_MAP = combined_n * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;

    // Leichter Specular-Boost für nasse Stellen
    SPECULAR = mix(0.3, 0.6, wetness);
}