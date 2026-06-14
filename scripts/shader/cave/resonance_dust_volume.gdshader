shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

void vertex() {
	// Kamera-ausgerichtetes Billboard: Quad zeigt immer zur Kamera,
	// dadurch keine Durchdringungskanten mit anderen Flächen.
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	// Rotation entfernen, Translation + Skalierung behalten
	mv[0] = vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0);
	mv[1] = vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0);
	mv[2] = vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0);
	MODELVIEW_MATRIX = mv;
}

// Volumetrische Staubwolke nach FogPatch-Prinzip:
// stehende Geometrie, innere Bewegung über FBM, lebenszeit-getrieben.

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

uniform vec4 core_color : source_color = vec4(0.65, 0.69, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.45, 0.6, 0.95, 1.0);
uniform float opacity : hint_range(0.0, 2.0) = 0.9;
uniform float coverage : hint_range(0.0, 1.0) = 0.35;
uniform float noise_softness : hint_range(0.01, 1.0) = 0.45;
uniform float noise_scale = 2.5;
uniform float detail_scale = 6.0;
uniform float anim_speed : hint_range(0.0, 4.0) = 1.5;
uniform float soft_distance = 0.8;

// 0 = gerade entstanden, 1 = gleich verschwunden. Vom Skript getweent.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 noise_offset = vec2(0.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float t = TIME * anim_speed;

	// Noise driftet langsam nach oben (UV.y) → Staub wabert aufwärts ohne Partikel
	vec2 drift = vec2(t * 0.02, -t * 0.06);
	float n = fbm(UV * noise_scale + noise_offset + drift) * 0.6
	        + fbm(UV * detail_scale + noise_offset * 1.7 - drift * 0.5) * 0.4;

	// Coverage öffnet sich beim Entstehen (dichter) und löst sich am Ende auf
	float cov = mix(coverage * 0.5, coverage + 0.25, smoothstep(0.0, 0.3, progress));
	float cloud = smoothstep(cov, cov + noise_softness, n);

	// Radiale Maske: weiche runde Wolke, keine Box-Kanten
	float r = length(UV - 0.5) * 2.0;
	float mask = smoothstep(1.0, 0.0, r);
	mask = pow(mask, 1.8);

	// Pro-Achsen-Kantenfade → auch die geraden Quad-Ränder weich
	vec2 edge = smoothstep(0.0, 0.35, UV) * smoothstep(0.0, 0.35, 1.0 - UV);
	float edge_fade = edge.x * edge.y;

	// Lebenszyklus
	float fade_in = smoothstep(0.0, 0.12, progress);
	float fade_out = 1.0 - smoothstep(0.55, 1.0, progress);
	float life = fade_in * fade_out;

	vec3 col = mix(core_color.rgb, edge_color.rgb, progress);

	float alpha = cloud * mask * edge_fade * life * opacity;
	// Soft Particles — weiche Kante an Geometrie (Brocken, Boden)
	float scene_d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float frag_depth = -VERTEX.z;
	alpha *= clamp((scene_depth - frag_depth) / max(soft_distance, 0.001), 0.0, 1.0);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}