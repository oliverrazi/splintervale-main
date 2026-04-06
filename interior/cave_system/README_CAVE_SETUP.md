# Cave System — Setup Guide

## Overview

A professional cave system for 2.5D top-down RPGs in Godot 4.5.
Designed for pixel-art games with 3D depth, inspired by the HD-2D aesthetic.

**What's included:**

| File | Purpose |
|------|---------|
| `global_cave_data.gd` | Autoload — scene transition & persistence state |
| `cave_entrance.gd` | Overworld entrance trigger with visual effects |
| `cave_system.gd` | Main cave scene controller |
| `shaders/cave_floor.gdshader` | Stone floor with wetness, AO, variation |
| `shaders/cave_water.gdshader` | Animated water with flow, caustics, foam |
| `shaders/cave_wall_fade.gdshader` | Wall-to-void edge transition |
| `shaders/cave_stalactite.gdshader` | Overhead ceiling decorations |
| `shaders/cave_caustics.gdshader` | Water light projection on surfaces |
| `components/cave_atmosphere.gd` | Dust, drips, mist, firefly particles |
| `components/cave_lighting_manager.gd` | Dynamic light system with proximity culling |
| `components/cave_stream.gd` | Self-contained water stream component |
| `components/cave_crystal.gd` | Glowing crystal with interaction support |
| `components/cave_stalactite.gd` | Overhead stalactite with drip effects |
| `components/cave_exit.gd` | Exit trigger back to overworld |

---

## Step 1: Project Setup

### 1.1 — Register the Autoload

Go to **Project → Project Settings → Autoload** and add:

```
Path: res://scripts/cave/global_cave_data.gd
Name: GlobalCaveData
```

### 1.2 — File Placement

Copy the files into your project. Recommended structure:

```
res://
├── scripts/cave/
│   ├── global_cave_data.gd
│   ├── cave_entrance.gd
│   ├── cave_system.gd
│   └── components/
│       ├── cave_atmosphere.gd
│       ├── cave_lighting_manager.gd
│       ├── cave_stream.gd
│       ├── cave_crystal.gd
│       ├── cave_stalactite.gd
│       └── cave_exit.gd
├── shaders/cave/
│   ├── cave_floor.gdshader
│   ├── cave_water.gdshader
│   ├── cave_wall_fade.gdshader
│   ├── cave_stalactite.gdshader
│   └── cave_caustics.gdshader
└── scenes/caves/
    └── cave_01.tscn          ← Your first cave scene
```

### 1.3 — Player Requirements

Your player scene needs:
- To be in the **`player` group** (`Node → Groups → add "player"`)
- A **`set_input_enabled(enabled: bool)`** method (for transition lockout)
- **Collision layer 2** (or adjust the `collision_mask` in entrance/exit scripts)

### 1.4 — Audio Bus Setup (Optional but Recommended)

Go to the **Audio** tab at the bottom of the Godot editor:

1. Click "Add Bus" → rename to **"CaveReverb"**
2. Add Effect → **Reverb**
3. Configure: Pre-delay 20ms, Room Size 0.75, Damping 0.4, Spread 0.8
4. Route CaveReverb output to Master

---

## Step 2: Building the Overworld Entrance

### 2.1 — Sculpt the Terrain

In your overworld scene with Terrain3D:
1. Use the sculpt tool to create a **shallow depression** where the cave mouth is
2. Paint the area with a dark rock/dirt texture
3. The depression doesn't need to be deep — it's mostly visual

### 2.2 — Add the Entrance Node

1. Add a **Node3D** to your overworld scene
2. Attach `cave_entrance.gd`
3. Position it at the depression
4. Configure in Inspector:
   - `cave_scene_path`: `res://scenes/caves/cave_01.tscn`
   - `cave_spawn_id`: `"entrance_main"` (must match a Marker3D name in the cave)
   - `trigger_radius`: 1.5 (adjust to your scale)
   - `require_interaction`: true (recommended — prevents accidental entry)
   - `fade_duration`: 0.8
   - `atmosphere_intensity`: 0.6

The script auto-generates placeholder visuals (dark circle + rocks). Replace
these with your pixel-art entrance sprites for the final look.

---

## Step 3: Building the Cave Scene

### 3.1 — Create the Scene

Create `cave_01.tscn` with this exact tree structure:

```
CaveSystem (Node3D) — attach cave_system.gd
├── WorldEnvironment
├── DirectionalLight3D (optional, very dim)
│
├── CaveFloor (Node3D)
│   ├── Floor_Main (MeshInstance3D — PlaneMesh)
│   ├── Floor_SideRoom (MeshInstance3D — PlaneMesh)
│   └── Floor_Corridor (MeshInstance3D — PlaneMesh)
│
├── CaveWalls (Node3D)
│   ├── Wall_North (MeshInstance3D)
│   ├── Wall_East (MeshInstance3D)
│   └── ... (more wall segments)
│
├── CaveWater (Node3D)
│   └── Stream_01 (Node3D) — attach cave_stream.gd
│
├── CaveDecorations (Node3D)
│   ├── Stalactite_01 (Node3D) — attach cave_stalactite.gd
│   ├── Stalactite_02 (Node3D)
│   ├── Crystal_01 (Node3D) — attach cave_crystal.gd
│   ├── Crystal_02 (Node3D)
│   └── ... (moss sprites, stalagmites, rubble, etc.)
│
├── CaveAtmosphere (Node3D) — attach cave_atmosphere.gd
│
├── CaveLighting (Node3D) — attach cave_lighting_manager.gd
│   ├── Torch_01 (OmniLight3D) — named with "torch" for auto-detect
│   ├── Crystal_Light_01 (OmniLight3D) — named with "crystal"
│   └── ...
│
├── UnreachableAreas (Node3D)
│   ├── DistantCavern (MeshInstance3D — visible scenery, no collision)
│   └── HiddenStream (Node3D) — a CaveStream far away for ambience
│
├── SpawnPoints (Node3D)
│   ├── entrance_main (Marker3D) — where player appears from overworld
│   └── entrance_secret (Marker3D) — alternative entrance
│
├── Navigation (NavigationRegion3D)
│   └── (bake your navmesh here)
│
├── Collision (StaticBody3D)
│   ├── CollisionShape3D (cave boundary walls)
│   └── ... (more shapes defining walkable boundaries)
│
├── CaveExits (Node3D)
│   └── Exit_Main (Area3D) — attach cave_exit.gd
│       └── CollisionShape3D
│
└── Enemies (Node3D) — your enemy spawns
```

### 3.2 — CaveSystem Configuration

Select the root CaveSystem node and configure:
- `cave_id`: `"cave_01"` (unique per cave, used for persistence)
- `fade_in_duration`: 1.0
- `ambient_color`: `Color(0.06, 0.065, 0.08)` (cool dark blue-gray)
- `ambient_energy`: 0.15 (very dim — lights do the work)
- `enable_reverb`: true
- `reverb_bus`: `"CaveReverb"`

### 3.3 — Floor Setup

For each floor section:
1. Create a **MeshInstance3D** with a **PlaneMesh**
2. Size the plane to match your room/corridor shape
3. Rotate the plane: `rotation.x = 0` (PlaneMesh is already horizontal)
4. Create a **ShaderMaterial**, assign `cave_floor.gdshader`
5. Configure shader parameters:
   - `texture_albedo`: Your pixel art stone texture (set Import → Filter: Nearest)
   - `texture_detail`: A noise/detail texture for tiling breakup
   - `texture_normal`: Normal map (optional but adds depth)
   - `uv_scale`: 4.0–8.0 depending on texture resolution
   - `base_tint`: Adjust to desired stone color
   - `wetness_strength`: 0.0 for dry areas, 0.5–1.0 near water
   - `edge_darkness`: 0.6 (darkens edges via vertex color alpha)

**Vertex Color Painting for Edge Darkening:**
- In Blender or a mesh editor, paint vertex color **alpha** channel:
  - Alpha = 1.0 in the center of rooms
  - Alpha = 0.0 at edges near walls/void
- This creates a natural ambient occlusion effect

**Alternative for quick setup:** Skip vertex painting and rely on the
`texture_ao` parameter with a hand-painted mask texture.

### 3.4 — Wall Setup

Cave walls define the boundary between walkable floor and black void.
For a 2.5D top-down game, walls are typically:

**Option A — Sprite3D Edges (Recommended for Pixel Art)**
1. Create Sprite3D nodes with your pixel art rock-face textures
2. Position at the cave boundary
3. Apply `cave_wall_fade.gdshader` as material override
4. Configure `fade_start` / `fade_end` to control the rock-to-void gradient

**Option B — Mesh Walls**
1. Create low-poly mesh strips that follow the cave boundary
2. Apply `cave_wall_fade.gdshader`
3. Paint vertex color RED channel: 1.0 = visible wall, 0.0 = fades to void
4. Set `use_vertex_color_fade = true` in shader

**Option C — Simple Approach**
For quick prototyping, just leave the floor edges as-is. The black
WorldEnvironment background automatically creates the void. Add Sprite3D
rock decorations at the edges later.

### 3.5 — Water / Streams

1. Add a **Node3D** to CaveWater
2. Attach `cave_stream.gd`
3. Configure:
   - `stream_width` / `stream_length`: Match your desired water area
   - `water_shader`: Assign `cave_water.gdshader`
   - `caustics_shader`: Assign `cave_caustics.gdshader`
   - `flow_direction`: `(0, 1)` for Z-direction flow, `(1, 0)` for X
   - `flow_speed`: 0.3 for calm stream, 0.6+ for rushing water
   - `enable_audio`: true (assign a looping water AudioStream)
4. Position the stream node where you want water

**For puddles:** Set `flow_speed = 0`, use a smaller plane.

**For rivers:** Chain multiple CaveStream components along a path.

### 3.6 — Decorations

**Stalactites:**
1. Add Node3D under CaveDecorations
2. Attach `cave_stalactite.gd`
3. Assign your pixel art stalactite texture
4. Configure `height`: 3.0+ (above player Y so it renders on top)
5. `drip_enabled`: true for occasional water drip particles
6. `cast_shadow`: true for a floor shadow silhouette

**Crystals:**
1. Add Node3D under CaveDecorations
2. Attach `cave_crystal.gd`
3. Assign your pixel art crystal texture
4. Choose `crystal_color` (blue, green, purple, etc.)
5. `interactable`: true if the player can collect/break them
6. `cave_object_id`: unique ID for persistence (e.g., `"crystal_01"`)

**Other decorations (moss, stalagmites, rubble, mushrooms):**
- Use regular Sprite3D with your pixel art textures
- Position at appropriate heights
- For mushrooms with glow, add an OmniLight3D as child
- For moss on walls, layer sprites over wall geometry

### 3.7 — Lighting

The CaveLightingManager handles animated lights. You can either:

**Pre-place lights in the editor:**
1. Add OmniLight3D nodes as children of CaveLighting
2. Name them with keywords for auto-detection:
   - `Torch_01`, `Torch_Entrance` → torch flicker animation
   - `CrystalLight_01` → crystal pulse animation
   - `Glow_Mushroom` → generic pulse animation
3. The manager auto-registers and animates them

**Create lights via code:**
```gdscript
@onready var lighting: CaveLightingManager = $CaveLighting

func _ready():
    lighting.add_torch(Vector3(5, 1, 3))
    lighting.add_crystal_light(Vector3(-2, 0.5, 8), Color(0.5, 1.0, 0.3))
    lighting.add_pulse_light(Vector3(10, 0.3, 5), Color(0.8, 0.3, 1.0), 0.3, 2.5)
```

**Performance:** The manager automatically disables lights too far from the
player. Adjust `max_active_lights` and `activation_radius` as needed.

### 3.8 — Collision & Navigation

**Collision (walls the player can't walk through):**
1. Select the Collision StaticBody3D
2. Add CollisionShape3D children with shapes matching your cave walls
3. For complex cave shapes, use ConvexPolygonShape3D or multiple boxes
4. Alternatively, use CollisionPolygon3D for a 2D polygon extruded in Y

**Navigation (pathfinding for enemies):**
1. Select the NavigationRegion3D
2. Add a NavigationMesh resource
3. Configure the navmesh:
   - Agent Radius: match your enemy size
   - Agent Height: 2.0
   - Cell Size: 0.1–0.25
4. Bake the navmesh (it will automatically avoid collision shapes)

### 3.9 — Exit Placement

1. Create an Area3D under CaveExits
2. Attach `cave_exit.gd`
3. Add a CollisionShape3D as child (BoxShape or Sphere for trigger zone)
4. Position at the cave mouth / exit location
5. Configure:
   - `require_interaction`: true (recommended)
   - `override_return_scene`: Leave empty to use the stored return path
6. Add a visual indicator (glowing sprite, light, arrow) so players see the exit

---

## Step 4: Texture Preparation

### Required Textures (Prepare These)

| Texture | Size Suggestion | Description |
|---------|----------------|-------------|
| `stone_floor.png` | 32×32 or 64×64 | Tiling stone floor, pixel art |
| `stone_detail.png` | 32×32 | Subtle crack/noise overlay |
| `stone_normal.png` | 32×32 | Normal map for stone depth |
| `wall_rock.png` | 32×64 or 64×64 | Rock face texture for walls |
| `water_surface.png` | 32×32 | Water surface pattern, tiling |
| `water_caustics.png` | 32×32 | Light refraction pattern |
| `water_foam.png` | 16×16 | Shore foam pattern |
| `stalactite_01.png` | 16×48 or similar | Stalactite sprite (transparent bg) |
| `crystal_blue.png` | 16×32 | Crystal sprite (transparent bg) |
| `crystal_green.png` | 16×32 | Color variant |

### Import Settings for ALL Pixel Art

For every texture, set in the **Import** tab:
- **Filter**: `Nearest` (no filtering — keeps pixels sharp)
- **Mipmaps**: Off
- **Repeat**: Enabled (for tiling textures)

---

## Step 5: Polish & AAA Quality Touches

### 5.1 — Unreachable Areas (Background Scenery)

Create visible-but-unreachable areas beyond chasms:
1. Add floor planes on the far side of gaps
2. Use dimmer lighting / no lighting for a "distant" feel
3. Add a CaveStream far away — the audio creates spatial depth
4. Scatter crystal sprites with faint glow
5. **No collision** on these — they're pure scenery

### 5.2 — Camera Adjustments

For cave interiors, consider:
- Slightly tighter zoom than overworld
- Slower camera follow speed for claustrophobic feel
- Optional subtle camera shake near waterfalls
- Vignette post-processing (enable in Environment)

### 5.3 — Audio Layering

Layer these ambient sounds for rich cave atmosphere:
1. **Cave ambience base** — low rumble/drone (AudioStreamPlayer, always playing)
2. **Water drips** — randomized 3D positioned (AudioStreamPlayer3D)
3. **Wind** — subtle, panning (AudioStreamPlayer3D near entrances)
4. **Streams** — spatial 3D audio from CaveStream components
5. **Creature sounds** — distant skittering, bat chirps (3D, random intervals)

All audio should route to the CaveReverb bus for echo.

### 5.4 — Bioluminescence (Optional)

For magical caves, enable `fireflies_enabled` on CaveAtmosphere:
- Set `firefly_color` to match your cave theme (green, blue, purple)
- Add pulse lights for bioluminescent mushrooms
- Combine with crystal glow for a magical atmosphere

### 5.5 — Performance Checklist

- [ ] CaveLightingManager `max_active_lights` ≤ 12
- [ ] Shadow-casting lights ≤ 2–3 total
- [ ] Particles use `fixed_fps` (30 for detail, 20 for ambient)
- [ ] SSAO disabled on low-end (toggle in quality settings)
- [ ] Glow kept to 3 levels max
- [ ] Navmesh baked (not real-time)
- [ ] Distant decoration LOD (reduce particle count when far from player)

---

## Quick Start Checklist

1. [ ] Register GlobalCaveData as Autoload
2. [ ] Place CaveEntrance on overworld, configure cave_scene_path
3. [ ] Create cave_01.tscn with CaveSystem root
4. [ ] Add at least one SpawnPoint (Marker3D named matching entrance's spawn_id)
5. [ ] Add floor planes with cave_floor.gdshader
6. [ ] Add collision boundaries
7. [ ] Add CaveAtmosphere for particles
8. [ ] Add CaveLighting with at least one light
9. [ ] Add at least one CaveExit
10. [ ] Test: Run game, walk into entrance, verify cave loads and exit works

---

## Troubleshooting

**Player doesn't appear in cave:**
→ Check player is in "player" group. Check SpawnPoint name matches `cave_spawn_id`.

**Cave is completely dark:**
→ WorldEnvironment might be overriding your lights. Check `ambient_energy` > 0.
Add at least one OmniLight3D.

**Transition doesn't work:**
→ Verify GlobalCaveData is registered as Autoload. Check `cave_scene_path` is correct.

**Textures look blurry:**
→ Set Import → Filter: Nearest on all textures. In shader, `filter_nearest` is set.

**Performance issues:**
→ Reduce `max_active_lights`, disable SSAO, reduce particle counts, disable shadows.
