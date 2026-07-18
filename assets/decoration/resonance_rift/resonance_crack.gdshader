shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
// =============================================================
//  Resonance Crack (HD-2D)  – leuchtender Riss am Boden
//
//  Gedacht für ein flaches PlaneMesh, ~0.01 über dem Terrain
//  (Z-Fighting). Prozedurale Risse über Voronoi-Kanten (F-Border-
//  Distanz), mit Noise-Warp organisch verzogen. Heißer weißer
//  Kern in der Mitte, hellblaue Rissarme nach außen, radiale
//  Maske wie beim FogPatch -> keine sichtbare Plane-Kante.
//
//  `pulse` ist ein instance uniform (Script-getrieben, synchron
//  zum OmniLight und zum Beam). `crack_offset` ebenfalls, damit
//  jeder Riss bei geteiltem Material anders aussieht.
// =============================================================
uniform vec4  core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4  edge_color : source_color = vec4(0.50, 0.75, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 3.0;
instance uniform float pulse : hint_range(0.0, 2.0) = 1.0;
instance uniform vec2 crack_offset = vec2(0.0);

uniform float crack_scale = 3.5;      // Anzahl Voronoi-Zellen über die Plane
uniform float crack_width : hint_range(0.005, 0.2) = 0.045;
uniform float warp_amount : hint_range(0.0, 1.0) = 0.35;  // organisches Verziehen

uniform float core_strength : hint_range(0.0, 3.0) = 1.2; // heller Mittelkern
uniform float core_tightness = 9.0;   // groß = kleiner Kern

uniform float anim_speed : hint_range(0.0, 2.0) = 0.5;    // Energie-Schimmern
uniform float radial_softness : hint_range(0.05, 1.0) = 0.55;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
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

// Voronoi-Kanten-Distanz (iq): Distanz zur nächsten Zellgrenze.
// Kleine Werte = auf einer Grenze = Riss.
float voronoi_edge(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	// --- Radiale Maske (wie FogPatch): keine sichtbaren Plane-Ecken
	float r = length(UV - 0.5) * 2.0;
	float mask = smoothstep(1.0, 1.0 - radial_softness, r);

	// --- Risse: Voronoi-Kanten, organisch verzogen ----------------
	vec2 p = UV * crack_scale + crack_offset;
	p += (vec2(vnoise(p * 3.0), vnoise(p * 3.0 + 17.3)) - 0.5) * warp_amount;
	float edge = voronoi_edge(p);
	float crack = 1.0 - smoothstep(0.0, crack_width, edge);

	// --- Energie schimmert die Rissarme entlang ------------------
	float t = TIME * anim_speed;
	crack *= 0.7 + 0.3 * fbm(UV * 6.0 + crack_offset + vec2(t, t * 0.6));

	// --- Heißer Kern in der Mitte ---------------------------------
	float core = exp(-r * r * core_tightness) * core_strength;

	float glow = (crack * mask + core) * pulse;
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(core + crack * 0.35, 0.0, 1.0));
	ALBEDO = col * intensity * glow;
	ALPHA = clamp(glow, 0.0, 1.0);
}
