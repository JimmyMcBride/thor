# Thor

> A custom 3D action RPG engine built in Odin — cel shaded, procedural-first, Blender-native.

---

## Vision

Thor is an attempt to build the game engine I've always wanted: one purpose-built for the kind of games I love. Think Skyrim's sense of open-world exploration fused with the tight, punishing combat of FromSoftware's Souls series — rendered in a striking cel shaded style and powered by procedural systems at every level.

The guiding philosophy is **procedural-first**. Rather than hand-authoring content, the engine is designed from the ground up to generate it:

- **Procedural animation** — inverse kinematics, locomotion blending, and foot placement that responds to the world in real time, not canned clips
- **Procedural textures** — materials generated at runtime, not baked ahead of time
- **Procedural terrain** — landscapes that emerge from noise and rules rather than heightmap painting
- **Procedural enemies and objects** — entity variety without exponential asset counts

The other non-negotiable: **Blender as a first-class citizen**. The engine's coordinate system matches Blender's (Z-up, right-handed, X=right, Y=forward). The long-term goal is a workflow where Blender serves as the live level and asset editor — not a separate tool you round-trip through, but an integrated part of the development loop.

---

## Current State — Milestone 3 (First Slice)

What exists today:

- **Language**: Odin (nightly build)
- **Graphics backend**: Vulkan 1.3 — instance, physical device, logical device, swapchain, image views, render pass, framebuffers, graphics pipeline, double-buffered frame loop with semaphore/fence synchronization
- **Asset import**: `.glb` mesh loading for a first Blender-to-engine path — extracts indexed triangle geometry, skinning data, and animation clips from the sample asset
- **Shaders**: GLSL compiled to SPIR-V via glslc at build time
- **Windowing & input**: SDL2 — keyboard, mouse, and window events (resize, close)
- **Game loop**: Fixed 60 Hz timestep with accumulator pattern, variable render tick, delta cap at 0.25s
- **ECS foundation**: `Entity` (distinct u64) + `World` type — spawn/destroy infrastructure, no component storage yet
- **Rendering**: Imported mesh rendering from `examples/assets/` on a dark blue-gray background. Dynamic viewport/scissor — survives window resize without pipeline recreation.
- **Animation playback**: `examples/animation_viewer` evaluates the sample GLB's skeletal clips on the CPU, skins the mesh every frame, and provides an in-window searchable clip picker with Play and Loop controls.

Honest status: first Blender-exported mesh is on the render path. Materials, scene traversal, coordinate-bridge cleanup, and animation are still ahead.

---

## Roadmap

Rough milestone breakdown of what comes next, roughly in order:

| Milestone | Focus |
|-----------|-------|
| ~~**M2**~~ | ~~Triangle on screen — graphics pipeline, shaders, vertex buffers~~ ✓ |
| ~~**M3**~~ | ~~Initial mesh loading + Blender `.glb` import path~~ ✓ |
| **M4** | Blender coordinate bridge — Z-up import with no surprises |
| **M5** | Materials + cel shading render pass |
| **M6** | ECS component storage + basic transform/render components |
| **M7** | Skeletal animation system |
| **M8** | IK / reverse IK for procedural locomotion |
| **M9** | Procedural texture generation |
| **M10** | Procedural terrain |
| **M11** | Entity/AI systems — souls-style combat foundation |
| **M12** | Blender plugin / live-link for in-engine editing |

---

## Blender Integration

Blender integration is a first-class design goal, not an afterthought.

**Coordinate system**: The engine uses Blender's native coordinate system — X=right, Y=forward, Z=up (right-handed). Assets exported from Blender should require no axis remapping.

**Import workflow goal**: export from Blender → drop asset in project → it works. Hot-reload when files change.

**Long-term goal**: Blender as the level editor. Rather than building a proprietary editor, the plan is to drive Blender via a plugin that syncs scene state with the running engine in real time — place objects in Blender, see them in the engine immediately.

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Language | Odin |
| Graphics API | Vulkan 1.3 |
| Windowing / Input | SDL2 |
| 3D authoring | Blender |
| Build | bash + Odin compiler (nightly) |

---

## Building, Running, Testing

Requires:
- [Odin nightly](https://github.com/odin-lang/Odin/releases) compiler
- Vulkan-capable GPU with up-to-date drivers
- SDL2 installed
- glslc (from the Vulkan SDK) on your PATH

```bash
# Build example apps (debug mode; validation enabled when installed)
bash build.sh

# Run the desktop examples
./bin/mesh_viewer
./bin/animation_viewer

# Run headless tests + smoke example
bash test.sh
```

Press **ESC** to quit.

## Example Apps

- `examples/mesh_viewer` is the current desktop/Vulkan consumer of the engine packages.
- `examples/animation_viewer` plays the sample GLB's skeletal clips with a searchable in-window picker, clickable Play and Loop controls, and mouse-wheel scrolling through the clip list.
- `examples/headless_smoke` exercises the headless app loop without SDL2 or Vulkan.

The examples import the engine through the local collection:

```bash
-collection:thor=.
```

That keeps the repo moving toward a library-style workflow instead of a root executable.
