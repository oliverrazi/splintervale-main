shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, depth_test_disabled;

// Weiches, rundes Rauch-Billboard
// Wird als Mesh-Material auf QuadMesh der GPUParticles3D gesetzt

uniform sampler2D smoke_texture : hint_default_white;
uniform float softness : hint_range(0.1, 1.0) = 0.55;

void fragment() {
    // Erzeuge weiche Kreisform aus UV
    vec2 uv = UV - 0.5;
    float dist = length(uv) * 2.0;
    float alpha = 1.0 - smoothstep(softness, 1.0, dist);
    // Zusätzlich: innere Turbulenz durch Noise-artige Verzerrung
    float noise = sin(UV.x * 12.0 + TIME * 0.3) * cos(UV.y * 11.0 + TIME * 0.25) * 0.05;
    alpha *= max(0.0, 1.0 - smoothstep(softness + noise, 1.0, dist));

    // Farbe kommt aus dem Particle-COLOR (vom process-Shader oben)
    vec4 particle_color = COLOR;
    ALBEDO = particle_color.rgb;
    ALPHA  = particle_color.a * alpha;
}
