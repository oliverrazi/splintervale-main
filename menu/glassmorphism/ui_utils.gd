extends Node

# Fügt einen Blur-Effekt zum gesamten Hintergrund eines Menüs hinzu
func add_background_blur(parent: Control, blur_amount: float = 3.0) -> ColorRect:
	if parent == null:
		return null
	
	if parent.has_node("FullScreenBlur"):
		return parent.get_node("FullScreenBlur") as ColorRect
	
	var blur_rect := ColorRect.new()
	blur_rect.name = "FullScreenBlur"
	blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 10.0) = 3.0;
uniform float darken : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE;
	vec4 color = vec4(0.0);
	
	float weights[9] = {0.0625, 0.125, 0.0625, 0.125, 0.25, 0.125, 0.0625, 0.125, 0.0625};
	vec2 offsets[9] = {
		vec2(-1, -1), vec2(0, -1), vec2(1, -1),
		vec2(-1, 0), vec2(0, 0), vec2(1, 0),
		vec2(-1, 1), vec2(0, 1), vec2(1, 1)
	};
	
	for (int i = 0; i < 9; i++) {
		color += texture(screen_texture, SCREEN_UV + offsets[i] * ps * blur_amount) * weights[i];
	}
	
	// Abdunkeln
	color.rgb *= (1.0 - darken);
	color.a = 1.0;
	
	COLOR = color;
}
"""
	
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("blur_amount", blur_amount)
	material.set_shader_parameter("darken", 0.3)
	blur_rect.material = material
	
	parent.add_child(blur_rect)
	parent.move_child(blur_rect, 0)
	
	return blur_rect


# Glass-Effekt für einzelne Panels (ohne echten Blur, aber mit Glas-Look)
func create_glass_style(tint_color: Color = Color(0.1, 0.1, 0.15, 0.85), corner_radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint_color
	
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	
	# Heller Rand oben für Glas-Reflektion
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	
	# Innerer Schatten-Effekt
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.2)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.content_margin_left = 16
	style.content_margin_right = 16
	
	return style
