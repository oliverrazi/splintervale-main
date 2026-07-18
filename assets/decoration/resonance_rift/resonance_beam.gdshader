shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
// =============================================================
//  Resonance Beam v3 (HD-2D)  – statische God Rays aus dem Boden
//
//  Änderungen ggü. v2:
//   - KOMPLETT STATISCH: kein Noise-Scrolling, kein Sway mehr.
//     Bewegung kommt aus Motes + Puls (Helligkeit), nicht aus
//     dem Strahlmuster. Klassischer God-Ray-Look, und billiger.
//   - stretch_scale = 0.0 -> perfekt gerade, durchgezogene
//     Strahlen. Kleine Werte (0.3) -> leichte vertikale Variation.
//
//  Bewährt aus v2:
//   - Triplanar-Noise (nahtfrei, keine Streifen-Scheiben)
//   - back_face_dim gegen die additive Doppel-Schale
//   - Crack-Maske: Strahl nur wo der Riss offen ist, weitet sich
//     nach oben auf (mask_spread) und wird weicher (mask_blur).
//     Sampler kann kein instance uniform sein -> pro Riss mit
//     eigener Maske eine Material-Kopie.
//
//  Mesh: CylinderMesh als Kegel, Caps AUS. beam_height muss zur
//  Mesh-Höhe passen.
// =============================================================
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

uniform vec4  core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);   // Weiß
uniform vec4  edge_color : source_color = vec4(0.55, 0.78, 1.0, 1.0); // Hellblau
uniform float intensity : hint_range(0.0, 8.0) = 2.4;   // >1 = Glow-Futter
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
instance uniform float pulse : hint_range(0.0, 2.0) = 1.0;

uniform float beam_height = 1.6;      // MUSS zur Mesh-Höhe passen
uniform float falloff_power : hint_range(0.5, 6.0) = 2.0;  // vertikales Ausfaden

// --- Doppel-Schalen-Fix ------------------------------------------
uniform float back_face_dim : hint_range(0.0, 1.0) = 0.3;

// --- Strahlen-Struktur (statisch, triplanar) ----------------------
uniform float streak_scale = 6.0;     // horizontale Frequenz der Strahlen
uniform float stretch_scale : hint_range(0.0, 3.0) = 0.0; // 0 = kerzengerade Rays
uniform float ray_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float ray_softness : hint_range(0.01, 1.0) = 0.45;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.75; // 0 = homogen

// --- Crack-Maske ---------------------------------------------------
uniform bool use_mask = false;
uniform sampler2D crack_mask : source_color, filter_linear_mipmap;
uniform float mask_size = 0.5;        // Weltbreite (m), die die Maske am Fuß abdeckt
uniform float mask_spread : hint_range(0.0, 3.0) = 0.8;  // Aufweitung nach oben
uniform float mask_blur : hint_range(0.0, 8.0) = 3.0;    // Mip-LOD an der Spitze

// --- Silhouette / Kern -------------------------------------------
uniform float edge_softness : hint_range(0.05, 1.0) = 0.45;
uniform float core_power : hint_range(0.5, 8.0) = 2.5;

// --- Schnitt mit Geometrie / Kamera-Nähe -------------------------
uniform float soft_distance = 0.15;   // Miniatur-Skala
uniform float fade_near = 0.15;

varying float v_h;       // 0 = Fuß, 1 = Spitze
varying vec3  v_local;   // Model-Space-Position (Noise + Maske)
varying vec3  v_nrm;     // Model-Space-Normale (Triplanar-Gewichte)

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
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX;
	v_nrm = NORMAL;
	v_h = clamp(VERTEX.y / max(beam_height, 0.001) + 0.5, 0.0, 1.0);
}

void fragment() {
	// --- Statische Strahlen: Triplanar-Noise, nahtfrei ------------
	// x-zugewandte Flächen sampeln in der Z-Ebene, z-zugewandte in X.
	// stretch_scale = 0 -> Noise hängt nur von der horizontalen
	// Position ab -> jede "Strähne" läuft gerade von unten bis oben.
	float wx = v_nrm.x * v_nrm.x;
	float wz = v_nrm.z * v_nrm.z;
	float wsum = max(wx + wz, 0.001);
	float n_a = fbm(vec2(v_local.z * streak_scale, v_h * stretch_scale));
	float n_b = fbm(vec2(v_local.x * streak_scale + 31.4, v_h * stretch_scale + 5.2));
	float n = (n_a * wx + n_b * wz) / wsum;

	float rays = smoothstep(ray_coverage, ray_coverage + ray_softness, n);
	rays = mix(1.0, rays, ray_strength);

	// --- Vertikales Ausfaden: unten dicht, oben nichts -----------
	float fall = pow(clamp(1.0 - v_h, 0.0, 1.0), falloff_power);

	// --- Fresnel: weiche Silhouette + heller weißer Kern ---------
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_fade = smoothstep(0.0, edge_softness, ndv);
	float core = pow(ndv, core_power);

	float alpha = fall * rays * edge_fade * opacity;

	// --- Doppel-Schalen-Fix: Rückseite dimmen ---------------------
	if (!FRONT_FACING) {
		alpha *= back_face_dim;
	}

	// --- Crack-Maske: Strahl nur wo der Riss offen ist ------------
	if (use_mask) {
		float spread = 1.0 + v_h * mask_spread;
		vec2 muv = v_local.xz / (mask_size * spread) + 0.5;
		float m = textureLod(crack_mask, muv, v_h * mask_blur).r;
		m *= step(0.0, muv.x) * step(muv.x, 1.0) * step(0.0, muv.y) * step(muv.y, 1.0);
		alpha *= m;
	}

	// --- Soft Particles (identisch zum FogPatch) ------------------
	float scene_d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float frag_depth = -VERTEX.z;
	alpha *= clamp((scene_depth - frag_depth) / max(soft_distance, 0.001), 0.0, 1.0);
	alpha *= clamp((frag_depth - fade_near) / max(fade_near, 0.001), 0.0, 1.0);

	ALBEDO = mix(edge_color.rgb, core_color.rgb, core) * intensity * pulse;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
