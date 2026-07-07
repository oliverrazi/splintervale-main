// ============================================================================
// cave_mouth_textured.gdshader
// ----------------------------------------------------------------------------
// Hoehleneingang per Parallax Occlusion Mapping gegen eine DEPTH-MAP.
//
// Statt prozeduraler Tunnelgeometrie faellt der Blickstrahl so tief in den
// Schacht, wie die Depth-Map an der getroffenen Stelle vorgibt. Die
// Farb-Textur (dein Hoehlen-Screenshot) liefert die sichtbare Oberflaeche.
//
// Zwei Texturen:
//   farb_textur  : dein Hoehlenfoto/Screenshot (was man sieht)
//   tiefen_karte : Graustufen-Depth-Map (HELL = nah/vorne, DUNKEL = tief/hinten)
//                  -> per Depth Anything V2 aus dem Foto generierbar.
//
// Flacher Boden: einfach in der Depth-Map den unteren Bereich HELL lassen
// (= nah = kein Zurueckweichen). Kein separater Shader-Regler noetig.
//
// Palette-Anpassung an die Welt: tint, helligkeit, kontrast, tiefen_daempfung.
// Glimm-Slot fuer Resonanzen-Licht aus der Tiefe bleibt (default aus).
//
// WICHTIG: Depth-Map mit filter_linear, OHNE sRGB (hint_default_black + kein
// source_color) -> Tiefenwerte muessen linear gelesen werden, nicht gamma-korrigiert.
// resource_local_to_scene = true am Material wenn gepoolt.
// ============================================================================
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, shadows_disabled,
	specular_disabled, ambient_light_disabled, unshaded;

// --- Texturen ---------------------------------------------------------------
uniform sampler2D farb_textur : source_color, filter_linear_mipmap;
uniform sampler2D tiefen_karte : hint_default_black, filter_linear_mipmap; // linear!

// --- Parallax ---------------------------------------------------------------
uniform float tiefe : hint_range(0.0, 1.5) = 0.55;          // max. Parallax-Versatz
uniform int schritte : hint_range(8, 64) = 32;              // Ray-March-Aufloesung
uniform bool tiefe_invertieren = false;                     // falls Depth-Map umgekehrt
uniform int verfeinerung : hint_range(0, 8) = 4;            // Binary-Search-Schaerfe an der Trefferkante

// --- Palette-Anpassung an die Welt -----------------------------------------
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);     // Einfaerbung
uniform float helligkeit : hint_range(0.0, 2.0) = 1.0;
uniform float kontrast : hint_range(0.0, 2.0) = 1.0;
uniform float saettigung : hint_range(0.0, 2.0) = 1.0;

// --- Tiefen-Verdunklung (Atmosphaere) --------------------------------------
uniform vec3 tiefen_farbe : source_color = vec3(0.03, 0.03, 0.04); // Farbe ganz hinten
uniform float tiefen_daempfung : hint_range(0.0, 1.0) = 0.7;       // wie stark Tiefe abdunkelt
uniform float tiefen_kurve : hint_range(0.5, 4.0) = 1.5;

// --- Saum an der Oeffnungskante --------------------------------------------
uniform vec3 saum_licht : source_color = vec3(0.5, 0.45, 0.38);
uniform float saum_staerke : hint_range(0.0, 2.0) = 0.25;
uniform float saum_breite : hint_range(0.01, 0.5) = 0.14;

// --- Glimmen aus der Tiefe (Resonanzen-Slot) -------------------------------
uniform vec3 glimm_farbe : source_color = vec3(0.35, 0.62, 0.85);
uniform float glimm_staerke : hint_range(0.0, 4.0) = 0.0;
uniform float glimm_puls : hint_range(0.0, 4.0) = 0.0;

varying vec3 v_view_ts;
varying vec2 v_uv;

float sample_depth(vec2 uv) {
	float d = texture(tiefen_karte, uv).r;
	return tiefe_invertieren ? (1.0 - d) : d;
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
	vdir.z = max(abs(vdir.z), 0.15) * sign(vdir.z + 1e-4);

	// Gesamter UV-Versatz ueber die volle Tiefe.
	vec2 max_offset = (vdir.xy / vdir.z) * tiefe;
	vec2 step_offset = max_offset / float(schritte);
	float layer_step = 1.0 / float(schritte);

	// --- Linearer Such-March (Steep Parallax) -----------------------------
	// Tunnel-"Tiefe" 0 an der Oeffnung, 1 ganz hinten. Depth-Map: hell(1)=nah,
	// also vergleichen wir gegen (1 - depth) als Tunnel-Tiefe.
	vec2 cur_uv = v_uv;
	float cur_layer = 0.0;
	float cur_depth = 1.0 - sample_depth(cur_uv);

	vec2 prev_uv = cur_uv;
	float prev_layer = 0.0;
	float prev_depth = cur_depth;

	for (int i = 0; i < 64; i++) {
		if (i >= schritte) break;
		if (cur_layer >= cur_depth) break;   // Strahl hat die Wand durchstossen
		prev_uv = cur_uv;
		prev_layer = cur_layer;
		prev_depth = cur_depth;

		cur_uv += step_offset;
		cur_layer += layer_step;
		cur_depth = 1.0 - sample_depth(cur_uv);
	}

	// --- Binary-Search-Verfeinerung an der Trefferkante -------------------
	vec2 lo_uv = prev_uv;
	vec2 hi_uv = cur_uv;
	for (int j = 0; j < 8; j++) {
		if (j >= verfeinerung) break;
		vec2 mid_uv = (lo_uv + hi_uv) * 0.5;
		float mid_layer = (prev_layer + cur_layer) * 0.5;
		float mid_depth = 1.0 - sample_depth(mid_uv);
		if (mid_layer < mid_depth) {
			lo_uv = mid_uv;
			prev_layer = mid_layer;
		} else {
			hi_uv = mid_uv;
			cur_layer = mid_layer;
		}
	}
	vec2 hit_uv = (lo_uv + hi_uv) * 0.5;
	float t_norm = clamp((prev_layer + cur_layer) * 0.5, 0.0, 1.0); // getroffene Tiefe 0..1

	// --- Farbe aus der Textur ---------------------------------------------
	vec3 farbe = texture(farb_textur, hit_uv).rgb;

	// Palette-Anpassung: Saettigung -> Kontrast -> Helligkeit -> Tint.
	float luma = dot(farbe, vec3(0.299, 0.587, 0.114));
	farbe = mix(vec3(luma), farbe, saettigung);
	farbe = (farbe - 0.5) * kontrast + 0.5;
	farbe *= helligkeit;
	farbe *= tint;

	// --- Tiefen-Verdunklung -----------------------------------------------
	float fade = pow(t_norm, tiefen_kurve) * tiefen_daempfung;
	farbe = mix(farbe, tiefen_farbe, fade);

	// --- Saum an der Kante ------------------------------------------------
	vec2 pc = v_uv * 2.0 - 1.0;
	float rand = length(pc);
	float saum = smoothstep(1.0, 1.0 - saum_breite, rand) * (1.0 - t_norm);
	farbe += saum_licht * saum * saum_staerke;

	// --- Glimmen ----------------------------------------------------------
	if (glimm_staerke > 0.001) {
		float g = pow(t_norm, 2.0);
		if (glimm_puls > 0.001) {
			g *= 0.6 + 0.4 * sin(TIME * glimm_puls);
		}
		farbe += glimm_farbe * g * glimm_staerke;
	}

	ALBEDO = farbe;
	EMISSION = farbe;
	ALPHA = 1.0;
}
