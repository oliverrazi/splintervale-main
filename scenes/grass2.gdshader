shader_type spatial;
render_mode cull_disabled;

uniform float size = 0.5;
uniform float blade_bend = 0.4;
uniform float size_small = 0.2;
uniform float size_large = 0.6;


uniform vec3 color = vec3(0.05, 0.2, 0.05);

uniform vec3 color_small: source_color = vec3(0.3, 0.6, 0.1);
uniform vec3 color_large: source_color = vec3(0.9, 0.9, 0.2);

uniform sampler2D patch_noise;
uniform float patch_scale = 5.0;
varying float patch_factor;

uniform sampler2D wind_noise;
uniform float wind_strength = 0.1;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_bend_strength = 1.0;
uniform float wind_ao_affect = 1.5;

uniform float object_radius = 1.0;
uniform vec3 object_position;

varying float bottom_to_top;
varying float current_wind_bend;
varying float cut_height;

uniform sampler2D path_mask : hint_default_white;
uniform vec2 mask_world_offset = vec2(0.0, 0.0);
uniform float mask_world_size = 100.0;
uniform float mask_edge_softness = 0.1;
uniform bool use_path_mask = false;

varying float mask_value;

void vertex() {
	if (use_path_mask) {
	    vec2 world_pos_2d = NODE_POSITION_WORLD.xz;
	    vec2 mask_uv = (world_pos_2d - mask_world_offset) / mask_world_size;

	    if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
	        mask_value = texture(path_mask, mask_uv).r;
	    } else {
	        mask_value = 1.0;
	    }

	    // Gras schrumpfen wo Maske dunkel ist
	    float visibility = smoothstep(0.0, mask_edge_softness + 0.01, mask_value);
	    if (visibility < 0.1) {
	        VERTEX.y *= visibility * 0.1;
	        VERTEX.xz *= visibility;
	    }
	} else {
	    mask_value = 1.0;
	}
	/*cut_height = 0.5;

	// Cutting all grass on the right
	if (NODE_POSITION_WORLD.x > 0.0) {
		cut_height = 0.5;

		VERTEX.y = min(VERTEX.y, cut_height);
		UV.y = max(UV.y, 1.0 - cut_height);
	}*/

	bottom_to_top = 1.0 - UV.y;

	// Wind logic
	vec2 wind_position = NODE_POSITION_WORLD.xz / 10.0;
	wind_position -= (TIME + 8.0) * wind_direction * wind_strength;

	current_wind_bend = texture(wind_noise, wind_position).x;

	current_wind_bend *= wind_strength;
	current_wind_bend *= bottom_to_top * 2.0;

	mat4 inv_model = inverse(MODEL_MATRIX);
	vec2 local_direction = (inv_model * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xz;

	VERTEX.xz += current_wind_bend * local_direction * wind_bend_strength;

	// Bend away from the object
	float object_distance = distance(object_position, NODE_POSITION_WORLD);
	float bend_away_strength = max(object_radius - object_distance, 0.0) / object_radius;
	vec2 bend_direction = normalize(object_position.xz - NODE_POSITION_WORLD.xz);

	VERTEX.xz -= (inv_model * vec4(bend_direction.x, 0.0, bend_direction.y, 0.0)).xz
			* bend_away_strength * bottom_to_top;
	VERTEX.y -= bend_away_strength * bottom_to_top * 0.5;

	// General appearance
	VERTEX.z += blade_bend * pow(bottom_to_top, 2.0);

	patch_factor = texture(patch_noise, NODE_POSITION_WORLD.xz / patch_scale).r;
	VERTEX *= mix(size_small, size_large, patch_factor);

	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), bottom_to_top);
}

void fragment() {
	if (use_path_mask && mask_value < 0.05) {
	    discard;
	}

	if (!FRONT_FACING) NORMAL = -NORMAL;
	AO = bottom_to_top;
	AO_LIGHT_AFFECT = 1.0;

	ALBEDO = mix(color_small, color_large, patch_factor);
	BACKLIGHT = vec3(0.2);

	ROUGHNESS = 0.4;

	SPECULAR = 0.2;
}