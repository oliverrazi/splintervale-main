shader_type spatial;
render_mode unshaded, shadows_disabled, cull_back, depth_draw_opaque;

// --- Größe (Meter, Weltmaßstab) ---
uniform float flame_height : hint_range(0.02, 1.0) = 0.09;
uniform float flame_radius : hint_range(0.005, 0.5) = 0.025;
uniform float profile_exp  : hint_range(0.3, 1.5)  = 0.55; // <1 = Bauch weiter unten

// --- Bewegung ---
uniform float scroll_speed  : hint_range(0.2, 4.0)  = 1.3;
uniform float wobble_amount : hint_range(0.0, 0.05) = 0.008;
uniform float wobble_speed  : hint_range(0.0, 12.0) = 5.0;

// --- Noise / Erosion ---
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float noise_tiles_around : hint_range(0.5, 4.0) = 1.0;
uniform float noise_tiles_height : hint_range(0.5, 4.0) = 1.5;
uniform float erode_base : hint_range(0.0, 1.0) = 0.15; // Threshold an der Basis
uniform float erode_tip  : hint_range(0.5, 1.5) = 1.0;  // Threshold an der Spitze

// --- Farben (hartes Banding) ---
uniform vec4 color_outer : source_color = vec4(0.9, 0.2, 0.05, 1.0);
uniform vec4 color_mid   : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform vec4 color_core  : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float band_mid  : hint_range(0.0, 0.5) = 0.12;
uniform float band_core : hint_range(0.0, 0.5) = 0.26;
uniform float emission_energy : hint_range(0.5, 8.0) = 2.5;

instance uniform float phase_offset = 0.0;

varying float v_h; // 0 = Basis, 1 = Spitze

void vertex() {
	// Einheitszylinder (Höhe 1, Radius 0.5) -> Flammen-Silhouette
	float h = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	v_h = h;

	// Tropfenprofil: unten schmal, Bauch im unteren Drittel, spitz zulaufend
	float profile = sin(PI * pow(h, profile_exp));

	vec2 xz = VERTEX.xz * 2.0 * profile * flame_radius;
	float y = h * flame_height; // Origin = Flammenbasis, bequem zum Platzieren

	// Großräumiges Wabern, nimmt zur Spitze quadratisch zu
	vec2 sway = vec2(
		sin(TIME * wobble_speed + phase_offset),
		cos(TIME * wobble_speed * 0.73 + phase_offset * 1.3));
	xz += sway * wobble_amount * h * h;

	VERTEX = vec3(xz.x, y, xz.y);
}

void fragment() {
	float t = TIME * scroll_speed + phase_offset;

	// Noise scrollt nach unten -> Strukturen wandern optisch nach oben
	vec2 uv1 = vec2(UV.x * noise_tiles_around, v_h * noise_tiles_height - t);
	vec2 uv2 = uv1 * 2.3 + vec2(0.37, -t * 0.6);
	float n = texture(noise_tex, uv1).r * 0.7 + texture(noise_tex, uv2).r * 0.3;

	// EROSION: unten solide, oben frisst der Noise die Form weg
	// -> erzeugt die klaren, sich ablösenden Flammenzungen
	float threshold = mix(erode_base, erode_tip, pow(v_h, 1.3));
	float d = n - threshold;

	ALPHA = step(0.0, d);
	ALPHA_SCISSOR_THRESHOLD = 0.5; // hält uns im Opaque-Pass, Depth wird geschrieben

	// Harte Farbrampe: je weiter über dem Threshold, desto heißer
	vec3 col = color_outer.rgb;
	col = mix(col, color_mid.rgb, step(band_mid, d));
	// Kern nur im unteren Bereich der Flamme
	col = mix(col, color_core.rgb, step(band_core, d) * (1.0 - smoothstep(0.4, 0.8, v_h)));

	ALBEDO = col * emission_energy;
}