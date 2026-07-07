shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, depth_prepass_alpha;


// =============================================================================
// SMOOTH PIXEL ART SHADER v5
// - Korrektes Billboard (nur MODELVIEW_MATRIX, kein VERTEX)
// - Modulate-Unterstützung (Farbe + Alpha)
// - Smooth Pixel Filtering
// - Spritesheet Bleed-Schutz
// - NEU: HD-2D Beleuchtung (Normal-Up-Blend, damit Licht von oben wirkt)
// - NEU: self_illumination als Uniform (vorher hartkodiert 0.3)
// - NEU: Specular deaktiviert (verhindert Glanz-Blowout bei nahen Lichtern)
// =============================================================================

uniform sampler2D sprite_texture : source_color, filter_linear_mipmap;

// --- Spritesheet ---
uniform vec2 frame_coords = vec2(0.0, 0.0);
uniform vec2 frame_size = vec2(1.0, 1.0);
uniform bool flip_h = false;

// --- Modulate (Ersatz für Sprite3D.modulate) ---
uniform vec4 modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// --- Billboard ---
// 0 = Full Billboard (Sprite schaut komplett zur Kamera)
// 1 = Y-Billboard (dreht nur um Y-Achse)
// 2 = Y-Billboard + Neigung (HD-2D)
// 3 = Kein Billboard
uniform int billboard_mode : hint_range(0, 3) = 0;
uniform float tilt_amount : hint_range(0.0, 0.5) = 0.15;

// --- Smooth Pixel Filtering ---
uniform float aa_sharpness : hint_range(0.3, 3.0) = 1.2;
uniform int filter_mode : hint_range(0, 2) = 0;

// --- Spritesheet Bleed-Schutz ---
uniform float frame_bleed_guard : hint_range(0.0, 1.0) = 0.5;

uniform float depth_bias : hint_range(0.0, 0.1) = 0.0;

// --- Beleuchtung (HD-2D) ---
// Billboard-Normalen zeigen zur Kamera -> Licht von oben trifft das Quad nur
// streifend (N·L ~ 0) und hat quasi keine Wirkung. normal_up_blend biegt die
// Normale teilweise Richtung Welt-Oben, damit der Sprite wie eine stehende
// Figur beleuchtet wird (Octopath-Technik).
// 0.0 = nur Frontal-Licht wirkt | 1.0 = nur Licht von oben wirkt
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.6;

// Lichtunabhängiges Eigenleuchten. Hoch = Sprite ignoriert Beleuchtung,
// niedrig = Lichter haben volle Kontrolle. Für HD-2D-Lighting eher 0.1-0.2.
uniform float self_illumination : hint_range(0.0, 1.0) = 0.15;

void vertex() {
	// Scale aus dem Transform erhalten (z.B. 1.5)
	float scale_x = length(MODEL_MATRIX[0].xyz);
	float scale_y = length(MODEL_MATRIX[1].xyz);
	float scale_z = length(MODEL_MATRIX[2].xyz);


	if (billboard_mode == 0) {
		// ==========================================================
		// FULL BILLBOARD (mit erhaltener Scale)
		// ==========================================================
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * scale_x,
			INV_VIEW_MATRIX[1] * scale_y,
			INV_VIEW_MATRIX[2] * scale_z,
			MODEL_MATRIX[3]
		);

	} else if (billboard_mode == 1) {
		// ==========================================================
		// Y-BILLBOARD (mit erhaltener Scale)
		// ==========================================================
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 forward = normalize(cross(right, up));

		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right * scale_x, 0.0),
			vec4(up * scale_y, 0.0),
			vec4(forward * scale_z, 0.0),
			MODEL_MATRIX[3]
		);

	} else if (billboard_mode == 2) {
		// ==========================================================
		// Y-BILLBOARD + NEIGUNG (HD-2D, mit erhaltener Scale)
		// ==========================================================
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 forward = normalize(cross(right, up));

		up = normalize(mix(up, forward, tilt_amount));

		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right * scale_x, 0.0),
			vec4(up * scale_y, 0.0),
			vec4(forward * scale_z, 0.0),
			MODEL_MATRIX[3]
		);
	}
	// billboard_mode == 3: nichts tun, Transform wird normal angewendet
	if (depth_bias > 0.0) {
		vec4 view_vertex = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		view_vertex.z += depth_bias;
		VERTEX = view_vertex.xyz;
		MODELVIEW_MATRIX = mat4(
			vec4(1.0, 0.0, 0.0, 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0)
		);
	}
}

// =============================================================================
// FILTER
// =============================================================================

vec2 uv_smoothstep_filter(vec2 uv, vec2 texture_res, float width) {
	vec2 pixels = uv * texture_res;
	vec2 pixels_floor = floor(pixels + 0.5);
	vec2 pixels_fract = fract(pixels + 0.5);
	vec2 aa_range = fwidth(pixels) * width * 0.5;
	pixels_fract = smoothstep(
		vec2(0.5) - aa_range,
		vec2(0.5) + aa_range,
		pixels_fract
	);
	return (pixels_floor + pixels_fract - 0.5) / texture_res;
}

vec2 uv_iq_filter(vec2 uv, vec2 texture_res, float width) {
	vec2 pixels = uv * texture_res;
	vec2 seam = floor(pixels + 0.5);
	vec2 dudv = fwidth(pixels) * width;
	pixels = seam + clamp((pixels - seam) / dudv, -0.5, 0.5);
	return pixels / texture_res;
}

vec4 texture_point_smooth(sampler2D smp, vec2 uv, vec2 pixel_size) {
	vec2 ddx_uv = dFdx(uv);
	vec2 ddy_uv = dFdy(uv);
	vec2 lxy = sqrt(ddx_uv * ddx_uv + ddy_uv * ddy_uv);
	vec2 uv_pixels = uv / pixel_size;
	vec2 uv_pixels_floor = round(uv_pixels) - vec2(0.5);
	vec2 uv_dxy_pixels = uv_pixels - uv_pixels_floor;
	uv_dxy_pixels = clamp(
		(uv_dxy_pixels - vec2(0.5)) * pixel_size / lxy + vec2(0.5),
		0.0, 1.0
	);
	vec2 final_uv = uv_pixels_floor * pixel_size;
	return textureGrad(smp, final_uv + uv_dxy_pixels * pixel_size, ddx_uv, ddy_uv);
}

void fragment() {
	vec2 uv = UV;
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	uv = uv * frame_size + frame_coords;

	// Bleed-Schutz
	vec2 tex_res = vec2(textureSize(sprite_texture, 0));
	vec2 half_texel = frame_bleed_guard / tex_res;
	vec2 frame_min = frame_coords + half_texel;
	vec2 frame_max = frame_coords + frame_size - half_texel;

	vec4 color;
	if (filter_mode == 0) {
		vec2 filtered_uv = uv_smoothstep_filter(uv, tex_res, aa_sharpness);
		filtered_uv = clamp(filtered_uv, frame_min, frame_max);
		color = texture(sprite_texture, filtered_uv);
	} else if (filter_mode == 1) {
		vec2 filtered_uv = uv_iq_filter(uv, tex_res, aa_sharpness);
		filtered_uv = clamp(filtered_uv, frame_min, frame_max);
		color = texture(sprite_texture, filtered_uv);
	} else {
		uv = clamp(uv, frame_min, frame_max);
		vec2 pixel_size = 1.0 / tex_res;
		color = texture_point_smooth(sprite_texture, uv, pixel_size);
	}

	if (color.a < 0.01) {
		discard;
	}

	// Modulate anwenden (wie Sprite3D.modulate)
	color *= modulate;

	// =========================================================================
	// HD-2D BELEUCHTUNG
	// =========================================================================

	// cull_disabled: Rückseiten-Normale zur Kamera drehen, sonst wird der
	// Sprite von hinten betrachtet komplett schwarz beleuchtet.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	// Normale teilweise Richtung Welt-Oben biegen (in View-Space), damit
	// Licht von oben (Key Light) den Sprite wie eine stehende Figur trifft.
	vec3 up_view = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	NORMAL = normalize(mix(NORMAL, up_view, normal_up_blend));

	// Kein Specular auf Pixel-Art: verhindert weiße Glanz-Schleier, wenn
	// Lichter nah am Billboard stehen.
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;

	EMISSION = color.rgb * self_illumination;
	ALBEDO = color.rgb;
}
