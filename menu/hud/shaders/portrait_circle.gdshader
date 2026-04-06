shader_type canvas_item;

uniform sampler2D portrait_texture : source_color;
uniform vec2 portrait_offset = vec2(0.0, -0.1); // Portrait vertikal verschieben
uniform float portrait_scale = 1.2;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    // Außerhalb des Kreises: unsichtbar
    if (dist > 0.5) {
        COLOR = vec4(0.0);
    }

    // Portrait samplen mit Offset & Scale
    vec2 portrait_uv = (uv / portrait_scale) - portrait_offset + vec2(0.5);
    COLOR = texture(portrait_texture, portrait_uv);

    // Weiche Kante am Rand
    float edge = 1.0 - smoothstep(0.46, 0.5, dist);
    COLOR.a *= edge;
}