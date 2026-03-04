# Architecture Overview

> **Read when:** Understanding system design, module relationships, data flow, or the main game loop.

## Module Dependency Graph

```
examples/mesh_viewer/main.odin
  ├── engine/app        (Headless app lifecycle, schedules, time/resources)
  ├── engine/platform   (SDL2 windowing, input, Vulkan surface)
  ├── engine/gfx        (Vulkan rendering — depends on platform)
  └── engine/game       (Game systems + temporary render bridge)
        └── engine/ecs  (Entity-Component System)

examples/headless_smoke/main.odin
  └── engine/app        (Headless app lifecycle, schedules, time/resources)
```

- `app` depends on `ecs` and owns engine state, schedules, and timestep flow
- `platform` has no engine dependencies (only `core:c`, `vendor:sdl2`, `vendor:vulkan`)
- `gfx` depends on `platform` (for window handle and Vulkan surface)
- `game` depends on `app`; rendering remains temporarily bridged through `gfx`
- `ecs` has no dependencies

## Desktop Example Flow (examples/mesh_viewer/main.odin)

```
1. create_window()             → platform.Window
2. create_context(&win)        → gfx.Gfx_Context (full Vulkan init)
3. app.init(&engine_app)       → app.App with ECS World + time/resources
4. platform.install(&engine_app, bridge)
5. gfx.install(&engine_app, bridge)
6. game.register_game_systems(&engine_app)
7. app.run_startup(&engine_app)
4. Loop:
   a. Compute frame delta, cap at 0.25s (spiral of death prevention)
   b. poll_events()         → updates Input, Window.resized, Window.should_close
   c. app.tick()            → platform install hook syncs backend state into headless resources
   d. gfx.render_app()      → render adapter handles resize, begin/end frame, and render stage
5. Cleanup (defer): app.destroy → gfx.destroy_context → platform.destroy_window
```

## Headless Smoke Flow (examples/headless_smoke/main.odin)

```
1. app.init(&engine_app)
2. Register startup/fixed/update systems
3. app.run_startup(&engine_app)
4. Tick for N fixed steps with synthetic dt
5. Inspect counters / print smoke result
```

## App Module (engine/app/app.odin)

**Purpose**: Own engine state, timestep flow, and headless schedules.

### Key Types
- `App` — contains `ecs.World`, `Time`, `App_Exit`, and headless input/window resources
- `Stage` — `Startup`, `Fixed_Update`, `Update`, `Render`, `Shutdown`
- `System` — `proc(engine: ^App)`
- `Time` — `delta`, `fixed_delta`, `accumulator`, `frame_count`
- `Input_State`, `Window_State` — backend-agnostic per-frame resources

### Key Procedures
- `init(app)` — creates ECS world and default fixed timestep
- `destroy(app)` — runs shutdown systems and destroys ECS world
- `add_system(app, stage, system)` — registers a system for a lifecycle stage
- `run_startup(app)` — runs startup systems once
- `tick(app, frame_dt)` — caps frame delta, runs fixed-update and update systems
- `render(app)` — runs render systems; backend adapters decide when to call it
- `set_input(app, input)` / `set_window(app, window)` — copy backend state into engine resources
- `request_exit(app)` — sets `App_Exit.should_exit = true`

## Platform Module (engine/platform/platform.odin)

**Purpose**: Abstract SDL2 windowing and input into engine-friendly types.

### Key Types
- `Window` — SDL window handle, dimensions, `should_close`, `resized` flags
- `Input` — 512-key state arrays (down/pressed/released), mouse position + delta, 5 mouse buttons
- `Window_Config` — creation params (title, width, height)

### Key Procedures
- `create_window(cfg) → (Window, bool)` — inits SDL2, loads Vulkan library, creates window
- `destroy_window(win)` — destroys window, unloads Vulkan, quits SDL
- `install(app, bridge)` — registers app sync systems for a window/input pair
- `poll_events(win, input)` — clears per-frame state, processes SDL events
- `get_time() → f64` — high-precision timer via SDL performance counter
- `create_vulkan_surface(win, instance) → (SurfaceKHR, bool)` — SDL-managed Vulkan surface
- `get_vulkan_instance_extensions(win) → ([]cstring, bool)` — required instance extensions
- `get_drawable_size(win) → (w, h: i32)` — actual drawable dimensions (for HiDPI)

### Input Model
- `keys_down[scancode]` — held state (persists across frames)
- `keys_pressed[scancode]` — just pressed this frame (cleared each poll)
- `keys_released[scancode]` — just released this frame (cleared each poll)
- ESC key hardcoded to set `should_close = true`
- `install` currently bridges one SDL window/input pair into `app.Input_State` and `app.Window_State`

## Graphics Module (engine/gfx/)

**Purpose**: Manage the full Vulkan rendering pipeline.

### Adapter Surface
- `install(app, bridge)` — registers the active graphics context with the app
- `render_app(app)` — owns resize handling, `begin_frame`, render-stage execution, and `end_frame`
- `current_context()` — exposes the active Vulkan context to transitional render systems

### Initialization Order (in create_context)
1. Load global Vulkan function pointers (via SDL)
2. Create Vulkan instance (enable validation layers in debug when available)
3. Create surface (via platform)
4. Pick physical device (prefer discrete GPU, score-based)
5. Find queue families (graphics + present)
6. Create logical device + load device function pointers
7. Create swapchain (MAILBOX preferred, FIFO fallback)
8. Create render pass, framebuffers, and graphics pipeline
9. Load the example `.glb` mesh and upload vertex/index buffers
10. Create command pool + allocate command buffers (per frame-in-flight)
11. Create sync objects (semaphores + fences, per frame-in-flight)

### Frame Lifecycle
1. `begin_frame()`: wait fence → acquire image → reset fence → reset cmd buffer → record clear commands with image transitions
2. Game submits additional draw commands (future)
3. `end_frame()`: submit queue → present → handle out-of-date/suboptimal → advance frame counter

### Swapchain Recreation
Triggered by `ERROR_OUT_OF_DATE_KHR`, `SUBOPTIMAL_KHR`, or `framebuffer_resized` flag.
Waits for device idle, creates new swapchain with old as `oldSwapchain`, destroys old after.

### Constants
- `MAX_FRAMES_IN_FLIGHT :: 2` — double buffering
- `VALIDATION_LAYER :: "VK_LAYER_KHRONOS_validation"`
- Clear color: `{0.01, 0.01, 0.02, 1.0}` (dark blue-gray)
- Vulkan API version: 1.3
- Preferred surface format: `B8G8R8A8_SRGB` / `SRGB_NONLINEAR`
- Image usage: `COLOR_ATTACHMENT | TRANSFER_DST`

## Game Module (engine/game/game.odin)

**Purpose**: Register gameplay systems, including the transitional render system.

- `register_game_systems(app)` — wires startup, fixed-update, and update systems into `app`
- `startup_system`, `fixed_update_system`, `update_system`, `render_system` — current gameplay stubs
- `render_system` still accesses Vulkan through `gfx.current_context()` during the transition

## ECS Module (engine/ecs/ecs.odin)

**Purpose**: Entity management foundation. Currently minimal.

- `Entity` — `distinct u64`, IDs start at 1
- `World` — `next_entity: u64` counter
- `world_create()` → World with counter at 1
- `world_spawn(world)` → new Entity with incrementing ID
- `world_destroy(world)` → zeros the world

**Not yet implemented**: component storage, systems, queries.
