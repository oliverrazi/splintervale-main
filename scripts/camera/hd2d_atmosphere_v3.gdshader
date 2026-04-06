shader_type canvas_item;

// =============================================================================
// HD-2D ATMOSPHERE SHADER (ohne Blur)
// =============================================================================
// Vignette + Color Grading + Ambient Light in einem Pass.
// Kein Blur – das übernimmt WorldEnvironment.
//
// SETUP: CanvasLayer (Layer 100) → ColorRect (Full Rect) → Dieses Material
// =============================================================================

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

// === VIGNETTE ===
group_uniforms Vignette;
uniform bool vignette_enabled = true;
uniform float vignette_intensity : hint_range(0.0, 1.5) = 0.4;
uniform float vignette_size : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.45;
uniform vec4 vignette_color : source_color = vec4(0.05, 0.02, 0.01, 1.0);

// === COLOR GRADING ===
group_uniforms ColorGrading;
uniform bool grading_enabled = true;
uniform float warmth : hint_range(-0.5, 0.5) = 0.08;
uniform float contrast : hint_range(0.5, 1.5) = 1.05;
uniform float saturation : hint_range(0.0, 2.0) = 1.1;
uniform float brightness : hint_range(-0.5, 0.5) = 0.0;

// === AMBIENT LIGHT ===
group_uniforms AmbientLight;
uniform bool ambient_enabled = true;
uniform vec4 ambient_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float ambient_strength : hint_range(0.0, 0.5) = 0.05;

void fragment() {
	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	// === COLOR GRADING ===
	if (grading_enabled) {
		color += brightness;
		color = (color - 0.5) * contrast + 0.5;
		color.r += warmth * 0.5;
		color.b -= warmth * 0.3;
		float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color = mix(vec3(grey), color, saturation);
	}

	// === AMBIENT LIGHT ===
	if (ambient_enabled) {
		color = mix(color, color * ambient_color.rgb, ambient_strength);
	}

	// === VIGNETTE ===
	if (vignette_enabled) {
		vec2 vig_uv = SCREEN_UV - 0.5;
		vig_uv.x *= 1.2;
		float dist = length(vig_uv);
		float vig = smoothstep(vignette_size, vignette_size + vignette_softness, dist);
		vig *= vignette_intensity;
		color = mix(color, vignette_color.rgb, vig);
	}

	COLOR.rgb = clamp(color, 0.0, 1.0);
	COLOR.a = 1.0;
}
