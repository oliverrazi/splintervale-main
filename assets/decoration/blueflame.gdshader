shader_type spatial;

render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Flame shape & animation
uniform float flame_speed : hint_range(0.5, 5.0) = 1.5;
uniform float flame_intensity : hint_range(0.5, 5.0) = 2.0;
uniform float flame_height : hint_range(0.5, 3.0) = 1.2;
uniform float flame_width : hint_range(0.1, 2.0) = 0.6;
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.35;

// Color control
uniform vec3 color_core : source_color = vec3(1.0, 1.0, 1.0);          // Weißer Kern
uniform vec3 color_mid : source_color = vec3(0.6, 0.8, 1.0);           // Hellblau
uniform vec3 color_outer : source_color = vec3(0.1, 0.3, 0.9);         // Tiefblau
uniform vec3 color_tip : source_color = vec3(0.05, 0.1, 0.4);          // Dunkelblaue Spitze

// --- Noise functions ---

// Hash function for pseudo-random values
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 2D value noise
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion (layered noise)
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// --- Flame shape ---

float flame_shape(vec2 uv, float time) {
	// Zentriere UV: x von -1..1, y von 0..1 (Basis unten)
	vec2 p = vec2((uv.x - 0.5) * 2.0 / flame_width, uv.y);

	// Turbulenz / Verzerrung
	float turb = fbm(vec2(p.x * 3.0, p.y * 2.0 - time * flame_speed), 5);
	p.x += (turb - 0.5) * distortion_strength * (p.y * p.y); // Mehr Verzerrung oben

	// Flammenform: schmaler nach oben, breiter an der Basis
	float taper = 1.0 - pow(p.y, flame_height);
	float width = taper * 1.0;
	float shape = 1.0 - smoothstep(0.0, width, abs(p.x));

	// Vertikaler Falloff
	float vertical = 1.0 - smoothstep(0.0, 1.0, p.y);
	vertical = pow(vertical, 0.8);

	// Flackern
	float flicker = 0.9 + 0.1 * sin(time * 8.0 + p.y * 5.0);
	flicker *= 0.95 + 0.05 * noise(vec2(time * 12.0, 0.0));

	return shape * vertical * flicker;
}

// --- Main ---

void fragment() {
	float time = TIME;
	vec2 uv = UV;

	// Berechne Flammenintensität
	float flame = flame_shape(uv, time);

	// Zusätzliche Noise-Schicht für Details
	float detail_noise = fbm(vec2(uv.x * 6.0 + time * 0.5, uv.y * 4.0 - time * flame_speed * 1.5), 4);
	flame *= 0.7 + 0.3 * detail_noise;
	
	float bottom_fade = smoothstep(0.02, 0.10, uv.y); // 0..1, blendet die untersten ~10% ein
	flame *= bottom_fade;

	// Farbverlauf basierend auf Intensität und Höhe
	float intensity = flame * flame_intensity;

	// Innerer Kern (weiß-heißer Bereich)
	float core_mask = smoothstep(0.3, 1.5, intensity) * (1.0 - smoothstep(0.0, 0.4, uv.y));

	// Mittlerer Bereich (hellblau)
	float mid_mask = smoothstep(0.15, 0.8, intensity);

	// Äußerer Bereich (tiefblau)
	float outer_mask = smoothstep(0.0, 0.3, intensity);

	// Spitze der Flamme
	float tip_mask = smoothstep(0.5, 0.9, uv.y) * outer_mask;

	// Farben zusammenmischen
	vec3 color = color_outer * outer_mask;
	color = mix(color, color_mid, mid_mask * 0.8);
	color = mix(color, color_core, core_mask);
	color = mix(color, color_tip, tip_mask * 0.5);

	// Finale Helligkeit
	color *= intensity;

	// Glow-Effekt für den Kern
	float glow = core_mask * 0.5;
	color += color_core * glow;

	ALBEDO = color;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
