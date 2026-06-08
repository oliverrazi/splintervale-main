shader_type canvas_item;

// =============================================================
//  Low HP Vignette
//
//  Rot-bluetender Vignetten-Rand mit organischer Noise-Kontur und
//  Heartbeat-Puls. Wird vom LowHpVignette-Node ueber `intensity`
//  und `pulse` getrieben.
//
//  Reines Overlay (kein screen_texture), darum sehr guenstig.
//
//  r-Berechnung: length(SCREEN_UV - 0.5). Laeuft von 0 (Mitte) bis
//  ~0.707 (Ecke). vignette_radius/softness sind auf diesen Bereich
//  abgestimmt. Die Vignette folgt dem Bildschirm (leicht elliptisch
//  auf Breitbild) – fuer eine Damage-Vignette genau richtig.
// =============================================================

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

uniform vec4  tint_color : source_color = vec4(0.85, 0.05, 0.05, 1.0);

// Ab welchem Radius (0=Mitte, ~0.707=Ecke) die Vignette einsetzt.
uniform float vignette_radius : hint_range(0.0, 0.71) = 0.32;
// Wie weich der Uebergang ist.
uniform float vignette_softness : hint_range(0.05, 0.6) = 0.3;

uniform float noise_strength : hint_range(0.0, 1.0) = 0.5;
uniform float noise_scale : hint_range(0.5, 10.0) = 3.0;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.5;

// Wie stark der Puls die Vignette moduliert.
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Radialer Abstand zur Bildmitte: 0 in der Mitte, ~0.707 in der Ecke.
	float r = length(SCREEN_UV - vec2(0.5));

	// Vignette: 0 innen, 1 am Rand
	float vig = smoothstep(vignette_radius,
	                       vignette_radius + vignette_softness, r);

	// Noise moduliert den Rand -> ungleichmaessig, organisch
	float t = TIME * noise_speed;
	float n = fbm(SCREEN_UV * noise_scale + vec2(t, t * 0.7));
	vig *= mix(1.0 - noise_strength, 1.0, n);

	// Heartbeat-Puls: zwischen 1-depth und 1.0 atmen
	float pulse_mod = 1.0 - pulse_depth + pulse * pulse_depth;

	float alpha = clamp(vig * intensity * pulse_mod, 0.0, 1.0);

	COLOR = vec4(tint_color.rgb, alpha);
}
