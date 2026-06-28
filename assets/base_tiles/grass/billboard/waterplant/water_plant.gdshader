shader_type spatial;
// LOESUNG (Godot-Doku): Das Wasser liest DEPTH_TEXTURE/SCREEN_TEXTURE.
// TRANSPARENTE Materialien stehen NICHT in diesen Texturen -> das Wasser
// kann sie nicht einfaerben. Ein Material wird transparent, sobald man auf
// ALPHA schreibt. Daher: NIE auf ALPHA schreiben, stattdessen
// ALPHA_SCISSOR_THRESHOLD nutzen. So bleibt die Pflanze OPAK, steht in der
// Tiefentextur, und das Wasser faerbt sie korrekt nach Tiefe ein.
render_mode cull_disabled, shadows_disabled, unshaded;


// --- Textur ---
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

// --- Bewegung (global) ---
uniform float wave_speed     = 1.6;   // Grundtempo der Hauptdrift
uniform float wave_amplitude = 0.12;  // max. horizontale Auslenkung der Spitze (m)
uniform float sway_speed     = 3.4;   // schnelle kleine Oszillation
uniform float sway_amplitude = 0.04;
uniform float base_lean      = 0.05;  // subtile gemeinsame Grundneigung (statt Symmetrie)
uniform float bend_curve     = 2.0;   // Exponent: höher = steiferer Fuß

// --- Wandernde Welle (positionsbasiert) ---
// Die Welle laeuft in diese Richtung durchs Wasser. Benachbarte Pflanzen
// teilen dadurch fast die gleiche Phase und schwingen GEMEINSAM.
uniform vec2 wave_dir = vec2(1.0, 0.3);  // Richtung in Welt-XZ
uniform float wave_length = 1.5;         // raeumliche Wellenlaenge (kleiner = engere Wellen)

// --- Tiefen-Angleichung der Spitzen ---
// Die Spitzen liegen naeher an der Oberflaeche und werden vom Wasser weniger
// blau ueberlagert -> sie stechen kraeftig-gruen heraus. Hier gleichen wir
// das an, indem wir die Spitzen leicht in Richtung Wasserfarbe tinten.
// depth_tint_color sollte etwa der Tiefenfarbe deines Wassers entsprechen.
uniform vec4 depth_tint_color : source_color = vec4(0.10, 0.30, 0.45, 1.0);
uniform float depth_tint_strength : hint_range(0.0, 1.0) = 0.35;
// Exponent: wie stark der Effekt zur Spitze hin konzentriert ist.
uniform float depth_tint_curve : hint_range(0.5, 4.0) = 1.5;

// --- Saettigung ---
// Daempft die (zu leuchtenden) Pflanzenfarben, OHNE die Pixelkanten weich zu
// machen. 1.0 = unveraendert, niedriger = entsaettigt (realistischer unter
// Wasser, Raender stechen weniger heraus). Schaerfe bleibt voll erhalten.
uniform float saturation : hint_range(0.0, 1.5) = 0.8;

varying float v_tip_weight;
varying vec4 v_custom;
varying vec3 v_tint;   // per-Instance Helligkeit aus set_instance_color (COLOR)

// INSTANCE_CUSTOM aus Baker:
//   .r = Phasen-Offset
//   .g = Amplituden-Variation (0..1)
//   .b = Frequenz-Jitter      (0..1)
//   .a = Hue-Shift (0.5 = neutral, Abweichung = Rotation auf dem Farbkreis)

// Rotiert den Farbton einer RGB-Farbe um 'shift' (in Umdrehungen, 1.0 = 360 Grad).
vec3 hue_rotate(vec3 col, float shift) {
	// RGB -> HSV
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(col.bg, K.wz), vec4(col.gb, K.xy), step(col.b, col.g));
	vec4 q = mix(vec4(p.xyw, col.r), vec4(col.r, p.yzx), step(p.x, col.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	vec3 hsv = vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
	// Hue rotieren
	hsv.x = fract(hsv.x + shift);
	// HSV -> RGB
	vec3 rgb = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return hsv.z * mix(vec3(1.0), rgb, hsv.y);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR.rgb;   // per-Instance Farbvariation aus dem Baker
	// Random-Werte nur noch fuer SUBTILE Variation, nicht fuer die Hauptphase.
	float amp_var = mix(0.85, 1.15, INSTANCE_CUSTOM.g);
	float freq_var = mix(0.95, 1.05, INSTANCE_CUSTOM.b);

	// Weltposition dieser Instanz (Translation der Modelmatrix).
	vec3 world_pos = MODEL_MATRIX[3].xyz;

	// Positionsbasierte Phase: die Welle WANDERT durchs Feld.
	// wave_dir gegen (0,0) absichern -> normalize() waere sonst NaN.
	vec2 dir = wave_dir;
	float dir_len = length(dir);
	dir = (dir_len > 0.0001) ? dir / dir_len : vec2(1.0, 0.0);
	float spatial = dot(world_pos.xz, dir) / max(wave_length, 0.001);
	// winziger Rest-Jitter aus dem Random, damit es nicht mechanisch wirkt.
	float jitter = (INSTANCE_CUSTOM.r - 0.5) * 0.4;
	float phase = spatial + jitter;

	// Fuß hat UV.y = 1, Spitze UV.y = 0 (siehe Mesh-Generator).
	// h gegen kleine negative Rundungsfehler clampen -> pow(negativ, x) ist
	// in GLSL undefiniert und erzeugt auf manchen GPUs NaN (flackernde Quads).
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float w = pow(h, bend_curve);
	v_tip_weight = h;

	float t = TIME;
	float main_wave = sin(t * wave_speed * freq_var + phase) * wave_amplitude;
	float micro     = sin(t * sway_speed * freq_var + phase * 1.7) * sway_amplitude;
	float offset_x = (main_wave + micro) * amp_var * w + base_lean * w;

	VERTEX.x += offset_x;

	// Bogen-Korrektur: Spitze sinkt bei Auslenkung leicht in Y -> biegt statt streckt.
	VERTEX.y -= abs(offset_x) * 0.35 * w;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);

	// Echter Hue-Shift pro Pflanze: v_custom.a ist 0.5 = neutral. Die Abweichung
	// davon rotiert den Farbton ueber den Farbkreis (korallenbunt bei hohem
	// color_spread im Baker, subtil bei niedrigem).
	float hue_shift = v_custom.a - 0.5;
	vec3 base = hue_rotate(tex.rgb, hue_shift);

	// Per-Instance Helligkeit (COLOR) drauf.
	vec3 col = base * v_tint;

	// Saettigung daempfen: Richtung Graustufen-Luminanz mischen. Nimmt den
	// leuchtenden Raendern die Kraft, Pixelkanten bleiben hart.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);

	// Tiefen-Angleichung (Gradient): Spitzen leicht zur Wasserfarbe tinten.
	float tip_w = clamp(v_tip_weight, 0.0, 1.0);
	float tip_factor = pow(tip_w, depth_tint_curve) * depth_tint_strength;
	col = mix(col, depth_tint_color.rgb, tip_factor);

	ALBEDO = col;
	// ALPHA_SCISSOR_THRESHOLD haelt das Material opak (sichtbar fuers Wasser).
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
