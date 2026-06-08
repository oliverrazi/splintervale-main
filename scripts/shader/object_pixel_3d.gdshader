shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform vec4 base_color : source_color = vec4(0.65, 0.62, 0.58, 1.0);  // Stein-Ton
uniform int posterize_levels : hint_range(2, 16) = 4;
uniform vec3 stylized_ambient : source_color = vec3(0.3, 0.3, 0.4);

void fragment() {
	ALBEDO = base_color.rgb;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float posterized = round(ndotl * (float(posterize_levels) - 1.0)) / (float(posterize_levels) - 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * posterized * ATTENUATION;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, ALBEDO * stylized_ambient);
}