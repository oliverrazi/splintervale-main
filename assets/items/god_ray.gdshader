shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

// God Ray: vertikaler Lichtschacht der wie ein "Strahl von oben" wirkt.
// Y-Billboard - immer breit zur Kamera, vertikal bleibend.

uniform vec4 ray_color : source_color = vec4(0.55, 0.82, 1.0, 1.0);
uniform float core_brightness : hint_range(0.5, 5.0) = 2.0;
uniform float fade_in : hint_range(0.0, 1.0) = 0.0;
uniform float top_fade : hint_range(0.0, 0.5) = 0.15;
uniform float horizontal_softness : hint_range(0.0, 2.0) = 0.7;

// Schimmer (animierte leichte Helligkeitsvariation)
uniform float shimmer_speed : hint_range(0.0, 3.0) = 1.2;
uniform float shimmer_amount : hint_range(0.0, 0.5) = 0.15;


void vertex() {
	// Y-Billboard: behaelt Y-Achse, X-Achse zeigt zur Kamera-Seitlich
	mat4 m = MODEL_MATRIX;
	vec3 cam_dir = normalize(INV_VIEW_MATRIX[3].xyz - m[3].xyz);
	cam_dir.y = 0.0;
	cam_dir = normalize(cam_dir);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), cam_dir));
	m[0] = vec4(right * length(MODEL_MATRIX[0].xyz), 0.0);
	m[2] = vec4(cam_dir * length(MODEL_MATRIX[2].xyz), 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
}


void fragment() {
	// Horizontal: heller Kern in der Mitte, weich am Rand
	float h = 1.0 - abs(UV.x - 0.5) * 2.0;
	h = pow(h, 1.0 + horizontal_softness);

	// Vertikal: weiche Spitze oben, kein hard cut unten (geht in den Boden)
	float v_top = 1.0 - smoothstep(1.0 - top_fade, 1.0, UV.y);

	// Schimmer ueber die Hoehe
	float shimmer = 1.0 + sin(TIME * shimmer_speed + UV.y * 8.0) * shimmer_amount;

	float intensity = h * v_top * shimmer * core_brightness * fade_in;

	if (intensity < 0.01) discard;

	ALBEDO = ray_color.rgb;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
