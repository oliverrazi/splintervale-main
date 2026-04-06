# AAA Cave Enhancement Systems — Integration Guide

## Overview

These three systems elevate the base cave system to AAA quality,
matching the HD-2D reference aesthetic (dramatic depth, cinematic lighting,
foreground framing).

| System | File(s) | What It Does |
|--------|---------|-------------|
| **3D Rock Geometry** | `cave_rock_geometry.gd`, `cave_rock.gdshader` | Real 3D rock walls with overhangs, strata, depth |
| **Foreground Layer** | `cave_foreground.gd`, `cave_foreground.gdshader` | Rocks over the player for "inside the cave" feel |
| **Lighting Rig** | `cave_lighting_rig.gd` (includes inline vignette shader) | Dramatic spotlight, shadows, vignette, color grading |

---

## Updated Scene Tree

```
CaveSystem (Node3D) — cave_system.gd
├── WorldEnvironment
│
├── CaveLightingRig (Node3D) — cave_lighting_rig.gd ← NEW
│
├── CaveFloor (Node3D)
│   ├── Floor_MainRoom (MeshInstance3D + cave_floor.gdshader)
│   └── Floor_Corridor (MeshInstance3D + cave_floor.gdshader)
│
├── CaveRockGeometry (Node3D) — cave_rock_geometry.gd ← NEW
│   ├── [Auto-generated rocks, or pre-placed MeshInstance3D from Blender]
│   ├── Wall_North_Rocks (MeshInstance3D + cave_rock.gdshader)
│   ├── Overhang_East (MeshInstance3D)
│   └── Strata_South (MeshInstance3D)
│
├── CaveWater (Node3D)
│   └── Stream_01 (Node3D) — cave_stream.gd
│
├── CaveDecorations (Node3D)
│   ├── Stalactite_01 — cave_stalactite.gd
│   ├── Crystal_01 — cave_crystal.gd
│   └── ...
│
├── CaveAtmosphere (Node3D) — cave_atmosphere.gd
│
├── CaveLighting (Node3D) — cave_lighting_manager.gd
│   ├── Torch_01 (OmniLight3D)
│   └── CrystalLight_01 (OmniLight3D)
│
├── CaveForeground (Node3D) — cave_foreground.gd ← NEW
│   ├── FG_BottomLeft (MeshInstance3D or Sprite3D)
│   ├── FG_BottomRight (MeshInstance3D or Sprite3D)
│   └── FG_TopEdge (MeshInstance3D or Sprite3D)
│
├── UnreachableAreas (Node3D)
├── SpawnPoints (Node3D)
├── Navigation (NavigationRegion3D)
├── Collision (StaticBody3D)
├── CaveExits (Node3D)
└── Enemies (Node3D)
```

---

## System 1: 3D Rock Geometry

### Purpose
Replaces flat wall sprites with actual 3D rock meshes that have
overhangs, layered strata, and irregular surfaces — the #1 visual
difference between indie and AAA cave scenes.

### File Placement
```
res://scripts/cave/cave_rock_geometry.gd
res://shaders/cave/cave_rock.gdshader
```

### Setup

**Option A — Blender Meshes (Recommended for Final Quality)**

1. In Blender, model 5-10 rock variations:
   - Sizes from 0.5m to 2.5m
   - Organic, irregular shapes
   - Low-to-medium poly (200-800 faces per rock)
   - NO UV mapping needed — the shader uses triplanar mapping
2. Export as `.glb` (GLB Binary)
3. Import into Godot (Import settings: no compression, no animation)
4. In the CaveRockGeometry inspector, add them to `rock_meshes` array
5. Assign `cave_rock.gdshader` to `rock_shader`

**Option B — Procedural (For Prototyping)**

1. Add CaveRockGeometry to your cave scene
2. Set `use_procedural = true`
3. In a script, call the placement API:

```gdscript
@onready var rocks: CaveRockGeometry = $CaveRockGeometry

func _ready():
    # Wall segment from point A to point B
    rocks.place_wall_segment(
        Vector3(-5, 0, -3),   # Start
        Vector3(5, 0, -3),    # End
        2.5,                   # Depth (thickness)
        Vector2(-0.5, 3.0),   # Height range
        12                     # Density (number of rocks)
    )

    # Overhang leaning inward over the walkable area
    rocks.place_overhang(
        Vector3(-4, 0, -2),          # Base position
        Vector3(1, 0, 0.5),          # Lean direction (inward)
        6,                            # Rock count
        3.0,                          # Height
        1.8                           # How far they lean
    )

    # Ceiling stalactite cluster
    rocks.place_ceiling_rocks(
        Vector3(0, 0, 0),    # Center
        8,                     # Count
        3.0,                   # Spread
        5.0                    # Hang height
    )

    # Layered rock strata (horizontal bands)
    rocks.place_rock_strata(
        Vector3(6, 0, 0),             # Base
        Vector3(-1, 0, 0),            # Wall normal (facing left)
        4.0,                           # Width
        5,                             # Number of layers
        0.4                            # Layer height
    )
```

### Rock Shader Configuration

Select a rock MeshInstance3D and configure the shader:

| Parameter | Recommended Value | Notes |
|-----------|------------------|-------|
| `texture_albedo` | Your stone texture | Tiling, pixel art, filter_nearest |
| `texture_normal` | Stone normal map | Optional but adds huge depth |
| `texture_detail` | Noise/crack texture | Breaks up tiling at larger scale |
| `texture_moss` | Green moss texture | Applied on upward-facing surfaces |
| `triplanar_scale` | 2.0 - 4.0 | How the texture maps onto irregular shapes |
| `wall_tint` | (0.22, 0.20, 0.18) | Base brown-gray rock color |
| `brightness` | 0.4 - 0.5 | Keep dark for cave mood |
| `height_darkening` | 0.5 - 0.7 | Lower rocks are darker |
| `bottom_fade_start` | -0.3 | Where rock fades to void |
| `moss_amount` | 0.1 - 0.2 | Subtle moss patches |
| `wetness` | 0.2 - 0.4 | Near water sources, increase this |
| `enable_rim` | true | Edge highlight against dark background |

---

## System 2: Foreground Layer

### Purpose
Rocks at screen edges that render OVER the player, creating the
"looking through a gap" effect visible in the reference screenshot.

### File Placement
```
res://scripts/cave/cave_foreground.gd
res://shaders/cave/cave_foreground.gdshader
```

### Setup

1. Add a **Node3D** to your cave scene
2. Attach `cave_foreground.gd`
3. Configure in inspector:
   - `mode`: FIXED (for hand-placed rocks) or CAMERA_RELATIVE
   - `player_behind_alpha`: 0.3 (fade when player walks behind)
   - `fade_distance`: 3.0
   - `render_height`: 4.0 (must be above your player Y)
   - `foreground_darkening`: 0.7 (darker = more silhouette)

### Adding Foreground Rocks

**With textures (final quality):**
```gdscript
@onready var fg: CaveForeground = $CaveForeground

func _ready():
    # Sprite-based foreground (pixel art rock silhouettes)
    var rock_tex = preload("res://textures/cave/fg_rock_large.png")
    fg.add_foreground_sprite(rock_tex, Vector3(-6, 0, 5), 2.0, false)
    fg.add_foreground_sprite(rock_tex, Vector3(7, 0, 5), 2.0, true)  # Flipped

    # Frame all edges at once
    fg.add_foreground_frame({
        "bottom_left": preload("res://textures/cave/fg_bottom_left.png"),
        "bottom_right": preload("res://textures/cave/fg_bottom_right.png"),
    })
```

**Procedural (for prototyping):**
```gdscript
func _ready():
    # Auto-generate dark rock shapes around cave bounds
    var bounds = AABB(Vector3(-8, 0, -6), Vector3(16, 4, 12))
    fg.add_procedural_frame(bounds)
```

### Critical Design Rules

1. **Don't overdo it.** The reference shows rocks at 2-3 edges, not all around.
   Leave the "deep" side of the cave open for dramatic depth.
2. **Bottom-heavy.** More foreground at the bottom of the screen (closer to camera)
   creates the strongest sense of being underground.
3. **Asymmetric.** Left and right foreground should differ — same shapes on both
   sides looks artificial.
4. **The fade is essential.** Without player-proximity fade, foreground will block
   gameplay. Test that `player_behind_alpha` gives enough visibility.

---

## System 3: Dramatic Lighting Rig

### Purpose
The single biggest quality upgrade. One dramatic spotlight from above
with real shadows, combined with cinematic post-processing (vignette,
color grading, SSAO), transforms a flat cave into a moody environment.

### File Placement
```
res://scripts/cave/cave_lighting_rig.gd
```

### Setup

1. Add a **Node3D** to your cave scene (as child of CaveSystem)
2. Attach `cave_lighting_rig.gd`
3. Configure the spotlight:
   - `spotlight_position`: Where the "light well" is (above the main area)
   - `spotlight_energy`: 2.5 - 4.0 (higher = more dramatic)
   - `spotlight_angle`: 30° - 45° (narrow = focused beam, wide = ambient)
   - `spotlight_shadows`: true (this is expensive but essential for AAA)
   - `spotlight_color`: Warm for torchlit caves, cool-white for natural light
4. Configure post-processing:
   - `vignette_intensity`: 0.4 - 0.5
   - `saturation`: 0.7 - 0.8 (desaturated = moody)
   - `contrast`: 1.1 - 1.2 (lifted shadows, punchy look)
   - `color_temperature`: -0.15 (slightly cool for underground)

### Multiple Light Wells

For caves with several openings or interesting light sources:

```gdscript
@onready var rig: CaveLightingRig = $CaveLightingRig

# Move the spotlight when player enters a new room
func _on_room_entered(room_name: String):
    match room_name:
        "main_hall":
            rig.move_spotlight_to(Vector3(0, 8, 0), 2.0)
            rig.set_spotlight_intensity(3.0, 1.0)
        "crystal_grotto":
            rig.move_spotlight_to(Vector3(10, 6, 5), 2.0)
            rig.set_spotlight_intensity(1.5, 1.0)
            rig.set_vignette(0.6, 1.5)  # Darker, more intimate
        "boss_chamber":
            rig.dramatic_reveal(5.0, 3.0)  # Flash then settle
```

### Performance Notes

The lighting rig is the most performance-intensive system:

| Feature | Cost | Recommendation |
|---------|------|---------------|
| SpotLight3D shadows | High | Keep ONE shadow-casting spotlight |
| SSAO | Medium | Disable on low-end |
| SSIL | Medium | Disable on low-end |
| Glow (4 levels) | Low | Keep enabled |
| Vignette shader | Very Low | Always enabled |
| DoF | Medium | Optional, disable if FPS drops |
| Beam particles | Low | 30 particles, fine on all hardware |

**Quality settings presets:**
```gdscript
func set_quality_low():
    _spotlight.shadow_enabled = false
    _env.ssao_enabled = false
    _env.ssil_enabled = false
    _env.dof_blur_far_enabled = false
    _env.glow_enabled = true  # Keep this, it's cheap

func set_quality_high():
    _spotlight.shadow_enabled = true
    _env.ssao_enabled = true
    _env.ssil_enabled = true
```

---

## How They Work Together

The three systems layer on top of each other:

```
LAYER (back to front, bottom to top):

1. BLACK VOID (WorldEnvironment background_color = black)
2. UNREACHABLE AREAS (distant floor + faint lights)
3. CAVE FLOOR (cave_floor.gdshader — walkable ground)
4. CAVE WATER (cave_water.gdshader + caustics on floor)
5. 3D ROCK WALLS (cave_rock.gdshader — real geometry, overhangs)
6. PLAYER + ENEMIES (your game entities)
7. STALACTITES (overhead, rendered above player Y)
8. FOREGROUND ROCKS (cave_foreground.gd — screen-edge silhouettes)

LIGHTING:
→ CaveLightingRig provides the main spotlight + shadows + post-processing
→ CaveLightingManager handles individual torches/crystals
→ CaveAtmosphere adds particle ambience throughout

POST-PROCESSING (via CaveLightingRig):
→ Vignette (screen-space overlay, always on)
→ SSAO (depth in crevices)
→ Glow (bloom on bright light sources)
→ Color grading (saturation, contrast, temperature)
→ Optional DoF
```

---

## Texture Checklist (Updated)

All new textures to prepare, in addition to the base set:

| Texture | Size | Used By | Notes |
|---------|------|---------|-------|
| `rock_albedo.png` | 64×64 | cave_rock.gdshader | Tiling stone, good detail |
| `rock_normal.png` | 64×64 | cave_rock.gdshader | Normal map for rock depth |
| `rock_detail.png` | 32×32 | cave_rock.gdshader | Crack/variation overlay |
| `rock_moss.png` | 32×32 | cave_rock.gdshader | Green moss texture |
| `fg_rock_left.png` | 128×256+ | cave_foreground | Silhouette, transparent bg |
| `fg_rock_right.png` | 128×256+ | cave_foreground | Different from left |
| `fg_rock_top.png` | 256×64+ | cave_foreground | Optional ceiling edge |

Import settings: Filter = Nearest, Mipmaps = Off, Repeat = Enable (for tiling).

---

## Quick Start: Minimum Viable AAA Cave

If you want to get the AAA look with minimum effort, prioritize:

1. **CaveLightingRig** — single biggest visual impact, just add the node
2. **CaveForeground** — even with procedural rocks, instant depth
3. **CaveRockGeometry** — use procedural mode first, replace with Blender meshes later

```gdscript
# In your cave scene's _ready():
func _ready():
    # Quick rock walls (procedural)
    var rocks = $CaveRockGeometry
    rocks.place_wall_segment(Vector3(-6, 0, -4), Vector3(6, 0, -4), 3.0)
    rocks.place_wall_segment(Vector3(-6, 0, 4), Vector3(6, 0, 4), 3.0)
    rocks.place_overhang(Vector3(-5, 0, -3), Vector3(1, 0, 1), 5, 3.0)

    # Quick foreground
    var fg = $CaveForeground
    fg.add_procedural_frame(AABB(Vector3(-6, 0, -4), Vector3(12, 4, 8)))

    # Lighting rig handles itself via @export configuration
```

That's it — three nodes, a few lines of code, and your cave looks
dramatically different from before.
