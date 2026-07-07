shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded;

uniform vec3 mist_color : source_color = vec3(0.95, 0.98, 1.0);
uniform sampler2D mist_tex : source_color;
uniform float base_alpha : hint_range(0.0, 1.0, 0.01) = 0.35;

void fragment() {
    vec4 tex = texture(mist_tex, UV);
    ALBEDO = mist_color;
    // Alpha aus Textur mal Basiswert — dezenter Dunst, nicht deckend
    ALPHA = tex.a * base_alpha;
    EMISSION = mist_color * 0.1;
}