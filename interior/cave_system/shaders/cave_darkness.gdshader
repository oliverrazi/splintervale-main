shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;

// ============================================================
// CAVE DARKNESS v2 - Fullscreen post-pass
// Geometrie-Pixel: Box-SDF-Test der World-Position.
// Leere Pixel (kein Depth): Ray-vs-Box-Test der Sichtlinie.
// -> Void wird nur dort geschwaerzt, wo ein Volume liegt.
// Ein Draw Call fuer alle Volumes. Godot 4.3+ (Reversed-Z).
// ============================================================

const int MAX_VOLUMES = 16;

uniform int volume_count = 0;
uniform vec3 volume_pos[MAX_VOLUMES];
uniform vec3 volume_axis_x[MAX_VOLUMES];
uniform vec3 volume_axis_y[MAX_VOLUMES];
uniform vec3 volume_axis_z[MAX_VOLUMES];
uniform vec3 volume_extents[MAX_VOLUMES];   // Halbe Kantenlaengen
uniform float volume_softness[MAX_VOLUMES]; // Breite des Falloff-Bands

uniform vec4 darkness_color : source_color = vec4(0.016, 0.024, 0.045, 1.0);
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D edge_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale : hint_range(0.01, 2.0) = 0.25;
uniform float noise_strength : hint_range(0.0, 2.0) = 0.6;

// Wird nicht mehr fuer globales Schwaerzen genutzt, sondern schaltet
// den Ray-Test fuer leere Pixel an/aus (true lassen).
uniform bool darken_background = true;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float box_sdf(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Slab-Test: Strecke, die der Ray innerhalb der Box zuruecklegt (0 = kein Treffer)
float ray_box_penetration(vec3 ro, vec3 rd, vec3 extents) {
	vec3 inv = 1.0 / rd; // inf bei rd-Komponente 0 ist im Slab-Test unkritisch
	vec3 t1 = (-extents - ro) * inv;
	vec3 t2 = ( extents - ro) * inv;
	vec3 tmin3 = min(t1, t2);
	vec3 tmax3 = max(t1, t2);
	float tmin = max(max(tmin3.x, tmin3.y), tmin3.z);
	float tmax = min(min(tmax3.x, tmax3.y), tmax3.z);
	return max(tmax - max(tmin, 0.0), 0.0) * step(max(tmin, 0.0), tmax);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;

	// World-Position rekonstruieren (Reversed-Z, Vulkan NDC)
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;

	// Kamera-Position + Sichtlinien-Richtung fuer den Void-Ray-Test
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 ray_dir = normalize(world_pos - cam_pos);

	// Reversed-Z: Background = 0.0
	float is_background = step(depth, 0.0000001);

	// Noise VOR dem Loop unconditionally samplen (Derivative-Problem)
	// Bei Background-Pixeln gibt world_pos.xz Far-Plane-Koordinaten -> fuer
	// Kanten-Fransen trotzdem brauchbar, da stetig ueber den Screen.
	float n = texture(edge_noise, world_pos.xz * noise_scale).r;

	float dark = 0.0;
	for (int i = 0; i < MAX_VOLUMES; i++) {
		if (i >= volume_count) { break; }

		float soft = max(volume_softness[i], 0.001);
		float a = 0.0;

		if (is_background > 0.5) {
			// --- VOID-PFAD: Ray-vs-OBB ---
			if (darken_background) {
				vec3 rel = cam_pos - volume_pos[i];
				vec3 ro_local = vec3(
					dot(rel, volume_axis_x[i]),
					dot(rel, volume_axis_y[i]),
					dot(rel, volume_axis_z[i])
				);
				vec3 rd_local = vec3(
					dot(ray_dir, volume_axis_x[i]),
					dot(ray_dir, volume_axis_y[i]),
					dot(ray_dir, volume_axis_z[i])
				);
				float pen = ray_box_penetration(ro_local, rd_local, volume_extents[i]);
				// Je tiefer die Sichtlinie die Box durchquert, desto dunkler.
				// Noise verschiebt die Schwelle -> organische Kante statt Slab-Silhouette.
				float noisy_pen = pen - (n - 0.5) * noise_strength * soft;
				a = smoothstep(0.0, soft, noisy_pen);
			}
		} else {
			// --- GEOMETRIE-PFAD: SDF wie gehabt ---
			vec3 rel = world_pos - volume_pos[i];
			vec3 local = vec3(
				dot(rel, volume_axis_x[i]),
				dot(rel, volume_axis_y[i]),
				dot(rel, volume_axis_z[i])
			);
			float d = box_sdf(local, volume_extents[i]);
			float noisy_d = d + (n - 0.5) * noise_strength * soft;
			a = 1.0 - smoothstep(-soft, 0.0, noisy_d);
		}

		dark = max(dark, a);
	}

	// Screen-Space-Dither gegen Banding
	float dither = (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * (2.0 / 255.0);

	ALBEDO = darkness_color.rgb;
	ALPHA = clamp(dark * max_opacity + dither * step(0.001, dark) * step(dark, 0.999), 0.0, 1.0);
}