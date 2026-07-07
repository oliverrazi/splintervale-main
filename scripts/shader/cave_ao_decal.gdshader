// ============================================================================
// cave_ao_decal.gdshader
// ----------------------------------------------------------------------------
// Weicher, multiplikativer Ambient-Occlusion-Schatten auf dem Fels rund um
// eine Hoehlenoeffnung. Laesst die Oeffnung "eingegraben" wirken statt
// aufgesetzt.
//
// Prinzip: Ein Quad liegt flach an der Felswand, groesser als die Oeffnung.
// blend_mul multipliziert den Fels dahinter mit einem Dunkelwert -> Fels-
// Textur/Beleuchtung bleiben erhalten, werden nur natuerlich abgedunkelt
// (wie echtes AO, kein Farbauftrag).
//
// Form: weich-rund. Am staerksten in einem Ring um die Oeffnung, blendet nach
// aussen (zum Quad-Rand) auf 1.0 (kein Effekt) und im Zentrum ebenfalls
// schwaecher (dort ist ja die Oeffnung, nicht Fels).
//
// blend_mul: ALBEDO wird mit dem Framebuffer multipliziert. Weiss (1) = kein
// Effekt, dunkel = abdunkeln. Wir schreiben also einen Grauwert 1..dunkel.
// ============================================================================
shader_type spatial;
render_mode blend_mul, cull_back, depth_draw_never,
	shadows_disabled, specular_disabled, ambient_light_disabled, unshaded;

// --- AO-Form ----------------------------------------------------------------
uniform float ao_staerke : hint_range(0.0, 1.0) = 0.55;      // wie dunkel max.
uniform float ao_innen : hint_range(0.0, 1.0) = 0.28;        // Radius wo AO beginnt (Oeffnungskante)
uniform float ao_aussen : hint_range(0.0, 1.5) = 0.95;       // Radius wo AO auf 0 ausgeblendet ist
uniform float ao_kurve : hint_range(0.5, 4.0) = 1.6;         // Verlaufskontrast

// --- Optionaler Form-Aufbruch (leichte Unregelmaessigkeit) -----------------
uniform float form_noise : hint_range(0.0, 0.4) = 0.0;       // 0 = perfekt rund
uniform float noise_skala : hint_range(1.0, 8.0) = 3.0;

varying vec2 v_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 pc = v_uv * 2.0 - 1.0;   // -1..1, Zentrum = Oeffnung
	float r = length(pc);         // weich-rund

	// Optionaler Aufbruch der Radialdistanz -> leicht unregelmaessiger Rand.
	if (form_noise > 0.001) {
		r += (noise2(pc * noise_skala + 3.7) - 0.5) * 2.0 * form_noise;
	}

	// AO-Profil: 0 innen (an der Oeffnung), hoch im Ring, 0 aussen.
	// Zwei smoothsteps bilden einen weichen Ring.
	float einblend = smoothstep(ao_innen, ao_innen + 0.15, r);   // waechst ab Oeffnungskante
	float ausblend = 1.0 - smoothstep(ao_aussen - 0.3, ao_aussen, r); // faellt zum Rand
	float ao = einblend * ausblend;
	ao = pow(ao, ao_kurve) * ao_staerke;

	// Multiplikativer Wert: 1 = kein Effekt, (1-ao) = abdunkeln.
	float mul = 1.0 - ao;
	vec3 farbe = vec3(mul);

	ALBEDO = farbe;
	// Bei blend_mul zaehlt ALBEDO als Multiplikator. Alpha irrelevant, aber
	// sauber auf 1 fuer den Fall dass Blending es liest.
	ALPHA = 1.0;
}
