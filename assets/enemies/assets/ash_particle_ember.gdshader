shader_type spatial;
render_mode unshaded, blend_add, depth_draw_disabled, cull_disabled;

uniform float core_boost : hint_range(0.5, 5.0) = 2.5;
uniform float core_radius : hint_range(0.05, 0.6) = 0.2;
uniform float halo_strength : hint_range(0.0, 1.0) = 0.5;

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
	vec2 c = UV - 0.5;
	float d = length(c) * 2.0;

	float core = 1.0 - smoothstep(0.0, core_radius, d);
	float halo = 1.0 - smoothstep(0.0, 1.0, d);
	halo = halo * halo;

	float intensity = core * core_boost + halo * halo_strength;
	if (intensity < 0.01) discard;

	ALBEDO = v_color.rgb;
	ALPHA = intensity * v_color.a;
}
