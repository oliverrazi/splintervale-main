shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_disabled, cull_disabled;

// Extra weicher Falloff fuer Smoke - sieht wolkiger aus
uniform float softness : hint_range(0.5, 1.0) = 0.95;

// Wieviel die UVs ueber Lifetime noisig verzerrt werden
uniform sampler2D distortion_tex : repeat_enable, filter_linear;
uniform float distortion_strength : hint_range(0.0, 0.3) = 0.08;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	vec2 uv = UV;

	// UV-Distortion mit Noise, damit jede Wolke individuell und nicht
	// wie ein perfekter Kreis aussieht
	vec2 noise_uv = uv + vec2(TIME * 0.05, TIME * -0.03);
	vec2 distortion = (texture(distortion_tex, noise_uv).rg - 0.5) * distortion_strength;
	uv += distortion;

	vec2 c = uv - 0.5;
	float d = length(c) * 2.0;

	// Sehr weicher Falloff - reine Form, keine Kante sichtbar
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	if (a < 0.005) discard;

	// Sanfte Helligkeitsvariation im Zentrum, dunkler an den Raendern
	float center_glow = 1.0 + (1.0 - d) * 0.3;

	ALBEDO = v_color.rgb * center_glow;
	ALPHA = a * v_color.a;
}
