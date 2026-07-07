shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, depth_test_disabled;

uniform float splash_time = 0.0;
uniform float lifetime = 0.7;
uniform float intensity = 1.0;

uniform sampler2D noise_tex    : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_pattern : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);

uniform float flow_speed   : hint_range(0.0, 4.0, 0.05) = 0.8;
uniform float density      : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float emission     : hint_range(0.0, 2.0, 0.05) = 0.25;
uniform float ring_count     : hint_range(2.0, 20.0, 0.5) = 6.0;
uniform float ring_speed     : hint_range(0.0, 4.0, 0.05) = 1.5;
uniform float ring_strength  : hint_range(0.0, 2.0, 0.01) = 0.8;
uniform float ring_sharpness : hint_range(1.0, 8.0, 0.1) = 2.5;
uniform float angular_chaos  : hint_range(0.0, 1.0, 0.01) = 0.15;

varying float v_life01;

void vertex() {
    v_life01 = clamp(splash_time / lifetime, 0.0, 1.0);
}

void fragment() {
    vec2 centered = UV - vec2(0.5);
    float dist = length(centered);
    float angle = atan(centered.y, centered.x);

    // Ring-Front breitet sich über die Lebensdauer nach außen aus
    float front = 0.1 + 0.35 * smoothstep(0.0, 0.85, v_life01) * intensity;

    // Konzentrische Wellen (nutzen splash_time statt TIME für Einmaligkeit)
    float ring_phase = dist * ring_count - splash_time * ring_speed * 4.0;
    float ring_wave = sin(ring_phase * 6.2831) * 0.5 + 0.5;
    ring_wave = pow(ring_wave, ring_sharpness);

    float angular_noise = texture(noise_tex, vec2(angle / 6.2831, dist) * vec2(3.0, 4.0) + vec2(0.0, -splash_time * 0.5)).r;
    angular_noise = mix(1.0, angular_noise, angular_chaos);

    vec2 polar_uv = vec2(angle / 6.2831 + splash_time * 0.02, dist);
    vec2 scroll_uv = polar_uv * vec2(3.0, 4.0) + vec2(0.0, -splash_time * flow_speed * 2.0);
    float pattern = texture(foam_pattern, scroll_uv).r;
    float noise = texture(noise_tex, polar_uv * vec2(5.0, 7.0) + vec2(splash_time * 0.1, 0.0)).r;
    float foam_detail = smoothstep(1.0 - density, 1.0, pattern * noise);
    float foam_rings = ring_wave * ring_strength * angular_noise;
    float foam = clamp(foam_detail + foam_rings, 0.0, 1.0);

    // Ring-Maske: wächst nach außen, innen ausgehöhlt
    float edge_noise = texture(noise_tex, vec2(angle / 6.2831 * 4.0, splash_time * 0.1)).r;
    float perturbed_dist = dist + (edge_noise - 0.5) * 0.05;
    float inner = smoothstep(front * 0.3, front * 0.5, perturbed_dist);
    float outer = 1.0 - smoothstep(front * 0.7, front, perturbed_dist);
    float radial_mask = inner * outer;
    float final_foam = clamp(foam * radial_mask, 0.0, 1.0);

    // Ein- und Ausfaden über die Lebensdauer
    float fade = smoothstep(0.0, 0.1, v_life01) * (1.0 - smoothstep(0.5, 1.0, v_life01));

    ALBEDO   = foam_color.rgb;
    EMISSION = foam_color.rgb * emission;
    ALPHA    = final_foam * foam_color.a * fade;
}