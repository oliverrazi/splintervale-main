shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// =============================================================
//  Ground Fog Patch (HD-2D)  – flach liegende Nebelfläche
//
//  Behebt ggü. der ersten Version:
//   - RADIALE Maske statt rechteckiger Border -> keine Ecken,
//     nahtloser Verlauf in alle Richtungen
//   - Bewegung NUR über langsam wabernden Noise (Fläche bleibt
//     stehen), Tempo über anim_speed (klein = fast still)
//   - gedacht für PlaneMesh (flach), kein Billboard
//
//  Soft Particles: wo der Nebel feste Geometrie (Baumstämme,
//  Statue) schneidet, blendet er weich aus statt harter Kante.
// =============================================================

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

uniform vec4  fog_color : source_color = vec4(0.72, 0.78, 0.85, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.40;

uniform float noise_scale  = 2.0;   // große Schwaden
uniform float detail_scale = 5.0;   // feine Struktur
uniform float anim_speed : hint_range(0.0, 2.0) = 0.4;   // klein = fast still
uniform vec2  drift = vec2(0.6, 0.35);                    // Richtung des Wabern

uniform float coverage : hint_range(0.0, 1.0) = 0.45;       // niedrig = wispy
uniform float noise_softness : hint_range(0.01, 1.0) = 0.40;
uniform float radial_softness : hint_range(0.05, 1.0) = 0.65; // Rand der Fläche

uniform float soft_distance = 1.5;   // Soft-Particle-Fade (Meter)
uniform float fade_near = 0.6;       // ausblenden, wenn zu nah an Kamera

uniform vec2  noise_offset = vec2(0.0);   // pro Patch unterschiedlich

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
	vec2 d = drift * t * 0.01;   // bewusst klein

	float n = fbm(UV * noise_scale + noise_offset + d) * 0.6
	        + fbm(UV * detail_scale + noise_offset * 1.7 - d * 0.6) * 0.4;
	float cloud = smoothstep(coverage, coverage + noise_softness, n);

	// --- RADIALE Maske: weich, rund, keine Ecken --------------------
	float r = length(UV - 0.5) * 2.0;                 // 0 Mitte .. ~1.41 Ecke
	float mask = smoothstep(1.0, 1.0 - radial_softness, r);

	float alpha = cloud * mask * opacity;

	// --- Soft Particles ---------------------------------------------
	float scene_d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float frag_depth = -VERTEX.z;
	alpha *= clamp((scene_depth - frag_depth) / max(soft_distance, 0.001), 0.0, 1.0);
	alpha *= clamp((frag_depth - fade_near) / max(fade_near, 0.001), 0.0, 1.0);

	ALBEDO = fog_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
