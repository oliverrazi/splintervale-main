shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, depth_draw_opaque;

uniform sampler2D flame_tex : source_color, filter_linear; // deine Textur ODER NoiseTexture2D
uniform bool mask_from_alpha = false; // an, falls die PNG ihre Form im Alpha trägt
uniform sampler2D erode_noise : repeat_enable, filter_linear; // kleines Cellular-Noise

uniform float erode_start : hint_range(-0.5, 1.0) = 0.1;
uniform float erode_end   : hint_range(0.5, 2.0)  = 1.2;

uniform vec4 col_core  : source_color = vec4(1.0, 0.97, 0.8, 1.0);
uniform vec4 col_mid   : source_color = vec4(1.0, 0.55, 0.08, 1.0);
uniform vec4 col_outer : source_color = vec4(0.85, 0.18, 0.03, 1.0);
uniform vec4 col_old   : source_color = vec4(0.25, 0.12, 0.10, 1.0); // Ruß am Lebensende
uniform float emission_energy : hint_range(0.5, 10.0) = 3.0;

void vertex() {
	// Partikel-Rotation (CUSTOM.x) auf dem Quad anwenden, dann billboarden
	float ang = INSTANCE_CUSTOM.x;
	vec2 rc = vec2(cos(ang), sin(ang));
	VERTEX.xy = vec2(VERTEX.x * rc.x - VERTEX.y * rc.y,
	                 VERTEX.x * rc.y + VERTEX.y * rc.x);

	mat4 mv = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
	// Partikel-Scale erhalten
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = mv * mat4(
		vec4(s,0,0,0), vec4(0,s,0,0), vec4(0,0,s,0), vec4(0,0,0,1));
}

void fragment() {
	float age = INSTANCE_CUSTOM.y; // 0 = geboren, 1 = tot (liefert ParticleProcessMaterial)

	vec4 t = texture(flame_tex, UV);
	float mask = mask_from_alpha ? t.a : t.r;

	// Detail-Noise moduliert die Maske, damit kein Partikel wie das andere aussieht
	float n = texture(erode_noise, UV * 1.7 + vec2(float(INSTANCE_ID) * 0.173)).r;
	mask *= 0.65 + 0.35 * n;

	// EROSION über Lebenszeit: Threshold steigt, Partikel löst sich in Fetzen auf
	float threshold = mix(erode_start, erode_end, age * age);
	float d = mask - threshold;

	ALPHA = step(0.0, d);
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Farbrampe: Hitze aus d, Alterung Richtung Ruß
	vec3 col = col_outer.rgb;
	col = mix(col, col_mid.rgb,  smoothstep(0.05, 0.25, d));
	col = mix(col, col_core.rgb, smoothstep(0.30, 0.55, d));
	col = mix(col, col_old.rgb,  smoothstep(0.55, 1.0, age));

	ALBEDO = col * emission_energy * (1.0 - age * 0.6); // ausglühen
}