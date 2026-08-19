shader_type spatial;
render_mode cull_disabled;
// Höhlenboden-Shader v2: ersetzt cave_texture_floor_wet.tres (StandardMaterial3D)
// 1:1-Basis (Albedo, Normal Map, Vertex-Color-Tint) + Riss-Layer + Wetness→Roughness.
//
// v2: Risse sind jetzt kantig/geknickt statt geschwungen.
//   - Domain-Warp stark entschärft (nur noch globale, sehr niederfrequente Biegung)
//   - crack_angularity blendet die Voronoi-Distanzmetrik Euklidisch → Manhattan:
//     Kanten werden zu geraden Segmenten mit harten Knicken (Bruchstein-Look)
//   - crack_grid_rotation dreht das Rissgitter, damit die kantigen Linien
//     nicht mit den Weltachsen fluchten
//
// Risse werden WORLD-SPACE gesampelt → laufen nahtlos über CavePiece
// und Cave-Edge-Meshes, solange beide diesen Shader auf der Oberseite nutzen.

group_uniforms Basis;
instance uniform float occluder_fade : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.5;
group_uniforms;

group_uniforms Wetness;
// Vertex-Alpha aus CavePiece: alpha = 1 - wetness
uniform float roughness_dry : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.08;
uniform float wet_darken : hint_range(0.5, 1.0) = 0.87;
group_uniforms;

group_uniforms Risse;
uniform bool cracks_enabled = true;
// Texel-Dichte der Boden-Textur: texture_px * top_uv_scale (z.B. 512 * 0.25 = 128)
uniform float crack_pixels_per_meter : hint_range(8.0, 512.0) = 128.0;
// Mittlerer Abstand der Risslinien in Metern
uniform float crack_cell_size : hint_range(0.1, 10.0) = 0.8;
// Rissbreite (relativ zur Zelle)
uniform float crack_width : hint_range(0.005, 0.25) = 0.05;
// 0 = runde Zellen (weiche Winkel), 1 = Manhattan-Metrik (harte Knicke, Bruchstein)
uniform float crack_angularity : hint_range(0.0, 1.0) = 0.7;
// Rotation des Rissgitters in Grad — verhindert Achsen-Fluchten der Knicke
uniform float crack_grid_rotation : hint_range(0.0, 90.0) = 17.0;
// Höhenfeld-Tiefe → wie stark die Bruchkante Licht fängt
uniform float crack_depth : hint_range(0.0, 0.3) = 0.06;
// Abdunkelung des Risskerns
uniform float crack_darkness : hint_range(0.0, 1.0) = 0.55;
// Heller Abrieb-Saum an der Bruchkante
uniform float edge_highlight : hint_range(0.0, 0.5) = 0.08;
// Sehr niederfrequente Gesamt-Biegung. Bewusst klein halten —
// hohe Werte machen die Linien wieder geschwungen.
uniform float warp_strength : hint_range(0.0, 1.5) = 0.15;
// Anteil des Bodens, der überhaupt Risse trägt (Patch-Zonen)
uniform float patch_coverage : hint_range(0.0, 1.0) = 0.4;
// Größe der Riss-Zonen: kleiner = größere zusammenhängende Zonen (Frequenz in 1/m)
uniform float patch_frequency : hint_range(0.02, 2.0) = 0.35;
group_uniforms;

group_uniforms RissTextur;
// Später einsteckbare, handgemalte Riss-Map (R-Kanal, weiß = Riss).
// Ersetzt NUR das prozedurale Rissfeld — Patch-Maske, Breiten-Presence,
// Bevel-Licht und Pixel-Quantisierung bleiben identisch aktiv.
uniform bool use_crack_map = false;
uniform sampler2D crack_map : hint_default_black, filter_linear_mipmap, repeat_enable;
// Wiederholungen der Riss-Map pro Meter
uniform float crack_map_scale : hint_range(0.01, 4.0) = 0.5;
group_uniforms;

varying vec3 v_world_pos;
varying vec3 v_world_normal;


void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


// ═════════════════════════════════════════════════════════════
// NOISE
// ═════════════════════════════════════════════════════════════

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

// Distanzmetrik: Euklidisch (rund) → Manhattan (kantig, 45°-Segmente).
// Der 0.7071-Faktor gleicht die Skalen der beiden Metriken an,
// damit crack_width bei jedem Angularity-Wert vergleichbar bleibt.
float crack_dist(vec2 v) {
	float d_euclid = length(v);
	float d_manhattan = (abs(v.x) + abs(v.y)) * 0.7071;
	return mix(d_euclid, d_manhattan, crack_angularity);
}

// F2 - F1: wird 0 an Zellgrenzen → dort liegen die Risse.
// Mit Manhattan-Anteil bestehen die Grenzen aus geraden Segmenten
// mit harten Knicken an den Zell-Ecken — Bruchstein statt Bienenwabe.
float voronoi_ridge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			float d = crack_dist(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}


// ═════════════════════════════════════════════════════════════
// RISSFELD — p in Metern (world XZ, bereits pixel-quantisiert)
// Rückgabe: 0 = intakt, 1 = Risskern
// ═════════════════════════════════════════════════════════════

float crack_field(vec2 p) {
	// Breiten-Presence: lässt Risse stellenweise dünn werden / ganz abreißen
	float wmod = vnoise(p / crack_cell_size * 0.7 + 31.0);
	float presence = smoothstep(0.18, 0.38, wmod);
	if (presence <= 0.001) {
		return 0.0;
	}

	float c;
	if (use_crack_map) {
		// Gemalte Map als alternativer Feld-Eingang (gleicher Vertrag: 1 = Riss)
		c = textureLod(crack_map, p * crack_map_scale, 0.0).r;
	} else {
		// Rissgitter drehen, damit Manhattan-Knicke nicht mit den
		// Weltachsen fluchten
		float ang = radians(crack_grid_rotation);
		float ca = cos(ang);
		float sa = sin(ang);
		vec2 pr = mat2(vec2(ca, -sa), vec2(sa, ca)) * p;

		// v2: Warp nur noch als globale Biegung — sehr niedrige Frequenz
		// (über ~4 Zellen), damit Segmente lokal GERADE bleiben
		vec2 w = pr + warp_strength * crack_cell_size
			* (vec2(vnoise(pr / crack_cell_size * 0.25),
					vnoise(pr / crack_cell_size * 0.25 + 17.0)) - 0.5) * 2.0;
		float ridge = voronoi_ridge(w / crack_cell_size);
		// Breite entlang des Risses modulieren
		float width_eff = crack_width * mix(0.35, 1.0, wmod);
		c = 1.0 - smoothstep(0.0, width_eff, ridge);
	}
	return c * presence;
}


// ═════════════════════════════════════════════════════════════
// FRAGMENT
// ═════════════════════════════════════════════════════════════

void fragment() {
	if (occluder_fade < 0.999) {
		vec2 sp = FRAGCOORD.xy;
		float dither = fract(sin(dot(floor(sp), vec2(12.9898, 78.233))) * 43758.5453);
		if (dither > occluder_fade) {
			discard;
		}
	}
	vec3 albedo = texture(albedo_tex, UV).rgb * COLOR.rgb;

	// Wetness aus Vertex-Alpha (CavePiece bäckt alpha = 1 - wetness)
	float wetness = 1.0 - COLOR.a;
	float rough = mix(roughness_dry, roughness_wet, wetness);
	albedo *= mix(1.0, wet_darken, wetness);

	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;

	float ao = 1.0;

	if (cracks_enabled) {
		// Nur auf oben zeigenden Flächen — blendet die Risse auf steilen
		// Flanken der Cave-Edge-Meshes automatisch aus
		float upness = smoothstep(0.55, 0.85, v_world_normal.y);
		if (upness > 0.001) {
			// Pixel-Quantisierung: Risskanten haben dieselbe Texel-Dichte
			// wie die Boden-Textur → fügt sich in die HD-2D-Optik ein
			float ppm = crack_pixels_per_meter;
			float texel = 1.0 / ppm;
			vec2 qp = (floor(v_world_pos.xz * ppm) + 0.5) * texel;

			// Patch-Maske: Zonen mit Rissen, Zonen ohne (billiger Early-Out)
			float patch_n = vnoise(qp * patch_frequency);
			float th = 1.0 - patch_coverage;
			float patch = smoothstep(th - 0.12, th + 0.12, patch_n);

			if (patch > 0.001) {
				float k = patch * upness;

				// 3 Taps: Zentrum + 1 Texel in X und Z → Gradient fürs Bevel
				float c = crack_field(qp);
				float cx = crack_field(qp + vec2(texel, 0.0));
				float cz = crack_field(qp + vec2(0.0, texel));

				// Höhenfeld h = -c * depth → Bruchkante fängt Licht
				vec2 grad = vec2(cx - c, cz - c) * (crack_depth / texel) * k;
				vec3 world_n = normalize(v_world_normal + vec3(grad.x, 0.0, grad.y));
				NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

				// Dunkler Kern + AO
				float core = smoothstep(0.5, 0.95, c) * k;
				albedo *= 1.0 - core * crack_darkness;
				ao = 1.0 - core * 0.45;

				// Heller Abrieb-Saum am Rissrand (Band auf der Flanke)
				float rim = smoothstep(0.05, 0.3, c) * (1.0 - smoothstep(0.35, 0.6, c));
				albedo += rim * k * edge_highlight;

				// Risskern wirkt staubig-trocken → Roughness leicht hoch
				rough = min(rough + core * 0.2, 1.0);
			}
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	AO = ao;
	if (occluder_fade < 0.999) {
		vec2 sp = FRAGCOORD.xy;
		float dither = fract(sin(dot(floor(sp), vec2(12.9898, 78.233))) * 43758.5453);
		if (dither > occluder_fade) {
			discard;
		}
	}
}
