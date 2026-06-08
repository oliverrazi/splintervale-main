// pixelate_3d.gdshader
// Pixelation shader für 3D-Meshes im HD-2D-Stil (Octopath / Adventures of Elliot)
// Quantisiert UVs auf ein konfigurierbares Pixel-Grid und nutzt nearest-neighbor sampling
// mit korrekten Mipmap-Derivaten gegen Snap-Grenz-Artefakte.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Textures ---
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform sampler2D orm_texture   : hint_default_white, filter_nearest_mipmap, repeat_enable;

uniform bool use_normal_map = false;
uniform bool use_orm_map    = false;

// --- Pixelation ---
// pixel_density = wie viele "Pixel" pro UV-Einheit aufgelöst werden.
// Bei einer 256x256-Textur entspricht 256 der nativen Auflösung, 64 ist deutlich gröber.
uniform vec2  pixel_density = vec2(64.0, 64.0);
uniform float uv_scale : hint_range(0.1, 32.0) = 1.0;

// --- PBR Defaults / Tint ---
uniform vec4  albedo_tint     : source_color           = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0)   = 0.9;
uniform float metallic_value  : hint_range(0.0, 1.0)   = 0.0;
uniform float specular_value  : hint_range(0.0, 1.0)   = 0.3;

// --- Color Quantization (optional, für "limitierte Palette"-Feel) ---
uniform bool quantize_colors = false;
uniform int  color_steps : hint_range(2, 64) = 16;

// --- Alpha (für Foliage, Zäune, Gitter etc.) ---
uniform bool  use_alpha_scissor = false;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // 1. UV skalieren und auf das Pixel-Grid snappen.
    //    +0.5 zentriert den Sample-Punkt im Pixel und ist stabiler an den Kanten.
    vec2 scaled_uv  = UV * uv_scale;
    vec2 snapped_uv = (floor(scaled_uv * pixel_density) + 0.5) / pixel_density;

    // 2. Mipmap-Derivate aus den NICHT-gesnappten UVs berechnen.
    //    Sonst sieht das LOD-Select Diskontinuitäten an jeder Snap-Grenze
    //    und du bekommst flickernde Mip-Sprünge in Bewegung.
    vec2 dx = dFdx(scaled_uv);
    vec2 dy = dFdy(scaled_uv);

    // 3. Albedo sampeln mit expliziten Derivaten.
    vec4 albedo_sample = textureGrad(albedo_texture, snapped_uv, dx, dy) * albedo_tint;

    // 4. Optionale Farb-Quantisierung pro Kanal.
    if (quantize_colors) {
        float steps = float(color_steps);
        albedo_sample.rgb = floor(albedo_sample.rgb * steps + 0.5) / steps;
    }

    ALBEDO = albedo_sample.rgb;
    ALPHA  = albedo_sample.a;

    if (use_alpha_scissor) {
        ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
    }

    // 5. Normal Map ebenfalls pixelated (sonst sieht die Beleuchtung "smooth"
    //    aus während die Textur grob ist - das beißt sich).
    if (use_normal_map) {
        NORMAL_MAP       = textureGrad(normal_texture, snapped_uv, dx, dy).rgb;
        NORMAL_MAP_DEPTH = 1.0;
    }

    // 6. ORM (Occlusion / Roughness / Metallic) oder Default-Werte.
    if (use_orm_map) {
        vec3 orm  = textureGrad(orm_texture, snapped_uv, dx, dy).rgb;
        AO        = orm.r;
        ROUGHNESS = orm.g;
        METALLIC  = orm.b;
        SPECULAR  = specular_value;
    } else {
        ROUGHNESS = roughness_value;
        METALLIC  = metallic_value;
        SPECULAR  = specular_value;
    }
}
