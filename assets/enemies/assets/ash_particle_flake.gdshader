shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_disabled, cull_disabled;

uniform float softness : hint_range(0.0, 1.0) = 0.85;
uniform float inner_variation : hint_range(0.0, 0.5) = 0.15;

// WICHTIG: COLOR vom Particle-System kommt im VERTEX stage rein.
// Muss per varying ins Fragment durchgereicht werden - sonst sind alle Partikel weiss.
varying vec4 v_color;

void vertex() {
	v_color = COLOR;

	// Full Billboard
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
	vec2 c = UV - 0.5;
	float d = length(c) * 2.0;

	// Sehr weicher radialer Falloff - keine harten Kanten mehr
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	if (a < 0.01) discard;

	ALBEDO = v_color.rgb * (1.0 - d * inner_variation);
	ALPHA = a * v_color.a;
}
