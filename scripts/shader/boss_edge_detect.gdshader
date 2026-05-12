shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform float depth_threshold : hint_range(0.0, 0.5, 0.0001) = 0.005;
uniform float outline_thickness : hint_range(1.0, 3.0, 0.5) = 1.0;

void vertex() {
    // Quad auf den vollen NDC-Bereich strecken, Position des Nodes wird irrelevant
    POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
    vec2 texel = 1.0 / vec2(textureSize(screen_tex, 0));
    vec2 offset = texel * outline_thickness;
    
    float d_c = texture(depth_tex, SCREEN_UV).r;
    
    // Sky-Pixel transparent lassen
    if (d_c < 0.0001) {
        discard;
    }
    
    float d_l = texture(depth_tex, SCREEN_UV - vec2(offset.x, 0.0)).r;
    float d_r = texture(depth_tex, SCREEN_UV + vec2(offset.x, 0.0)).r;
    float d_u = texture(depth_tex, SCREEN_UV - vec2(0.0, offset.y)).r;
    float d_d = texture(depth_tex, SCREEN_UV + vec2(0.0, offset.y)).r;
    
    float max_diff = max(
        max(abs(d_c - d_l), abs(d_c - d_r)),
        max(abs(d_c - d_u), abs(d_c - d_d))
    );
    
    bool neighbor_is_sky = (d_l < 0.0001) || (d_r < 0.0001) || (d_u < 0.0001) || (d_d < 0.0001);
    bool is_outline = neighbor_is_sky || max_diff > depth_threshold;
    
    if (is_outline) {
        ALBEDO = outline_color.rgb;
    } else {
        ALBEDO = texture(screen_tex, SCREEN_UV).rgb;
    }
}