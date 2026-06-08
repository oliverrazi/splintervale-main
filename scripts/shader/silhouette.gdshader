shader_type canvas_item;

// =============================================================
//  Silhouetten-Shader (2D / canvas_item)
//
//  - Erhält die Form über den Alphakanal des Sprites
//  - "darkness" zieht die Figur Richtung silhouette_color
//  - Optionaler Rim-Light über Kantenerkennung am Alpha:
//    setzt die Figur subtil vom dunklen Hintergrund ab
//    (rim_strength = 0 -> reine, harte Silhouette wie gewünscht)
//
//  Auf das Sprite/AnimatedSprite2D des Player-Rigs legen.
// =============================================================

uniform vec4  silhouette_color : source_color = vec4(0.02, 0.02, 0.035, 1.0);
uniform float darkness     : hint_range(0.0, 1.0) = 0.97;

uniform vec4  rim_color    : source_color = vec4(0.45, 0.55, 0.85, 1.0);
uniform float rim_strength : hint_range(0.0, 3.0) = 0.0;
uniform float rim_width    : hint_range(0.0, 8.0) = 1.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Grundfarbe: Originalfarbe -> Silhouettenfarbe verdunkeln.
	vec3 base = mix(tex.rgb, silhouette_color.rgb, darkness);

	// Kantenerkennung auf dem Alphakanal -> dünner Rand innen.
	vec2 px = TEXTURE_PIXEL_SIZE * rim_width;
	float a = tex.a;
	float a_max = a;
	a_max = max(a_max, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a_max = max(a_max, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	a_max = max(a_max, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a_max = max(a_max, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	float edge = clamp(a_max - a, 0.0, 1.0);

	vec3 col = base + rim_color.rgb * edge * rim_strength;

	COLOR = vec4(col, tex.a);
}
