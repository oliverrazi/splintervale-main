shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform int posterize_levels : hint_range(2, 16) = 4;
uniform vec3 stylized_ambient : source_color = vec3(0.3, 0.3, 0.4);

void fragment() {
    vec4 albedo_col = texture(albedo_texture, UV);
    ALBEDO = albedo_col.rgb;
}

void light() {
    float ndotl = max(dot(NORMAL, LIGHT), 0.0);
    float posterized = round(ndotl * (float(posterize_levels) - 1.0)) / (float(posterize_levels) - 1.0);
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * posterized * ATTENUATION;
    
    // Ambient als minimum hinzu (nicht akkumulieren über mehrere Lichter)
    DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, ALBEDO * stylized_ambient);
}