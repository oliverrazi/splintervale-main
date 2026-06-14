shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

// Staub statt Funken: weiche, fraktal-verrauschte Wolkenpartikel mit Alpha-Blending.
// Jeder Partikel ist selbst eine kleine Rauchscholle, viele überlappen zur Wolke.

uniform vec4 core_color : source_color = vec4(0.82, 0.90, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.35, 0.5, 0.95, 1.0);
uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform float softness : hint_range(0.5, 4.0) = 1.6;

varying float v_lifetime;

// Hash + value noise für prozedurale Wolkenstruktur
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion → wolkige, mehrskalige Struktur
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_lifetime = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;

	// Weicher runder Rand
	float radial = pow(clamp(1.0 - dist, 0.0, 1.0), softness);

	// Wolkenstruktur: FBM, leicht über Lebenszeit driftend (löst sich auf)
	float cloud = fbm(UV * 3.0 + vec2(v_lifetime * 0.5));
	cloud = smoothstep(0.2, 0.9, cloud);

	// Fade-In schnell, Fade-Out lang
	float fade_in = smoothstep(0.0, 0.05, v_lifetime);
	float fade_out = 1.0 - smoothstep(0.6, 1.0, v_lifetime);
	float life_alpha = fade_in * fade_out;

	vec3 col = mix(core_color.rgb, edge_color.rgb, v_lifetime);

	// Matt, nicht leuchtend: moderate Helligkeit, Alpha trägt den Look
	ALPHA = radial * cloud * life_alpha * density;
	ALBEDO = col;
}