# Thor

A Vulkan 1.3 game engine written in Odin, using SDL2 for windowing/input.
Currently at **Milestone 3 (first slice)**: imported `.glb` mesh rendering with a first cel-shaded + outline pass, skeletal animation playback in the sample viewer, full graphics pipeline, ECS foundation, and a fixed-timestep game loop.

## Quick Start

```bash
# Build example apps (debug mode with validation layers)
bash build.sh

# Run desktop examples
./bin/mesh_viewer
./bin/animation_viewer

# Run headless tests and smoke example
bash test.sh
```

**Compiler**: Odin nightly (`$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin`)
**Window**: 1280x720, titled "Thor", resizable

## Project Structure

```bash
build.sh                      # Builds example apps → bin/mesh_viewer, bin/animation_viewer, bin/headless_smoke
test.sh                       # Runs app tests + headless smoke example
engine/
  app/app.odin               # Headless app lifecycle, schedules, time/input/window resources
  animation/animation.odin   # CPU clip sampling + skinning runtime for the animation viewer
  assets/assets.odin         # Minimal GLB mesh/material loader + animation catalog extraction
  platform/platform.odin      # SDL2 windowing/input + app sync adapter bridge
  gfx/                        # Vulkan graphics subsystem
    gfx.odin                  #   Gfx_Context, create/destroy, swapchain recreation
    cel.odin                  #   Cel scene/material GPU data + descriptor plumbing
    instance.odin              #   Vulkan instance, queue families, device selection
    device.odin                #   Logical device creation
    swapchain.odin             #   Swapchain, image views, format/present mode
    frame.odin                 #   Frame sync, command recording, image transitions
    mesh.odin                  #   Vertex/index buffer upload for imported meshes
    pipeline.odin              #   Cel, outline, and shared mesh pipeline creation
    ui.odin                    #   Lightweight 2D overlay pipeline for debug/example UI
  game/game.odin              # Game system registration + temporary render bridge
  ecs/ecs.odin                # Entity (u64), World, spawn/destroy
examples/
  mesh_viewer/main.odin       # Desktop example consuming the engine through a collection import
  animation_viewer/main.odin  # Desktop example for searchable clip selection + skeletal playback
  headless_smoke/main.odin    # Headless smoke example for app-loop development
  assets/*.glb                # Example-owned mesh assets used to validate the import path
```

## Key Types and Imports

```odin
// Platform
import "engine/platform"
platform.Window, platform.Input, platform.Window_Config
platform.Platform_Bridge, platform.install()

// App
import "engine/app"
app.App, app.Stage, app.Time
app.init(), app.tick(), app.render(), app.add_system()

// Animation
import "engine/animation"
animation.Player
animation.create_player(), animation.play_clip(), animation.update()

// Graphics
import "engine/gfx"
gfx.Gfx_Context, gfx.Swapchain, gfx.Queue_Family_Indices, gfx.Context_Config
gfx.Render_Bridge, gfx.create_context(), gfx.install(), gfx.render_app()

// Assets
import "engine/assets"
assets.Mesh, assets.Mesh_Vertex, assets.Scene_Mesh, assets.Mesh_Primitive, assets.Material
assets.Animation_Catalog, assets.Animation_Clip_Info
assets.Skinned_Asset, assets.Animation_Clip, assets.Node_Transform
assets.load_mesh_from_glb(), assets.load_scene_mesh_from_glb()
assets.load_animation_catalog_from_glb(), assets.load_skinned_asset_from_glb()

// Game
import "engine/game"
game.register_game_systems()

// ECS
import "engine/ecs"
ecs.Entity (distinct u64), ecs.World
ecs.world_create(), ecs.world_spawn(), ecs.world_destroy()

// Vulkan & SDL2
import vk "vendor:vulkan"
import sdl "vendor:sdl2"
```

## Patterns

- **Error handling**: `or_return` pattern — procs return `(value, ok: bool)`
- **Resource cleanup**: `defer` for destruction in reverse creation order
- **Frame loop**: `begin_frame()` returns bool (false = skip frame, e.g. swapchain stale)
- **Fixed timestep**: accumulator pattern in `engine/app` at `DEFAULT_FIXED_DT :: 1.0 / 60.0`, capped at 0.25s
- **Examples as consumers**: build runnable apps from `examples/`, not from a root `main.odin`
- **Naming**: `Snake_Case` for types, `snake_case` for procs/vars, `UPPER_CASE` for constants
- **Vulkan structs**: always set `sType` field, use Odin struct literal syntax
- **Debug**: `when ODIN_DEBUG { ... }` for validation layers and debug logging

## Detailed Guides

> **Only read guides relevant to your current task to conserve tokens.**

| Guide                                                  | Read when...                                                    |
|--------------------------------------------------------|-----------------------------------------------------------------|
| [Architecture Overview](docs/architecture-overview.md) | Understanding system design, module relationships, or data flow |
| [Coding Standards](docs/coding-standards.md)           | Writing new code, reviewing style, or adding new modules        |
| [Graphics Guide](docs/graphics-guide.md)               | Working on Vulkan rendering, shaders, pipelines, or swapchain   |
| [Common Tasks](docs/common-tasks.md)                   | Adding entities, components, new engine systems, or new modules |

### Task → Guide Quick Reference

| Task                               | Guide(s) to read                          |
|------------------------------------|-------------------------------------------|
| Add a new component/entity         | Common Tasks                              |
| Add rendering (pipelines, shaders) | Graphics Guide                            |
| Add a new engine module            | Common Tasks, Coding Standards            |
| Fix a Vulkan error                 | Graphics Guide                            |
| Understand how systems connect     | Architecture Overview                     |
| Code review / style check          | Coding Standards                          |
| Add input handling                 | Architecture Overview (platform section)  |
| Modify the game loop               | Architecture Overview (main loop section) |

## Maintenance

When making changes that affect engine architecture, module interfaces, or conventions, update the relevant guide in
`docs/` and this file if the quick reference changes.
