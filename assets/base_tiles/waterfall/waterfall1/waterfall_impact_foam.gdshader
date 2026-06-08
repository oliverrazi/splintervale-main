shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D noise_tex    : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_pattern : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float flow_speed   : hint_range(0.0, 4.0, 0.05) = 0.8;
uniform float inner_solid  : hint_range(0.0, 0.5, 0.01) = 0.12; // voller Schaum
uniform float outer_radius : hint_range(0.0, 0.5, 0.01) = 0.48;
uniform float density      : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float opacity      : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float emission     : hint_range(0.0, 2.0, 0.05) = 0.35;

void fragment() {
    vec2 centered = UV - vec2(0.5);
    float dist = length(centered);
    float angle = atan(centered.y, centered.x);

    // Polar-UV: scrollt nach außen
    vec2 polar_uv = vec2(angle / 6.2831 + TIME * 0.02, dist);
    vec2 scroll_uv = polar_uv * vec2(3.0, 4.0) + vec2(0.0, -TIME * flow_speed);

    float pattern = texture(foam_pattern, scroll_uv).r;
    float noise   = texture(noise_tex, polar_uv * vec2(5.0, 7.0) + vec2(TIME * 0.1, 0.0)).r;

    float foam = smoothstep(1.0 - density, 1.0, pattern * noise);

    // Innerer voller Schaum + abklingender Außenrand
    float center_solid = 1.0 - smoothstep(0.0, inner_solid, dist);
    float outer_fade   = 1.0 - smoothstep(outer_radius * 0.6, outer_radius, dist);
    float radial_mask  = smoothstep(inner_solid, inner_solid + 0.05, dist) * outer_fade;

    float final_foam = clamp(foam * radial_mask + center_solid, 0.0, 1.0);

    ALBEDO   = foam_color.rgb;
    EMISSION = foam_color.rgb * emission;
    ALPHA    = final_foam * opacity;
}