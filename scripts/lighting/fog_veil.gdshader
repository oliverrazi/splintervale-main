shader_type canvas_item;

// =============================================================
//  Cinematic Fog Veil  – Noise Dissolve
//
//  Vollflächiger Nebelvorhang fürs Intro. Loest sich noise-basiert
//  auf: duenne Stellen zuerst, dichte zuletzt. Genau wie wenn man
//  am FogPatch `noise_softness` hochdreht, nur bildschirmweit.
//
//  Steuerung ueber EINE Variable:  reveal  (0..1)
//   - reveal = 0  -> komplett opak (NICHTS von der Szene sichtbar)
//   - reveal > 0  -> Noise-Pattern reisst von dünnen Stellen her auf
//   - reveal = 1  -> komplett frei
// =============================================================

uniform vec4  fog_color : source_color = vec4(0.60, 0.68, 0.78, 1.0);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float anim_speed : hint_range(0.0, 0.5) = 0.03;  // klein = fast still
uniform float noise_scale : hint_range(0.5, 8.0) = 2.5;
uniform float softness : hint_range(0.05, 1.0) = 0.45;   // Breite der Aufloesungszone

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
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float t = TIME * anim_speed;
	vec2 uv = SCREEN_UV * noise_scale + vec2(t, t * 0.6);

	// Zwei FBM-Lagen: große Schwaden + feine Struktur -> organisches Muster
	float n = fbm(uv) * 0.7 + fbm(uv * 2.3 + vec2(13.7, 27.1)) * 0.3;
	// n liegt typischerweise in ~[0.1 .. 0.9]

	// Threshold wandert von komplett über allen n-Werten (alles dicht)
	// bis komplett darunter (alles frei). Padding sorgt für saubere Endpunkte.
	float pad = softness;
	float thr = mix(-pad, 1.0 + pad, reveal);

	// alpha = 1 wenn n > thr (Nebel haelt), 0 wenn n < thr (aufgeloest).
	// Niedrige n-Werte = dünner Nebel = loesen sich zuerst auf.
	float alpha = smoothstep(thr - softness, thr + softness, n);

	COLOR = vec4(fog_color.rgb, clamp(alpha, 0.0, 1.0));
}
