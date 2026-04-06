shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
    vec2 texture_size = vec2(1152.0, 648.0);
    vec2 pixel = SCREEN_UV * texture_size;
    vec2 smooth_frac = smoothstep(0.2, 0.8, fract(pixel));
    vec2 smooth_uv = (floor(pixel) + smooth_frac) / texture_size;
    
    COLOR = texture(screen_texture, smooth_uv);
}