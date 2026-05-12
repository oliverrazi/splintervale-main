shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// === BASE ===
uniform vec4 BaseColor : source_color = vec4(1.0);
uniform sampler2D BaseTexture : filter_nearest, repeat_disable;

// === HIGHLIGHT ===
uniform vec4 HighlightColor : source_color = vec4(1.0);
uniform sampler2D HighlightTexture : filter_nearest, repeat_disable;

// === ANIMATION ===
uniform float progress : hint_range(-1.0, 1.0) = 0.0;

// === DISSOLVE ===
uniform sampler2D DissolveTexture : repeat_enable;
uniform float DissolveValue : hint_range(0.0, 1.0) = 0.0;

// === GLOW ===
uniform float GlowIntensity : hint_range(0.0, 7.0) = 2.0;
uniform vec4 GlowColor : source_color = vec4(1.0, 0.9, 0.6, 1.0);

// === DISTORTION ===
uniform float DistortionStrength : hint_range(0.0, 0.15) = 0.03;
uniform sampler2D DistortionTexture : hint_normal, repeat_enable;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // UV mit Progress-Offset (scrollt die Textur)
    vec2 uv_offset = vec2(UV.x - progress, UV.y);
    
    // === UV BOUNDS MASK ===
    // Verhindert dass edge-clamped Pixel außerhalb [0,1] U sichtbar werden.
    // Beim Halbkreis-Slash unsichtbar (Textur dort eh transparent), beim full-cone 
    // verhindert es, dass ungewollte Bereiche ausserhalb des aktiven Sweeps geometrie zeigen.
    float uv_mask = step(0.0, uv_offset.x) * step(uv_offset.x, 1.0);

    // === BASE TEXTURE ===
    vec4 base_tex = texture(BaseTexture, uv_offset);
    vec4 base_col = BaseColor * base_tex;

    // === HIGHLIGHT TEXTURE ===
    vec4 highlight_tex = texture(HighlightTexture, uv_offset);
    vec4 highlight_col = HighlightColor * highlight_tex;

    // Mix: Highlight überlagert Base basierend auf Highlight-Alpha
    vec4 final_color = mix(base_col, highlight_col, highlight_tex.a);

    // === ALPHA COMPOSITING ===
    float base_alpha = base_tex.a;
    float highlight_alpha = highlight_tex.a;
    float combined_alpha = base_alpha + (1.0 - base_alpha) * highlight_alpha;
    combined_alpha = clamp(combined_alpha, 0.0, 1.0);
    combined_alpha *= uv_mask;

    // === DISSOLVE ===
    float dissolve_noise = texture(DissolveTexture, UV).r;
    float dissolve_alpha = clamp(dissolve_noise - DissolveValue, 0.0, 1.0);
    float final_alpha = combined_alpha * dissolve_alpha;

    // === DISTORTION (Hintergrund verzerren) ===
    vec2 distort_sample = texture(DistortionTexture, uv_offset).rg * 2.0 - 1.0;
    float distort_mask = final_alpha * (1.0 - final_alpha) * 4.0; // Stärkste Verzerrung am Rand
    vec2 distorted_screen_uv = SCREEN_UV + distort_sample * DistortionStrength * distort_mask;
    vec4 screen_col = texture(SCREEN_TEXTURE, distorted_screen_uv);

    // Finale Farbe: Hintergrund + Slash drüber
    ALBEDO = mix(screen_col.rgb, final_color.rgb, final_alpha);

    // === GLOW / EMISSION ===
    // Glow basierend auf Helligkeit der finalen Farbe
    float luminance = dot(final_color.rgb, vec3(0.299, 0.587, 0.114));
    EMISSION = final_color.rgb * GlowColor.rgb * GlowIntensity * final_alpha * luminance;

    // Alpha für Transparenz
    ALPHA = max(final_alpha, distort_mask * 0.01); // Minimal-Alpha für Distortion
}
