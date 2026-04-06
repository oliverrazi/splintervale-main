shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, depth_prepass_alpha;


// =============================================================================
// SMOOTH PIXEL ART SHADER v4
// - Korrektes Billboard (nur MODELVIEW_MATRIX, kein VERTEX)
// - Modulate-Unterstützung (Farbe + Alpha)
// - Smooth Pixel Filtering
// - Spritesheet Bleed-Schutz
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

	
	EMISSION = color.rgb * 0.3; // 30% Eigenleuchten
	ALBEDO = color.rgb;
}
