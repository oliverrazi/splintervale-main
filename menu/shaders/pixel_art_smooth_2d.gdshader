shader_type canvas_item;

// =============================================================================
// SMOOTH PIXEL FILTER – 2D / UI Version
// =============================================================================
// Gleiche Technik wie die 3D-Version: Linear-Filter + UV-Manipulation
// für knackige Pixel mit glatten Kanten.
//
// SETUP:
// 1. TextureRect / Sprite2D / NinePatchRect → Material → New ShaderMaterial
// 2. Diesen Shader zuweisen
// 3. WICHTIG: Textur-Import auf "Linear" stellen (nicht Nearest!)
//    ODER: Textur per Uniform zuweisen (erzwingt Linear im Sampler)
//
// Funktioniert mit: TextureRect, Sprite2D, NinePatchRect, Button-Icons, etc.
// =============================================================================

// Wenn du die Textur per Uniform zuweist, wird Linear erzwungen.
// Bei normaler texture-Property des Nodes: Import auf Linear stellen!
uniform sampler2D sprite_texture : filter_linear, repeat_disable;
uniform bool use_node_texture = true; // true = Node-eigene Textur, false = sprite_texture

uniform int filter_mode : hint_range(0, 2) = 0;
// 0 = Smoothstep (weich, empfohlen)
// 1 = IQ Linear (schärfer)
// 2 = Floor + Fwidth (minimal)

uniform float aa_sharpness : hint_range(0.3, 3.0) = 1.2;

// Spritesheet-Support (optional, für animierte UI-Elemente)
uniform vec2 frame_coords = vec2(0.0, 0.0);
uniform vec2 frame_size = vec2(1.0, 1.0);
uniform bool use_spritesheet = false;
uniform float frame_bleed_guard : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// Textur-Auswahl
	vec2 uv = UV;
	vec4 tex_size_vec;

	if (use_spritesheet) {
		uv = frame_coords + uv * frame_size;
	}

	// Textur-Größe ermitteln
	vec2 tex_res;
	if (use_node_texture) {
		tex_res = vec2(textureSize(TEXTURE, 0));
	} else {
		tex_res = vec2(textureSize(sprite_texture, 0));
	}

	vec2 pixel_size = 1.0 / tex_res;

	// === SMOOTH PIXEL FILTERING ===
	// UV in Texel-Space umrechnen
	vec2 texel_uv = uv * tex_res;

	vec2 filtered_uv;

	if (filter_mode == 0) {
		// Smoothstep (t3ssel8r-Style)
		vec2 texel_floor = floor(texel_uv - 0.5) + 0.5;
		vec2 texel_fract = texel_uv - texel_floor;
		vec2 aa_range = fwidth(texel_uv) * aa_sharpness * 0.5;
		aa_range = max(aa_range, vec2(0.0001)); // Division by zero guard
		texel_fract = smoothstep(vec2(0.5) - aa_range, vec2(0.5) + aa_range, texel_fract);
		filtered_uv = (texel_floor + texel_fract) * pixel_size;

	} else if (filter_mode == 1) {
		// IQ Linear
		vec2 seam = floor(texel_uv + 0.5);
		vec2 dudv = fwidth(texel_uv) * aa_sharpness;
		dudv = max(dudv, vec2(0.0001));
		texel_uv = seam + clamp((texel_uv - seam) / dudv, -0.5, 0.5);
		filtered_uv = texel_uv * pixel_size;

	} else {
		// Floor + Fwidth (simplest)
		vec2 alpha = fwidth(texel_uv) * aa_sharpness;
		alpha = max(alpha, vec2(0.0001));
		vec2 fl = floor(texel_uv + 0.5);
		vec2 fr = fract(texel_uv + 0.5);
		vec2 aa = smoothstep(vec2(0.5) - alpha, vec2(0.5) + alpha, fr);
		filtered_uv = (fl + aa - 0.5) * pixel_size;
	}

	// Spritesheet Bleed Guard
	if (use_spritesheet && frame_bleed_guard > 0.0) {
		vec2 half_texel = frame_bleed_guard * pixel_size;
		vec2 fmin = frame_coords + half_texel;
		vec2 fmax = frame_coords + frame_size - half_texel;
		filtered_uv = clamp(filtered_uv, fmin, fmax);
	}

	// Samplen
	vec4 color;
	if (use_node_texture) {
		color = texture(TEXTURE, filtered_uv);
	} else {
		color = texture(sprite_texture, filtered_uv);
	}

	COLOR = color * COLOR; // Modulate-Kompatibilität
}
