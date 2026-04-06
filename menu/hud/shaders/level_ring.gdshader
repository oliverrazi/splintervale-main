shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 ring_bg_color : source_color = vec4(0.3, 0.3, 0.3, 0.6);
uniform float ring_width : hint_range(0.01, 0.15) = 0.06;
uniform float inner_shadow : hint_range(0.0, 0.1) = 0.03;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    float outer = 0.5;
    float inner = outer - ring_width;

    if (dist < inner - inner_shadow || dist > outer) {
        COLOR = vec4(0.0);
    }

    if (dist >= inner && dist <= outer) {
        // Winkel: Start oben, Uhrzeigersinn
        float angle = atan(uv.x, -uv.y);
        float normalized = (angle / (2.0 * PI)) + 0.5;

        if (normalized <= progress) {
            // Aktiver Teil: leuchtet
            float glow = 1.0 - smoothstep(inner, outer, dist) * 0.3;
            COLOR = vec4(ring_color.rgb * glow, ring_color.a);
        } else {
            COLOR = ring_bg_color;
        }
    } else {
        // Inner shadow
        float shadow = smoothstep(inner - inner_shadow, inner, dist) * 0.5;
        COLOR = vec4(0.0, 0.0, 0.0, shadow);
    }
}