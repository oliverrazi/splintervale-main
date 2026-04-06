shader_type spatial;

render_mode specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	ROUGHNESS = 0.0;
	METALLIC = 0.0;
	SPECULAR = 1.0;
}
