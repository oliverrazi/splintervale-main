// Foreground Rock Shader — Used for rocks that render OVER the player.
//
// These rocks are darkened silhouettes at screen edges, creating the
// "looking through a cave opening" effect. Key features:
//
//   • Very dark tint (near-silhouette)
//   • Subtle edge detail visibility (not completely flat black)
//   • Player-proximity alpha fade (controlled from script)
//   • Slight rim highlight from the cave spotlight
//   • Optional depth-based gradient (closer to camera = darker)
//
// Apply to: MeshInstance3D or Sprite3D foreground rock pieces.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

group_uniforms appearance;
uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform vec3 tint : source_color = vec3(0.06, 0.055, 0.05);
uniform float brightness : hint_range(0.0, 0.5) = 0.08;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms detail;
uniform sampler2D texture_detail : source_color, filter_nearest, repeat_enable;
uniform float detail_scale : hint_range(0.1, 10.0) = 3.0;
uniform float detail_visibility : hint_range(0.0, 0.3) = 0.05;

group_uniforms rim;
uniform bool enable_rim = true;
uniform vec3 rim_color : source_color = vec3(0.15, 0.13, 0.11);
uniform float rim_power : hint_range(1.0, 8.0) = 4.0;
uniform float rim_intensity : hint_range(0.0, 0.5) = 0.1;

group_uniforms edge;
// Edge fade — bottom of foreground rocks can be slightly transparent
uniform float bottom_fade : hint_range(0.0, 1.0) = 0.3;
uniform float bottom_fade_range : hint_range(0.0, 1.0) = 0.4;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Base color — very dark
	vec4 tex = texture(texture_albedo, UV);
	vec3 color = tex.rgb * tint * brightness;

	// Subtle detail so it's not flat black
	vec3 detail = texture(texture_detail, UV * detail_scale).rgb;
	color += detail * detail_visibility;

	// Rim highlight — catches light from the cave's main spotlight
	if (enable_rim) {
		vec3 wnorm = normalize(world_normal);
		float rim = 1.0 - max(dot(wnorm, VIEW), 0.0);
		rim = pow(rim, rim_power);
		color += rim_color * rim * rim_intensity;
	}

	// Alpha
	float alpha = tex.a * opacity;

	// Bottom edge fade (rocks at bottom of screen fade slightly)
	float bottom = smoothstep(0.0, bottom_fade_range, UV.y);
	alpha *= mix(1.0 - bottom_fade, 1.0, bottom);

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ALPHA = alpha;
}
