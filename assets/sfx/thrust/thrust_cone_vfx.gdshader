shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled;

// === FARBEN ===
uniform vec4 CoreColor : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 EdgeColor : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 StreakColor : source_color = vec4(1.0, 0.8, 0.3, 1.0);

// === DOME ===
uniform float dome_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float dome_alpha : hint_range(0.0, 1.0) = 0.6;

// === STREAKS ===
uniform float streak_count : hint_range(2.0, 20.0) = 8.0;
uniform float streak_speed : hint_range(0.0, 10.0) = 3.0;
uniform float streak_width : hint_range(0.01, 0.3) = 0.08;
uniform float streak_intensity : hint_range(0.0, 5.0) = 3.0;

// === ANIMATION ===
uniform float flicker : hint_range(0.5, 1.5) = 1.0;
uniform float time_offset : hint_range(0.0, 100.0) = 0.0;

// Pseudo-random
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

void fragment() {
    // === DOME FORM ===
    // UV.y: 0 = unten, 1 = oben (für Sphere)
    float height = UV.y;
    
    // Nur obere Hälfte zeigen (Hemisphere)
    if (height < 0.45) {
        discard;
    }
    
    // Dome-Gradient: oben hell, unten dunkler
    float dome_factor = smoothstep(0.45, 1.0, height);
    
    // Basis Dome-Farbe
    vec3 dome_color = mix(EdgeColor.rgb, CoreColor.rgb, dome_factor);
    float dome_a = dome_factor * dome_alpha * flicker;
    
    // === STREAKS ===
    // Horizontale Position (um die Kuppel herum)
    float angle = UV.x * 16.28318; // 0 bis 2*PI
    
    // Mehrere Streifen
    float streaks = 0.0;
    for (float i = 0.0; i < 12.0; i++) {
        if (i >= streak_count) break;
        
        // Jeder Streak hat eigene Phase und Geschwindigkeit
        float phase = hash(i * 17.3) * 6.28318;
        float speed_var = 0.7 + hash(i * 31.7) * 0.6;
        
        // Streak Position (läuft nach unten)
        float streak_pos = fract((TIME + time_offset) * streak_speed * speed_var * 0.1 + hash(i * 13.1));
        
        // Streak ist nur sichtbar wenn er "fällt" (von oben nach unten)
        float streak_y = 1.0 - streak_pos; // 1 = oben, 0 = unten
        
        // Vertikale Nähe zum Streak
        float y_dist = abs(height - streak_y);
        float y_mask = smoothstep(0.15, 0.0, y_dist);
        
        // Horizontale Position des Streaks
        float streak_angle = phase + i * (6.28318 / streak_count);
        float angle_dist = abs(sin((angle - streak_angle) * 0.5));
        float x_mask = smoothstep(streak_width, 0.0, angle_dist);
        
        // Streak Intensität (stärker oben, schwächer unten)
        float streak_fade = streak_y;
        
        streaks += x_mask * y_mask * streak_fade;
    }
    
    streaks = clamp(streaks, 0.0, 1.0);
    
    // === KOMBINIEREN ===
    vec3 final_color = dome_color;
    final_color += StreakColor.rgb * streaks * streak_intensity * flicker;
    
    float final_alpha = dome_a + streaks * 0.8 * flicker;
    final_alpha = clamp(final_alpha, 0.0, 1.0);
    
    // === OUTPUT ===
    ALBEDO = final_color;
    EMISSION = final_color * dome_intensity * flicker;
    ALPHA = final_alpha;
}