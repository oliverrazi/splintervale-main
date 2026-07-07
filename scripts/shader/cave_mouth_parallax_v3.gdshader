// ============================================================================
// cave_mouth_parallax.gdshader  (v3 - Atmosphaere)
// ----------------------------------------------------------------------------
// Prozeduraler Fake-Tunnelschacht per Parallax Occlusion Mapping auf EINEM Quad.
// Feste, dem Spieler folgende Kamera -> Blickwinkel wandert bei Bewegung ->
// Parallaxe entfaltet echte Tiefe.
//
// v3-Aenderungen gegenueber v2 (gezielt auf "weicher Uebergang" + "dunkler,
// mysterioeser, mehr Tiefe"):
//   1. WEICHER UEBERGANG Fels->Oeffnung:
//      - Oeffnungskante per fBm unregelmaessig aufgebrochen (Felszaehne/Rueckzuege)
//      - breite, weiche Kontakt-Verschattung an der Naht -> Oeffnung sitzt IM Fels
//      - ALPHA-Feather am aeussersten Rand -> kein harter Quad-/Ringrand mehr
//   2. MEHR TIEFE / DUNKELHEIT:
//      - staerkere, kurvigere Tiefendaempfung, tieferer Kern
//      - vertikaler Dunkel-Gradient (oben dunkler; Aussenlicht faellt unten ein)
//      - minimaler Rest-Detail-Erhalt im Kern (kein flaches schwarzes Loch)
//   3. UEBERHANG-SCHATTENLIPPE oben in der Oeffnung (Naturstein-Signature)
//
// Braucht blend_mix + Alpha fuer den Feather -> depth_draw_opaque bleibt, aber
// Kanten blenden weich. resource_local_to_scene = true wenn gepoolt.
// ============================================================================
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, shadows_disabled,
	specular_disabled, ambient_light_disabled, unshaded;

// --- Tunnel-Geometrie -------------------------------------------------------
uniform float tiefe : hint_range(0.0, 2.5) = 1.25;
uniform int schritte : hint_range(8, 64) = 36;
uniform float verjuengung : hint_range(0.0, 1.0) = 0.42;
uniform float roehre_rundung : hint_range(0.0, 1.0) = 0.82;

// --- Wand-Aufbruch ----------------------------------------------------------
uniform float wand_rauheit : hint_range(0.0, 0.5) = 0.2;
uniform float wand_skala : hint_range(1.0, 12.0) = 4.5;

// --- Naturstein-Farben ------------------------------------------------------
uniform vec3 fels_hell : source_color = vec3(0.40, 0.34, 0.27);
uniform vec3 fels_dunkel : source_color = vec3(0.13, 0.11, 0.09);
uniform vec3 tiefen_ambient : source_color = vec3(0.018, 0.016, 0.02); // sehr dunkel, leicht kalt
uniform float fade_kurve : hint_range(0.5, 5.0) = 2.4;      // hoeher = laenger hell, dann steil dunkel

// --- Struktur ---------------------------------------------------------------
uniform float struktur_staerke : hint_range(0.0, 1.0) = 0.55;
uniform float struktur_skala : hint_range(1.0, 16.0) = 6.0;

// --- Tiefe / Atmosphaere (v3) ----------------------------------------------
uniform float tiefen_daempfung : hint_range(0.0, 1.0) = 0.9;  // wie stark Tiefe abdunkelt
uniform float kern_restlicht : hint_range(0.0, 0.15) = 0.03;  // minimaler Detailerhalt im Schwarz
uniform float vertikal_dunkel : hint_range(0.0, 1.0) = 0.45;  // oben dunkler als unten

// --- Weicher Uebergang / Kanten-Feather (v3) -------------------------------
uniform float kante_breite : hint_range(0.05, 0.6) = 0.32;    // Breite der weichen Uebergangszone
uniform float kante_aufbruch : hint_range(0.0, 0.5) = 0.22;   // wie unregelmaessig die Kante bricht
uniform float kontakt_schatten : hint_range(0.0, 1.0) = 0.7;  // dunkle Naht Fels->Oeffnung
uniform float feather_alpha : hint_range(0.0, 0.4) = 0.14;    // aeusserster Rand blendet aus

// --- Ueberhang-Schattenlippe oben (v3) -------------------------------------
uniform float ueberhang_staerke : hint_range(0.0, 1.0) = 0.55;
uniform float ueberhang_hoehe : hint_range(0.0, 1.0) = 0.4;   // wie weit runter der Schatten reicht

// --- Saum-Restlicht (dezent) -----------------------------------------------
uniform vec3 saum_licht : source_color = vec3(0.34, 0.30, 0.25);
uniform float saum_staerke : hint_range(0.0, 2.0) = 0.22;

// --- Glimmen aus der Tiefe (Resonanzen-Slot) -------------------------------
uniform vec3 glimm_farbe : source_color = vec3(0.35, 0.62, 0.85);
uniform float glimm_staerke : hint_range(0.0, 4.0) = 0.0;
uniform float glimm_puls : hint_range(0.0, 4.0) = 0.0;

varying vec3 v_view_ts;
varying vec2 v_uv;

// -------- Noise ------------------------------------------------------------
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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return s;
}

// Querschnitts-Radius: mischt runde Roehre und Box nach roehre_rundung.
float quer_radius(vec2 pc) {
	float rund = length(pc);
	float eckig = max(abs(pc.x), abs(pc.y));
	return mix(eckig, rund, roehre_rundung);
}

void vertex() {
	v_uv = UV;
	vec3 view_os = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz - VERTEX;
	vec3 n = normalize(NORMAL);
	vec3 t = normalize(TANGENT);
	vec3 b = normalize(BINORMAL);
	v_view_ts = normalize(vec3(dot(view_os, t), dot(view_os, b), dot(view_os, n)));
}

void fragment() {
	vec2 uv = v_uv;

	// --- Parallax Ray-March ------------------------------------------------
	vec3 vdir = v_view_ts;
	vdir.z = max(abs(vdir.z), 0.15) * sign(vdir.z + 1e-4);

	vec2 par_step = (vdir.xy / vdir.z) * tiefe / float(schritte);
	float depth_step = 1.0 / float(schritte);

	vec2 p = uv;
	float virt_tiefe = 0.0;

	for (int i = 0; i < 64; i++) {
		if (i >= schritte) break;
		p += par_step;
		virt_tiefe += depth_step;

		vec2 pc = (p * 2.0 - 1.0);
		float r = quer_radius(pc);
		float bruch = (fbm(p * wand_skala + virt_tiefe * 2.0) - 0.5) * 2.0 * wand_rauheit;
		float wand_grenze = (1.0 - virt_tiefe * verjuengung) + bruch;
		if (r >= wand_grenze) break;
	}

	float t_norm = clamp(virt_tiefe / tiefe, 0.0, 1.0);

	// --- Naturstein-Wandfarbe ---------------------------------------------
	float grob = fbm(p * struktur_skala);
	float fein = fbm(p * struktur_skala * 3.3);
	float struktur = mix(grob, fein, 0.35);
	vec3 wand = mix(fels_dunkel, fels_hell, struktur);
	wand = mix(wand, wand * (0.55 + 0.9 * struktur), struktur_staerke);

	// --- Tiefen-Verdunklung (v3: staerker, mit Restlicht) -----------------
	float fade = pow(t_norm, fade_kurve) * tiefen_daempfung;
	vec3 tief = max(tiefen_ambient, vec3(kern_restlicht) * struktur); // Kern behaelt Mini-Detail
	vec3 farbe = mix(wand, tief, fade);

	// --- Vertikaler Dunkel-Gradient (v3: oben dunkler) --------------------
	// uv.y 0 unten .. 1 oben (Godot QuadMesh UV). Oben abdunkeln.
	float vgrad = mix(1.0, 1.0 - vertikal_dunkel, smoothstep(0.35, 1.0, uv.y));
	farbe *= vgrad;

	// --- Ueberhang-Schattenlippe oben (v3) --------------------------------
	// Zusaetzliche tiefe Verschattung im oberen Bereich der Oeffnung, als
	// haenge dort Fels ueber. Nur wirksam wo schon Oeffnung (t_norm > 0).
	float ueberhang = smoothstep(1.0 - ueberhang_hoehe, 1.0, uv.y) * ueberhang_staerke;
	ueberhang *= smoothstep(0.02, 0.25, t_norm); // nur in der Oeffnung, nicht auf Fels
	farbe *= (1.0 - ueberhang);

	// --- Weicher, aufgebrochener Uebergang Fels->Oeffnung (v3) ------------
	// rand0: radiale Distanz auf dem Quad. Kante per Noise aufgebrochen ->
	// keine saubere Kreislinie. kontakt: dunkle Naht. feather: Alpha-Ausblendung.
	vec2 pc0 = uv * 2.0 - 1.0;
	float rand0 = quer_radius(pc0);
	float kanten_noise = (fbm(pc0 * 3.5 + 7.0) - 0.5) * 2.0 * kante_aufbruch;
	float kante = rand0 + kanten_noise; // aufgebrochener Radius

	// Kontakt-Schatten: dunkle Zone kurz vor dem Rand (bettet Oeffnung ein).
	float kontakt = smoothstep(1.0 - kante_breite, 1.0, kante);
	farbe = mix(farbe, farbe * (1.0 - kontakt_schatten), kontakt);

	// Dezentes Saum-Restlicht ganz aussen (Andeutung Streiflicht auf Fels).
	float saum = smoothstep(1.0 - kante_breite * 0.5, 1.0, kante) * (1.0 - t_norm);
	farbe += saum_licht * saum * saum_staerke;

	// --- Glimmen ----------------------------------------------------------
	if (glimm_staerke > 0.001) {
		float g = pow(t_norm, 2.0);
		if (glimm_puls > 0.001) {
			g *= 0.6 + 0.4 * sin(TIME * glimm_puls);
		}
		farbe += glimm_farbe * g * glimm_staerke;
	}

	// --- Alpha-Feather am aeussersten Rand (v3) ---------------------------
	// Der aeusserste Ring blendet weich aus, damit KEIN harter Quadrand/Kreis
	// gegen den Fels liest. Innen voll deckend.
	float alpha = 1.0 - smoothstep(1.0 - feather_alpha, 1.0, kante);

	ALBEDO = farbe;
	EMISSION = farbe;
	ALPHA = alpha;
}
