shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, depth_prepass_alpha;

// =============================================================================
// SMOOTH PIXEL ART SHADER v3 - BILLBOARD + ANTI-FLICKER
// =============================================================================
// Textur MUSS NICHT manuell auf Linear umgestellt werden!
// Der Shader erzwingt Linear-Filter über die Sampler-Deklaration.
// =============================================================================

// --- Textur (Shader erzwingt Linear – Import-Einstellung egal) ---
uniform sampler2D sprite_texture : source_color, filter_linear_mipmap;

// --- Spritesheet ---
uniform vec2 frame_coords = vec2(0.0, 0.0);
uniform vec2 frame_size = vec2(1.0, 1.0);
uniform bool flip_h = false;

// --- Billboard-Modus ---
// 0 = Full Billboard (Sprite schaut immer komplett zur Kamera)
// 1 = Y-Billboard (dreht nur um Y-Achse, steht senkrecht)
// 2 = Y-Billboard + Neigung (HD-2D Style, Sprite leicht nach hinten geneigt)
uniform int billboard_mode : hint_range(0, 2) = 0;

// Nur für Modus 2: Wie stark nach hinten neigen (0.0 - 0.5)
uniform float tilt_amount : hint_range(0.0, 0.5) = 0.15;

// --- Smooth Pixel Filtering ---
uniform float aa_sharpness : hint_range(0.3, 3.0) = 1.2;
// 0 = Smoothstep, 1 = IQ Linear, 2 = CptPotato/textureGrad
uniform int filter_mode : hint_range(0, 2) = 0;

// --- Spritesheet Bleed-Schutz ---
uniform float frame_bleed_guard : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	if (billboard_mode == 0) {
		// =====================================================
		// FULL BILLBOARD – Sprite zeigt immer zur Kamera
		// =====================================================
		// Nutzt die Kamera-Basis direkt. Das Sprite wird exakt
		// so ausgerichtet, wie die Kamera es sieht → keine
		// perspektivische Verzerrung, kein "plattes" Aussehen.

		// Kamera-Richtungsvektoren aus der inversen View-Matrix
		vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
		vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
		vec3 cam_forward = -INV_VIEW_MATRIX[2].xyz;

		// Vertex im Kamera-Raum positionieren
		vec3 local_pos = cam_right * VERTEX.x + cam_up * VERTEX.y;
		VERTEX = local_pos;

		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(cam_right, 0.0),
			vec4(cam_up, 0.0),
			vec4(-cam_forward, 0.0),
			vec4(world_pos, 1.0)
		);

	} else if (billboard_mode == 1) {
		// =====================================================
		// Y-BILLBOARD – Dreht nur um Y-Achse
		// =====================================================
		vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
		vec3 to_cam_flat = normalize(vec3(to_cam.x, 0.0, to_cam.z));

		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam_flat));
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 forward = to_cam_flat;

		vec3 local_pos = right * VERTEX.x + up * VERTEX.y;
		VERTEX = local_pos;

		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right, 0.0),
			vec4(up, 0.0),
			vec4(forward, 0.0),
			vec4(world_pos, 1.0)
		);

	} else {
		// =====================================================
		// Y-BILLBOARD + NEIGUNG (HD-2D Style)
		// =====================================================
		vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
		vec3 to_cam_flat = normalize(vec3(to_cam.x, 0.0, to_cam.z));

		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam_flat));
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 forward = to_cam_flat;

		// Sprite leicht nach hinten neigen
		up = normalize(mix(up, forward, tilt_amount));

		vec3 local_pos = right * VERTEX.x + up * VERTEX.y;
		VERTEX = local_pos;

		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(right, 0.0),
			vec4(up, 0.0),
			vec4(forward, 0.0),
			vec4(world_pos, 1.0)
		);
	}
}

// =============================================================================
// FILTER-ALGORITHMEN
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

	// Spritesheet Bleed-Schutz
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

	ALBEDO = color.rgb;
	ALPHA = color.a;
}
