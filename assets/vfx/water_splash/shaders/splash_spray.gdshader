shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded;

uniform vec3 foam_color : source_color = vec3(0.97, 0.99, 1.0);
uniform sampler2D streak_tex : source_color;

void fragment() {
    vec4 tex = texture(streak_tex, UV);
    ALBEDO = foam_color;
    ALPHA = tex.a;
    EMISSION = foam_color * 0.15;
}