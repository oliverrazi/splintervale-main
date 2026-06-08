shader_type canvas_item;

// =============================================================
//  Dialogue Background mit weichem Rand-Fade
//
//  Wichtig: respektiert das geerbte modulate vom Parent-Control.
//  Vorher hat der Shader COLOR komplett aus bg_color geschrieben
//  und damit modulate ignoriert - so liess sich der Hintergrund
//  nicht uebers Panel mit ein-/ausfaden.
// =============================================================

uniform vec4 bg_color : source_color = vec4(0.05, 0.05, 0.1, 0.7);
uniform vec2 rect_size = vec2(1000.0, 150.0);
uniform float fade_px : hint_range(0.0, 200.0) = 40.0;
uniform float fade_power : hint_range(0.1, 4.0) = 1.4;

void fragment() {
    vec2 dist_px = min(UV, 1.0 - UV) * rect_size;
    float min_dist = min(dist_px.x, dist_px.y);
    float mask = pow(clamp(min_dist / fade_px, 0.0, 1.0), fade_power);

    // COLOR kommt von Godot als (vertex_color * modulate * self_modulate).
    // Wir multiplizieren bg_color damit -> Panel-modulate.a faded den
    // Hintergrund sauber mit aus.
    vec4 base = vec4(bg_color.rgb, bg_color.a * mask);
    COLOR = base * COLOR;
}
