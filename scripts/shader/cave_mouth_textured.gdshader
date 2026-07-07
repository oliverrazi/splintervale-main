// ============================================================================
// cave_mouth_textured.gdshader  (v2 - Anti-Flacker + Schatteneinbettung)
// ----------------------------------------------------------------------------
// Hoehleneingang per Parallax Occlusion Mapping gegen eine DEPTH-MAP.
//
// Zwei Texturen:
//   farb_textur  : Hoehlen-Screenshot (was man sieht)
//   tiefen_karte : Graustufen-Depth-Map (HELL = nah/vorne, DUNKEL = tief/hinten)
//
// v2-Aenderungen (gezielt gegen die zwei bekannten Probleme):
//   FLACKERN bei flachem Winkel (rechts-unten laufen) behoben durch:
//     - textureLod() mit fixem LOD im Ray-March -> keine Mipmap-Sprunge mehr
//     - vdir.z-Clamp angehoben (0.3) -> Parallax-Versatz kann nicht explodieren
//     - Winkel-Fade: bei sehr flachem Blick wird Parallax sanft reduziert
//   NAHTLOSER UEBERGANG durch:
//     - radiale Kontakt-Verschattung (Fels bettet Oeffnung ein)
//     - vertikaler Ueberhang-Schatten (oben dunkler, wie echte Felslippe)
//     - weicher Alpha-Feather am Rand (kein harter Quadrand)
//
// Depth-Map wird durch fehlenden source_color-Hint automatisch linear gelesen
// (Godot Shader-Hint gewinnt ueber Import-Einstellung). resource_local_to_scene
// = true am Material wenn gepoolt.
// ============================================================================
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, shadows_disabled,
	specular_disabled, ambient_light_disabled, unshaded;

// --- Texturen ---------------------------------------------------------------
uniform sampler2D farb_textur : source_color, filter_linear_mipmap;
uniform sampler2D tiefen_karte : hint_default_black, filter_linear_mipmap;

// --- Parallax ---------------------------------------------------------------
uniform float tiefe : hint_range(0.0, 1.5) = 0.5;
uniform int schritte : hint_range(8, 64) = 48;
uniform bool tiefe_invertieren = false;
uniform int verfeinerung : hint_range(0, 8) = 6;  // ungenutzt seit POM-Interpolation (Regler kann bleiben)

// --- Anti-Flacker (v2) ------------------------------------------------------
// Fixes LOD fuer das Depth-Sampling im March: verhindert Mipmap-Flimmern bei
// flachem Winkel. 0 = schaerfste Mip. Leicht erhoehen (0.5-1.5) falls noch
// Flimmern in der Distanz auftritt.
uniform float march_lod : hint_range(0.0, 4.0) = 0.0;
// Ab welchem Blickwinkel (Dot mit Normale) der Parallax sanft ausblendet.
// Niedriger = laenger voller Effekt. Gegen Versatz-Explosion bei flachem Blick.
uniform float winkel_fade : hint_range(0.0, 0.8) = 0.35;
// Glaettung des Depth-Samplings: mittelt Nachbarpixel -> keine harten
// Block-/Treppen-Artefakte an Tiefenkanten. 0 = aus, hoeher = weicher.
uniform float depth_glatt : hint_range(0.0, 4.0) = 1.2;
// Fixes LOD fuers Farb-Sampling. Gegen Helligkeits-"Atmen" bei Distanz-/
// Winkeländerung (instabile Mipmap-Wahl im Parallax-March). 0 = auto.
// Leicht erhoehen (0.5-2.0) falls die Oeffnung heller/dunkler flackert.
uniform float farb_lod : hint_range(0.0, 4.0) = 0.0;

// --- Palette ----------------------------------------------------------------
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float helligkeit : hint_range(0.0, 2.0) = 1.0;
uniform float kontrast : hint_range(0.0, 2.0) = 1.0;
uniform float saettigung : hint_range(0.0, 2.0) = 1.0;

// --- Tiefen-Verdunklung -----------------------------------------------------
uniform vec3 tiefen_farbe : source_color = vec3(0.02, 0.02, 0.03);
uniform float tiefen_daempfung : hint_range(0.0, 1.0) = 0.85;
uniform float tiefen_kurve : hint_range(0.5, 4.0) = 1.8;

// --- Schatteneinbettung (v2) -----------------------------------------------
// Radiale Kontakt-Verschattung: dunkle Zone am Rand, bettet Oeffnung in Fels.
uniform float kontakt_staerke : hint_range(0.0, 1.0) = 0.6;
uniform float kontakt_breite : hint_range(0.05, 0.7) = 0.35;
// Vertikaler Ueberhang-Schatten: oben dunkler (Felslippe wirft Schatten rein).
uniform float ueberhang_staerke : hint_range(0.0, 1.0) = 0.5;
uniform float ueberhang_hoehe : hint_range(0.0, 1.0) = 0.45;
// Weicher Alpha-Feather am aeussersten Rand.
uniform float feather : hint_range(0.0, 0.4) = 0.12;
// Form der Rand-/Schattenzone: 0 = rechteckig (fuellt Quad-Ecken aus),
// 1 = rund (kreisfoermig). Dazwischen abgerundetes Rechteck.
uniform float form_rundung : hint_range(0.0, 1.0) = 0.25;

// --- Glimmen (Resonanzen-Slot) ---------------------------------------------
uniform vec3 glimm_farbe : source_color = vec3(0.35, 0.62, 0.85);
uniform float glimm_staerke : hint_range(0.0, 4.0) = 0.0;
uniform float glimm_puls : hint_range(0.0, 4.0) = 0.0;

// --- Dunst aus der Tiefe (aufsteigender Hoehlennebel) ----------------------
uniform vec3 dunst_farbe : source_color = vec3(0.5, 0.52, 0.55); // neutrales Grau
uniform float dunst_staerke : hint_range(0.0, 2.0) = 0.0;        // 0 = aus
uniform float dunst_speed : hint_range(0.0, 1.0) = 0.12;         // Aufstiegs-Tempo
uniform float dunst_dichte : hint_range(0.5, 6.0) = 2.5;         // Noise-Frequenz
uniform float dunst_tiefe_bias : hint_range(0.0, 1.0) = 0.6;     // wie stark an Tiefe gekoppelt
uniform float dunst_boden : hint_range(0.0, 1.0) = 0.55;         // Dichte unten vs oben
uniform float dunst_richtung = 1.0;                              // +1 aufsteigen, -1 fallen

varying vec3 v_view_ts;
varying vec2 v_uv;

// Depth-Sampling mit FIXEM LOD -> keine ableitungsbasierte Mipmap-Wahl im
// Loop, damit kein Flimmern bei divergierenden March-UVs. Zusaetzlich optionale
// Glaettung: mischt einen hoeheren Mip-Level bei, der die harten Depth-Pixel
// weichzeichnet -> keine Block-/Treppen-Artefakte an Tiefenkanten.
float sample_depth(vec2 uv) {
	float d0 = textureLod(tiefen_karte, uv, march_lod).r;
	if (depth_glatt > 0.001) {
		float d1 = textureLod(tiefen_karte, uv, march_lod + depth_glatt).r;
		d0 = mix(d0, d1, 0.5);
	}
	return tiefe_invertieren ? (1.0 - d0) : d0;
}

// Rand-Distanz die der Quad-Form folgt: mischt Rechteck (max-Norm, fuellt die
// Ecken aus) und Kreis (length). form_rundung 0 = rechteckig, 1 = rund.
// pc ist in -1..1 (Quad-Zentrum = 0). Rueckgabe 0 Mitte -> ~1 Rand.
float rand_distanz(vec2 pc) {
	float eckig = max(abs(pc.x), abs(pc.y)); // Chebyshev -> quadratisch
	float rund = length(pc);                 // euklidisch -> kreisfoermig
	return mix(eckig, rund, form_rundung);
}

// -------- Noise (fuer Dunst) -----------------------------------------------
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
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return s;
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
	vec3 vdir = v_view_ts;

	// --- Winkel-Fade (optional, default AUS) ------------------------------
	// Reduziert Parallax-Staerke bei flachem Winkel. PROBLEM: gleitet mit der
	// Kamera -> effektive Tiefe schwankt -> Helligkeit "atmet" bei Schwenk/
	// Distanz. Seit der POM-Interpolation nicht mehr noetig (die ist winkel-
	// stabil). Bei winkel_fade <= 0 komplett neutral (parallax_faktor = 1).
	float parallax_faktor = 1.0;
	if (winkel_fade > 0.001) {
		float winkel = abs(vdir.z);
		parallax_faktor = smoothstep(winkel_fade, winkel_fade + 0.25, winkel);
	}

	// z-Clamp gegen Versatz-Explosion bei flachem Blick (bleibt, ist stabil).
	vdir.z = max(abs(vdir.z), 0.3) * sign(vdir.z + 1e-4);

	float eff_tiefe = tiefe * parallax_faktor;
	vec2 max_offset = (vdir.xy / vdir.z) * eff_tiefe;
	vec2 step_offset = max_offset / float(schritte);
	float layer_step = 1.0 / float(schritte);

	// --- Steep Parallax Such-March ----------------------------------------
	vec2 cur_uv = v_uv;
	float cur_layer = 0.0;
	float cur_depth = 1.0 - sample_depth(cur_uv);

	vec2 prev_uv = cur_uv;
	float prev_layer = 0.0;
	float prev_depth = cur_depth;

	for (int i = 0; i < 64; i++) {
		if (i >= schritte) break;
		if (cur_layer >= cur_depth) break;
		prev_uv = cur_uv;
		prev_layer = cur_layer;
		prev_depth = cur_depth;

		cur_uv += step_offset;
		cur_layer += layer_step;
		cur_depth = 1.0 - sample_depth(cur_uv);
	}

	// --- Interpolierte Trefferkante (Parallax Occlusion Mapping) ----------
	// Statt Binary-Search: exakte Schnittstelle zwischen prev (vor der Wand)
	// und cur (nach der Wand) analytisch bestimmen. Der March-Strahl (layer)
	// und das Tiefenprofil (depth) sind zwischen zwei Schritten je linear
	// angenommen -> Schnittpunkt = wo (layer - depth) das Vorzeichen wechselt.
	// Das glaettet die Stufen KONTINUIERLICH, nicht nur feiner unterteilt.
	float diff_cur = cur_layer - cur_depth;    // >= 0 (hat durchstossen)
	float diff_prev = prev_layer - prev_depth; // < 0 (noch davor)
	float w = diff_cur - diff_prev;
	// t_hit: Anteil, wie weit von cur zurueck nach prev der Nulldurchgang liegt.
	float t_hit = (abs(w) > 1e-5) ? (diff_cur / w) : 0.5;
	t_hit = clamp(t_hit, 0.0, 1.0);

	// Interpolierte UV und Tiefe an der exakten Schnittstelle.
	vec2 hit_uv = mix(cur_uv, prev_uv, t_hit);
	float t_norm = clamp(mix(cur_layer, prev_layer, t_hit), 0.0, 1.0);

	// --- Farbe aus der Textur ---------------------------------------------
	// Bei farb_lod > 0 mit fixem LOD sampeln -> stabile Helligkeit, kein
	// Mipmap-"Atmen" bei Distanz-/Winkeländerung. 0 = automatisches Mip.
	vec3 farbe;
	if (farb_lod > 0.001) {
		farbe = textureLod(farb_textur, hit_uv, farb_lod).rgb;
	} else {
		farbe = texture(farb_textur, hit_uv).rgb;
	}

	// Palette: Saettigung -> Kontrast -> Helligkeit -> Tint.
	float luma = dot(farbe, vec3(0.299, 0.587, 0.114));
	farbe = mix(vec3(luma), farbe, saettigung);
	farbe = (farbe - 0.5) * kontrast + 0.5;
	farbe *= helligkeit;
	farbe *= tint;

	// --- Tiefen-Verdunklung -----------------------------------------------
	float fade = pow(t_norm, tiefen_kurve) * tiefen_daempfung;
	farbe = mix(farbe, tiefen_farbe, fade);

	// --- Schatteneinbettung (v2) ------------------------------------------
	vec2 pc = v_uv * 2.0 - 1.0;   // -1..1
	// Formfolgende Rand-Distanz statt length() -> fuellt die Quad-Ecken aus,
	// keine abgeschnittene Ecke mehr. form_rundung steuert rund<->rechteckig.
	float rad = rand_distanz(pc);

	// Radiale Kontakt-Verschattung: dunkelt den Rand ab, bettet Oeffnung ein.
	float kontakt = smoothstep(1.0 - kontakt_breite, 1.0, rad) * kontakt_staerke;
	farbe *= (1.0 - kontakt);

	// Vertikaler Ueberhang-Schatten: oben (v_uv.y -> 1) dunkler.
	float ueberhang = smoothstep(1.0 - ueberhang_hoehe, 1.0, v_uv.y) * ueberhang_staerke;
	farbe *= (1.0 - ueberhang);

	// --- Glimmen ----------------------------------------------------------
	if (glimm_staerke > 0.001) {
		float g = pow(t_norm, 2.0);
		if (glimm_puls > 0.001) {
			g *= 0.6 + 0.4 * sin(TIME * glimm_puls);
		}
		farbe += glimm_farbe * g * glimm_staerke;
	}

	// --- Dunst aus der Tiefe (aufsteigender Hoehlennebel) -----------------
	if (dunst_staerke > 0.001) {
		// v_uv.y: in Godot QuadMesh ist 0 = OBEN, 1 = UNTEN. Fuer "aufsteigen"
		// muessen die Schwaden nach oben wandern, also v_uv.y + TIME scrollen
		// (positives TIME schiebt das Muster Richtung y=1/unten, wodurch es
		// optisch nach oben zu quellen scheint). Falls die Richtung bei dir
		// verkehrt wirkt, dunst_richtung im Material auf -1 setzen.
		float scroll = TIME * dunst_speed * dunst_richtung;
		vec2 uv1 = vec2(v_uv.x * dunst_dichte, v_uv.y * dunst_dichte + scroll);
		vec2 uv2 = vec2(v_uv.x * dunst_dichte * 1.7 + 4.0,
						v_uv.y * dunst_dichte * 1.7 + scroll * 1.6);
		float schwaden = fbm(uv1) * 0.6 + fbm(uv2) * 0.4;
		schwaden = smoothstep(0.35, 0.85, schwaden);

		// Tiefen-Kopplung: dichter wo der Schacht tief ist (t_norm hoch).
		float tiefe_faktor = mix(1.0, t_norm, dunst_tiefe_bias);

		// Vertikaler Gradient: UNTEN am dichtesten. Unten = v_uv.y NAHE 1,
		// also direkt v_uv.y als Dichtefaktor (nicht 1 - v_uv.y).
		float boden_faktor = mix(1.0, v_uv.y, dunst_boden);

		// Rand-Ausblendung: kein Dunst ueber der Fels-Kante (nutzt rad).
		float rand_fade = 1.0 - smoothstep(0.75, 1.0, rad);

		float d = schwaden * tiefe_faktor * boden_faktor * rand_fade * dunst_staerke;
		farbe += dunst_farbe * d;
	}

	// --- Alpha-Feather am Rand --------------------------------------------
	float alpha = 1.0 - smoothstep(1.0 - feather, 1.0, rad);

	ALBEDO = farbe;
	EMISSION = farbe;
	ALPHA = alpha;
}
