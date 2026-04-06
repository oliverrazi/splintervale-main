// HD-2D Vignette + Color Grading Post-Process Shader
// Apply this to a ColorRect or TextureRect that covers the full screen
// Set the material to a ShaderMaterial with this shader
// Make sure the node is in a CanvasLayer with layer >= 100

shader_type canvas_item;

// Screen texture — required for post-processing in Godot 4
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// --- Vignette ---
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform vec3 vignette_color : source_color = vec3(0.02, 0.02, 0.05);

// --- Color Grading ---
uniform float warmth : hint_range(-0.5, 0.5) = 0.08;
uniform float shadow_coolness : hint_range(0.0, 0.5) = 0.12;
uniform float highlight_warmth : hint_range(0.0, 0.5) = 0.1;

// --- Film Grain (subtle) ---
uniform float grain_intensity : hint_range(0.0, 0.1) = 0.02;
uniform float grain_speed : hint_range(0.0, 10.0) = 3.0;


float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	
	// --- Vignette ---
	vec2 center_uv = SCREEN_UV - 0.5;
	float dist = length(center_uv);
	float vignette = smoothstep(vignette_softness, vignette_softness + 0.5, dist);
	col = mix(col, vignette_color, vignette * vignette_intensity);
	
	// --- Shadow / Highlight Color Split ---
	float luminance = dot(col, vec3(0.299, 0.587, 0.114));
	
	// Cool shadows (add blue to dark areas)
	vec3 shadow_tint = vec3(-shadow_coolness * 0.5, -shadow_coolness * 0.3, shadow_coolness);
	col += shadow_tint * (1.0 - luminance) * (1.0 - luminance);
	
	// Warm highlights (add gold to bright areas)
	vec3 highlight_tint = vec3(highlight_warmth, highlight_warmth * 0.7, -highlight_warmth * 0.3);
	col += highlight_tint * luminance * luminance;
	
	// Overall warmth shift
	col.r += warmth * 0.5;
	col.g += warmth * 0.25;
	col.b -= warmth * 0.3;
	
	// --- Film Grain ---
	if (grain_intensity > 0.0) {
		float grain = random(SCREEN_UV + fract(TIME * grain_speed)) * 2.0 - 1.0;
		col += grain * grain_intensity;
	}
	
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
