shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// === FARBEN ===
uniform vec4 BaseColor : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform vec4 GlowColor : source_color = vec4(1.0, 0.6, 0.2, 1.0);

// === TEXTUREN ===
uniform sampler2D RingTexture : filter_linear, repeat_disable;
uniform sampler2D NoiseTexture : repeat_enable;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// === ANIMATION ===
uniform float progress : hint_range(0.0, 1.0) = 0.0; // 0 = Start, 1 = Vollkreis fertig
uniform float ring_thickness : hint_range(0.05, 0.5) = 0.15;
uniform float inner_radius : hint_range(0.1, 0.5) = 0.25;

// === EFFEKTE ===
uniform float GlowIntensity : hint_range(0.0, 5.0) = 2.5;
uniform float DistortionStrength : hint_range(0.0, 0.1) = 0.03;
uniform float trail_softness : hint_range(0.0, 0.5) = 0.1;

// === DISSOLVE ===
uniform float DissolveValue : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Zentrierte UV-Koordinaten (-1 bis 1)
	vec2 center_uv = UV * 2.0 - 1.0;
	
	// Polarkoordinaten
	float dist = length(center_uv);
	float angle = atan(center_uv.y, center_uv.x); // -PI bis PI
	float angle_normalized = (angle / 3.14159 + 1.0) * 0.5; // 0 bis 1
	
	// === RING MASKE ===
	float outer_radius = inner_radius + ring_thickness;
	float ring_mask = smoothstep(inner_radius - 0.02, inner_radius + 0.02, dist) 
	                * smoothstep(outer_radius + 0.02, outer_radius - 0.02, dist);
	
	// === WISCH-ANIMATION (Kreisförmig) ===
	// Progress bestimmt wie viel vom Kreis sichtbar ist
	float sweep_angle = progress * 2.0; // 0 bis 2 (für vollen Kreis)
	
	// Angle so verschieben dass Sweep bei "rechts" (0°) startet
	float adjusted_angle = mod(angle_normalized + 0.5, 1.0); // Start bei rechts
	
	// Sichtbarkeit basierend auf Sweep
	float sweep_mask = smoothstep(sweep_angle - trail_softness, sweep_angle, adjusted_angle);
	float trail_mask = smoothstep(0.0, trail_softness * 2.0, adjusted_angle);
	
	// Kombinierte Maske: Ring * Sweep * Trail-Fade
	float leading_edge = 1.0 - smoothstep(sweep_angle - 0.05, sweep_angle, adjusted_angle);
	float alpha = ring_mask * sweep_mask * trail_mask;
	
	// Hellerer "Kopf" des Sweeps
	float head_brightness = (1.0 - smoothstep(sweep_angle - 0.15, sweep_angle, adjusted_angle)) * 0.5;
	
	// === NOISE FÜR VARIATION ===
	vec2 noise_uv = vec2(angle_normalized * 3.0, dist * 2.0 + progress * 0.5);
	float noise = texture(NoiseTexture, noise_uv).r;
	alpha *= 0.7 + noise * 0.3;
	
	// === RING TEXTUR (optional) ===
	vec2 ring_uv = vec2(angle_normalized, (dist - inner_radius) / ring_thickness);
	vec4 ring_tex = texture(RingTexture, ring_uv);
	
	// === DISSOLVE ===
	float dissolve_noise = texture(NoiseTexture, UV * 2.0).r;
	float dissolve = smoothstep(DissolveValue - 0.1, DissolveValue + 0.1, dissolve_noise);
	alpha *= dissolve;
	
	// === DISTORTION ===
	vec2 distort_dir = normalize(center_uv);
	float distort_strength = DistortionStrength * alpha * (1.0 - alpha) * 4.0;
	vec2 screen_uv = SCREEN_UV + distort_dir * distort_strength;
	vec4 screen_col = texture(SCREEN_TEXTURE, screen_uv);
	
	// === FARBE ===
	vec3 base = BaseColor.rgb * ring_tex.rgb;
	vec3 final_color = base + head_brightness; // Hellerer Kopf
	
	ALBEDO = mix(screen_col.rgb, final_color, alpha);
	
	// === GLOW ===
	float glow_boost = 1.0 + head_brightness * 2.0; // Extra Glow am Kopf
	EMISSION = final_color * GlowColor.rgb * GlowIntensity * alpha * glow_boost;
	
	ALPHA = max(alpha, distort_strength * 0.1);
}
