shader_type spatial;
render_mode cull_front, depth_draw_opaque, unshaded;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform float outline_width = 0.003;

void vertex() {
    VERTEX += NORMAL * outline_width;
}

void fragment() {
    ALBEDO = outline_color.rgb;
}