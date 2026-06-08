// ============================================================================
//  tree_variation.gdshader
//  Per-Instance Farbvariation für MultiMesh-Bäume (AAA Vegetation Variation)
//
//  Liest INSTANCE_CUSTOM (4 floats, jeweils 0..1) und verschiebt pro Instanz:
//    .r  -> Hue-Shift        (Frühling <-> Herbst)
//    .g  -> Helligkeit       (Sonne <-> Schatten)
//    .b  -> Sättigung        (kräftig <-> verblasst)
//    .a  -> frei (z.B. Wind-Phase, hier ungenutzt)
//
//  Dieser Shader bildet den Look eines StandardMaterial3D nach (Albedo-Textur
//  + Albedo-Farbe + alpha-scissor für Blätter), erweitert um die Variation.
//  -> Scene und Meshes bleiben unangetastet; nur das MultiMesh nutzt dieses
//     Material als material_override.
// ============================================================================
shader_type spatial;

// Cutout für Blätter (Alpha-Kanten). Bei Stamm einfach hoch setzen / ignorieren.
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// --- Texturen / Basis (entspricht StandardMaterial3D) -----------------------
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

// Alpha-Scissor für Blätter (wie StandardMaterial3D "Alpha Scissor Threshold")
uniform bool use_alpha_scissor = true;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// --- Variations-Stärke (global einstellbar im Inspector) --------------------
// Maximaler Hue-Shift in beide Richtungen (in "Hue-Einheiten", 1.0 = 360°).
uniform float hue_variation_range : hint_range(0.0, 0.5) = 0.06;
// Helligkeit: wie stark darf abgedunkelt/aufgehellt werden.
uniform float brightness_variation_range : hint_range(0.0, 1.0) = 0.25;
// Sättigung: wie stark darf entsättigt/übersättigt werden.
uniform float saturation_variation_range : hint_range(0.0, 1.0) = 0.30;

// Optional: globaler Saison-Tint, der ALLE Bäume gemeinsam verschiebt
// (z.B. für Herbst-Areale). Identity = kein Effekt.
uniform float season_hue_shift : hint_range(-0.5, 0.5) = 0.0;

varying vec3 v_variation; // (hue_shift, brightness_mul, saturation_mul)

// --- RGB <-> HSV Hilfsfunktionen --------------------------------------------
vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	// INSTANCE_CUSTOM ist 0..1 (8-bit quantisiert von set_instance_custom_data).
	// Auf symmetrischen Bereich [-1..1] mappen für Hue/Brightness/Saturation.
	float hue_signed = (INSTANCE_CUSTOM.r * 2.0 - 1.0);
	float bri_signed = (INSTANCE_CUSTOM.g * 2.0 - 1.0);
	float sat_signed = (INSTANCE_CUSTOM.b * 2.0 - 1.0);

	v_variation = vec3(
		hue_signed * hue_variation_range + season_hue_shift,
		1.0 + bri_signed * brightness_variation_range,
		1.0 + sat_signed * saturation_variation_range
	);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base = tex.rgb * albedo_color.rgb;

	// In HSV verschieben
	vec3 hsv = rgb_to_hsv(base);
	hsv.x = fract(hsv.x + v_variation.x);          // Hue (wrap-around)
	hsv.y = clamp(hsv.y * v_variation.z, 0.0, 1.0); // Saturation
	hsv.z = clamp(hsv.z * v_variation.y, 0.0, 1.0); // Value/Brightness
	vec3 varied = hsv_to_rgb(hsv);

	ALBEDO = varied;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	float a = tex.a * albedo_color.a;
	if (use_alpha_scissor) {
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
		ALPHA = a;
	}
}
