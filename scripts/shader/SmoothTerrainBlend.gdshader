shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D grass_tex : source_color;
uniform sampler2D dirt_tex  : source_color;

// Schwellwert für Material-Auswahl basierend auf Normal-Richtung
// Normal mit Y > threshold = Gras (oben/flach)
// Normal mit Y <= threshold = Erde (Seite/steil)
uniform float material_threshold : hint_range(0.0, 1.0) = 0.7;

uniform float grass_uv_scale : hint_range(0.01, 5.0) = 0.5;
uniform float dirt_uv_scale  : hint_range(0.01, 5.0) = 0.5;

varying vec3 v_normal;

void vertex() {
	// Normale in Weltkoordinaten umrechnen
	mat3 nmat = transpose(inverse(mat3(MODEL_MATRIX)));
	v_normal = normalize(nmat * NORMAL);
}

void fragment() {
	// Y-Komponente der Normal zeigt wie "oben" die Fläche zeigt
	// 1.0 = perfekt horizontal (Gras oben)
	// 0.0 = vertikal (Seite/Wand)
	float vertical_component = v_normal.y;

	// Material-Auswahl:
	// Wenn Normal-Y > threshold = Gras
	// Wenn Normal-Y <= threshold = Erde (Wand)
	float is_grass = step(material_threshold, vertical_component);

	vec3 col_grass = texture(grass_tex, UV * grass_uv_scale).rgb;
	vec3 col_dirt  = texture(dirt_tex,  UV * dirt_uv_scale).rgb;

	ALBEDO = mix(col_dirt, col_grass, is_grass);
	ROUGHNESS = mix(0.7, 0.9, is_grass);  // Erde glatter, Gras rauer
	METALLIC = 0.0;
}