shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_disable;

// Wind
uniform float wind_strength : hint_range(0.0, 1.0) = 0.3;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.5;
uniform float wind_scale : hint_range(0.01, 1.0) = 0.1;
uniform vec2 wind_direction = vec2(1.0, 0.3);

// LOD
uniform float lod_fade_start : hint_range(0.0, 100.0) = 30.0;
uniform float lod_fade_end : hint_range(0.0, 200.0) = 50.0;

// Farbvariation (Perlin-basiert)
uniform float color_noise_scale : hint_range(0.01, 1.0) = 0.05;
uniform float brightness_variation : hint_range(0.0, 0.5) = 0.2;
uniform float saturation_variation : hint_range(0.0, 0.5) = 0.15;
uniform vec3 color_tint_a : source_color = vec3(0.85, 1.0, 0.75);
uniform vec3 color_tint_b : source_color = vec3(0.9, 0.8, 0.1);

// Höhenbasierte Tönung
uniform vec3 tip_tint : source_color = vec3(1.1, 1.15, 0.9);
uniform float tip_tint_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec3 base_tint : source_color = vec3(0.4, 0.55, 0.3);
uniform float base_tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.4;

varying float vertex_height;
varying flat float lod_alpha;       // KORREKTUR 1: flat — pro Instanz konstant
varying vec3 world_position;
varying float wind_tint;            // OPTIMIERUNG: Wind-Noise einmal im Vertex berechnen

// ============ PERLIN NOISE ============

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float perlin(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * perlin(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return value;
}

// ============ VERTEX ============

void vertex() {
	world_position = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// LOD (pro Instanz, am Fußpunkt → flat)
	float dist_to_cam = length(world_position - CAMERA_POSITION_WORLD);
	lod_alpha = 1.0 - smoothstep(lod_fade_start, lod_fade_end, dist_to_cam);

	// KORREKTUR 2: Quad NICHT auf vec3(0) kollabieren.
	// Das alte VERTEX = vec3(0.0) zog bei interpolierten AABBs Artefakte und
	// half dem Culling nicht (MultiMesh-AABB ist statisch). Das Distanz-Culling
	// macht jetzt visibility_range_end auf Chunk-Ebene; hier reicht ALPHA=0.

	// Y-Achsen Billboard
	vec3 cam_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 forward = normalize(cross(up, cam_right));

	mat4 billboard = mat4(
		vec4(cam_right, 0.0),
		vec4(up, 0.0),
		vec4(forward, 0.0),
		MODEL_MATRIX[3]
	);
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);

	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;

	vertex_height = UV.y;

	float height_from_base = 1.0 - UV.y;
	float wind_factor = height_from_base * height_from_base;

	// ============ PERLIN WIND ============
	vec2 wind_dir = normalize(wind_direction);
	vec2 wind_sample_pos = world_position.xz * wind_scale;
	wind_sample_pos -= wind_dir * TIME * wind_speed;

	// Per-Instanz Phase aus custom data (vom GrassSystem gesetzt).
	float phase = INSTANCE_CUSTOM.x;
	wind_sample_pos += vec2(phase) * 0.05;

	float wind_noise = fbm(wind_sample_pos, 2);   // OPT: 3 → 2 Oktaven reicht visuell
	float wind_amount = (wind_noise * 0.5 + 0.5) * wind_strength;
	float base_wind = wind_strength * 0.3;
	float total_wind = base_wind + wind_amount;

	VERTEX.x += wind_dir.x * total_wind * wind_factor;
	VERTEX.z += wind_dir.y * total_wind * wind_factor * 0.5;
	VERTEX.y -= total_wind * wind_factor * 0.15;

	wind_tint = wind_noise * 0.5 + 0.5;
}

// ============ FRAGMENT ============

void fragment() {
	// KORREKTUR 3: hartes Distanz-Discard vor der Textur spart Sampling.
	if (lod_alpha < 0.01) {
		discard;
	}

	vec4 tex = texture(grass_texture, UV);
	if (tex.a < 0.5) {
		discard;
	}

	float height_normalized = 1.0 - vertex_height;

	// ============ PERLIN FARBVARIATION ============
	// OPT: nur EIN fbm-Aufruf statt zwei. Den Detail-Layer ersetzen wir durch
	// den bereits im Vertex berechneten wind_tint (kostenlos interpoliert),
	// was zudem Farbe subtil an die Windwellen koppelt — wirkt lebendiger.
	vec2 color_sample_pos = world_position.xz * color_noise_scale;
	float color_noise = fbm(color_sample_pos, 2);
	float noise_normalized = clamp(color_noise * 0.5 + 0.5, 0.0, 1.0);
	noise_normalized = mix(noise_normalized, wind_tint, 0.15);

	vec3 color = tex.rgb * COLOR.rgb;
	vec3 tinted_color = mix(color * color_tint_b, color * color_tint_a, noise_normalized);

	float brightness = 1.0 + (noise_normalized - 0.5) * brightness_variation * 2.0;
	//tinted_color *= brightness;

	float luminance = dot(tinted_color, vec3(0.299, 0.587, 0.114));
	float sat_factor = 1.0 + (noise_normalized - 0.5) * saturation_variation * 2.0;
	sat_factor = clamp(sat_factor, 0.0, 1.0);
	//tinted_color = mix(vec3(luminance), tinted_color, sat_factor);

	color = tinted_color;

	// Höhenbasierte Tönung
	color = mix(color, color * tip_tint, height_normalized * tip_tint_strength);
	color = mix(color, color * base_tint, (1.0 - height_normalized) * base_tint_strength);

	float ao = mix(1.0 - ao_strength, 1.0, height_normalized);
	color *= ao;

	ALBEDO = color;
	ALPHA = tex.a * lod_alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.1;
}
